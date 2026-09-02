//
//  iOSSearchView.swift
//  SigmaStream-iOS
//
//  Created by Daniel Rafailov on 2026-09-01.
//

import SwiftUI
import TMDb

#if os(iOS)
enum SearchMode: String, CaseIterable, Identifiable {
    case standard = "Basic"
    case ai = "AI Mode ✨"
    
    var id: String { rawValue }
}

enum SearchSortOption: String, CaseIterable, Identifiable {
    case popularityDesc = "Popularity (Highest First)"
    case popularityAsc = "Popularity (Lowest First)"
    case ratingDesc = "Rating (Highest First)"
    case ratingAsc = "Rating (Lowest First)"
    case releaseDateDesc = "Release Date (Newest)"
    case releaseDateAsc = "Release Date (Oldest)"
    case titleAsc = "Title (A → Z)"
    case titleDesc = "Title (Z → A)"

    var id: String { rawValue }
}

struct SearchGenreItem: Identifiable {
    let id: Int
    let name: String
}

private let searchAvailableGenres: [SearchGenreItem] = [
    SearchGenreItem(id: 28, name: "Action"),
    SearchGenreItem(id: 12, name: "Adventure"),
    SearchGenreItem(id: 16, name: "Animation"),
    SearchGenreItem(id: 35, name: "Comedy"),
    SearchGenreItem(id: 80, name: "Crime"),
    SearchGenreItem(id: 99, name: "Documentary"),
    SearchGenreItem(id: 18, name: "Drama"),
    SearchGenreItem(id: 10751, name: "Family"),
    SearchGenreItem(id: 14, name: "Fantasy"),
    SearchGenreItem(id: 36, name: "History"),
    SearchGenreItem(id: 27, name: "Horror"),
    SearchGenreItem(id: 10402, name: "Music"),
    SearchGenreItem(id: 9648, name: "Mystery"),
    SearchGenreItem(id: 10749, name: "Romance"),
    SearchGenreItem(id: 878, name: "Sci-Fi"),
    SearchGenreItem(id: 53, name: "Thriller"),
    SearchGenreItem(id: 10752, name: "War"),
    SearchGenreItem(id: 37, name: "Western")
]

private let searchAvailableYears = [
    "All", "2025", "2024", "2023", "2022", "2021", "2020", "2010s", "2000s", "90s", "80s", "70s & older"
]

struct SearchFilterOptions: Equatable {
    var mediaType: Int = 0 // 0: All, 1: Movies, 2: TV Shows
    var selectedGenreIds: Set<Int> = []
    var selectedYear: String = "All"
    var actorName: String = ""
    var minRating: Double = 0.0
    var sortBy: SearchSortOption = .popularityDesc

    var isActive: Bool {
        mediaType != 0 || !selectedGenreIds.isEmpty || selectedYear != "All" || !actorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || minRating > 0 || sortBy != .popularityDesc
    }

    mutating func reset() {
        mediaType = 0
        selectedGenreIds.removeAll()
        selectedYear = "All"
        actorName = ""
        minRating = 0.0
        sortBy = .popularityDesc
    }
}

struct iOSSearchView: View {
    @Environment(AppState.self) private var appState

    @State private var searchText = ""
    @State private var searchMode: SearchMode = .standard
    @State private var filters = SearchFilterOptions()
    @State private var showFilterSheet = false
    @State private var searchResults: [MediaListItem] = []
    @State private var aiSpokenResponse: String?
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    // Detail Navigation
    @State private var selectedMovieId: Int?
    @State private var selectedTVSeriesId: Int?

    // 3 columns on iPhone with clean spacing
    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top Header: "Search Type:" Label + Dropdown Menu + Hamburger Filter Icon
                HStack(spacing: 10) {
                    Text("Search Type:")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Menu {
                        Button {
                            searchMode = .standard
                        } label: {
                            HStack {
                                Text("Basic")
                                if searchMode == .standard {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }

                        Button {
                            searchMode = .ai
                        } label: {
                            HStack {
                                Text("AI Mode ✨")
                                if searchMode == .ai {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(searchMode == .standard ? "Basic" : "AI Mode ✨")
                                .font(.subheadline.bold())
                                .foregroundStyle(.primary)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(uiColor: .secondarySystemBackground))
                        .clipShape(Capsule())
                    }

                    Spacer()

                    // Active Filters Summary or Hamburger Button
                    Button {
                        showFilterSheet = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 17, weight: .bold))
                            if filters.isActive {
                                Text("Filters (On)")
                                    .font(.caption2.bold())
                            }
                        }
                        .foregroundStyle(filters.isActive ? Color.blue : Color.primary)
                        .padding(.horizontal, filters.isActive ? 10 : 8)
                        .padding(.vertical, 6)
                        .background(Color(uiColor: .secondarySystemBackground))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 6)
                .onChange(of: searchMode) { _, newMode in
                    searchTask?.cancel()
                    appState.voiceService.stopSpeaking()
                    searchResults = []
                    aiSpokenResponse = nil
                    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !query.isEmpty || filters.isActive {
                        searchTask = Task {
                            await executeSearch(query: query, mode: newMode, isExplicitFilterSearch: false)
                        }
                    }
                }

                // Results / Content View
                if isSearching {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.3)
                        Text(searchMode == .ai ? "Sigma AI is analyzing..." : "Searching titles...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if searchResults.isEmpty && !searchText.isEmpty && aiSpokenResponse == nil {
                    if searchMode == .ai {
                        VStack(spacing: 12) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 44))
                                .foregroundStyle(.cyan)
                            Text("Press Search on your keyboard to ask Sigma AI")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ContentUnavailableView.search(text: searchText)
                    }
                } else if searchResults.isEmpty && aiSpokenResponse == nil {
                    VStack(spacing: 12) {
                        Image(systemName: searchMode == .ai ? "sparkles" : "magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundStyle(searchMode == .ai ? .cyan : .secondary)
                        Text(searchMode == .ai ? "Ask Sigma AI Anything" : "Search Movies & TV Shows")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        if searchMode == .ai {
                            Text("Try \"recommend a 90s action thriller\" or \"best sci-fi shows\"")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        } else {
                            Text("Use the search bar or tap the ☰ filter button to browse by genre, year, actor, and ratings")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            // AI Spoken Answer Card
                            if searchMode == .ai, let response = aiSpokenResponse, !response.isEmpty {
                                HStack(alignment: .top, spacing: 14) {
                                    Image(systemName: "waveform.circle.fill")
                                        .font(.system(size: 32))
                                        .foregroundStyle(.cyan)

                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text("Sigma AI (\(appState.voiceService.selectedVoiceName))")
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.cyan)

                                            Spacer()

                                            Button {
                                                appState.voiceService.speak(response)
                                            } label: {
                                                HStack(spacing: 4) {
                                                    Image(systemName: "speaker.wave.2.fill")
                                                    Text("Replay")
                                                }
                                                .font(.caption2.bold())
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.cyan.opacity(0.18))
                                                .clipShape(Capsule())
                                            }
                                        }

                                        Text(response)
                                            .font(.subheadline)
                                            .foregroundStyle(.white)
                                            .lineSpacing(3)
                                    }
                                }
                                .padding(16)
                                .background(Color.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                            }

                            // Active Filter Header (if applied)
                            if filters.isActive {
                                HStack {
                                    Text("\(searchResults.count) matching title\(searchResults.count == 1 ? "" : "s")")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("Sorted by: \(filters.sortBy.rawValue)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.top, 4)
                            }

                            // Media Grid
                            if !searchResults.isEmpty {
                                LazyVGrid(columns: columns, spacing: 16) {
                                    ForEach(searchResults) { item in
                                        Button {
                                            if item.isTVSeries {
                                                selectedTVSeriesId = item.id
                                            } else {
                                                selectedMovieId = item.id
                                            }
                                        } label: {
                                            iOSMediaCard(
                                                id: item.id,
                                                title: item.title,
                                                posterPath: item.posterURL,
                                                rating: item.rating,
                                                releaseYear: item.releaseYear,
                                                isTVSeries: item.isTVSeries,
                                                progress: nil
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("Search")
            .navigationDestination(isPresented: Binding(
                get: { selectedMovieId != nil },
                set: { if !$0 { selectedMovieId = nil } }
            )) {
                if let movieId = selectedMovieId {
                    iOSMovieDetailView(movieId: movieId)
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { selectedTVSeriesId != nil },
                set: { if !$0 { selectedTVSeriesId = nil } }
            )) {
                if let tvId = selectedTVSeriesId {
                    iOSTVSeriesDetailView(seriesId: tvId)
                }
            }
            .sheet(isPresented: $showFilterSheet) {
                SearchFilterSheetView(
                    filters: $filters,
                    onApplyFiltersOnly: {
                        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !query.isEmpty {
                            searchTask?.cancel()
                            searchTask = Task {
                                await executeSearch(query: query, mode: searchMode, isExplicitFilterSearch: false)
                            }
                        }
                    },
                    onApplySearch: {
                        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                        searchTask?.cancel()
                        searchTask = Task {
                            await executeSearch(query: query, mode: searchMode, isExplicitFilterSearch: true)
                        }
                    }
                )
            }
            .searchable(
                text: $searchText,
                prompt: searchMode == .ai ? "Ask AI Anything" : "Search titles, actors, genres..."
            )
            .onSubmit(of: .search) {
                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !query.isEmpty || filters.isActive else { return }
                searchTask?.cancel()
                searchTask = Task {
                    await executeSearch(query: query, mode: searchMode, isExplicitFilterSearch: false)
                }
            }
            .onChange(of: searchText) { _, newValue in
                searchTask?.cancel()
                appState.voiceService.stopSpeaking()
                if newValue.isEmpty && !filters.isActive {
                    searchResults = []
                    aiSpokenResponse = nil
                    isSearching = false
                } else if searchMode == .standard && !newValue.isEmpty {
                    // Fast debounce search in Basic mode
                    searchTask = Task {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        guard !Task.isCancelled else { return }
                        await executeSearch(query: newValue, mode: .standard, isExplicitFilterSearch: false)
                    }
                }
            }
            .onAppear {
                searchMode = .standard
            }
            .onDisappear {
                appState.voiceService.stopSpeaking()
            }
        }
    }

    private func executeSearch(query: String, mode: SearchMode, isExplicitFilterSearch: Bool) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty && !filters.isActive && !isExplicitFilterSearch { return }

        await MainActor.run {
            isSearching = true
            aiSpokenResponse = nil
        }

        do {
            if mode == .ai {
                var prompt = trimmed
                if filters.isActive || isExplicitFilterSearch {
                    var filterDetails: [String] = []
                    if filters.mediaType == 1 { filterDetails.append("Movies only") }
                    if filters.mediaType == 2 { filterDetails.append("TV shows only") }
                    if !filters.selectedGenreIds.isEmpty {
                        let names = searchAvailableGenres.filter { filters.selectedGenreIds.contains($0.id) }.map { $0.name }
                        filterDetails.append("Genres: \(names.joined(separator: ", "))")
                    }
                    if filters.selectedYear != "All" {
                        filterDetails.append("Year/Era: \(filters.selectedYear)")
                    }
                    if !filters.actorName.isEmpty {
                        filterDetails.append("Starring actor: \(filters.actorName)")
                    }
                    if filters.minRating > 0 {
                        filterDetails.append("Minimum Rating: \(filters.minRating)+")
                    }
                    filterDetails.append("Sort Order: \(filters.sortBy.rawValue)")

                    if prompt.isEmpty {
                        prompt = "Recommend top entertainment titles matching these filters: \(filterDetails.joined(separator: ", "))"
                    } else {
                        prompt += " (Filters: \(filterDetails.joined(separator: ", ")))"
                    }
                }

                let result = try await appState.aiService.query(prompt: prompt, tmdbService: appState.tmdbService)
                guard !Task.isCancelled else { return }

                var combined: [MediaListItem] = []
                if filters.mediaType != 2 {
                    let movieItems = result.movies.map {
                        MediaListItem(
                            id: $0.id,
                            title: $0.title,
                            posterURL: ImageURLBuilder.posterURL(for: $0.posterPath, config: appState.apiConfiguration, idealWidth: 342),
                            rating: $0.voteAverage,
                            releaseYear: $0.releaseDate.map { String(Calendar.current.component(.year, from: $0)) },
                            isTVSeries: false,
                            releaseDate: $0.releaseDate
                        )
                    }
                    combined.append(contentsOf: movieItems)
                }

                if filters.mediaType != 1 {
                    let tvItems = result.tvSeries.map {
                        MediaListItem(
                            id: $0.id,
                            title: $0.name,
                            posterURL: ImageURLBuilder.posterURL(for: $0.posterPath, config: appState.apiConfiguration, idealWidth: 342),
                            rating: $0.voteAverage,
                            releaseYear: $0.firstAirDate.map { String(Calendar.current.component(.year, from: $0)) },
                            isTVSeries: true,
                            releaseDate: $0.firstAirDate
                        )
                    }
                    combined.append(contentsOf: tvItems)
                }

                // Apply Sort Order to AI results as well
                combined = sortMediaItems(combined, by: filters.sortBy)

                await MainActor.run {
                    self.searchResults = combined
                    self.aiSpokenResponse = result.spokenResponse
                    self.isSearching = false
                }

                // Speak response via active celebrity voice
                appState.voiceService.speak(result.spokenResponse)
            } else {
                var results: [MediaListItem] = []
                
                // Determine search target: query text -> actor name -> first selected genre -> fallback default
                let searchTarget: String
                if !trimmed.isEmpty {
                    searchTarget = trimmed
                } else if !filters.actorName.isEmpty {
                    searchTarget = filters.actorName
                } else if let firstGenreId = filters.selectedGenreIds.first,
                          let genreObj = searchAvailableGenres.first(where: { $0.id == firstGenreId }) {
                    searchTarget = genreObj.name
                } else {
                    searchTarget = "Action"
                }

                if filters.mediaType == 0 || filters.mediaType == 1 {
                    let movies = try await appState.tmdbService.searchMovies(query: searchTarget)
                    let movieItems = movies.compactMap { m -> MediaListItem? in
                        // Year filter check
                        if filters.selectedYear != "All", let date = m.releaseDate {
                            let year = Calendar.current.component(.year, from: date)
                            if !matchesYearFilter(year: year, filter: filters.selectedYear) {
                                return nil
                            }
                        }
                        // Rating filter check
                        if filters.minRating > 0, let rating = m.voteAverage, rating < filters.minRating {
                            return nil
                        }
                        return MediaListItem(
                            id: m.id,
                            title: m.title,
                            posterURL: ImageURLBuilder.posterURL(for: m.posterPath, config: appState.apiConfiguration, idealWidth: 342),
                            rating: m.voteAverage,
                            releaseYear: m.releaseDate.map { String(Calendar.current.component(.year, from: $0)) },
                            isTVSeries: false,
                            releaseDate: m.releaseDate
                        )
                    }
                    results.append(contentsOf: movieItems)
                }

                if filters.mediaType == 0 || filters.mediaType == 2 {
                    let tvSeries = try await appState.tmdbService.searchTVSeries(query: searchTarget)
                    let tvItems = tvSeries.compactMap { tv -> MediaListItem? in
                        // Year filter check
                        if filters.selectedYear != "All", let date = tv.firstAirDate {
                            let year = Calendar.current.component(.year, from: date)
                            if !matchesYearFilter(year: year, filter: filters.selectedYear) {
                                return nil
                            }
                        }
                        // Rating filter check
                        if filters.minRating > 0, let rating = tv.voteAverage, rating < filters.minRating {
                            return nil
                        }
                        return MediaListItem(
                            id: tv.id,
                            title: tv.name,
                            posterURL: ImageURLBuilder.posterURL(for: tv.posterPath, config: appState.apiConfiguration, idealWidth: 342),
                            rating: tv.voteAverage,
                            releaseYear: tv.firstAirDate.map { String(Calendar.current.component(.year, from: $0)) },
                            isTVSeries: true,
                            releaseDate: tv.firstAirDate
                        )
                    }
                    results.append(contentsOf: tvItems)
                }

                // Apply Sorting
                results = sortMediaItems(results, by: filters.sortBy)

                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.searchResults = results
                    self.isSearching = false
                }
            }
        } catch {
            await MainActor.run {
                self.isSearching = false
            }
        }
    }

    private func sortMediaItems(_ items: [MediaListItem], by sort: SearchSortOption) -> [MediaListItem] {
        switch sort {
        case .popularityDesc:
            return items
        case .popularityAsc:
            return items.reversed()
        case .ratingDesc:
            return items.sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }
        case .ratingAsc:
            return items.sorted { ($0.rating ?? 0) < ($1.rating ?? 0) }
        case .releaseDateDesc:
            return items.sorted { ($0.releaseDate ?? .distantPast) > ($1.releaseDate ?? .distantPast) }
        case .releaseDateAsc:
            return items.sorted { ($0.releaseDate ?? .distantPast) < ($1.releaseDate ?? .distantPast) }
        case .titleAsc:
            return items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .titleDesc:
            return items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
        }
    }

    private func matchesYearFilter(year: Int, filter: String) -> Bool {
        if filter == "All" { return true }
        if let exactYear = Int(filter) { return year == exactYear }
        if filter == "2020s" { return year >= 2020 && year <= 2029 }
        if filter == "2010s" { return year >= 2010 && year <= 2019 }
        if filter == "2000s" { return year >= 2000 && year <= 2009 }
        if filter == "90s" { return year >= 1990 && year <= 1999 }
        if filter == "80s" { return year >= 1980 && year <= 1989 }
        if filter == "70s & older" { return year < 1980 }
        return true
    }
}

// MARK: - Search Filter Sheet View
struct SearchFilterSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var filters: SearchFilterOptions
    let onApplyFiltersOnly: () -> Void
    let onApplySearch: () -> Void

    @State private var draftFilters: SearchFilterOptions

    init(
        filters: Binding<SearchFilterOptions>,
        onApplyFiltersOnly: @escaping () -> Void,
        onApplySearch: @escaping () -> Void
    ) {
        self._filters = filters
        self.onApplyFiltersOnly = onApplyFiltersOnly
        self.onApplySearch = onApplySearch
        self._draftFilters = State(initialValue: filters.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                // Section 1: Media Type
                Section("Media Type") {
                    Picker("Category", selection: $draftFilters.mediaType) {
                        Text("All Content").tag(0)
                        Text("Movies Only").tag(1)
                        Text("TV Shows Only").tag(2)
                    }
                    .pickerStyle(.segmented)
                }

                // Section 2: Sort Order
                Section("Sort By") {
                    Picker("Order", selection: $draftFilters.sortBy) {
                        ForEach(SearchSortOption.allCases) { opt in
                            Text(opt.rawValue).tag(opt)
                        }
                    }
                    .pickerStyle(.menu)
                }

                // Section 3: Release Period / Year
                Section("Release Period") {
                    Picker("Year", selection: $draftFilters.selectedYear) {
                        ForEach(searchAvailableYears, id: \.self) { year in
                            Text(year).tag(year)
                        }
                    }
                    .pickerStyle(.menu)
                }

                // Section 4: Actor / Cast
                Section("Starring Actor / Cast") {
                    TextField("e.g. Tom Cruise, Cillian Murphy", text: $draftFilters.actorName)
                }

                // Section 5: Minimum Rating
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Minimum Rating")
                            Spacer()
                            Text(draftFilters.minRating > 0 ? String(format: "★ %.1f+", draftFilters.minRating) : "Any")
                                .font(.subheadline.bold())
                                .foregroundStyle(draftFilters.minRating > 0 ? .yellow : .secondary)
                        }
                        Slider(value: $draftFilters.minRating, in: 0...9.0, step: 0.5)
                    }
                }

                // Section 6: Genres
                Section("Genres") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
                        ForEach(searchAvailableGenres) { genre in
                            let isSelected = draftFilters.selectedGenreIds.contains(genre.id)
                            Button {
                                if isSelected {
                                    draftFilters.selectedGenreIds.remove(genre.id)
                                } else {
                                    draftFilters.selectedGenreIds.insert(genre.id)
                                }
                            } label: {
                                Text(genre.name)
                                    .font(.caption.weight(isSelected ? .bold : .medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .frame(maxWidth: .infinity)
                                    .background(isSelected ? Color.blue : Color(uiColor: .tertiarySystemFill))
                                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Section 7: Action Buttons (Apply Filter Search & Apply Filters)
                Section {
                    VStack(spacing: 12) {
                        // 1. Primary Button: Apply Filter Search (Immediately queries all entertainment matching filters)
                        Button {
                            filters = draftFilters
                            dismiss()
                            onApplySearch()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkle.magnifyingglass")
                                    .font(.headline)
                                Text("Apply Filter Search")
                                    .font(.headline.bold())
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.blue)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        // 2. Secondary Button: Apply Filters (Saves active filter preferences)
                        Button {
                            filters = draftFilters
                            dismiss()
                            onApplyFiltersOnly()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "line.3.horizontal.decrease")
                                    .font(.subheadline)
                                Text("Apply Filters")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(uiColor: .secondarySystemBackground))
                            .foregroundStyle(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Search Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        draftFilters.reset()
                    }
                    .foregroundStyle(.red)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct MediaListItem: Identifiable {
    let id: Int
    let title: String
    let posterURL: URL?
    let rating: Double?
    let releaseYear: String?
    let isTVSeries: Bool
    var releaseDate: Date? = nil
}
#endif
