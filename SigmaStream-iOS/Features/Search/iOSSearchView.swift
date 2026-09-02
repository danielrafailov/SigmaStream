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

struct iOSSearchView: View {
    @Environment(AppState.self) private var appState

    @State private var searchText = ""
    @State private var searchMode: SearchMode = .standard
    @State private var selectedFilter = 0 // 0: All, 1: Movies, 2: TV Shows
    @State private var searchResults: [MediaListItem] = []
    @State private var aiSpokenResponse: String?
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    // Adaptive grid: 3 columns on iPhone, 5-6 columns on iPad
    private let columns = [
        GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 14)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search Mode Selector (Basic vs AI)
                Picker("Search Mode", selection: $searchMode) {
                    ForEach(SearchMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 6)
                .onChange(of: searchMode) { _, newMode in
                    searchTask?.cancel()
                    appState.voiceService.stopSpeaking()
                    searchResults = []
                    aiSpokenResponse = nil
                    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !query.isEmpty {
                        searchTask = Task {
                            await executeSearch(query: query, mode: newMode)
                        }
                    }
                }

                // Filter Chips (Only in Basic mode)
                if searchMode == .standard {
                    Picker("Filter", selection: $selectedFilter) {
                        Text("All").tag(0)
                        Text("Movies").tag(1)
                        Text("TV Shows").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .onChange(of: selectedFilter) { _, _ in
                        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !query.isEmpty {
                            searchTask?.cancel()
                            searchTask = Task {
                                await executeSearch(query: query, mode: .standard)
                            }
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

                            // Media Grid
                            if !searchResults.isEmpty {
                                LazyVGrid(columns: columns, spacing: 16) {
                                    ForEach(searchResults) { item in
                                        NavigationLink {
                                            if item.isTVSeries {
                                                iOSTVSeriesDetailView(seriesId: item.id)
                                            } else {
                                                iOSMovieDetailView(movieId: item.id)
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
            .searchable(
                text: $searchText,
                prompt: searchMode == .ai ? "Ask AI Anything" : "Search titles, actors, genres..."
            )
            .onSubmit(of: .search) {
                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !query.isEmpty else { return }
                searchTask?.cancel()
                searchTask = Task {
                    await executeSearch(query: query, mode: searchMode)
                }
            }
            .onChange(of: searchText) { _, newValue in
                searchTask?.cancel()
                appState.voiceService.stopSpeaking()
                if newValue.isEmpty {
                    searchResults = []
                    aiSpokenResponse = nil
                    isSearching = false
                } else if searchMode == .standard {
                    // Fast debounce search only in Basic mode
                    searchTask = Task {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        guard !Task.isCancelled else { return }
                        await executeSearch(query: newValue, mode: .standard)
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

    private func executeSearch(query: String, mode: SearchMode) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        await MainActor.run {
            isSearching = true
            aiSpokenResponse = nil
        }

        do {
            if mode == .ai {
                let result = try await appState.aiService.query(prompt: trimmed, tmdbService: appState.tmdbService)
                guard !Task.isCancelled else { return }

                var combined: [MediaListItem] = []
                let movieItems = result.movies.map {
                    MediaListItem(
                        id: $0.id,
                        title: $0.title,
                        posterURL: ImageURLBuilder.posterURL(for: $0.posterPath, config: appState.apiConfiguration, idealWidth: 342),
                        rating: $0.voteAverage,
                        releaseYear: $0.releaseDate.map { String(Calendar.current.component(.year, from: $0)) },
                        isTVSeries: false
                    )
                }
                let tvItems = result.tvSeries.map {
                    MediaListItem(
                        id: $0.id,
                        title: $0.name,
                        posterURL: ImageURLBuilder.posterURL(for: $0.posterPath, config: appState.apiConfiguration, idealWidth: 342),
                        rating: $0.voteAverage,
                        releaseYear: $0.firstAirDate.map { String(Calendar.current.component(.year, from: $0)) },
                        isTVSeries: true
                    )
                }
                combined.append(contentsOf: movieItems)
                combined.append(contentsOf: tvItems)

                await MainActor.run {
                    self.searchResults = combined
                    self.aiSpokenResponse = result.spokenResponse
                    self.isSearching = false
                }

                // Speak response via active celebrity voice
                appState.voiceService.speak(result.spokenResponse)
            } else {
                var results: [MediaListItem] = []
                if selectedFilter == 0 || selectedFilter == 1 {
                    let movies = try await appState.tmdbService.searchMovies(query: trimmed)
                    let movieItems = movies.map {
                        MediaListItem(
                            id: $0.id,
                            title: $0.title,
                            posterURL: ImageURLBuilder.posterURL(for: $0.posterPath, config: appState.apiConfiguration, idealWidth: 342),
                            rating: $0.voteAverage,
                            releaseYear: $0.releaseDate.map { String(Calendar.current.component(.year, from: $0)) },
                            isTVSeries: false
                        )
                    }
                    results.append(contentsOf: movieItems)
                }

                if selectedFilter == 0 || selectedFilter == 2 {
                    let tvSeries = try await appState.tmdbService.searchTVSeries(query: trimmed)
                    let tvItems = tvSeries.map {
                        MediaListItem(
                            id: $0.id,
                            title: $0.name,
                            posterURL: ImageURLBuilder.posterURL(for: $0.posterPath, config: appState.apiConfiguration, idealWidth: 342),
                            rating: $0.voteAverage,
                            releaseYear: $0.firstAirDate.map { String(Calendar.current.component(.year, from: $0)) },
                            isTVSeries: true
                        )
                    }
                    results.append(contentsOf: tvItems)
                }

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
}

struct MediaListItem: Identifiable {
    let id: Int
    let title: String
    let posterURL: URL?
    let rating: Double?
    let releaseYear: String?
    let isTVSeries: Bool
}
#endif
