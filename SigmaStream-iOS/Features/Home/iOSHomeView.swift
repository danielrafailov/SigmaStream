//
//  iOSHomeView.swift
//  SigmaStream-iOS
//
//  Created by Daniel Rafailov on 2026-09-01.
//

import SwiftUI
import TMDb

#if os(iOS)
enum HomeTabSection: String, CaseIterable, Identifiable {
    case movies = "Movies"
    case tvShows = "TV Shows"

    var id: String { rawValue }
}

struct iOSHomeView: View {
    @Environment(AppState.self) private var appState

    @State private var selectedSection: HomeTabSection = .movies

    // MARK: - Movies Shelves
    @State private var movieHeroItems: [MediaListItem] = []
    @State private var trendingMovies: [iOSMediaRowItem] = []
    @State private var popularMovies: [iOSMediaRowItem] = []
    @State private var acclaimedMovies: [iOSMediaRowItem] = []
    @State private var newMovies: [iOSMediaRowItem] = []
    @State private var millennialMovies: [iOSMediaRowItem] = []
    @State private var genZMovies: [iOSMediaRowItem] = []
    @State private var genXMovies: [iOSMediaRowItem] = []
    @State private var nowPlayingMovies: [iOSMediaRowItem] = []
    @State private var movieExtraSections: [(MovieCategory, [iOSMediaRowItem])] = []

    // MARK: - TV Shelves
    @State private var tvHeroItems: [MediaListItem] = []
    @State private var trendingTV: [iOSMediaRowItem] = []
    @State private var popularTV: [iOSMediaRowItem] = []
    @State private var acclaimedTV: [iOSMediaRowItem] = []
    @State private var newTV: [iOSMediaRowItem] = []
    @State private var millennialTV: [iOSMediaRowItem] = []
    @State private var genZTV: [iOSMediaRowItem] = []
    @State private var genXTV: [iOSMediaRowItem] = []
    @State private var tvExtraSections: [(TVCategory, [iOSMediaRowItem])] = []

    @State private var isLoading = true
    @State private var selectedHeroIndex = 0

    // Detail & Category Navigation
    @State private var selectedMovieId: Int?
    @State private var selectedTVSeriesId: Int?
    @State private var selectedMovieCategory: MovieCategory?
    @State private var selectedTVCategory: TVCategory?
    @State private var selectedFeedCategory: String?

    private let curatedCategories = [
        "Action", "Anime", "Astrology", "Book Adaptations",
        "Canadian", "Comedies", "Critically Acclaimed",
        "Culture Edit", "Documentaries", "Dramas", "Emmys"
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top Header: App Logo (Sigma) + "Home" Title
                HStack(spacing: 10) {
                    Image("SigmaLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 30, height: 30)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                    Text("Home")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 6)

                // Horizontally Scrollable Liquid Glass Category Buttons (Shows, Movies, Categories ▾)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        // Shows button
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedSection = .tvShows
                            }
                        } label: {
                            Text("Shows")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(selectedSection == .tvShows ? Color.white.opacity(0.32) : Color.white.opacity(0.12))
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(selectedSection == .tvShows ? Color.white.opacity(0.55) : Color.white.opacity(0.2), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)

                        // Movies button
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedSection = .movies
                            }
                        } label: {
                            Text("Movies")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(selectedSection == .movies ? Color.white.opacity(0.32) : Color.white.opacity(0.12))
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(selectedSection == .movies ? Color.white.opacity(0.55) : Color.white.opacity(0.2), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)

                        // Categories Dropdown (Action, Anime, Astrology, Book Adaptations, Canadian, Comedies, Critically Acclaimed, Culture Edit, Documentaries, Dramas, Emmys)
                        Menu {
                            ForEach(curatedCategories, id: \.self) { category in
                                Button(category) {
                                    selectedFeedCategory = category
                                }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Text("Categories")
                                    .font(.system(size: 14, weight: .semibold))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
                .padding(.bottom, 6)

                ScrollView {
                    VStack(spacing: 20) {
                        if selectedSection == .movies {
                            moviesCatalogView
                        } else {
                            tvCatalogView
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
            .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
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
            .navigationDestination(isPresented: Binding(
                get: { selectedMovieCategory != nil },
                set: { if !$0 { selectedMovieCategory = nil } }
            )) {
                if let cat = selectedMovieCategory {
                    iOSMovieCategoryListView(category: cat)
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { selectedTVCategory != nil },
                set: { if !$0 { selectedTVCategory = nil } }
            )) {
                if let cat = selectedTVCategory {
                    iOSTVCategoryListView(category: cat)
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { selectedFeedCategory != nil },
                set: { if !$0 { selectedFeedCategory = nil } }
            )) {
                if let categoryName = selectedFeedCategory {
                    iOSCategoryFeedView(categoryName: categoryName)
                }
            }
            .task {
                await loadFeedData()
            }
            .refreshable {
                await loadFeedData()
            }
        }
    }

    // MARK: - Movies Catalog
    @ViewBuilder
    private var moviesCatalogView: some View {
        // Compact Hero Carousel
        if !movieHeroItems.isEmpty {
            heroCarousel(items: movieHeroItems, isTV: false)
        }

        // Core Shelves with See All
        if !trendingMovies.isEmpty {
            iOSMediaRow(
                title: "Trending Movies",
                items: trendingMovies,
                onSeeAll: { selectedMovieCategory = .trendingToday }
            ) { item in
                selectedMovieId = item.id
            }
        }

        if !popularMovies.isEmpty {
            iOSMediaRow(
                title: MovieCategory.popular.rawValue,
                items: popularMovies,
                onSeeAll: { selectedMovieCategory = .popular }
            ) { item in
                selectedMovieId = item.id
            }
        }

        if !newMovies.isEmpty {
            iOSMediaRow(
                title: MovieCategory.newReleases.rawValue,
                items: newMovies,
                onSeeAll: { selectedMovieCategory = .newReleases }
            ) { item in
                selectedMovieId = item.id
            }
        }

        if !acclaimedMovies.isEmpty {
            iOSMediaRow(
                title: MovieCategory.criticallyAcclaimed.rawValue,
                items: acclaimedMovies,
                onSeeAll: { selectedMovieCategory = .criticallyAcclaimed }
            ) { item in
                selectedMovieId = item.id
            }
        }

        if !millennialMovies.isEmpty {
            iOSMediaRow(
                title: MovieCategory.millennialFavorites.rawValue,
                items: millennialMovies,
                onSeeAll: { selectedMovieCategory = .millennialFavorites }
            ) { item in
                selectedMovieId = item.id
            }
        }

        if !genZMovies.isEmpty {
            iOSMediaRow(
                title: MovieCategory.genZPicks.rawValue,
                items: genZMovies,
                onSeeAll: { selectedMovieCategory = .genZPicks }
            ) { item in
                selectedMovieId = item.id
            }
        }

        if !genXMovies.isEmpty {
            iOSMediaRow(
                title: MovieCategory.genXClassics.rawValue,
                items: genXMovies,
                onSeeAll: { selectedMovieCategory = .genXClassics }
            ) { item in
                selectedMovieId = item.id
            }
        }

        if !nowPlayingMovies.isEmpty {
            iOSMediaRow(
                title: MovieCategory.nowPlaying.rawValue,
                items: nowPlayingMovies,
                onSeeAll: { selectedMovieCategory = .nowPlaying }
            ) { item in
                selectedMovieId = item.id
            }
        }

        // Extra Genre Discover Shelves
        ForEach(movieExtraSections, id: \.0) { cat, items in
            if !items.isEmpty {
                iOSMediaRow(
                    title: cat.rawValue,
                    items: items,
                    onSeeAll: { selectedMovieCategory = cat }
                ) { item in
                    selectedMovieId = item.id
                }
            }
        }
    }

    // MARK: - TV Catalog
    @ViewBuilder
    private var tvCatalogView: some View {
        // TV Hero Carousel
        if !tvHeroItems.isEmpty {
            heroCarousel(items: tvHeroItems, isTV: true)
        }

        // Core TV Shelves with See All
        if !trendingTV.isEmpty {
            iOSMediaRow(
                title: "Trending TV Shows",
                items: trendingTV,
                onSeeAll: { selectedTVCategory = .trendingToday }
            ) { item in
                selectedTVSeriesId = item.id
            }
        }

        if !popularTV.isEmpty {
            iOSMediaRow(
                title: TVCategory.popular.rawValue,
                items: popularTV,
                onSeeAll: { selectedTVCategory = .popular }
            ) { item in
                selectedTVSeriesId = item.id
            }
        }

        if !newTV.isEmpty {
            iOSMediaRow(
                title: TVCategory.newReleases.rawValue,
                items: newTV,
                onSeeAll: { selectedTVCategory = .newReleases }
            ) { item in
                selectedTVSeriesId = item.id
            }
        }

        if !acclaimedTV.isEmpty {
            iOSMediaRow(
                title: TVCategory.criticallyAcclaimed.rawValue,
                items: acclaimedTV,
                onSeeAll: { selectedTVCategory = .criticallyAcclaimed }
            ) { item in
                selectedTVSeriesId = item.id
            }
        }

        if !millennialTV.isEmpty {
            iOSMediaRow(
                title: TVCategory.millennialFavorites.rawValue,
                items: millennialTV,
                onSeeAll: { selectedTVCategory = .millennialFavorites }
            ) { item in
                selectedTVSeriesId = item.id
            }
        }

        if !genZTV.isEmpty {
            iOSMediaRow(
                title: TVCategory.genZPicks.rawValue,
                items: genZTV,
                onSeeAll: { selectedTVCategory = .genZPicks }
            ) { item in
                selectedTVSeriesId = item.id
            }
        }

        if !genXTV.isEmpty {
            iOSMediaRow(
                title: TVCategory.genXClassics.rawValue,
                items: genXTV,
                onSeeAll: { selectedTVCategory = .genXClassics }
            ) { item in
                selectedTVSeriesId = item.id
            }
        }

        // Extra TV Discover Shelves
        ForEach(tvExtraSections, id: \.0) { cat, items in
            if !items.isEmpty {
                iOSMediaRow(
                    title: cat.rawValue,
                    items: items,
                    onSeeAll: { selectedTVCategory = cat }
                ) { item in
                    selectedTVSeriesId = item.id
                }
            }
        }
    }

    // MARK: - Netflix-Style 3D Depth Hero Carousel (Infinite Looping)
    @ViewBuilder
    private func heroCarousel(items: [MediaListItem], isTV: Bool) -> some View {
        if !items.isEmpty {
            let count = items.count
            let virtualCount = count * 200

            TabView(selection: $selectedHeroIndex) {
                ForEach(0..<virtualCount, id: \.self) { vIndex in
                    let item = items[vIndex % count]
                    GeometryReader { geo in
                        let screenWidth = UIScreen.main.bounds.width
                        let midX = geo.frame(in: .global).midX
                        let distanceFromCenter = midX - (screenWidth / 2)
                        let normalizedDistance = max(-1.0, min(1.0, distanceFromCenter / screenWidth))
                        
                        // 3D Depth & Perspective transforms
                        let scale = max(0.88, 1.0 - abs(normalizedDistance) * 0.12)
                        let rotation = Double(normalizedDistance * -16)
                        let opacity = max(0.65, 1.0 - abs(normalizedDistance) * 0.35)

                        ZStack(alignment: .bottom) {
                            // Portrait Poster Art (Fills Card)
                            if let posterURL = item.posterURL {
                                AsyncImage(url: posterURL) { phase in
                                    if let img = phase.image {
                                        img
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: geo.size.width, height: geo.size.height)
                                            .clipped()
                                    } else {
                                        Color.white.opacity(0.08)
                                    }
                                }
                            }

                            // Bottom Gradient Scrim
                            LinearGradient(
                                colors: [
                                    Color.clear,
                                    Color.black.opacity(0.15),
                                    Color.black.opacity(0.65),
                                    Color.black.opacity(0.95)
                                ],
                                startPoint: .center,
                                endPoint: .bottom
                            )

                            // Bottom Overlay: Title, Subtitle, and 2 Big Pill Buttons
                            VStack(spacing: 12) {
                                // Title
                                Text(item.title)
                                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .shadow(color: .black.opacity(0.8), radius: 6, y: 2)
                                    .padding(.horizontal, 16)

                                // Tagline / Subtitle
                                Text(isTV ? "Watch All Episodes Now" : "Watch Now")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.92))
                                    .shadow(color: .black.opacity(0.7), radius: 4)

                                // Action Buttons Row: [Play Show / Movie] [My List]
                                HStack(spacing: 12) {
                                    // Play Button (White filled)
                                    Button {
                                        if isTV {
                                            selectedTVSeriesId = item.id
                                        } else {
                                            selectedMovieId = item.id
                                        }
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: "play.fill")
                                                .font(.system(size: 16, weight: .bold))
                                            Text(isTV ? "Play Show" : "Play Movie")
                                                .font(.system(size: 15, weight: .bold))
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color.white)
                                        .foregroundStyle(.black)
                                        .clipShape(Capsule())
                                        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                                    }

                                    // My List Button (+ / checkmark)
                                    let inList = isTV ? appState.myListManager.isSeriesInList(item.id) : appState.myListManager.isMovieInList(item.id)
                                    Button {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            if isTV {
                                                appState.myListManager.toggleSeries(item.id)
                                            } else {
                                                appState.myListManager.toggleMovie(item.id)
                                            }
                                        }
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: inList ? "checkmark" : "plus")
                                                .font(.system(size: 16, weight: .bold))
                                            Text("My List")
                                                .font(.system(size: 15, weight: .bold))
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color.white.opacity(0.22))
                                        .foregroundStyle(.white)
                                        .clipShape(Capsule())
                                        .overlay(
                                            Capsule()
                                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                        )
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.bottom, 16)
                            }
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
                        .scaleEffect(scale)
                        .rotation3DEffect(.degrees(rotation), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                        .opacity(opacity)
                    }
                    .padding(.horizontal, 20)
                    .tag(vIndex)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 500)
            .padding(.top, 4)
            .padding(.bottom, 10)
            .onAppear {
                if selectedHeroIndex == 0 {
                    selectedHeroIndex = (virtualCount / 2) - ((virtualCount / 2) % count)
                }
            }
        }
    }

    // MARK: - Data Loading
    private func loadFeedData() async {
        if appState.apiConfiguration == nil {
            await appState.loadConfiguration()
        }

        do {
            // Core First-Paint Parallel Fetch
            async let tMFetch = appState.tmdbService.trendingMovies()
            async let tTVFetch = appState.tmdbService.trendingTVSeries()
            async let pMFetch = appState.tmdbService.popularMovies()
            async let pTVFetch = appState.tmdbService.popularTVSeries()
            async let aMFetch = appState.tmdbService.moviesPaginated(for: .criticallyAcclaimed, page: 1)
            async let aTVFetch = appState.tmdbService.tvSeriesPaginated(for: .criticallyAcclaimed, page: 1)
            async let nMFetch = appState.tmdbService.moviesPaginated(for: .newReleases, page: 1)
            async let nTVFetch = appState.tmdbService.tvSeriesPaginated(for: .newReleases, page: 1)
            async let milMFetch = appState.tmdbService.moviesPaginated(for: .millennialFavorites, page: 1)
            async let genZMFetch = appState.tmdbService.moviesPaginated(for: .genZPicks, page: 1)
            async let genXMFetch = appState.tmdbService.moviesPaginated(for: .genXClassics, page: 1)
            async let npMFetch = appState.tmdbService.moviesPaginated(for: .nowPlaying, page: 1)
            async let milTVFetch = appState.tmdbService.tvSeriesPaginated(for: .millennialFavorites, page: 1)
            async let genZTVFetch = appState.tmdbService.tvSeriesPaginated(for: .genZPicks, page: 1)
            async let genXTVFetch = appState.tmdbService.tvSeriesPaginated(for: .genXClassics, page: 1)

            let (tM, tTV, pM, pTV, aM, aTV, nM, nTV, milM, gzM, gxM, npM, milTV, gzTV, gxTV) = try await (
                tMFetch, tTVFetch, pMFetch, pTVFetch, aMFetch, aTVFetch, nMFetch, nTVFetch, milMFetch, genZMFetch, genXMFetch, npMFetch, milTVFetch, genZTVFetch, genXTVFetch
            )

            // Map Movie Rows
            self.trendingMovies = mapMovies(tM)
            self.popularMovies = mapMovies(pM)
            self.acclaimedMovies = mapMovies(aM.items)
            self.newMovies = mapMovies(nM.items)
            self.millennialMovies = mapMovies(milM.items)
            self.genZMovies = mapMovies(gzM.items)
            self.genXMovies = mapMovies(gxM.items)
            self.nowPlayingMovies = mapMovies(npM.items)

            // Movie Hero Banner (Netflix-style portrait posters)
            self.movieHeroItems = tM.prefix(6).map {
                MediaListItem(
                    id: $0.id,
                    title: $0.title,
                    posterURL: ImageURLBuilder.posterURL(for: $0.posterPath, config: appState.apiConfiguration, idealWidth: 780) ?? ImageURLBuilder.backdropURL(for: $0.backdropPath, config: appState.apiConfiguration, idealWidth: 780),
                    rating: $0.voteAverage,
                    releaseYear: $0.releaseDate.map { String(Calendar.current.component(.year, from: $0)) },
                    isTVSeries: false
                )
            }

            // Map TV Rows
            self.trendingTV = mapTV(tTV)
            self.popularTV = mapTV(pTV)
            self.acclaimedTV = mapTV(aTV.items)
            self.newTV = mapTV(nTV.items)
            self.millennialTV = mapTV(milTV.items)
            self.genZTV = mapTV(gzTV.items)
            self.genXTV = mapTV(gxTV.items)

            // TV Hero Banner (Netflix-style portrait posters)
            self.tvHeroItems = tTV.prefix(6).map {
                MediaListItem(
                    id: $0.id,
                    title: $0.name,
                    posterURL: ImageURLBuilder.posterURL(for: $0.posterPath, config: appState.apiConfiguration, idealWidth: 780) ?? ImageURLBuilder.backdropURL(for: $0.backdropPath, config: appState.apiConfiguration, idealWidth: 780),
                    rating: $0.voteAverage,
                    releaseYear: $0.firstAirDate.map { String(Calendar.current.component(.year, from: $0)) },
                    isTVSeries: true
                )
            }

            self.isLoading = false

            // Concurrently fetch Extra Discover Genre Rows
            Task {
                var movieExtras: [(MovieCategory, [iOSMediaRowItem])] = []
                for cat in MovieCategory.catalogDiscoverRows {
                    if let items = try? await appState.tmdbService.moviesPaginated(for: cat, page: 1).items, !items.isEmpty {
                        movieExtras.append((cat, mapMovies(items)))
                    }
                }
                await MainActor.run {
                    self.movieExtraSections = movieExtras
                }
            }

            Task {
                var tvExtras: [(TVCategory, [iOSMediaRowItem])] = []
                for cat in TVCategory.catalogDiscoverRows {
                    if let items = try? await appState.tmdbService.tvSeriesPaginated(for: cat, page: 1).items, !items.isEmpty {
                        tvExtras.append((cat, mapTV(items)))
                    }
                }
                await MainActor.run {
                    self.tvExtraSections = tvExtras
                }
            }

        } catch {
            self.isLoading = false
        }
    }

    private func mapMovies(_ items: [MovieListItem]) -> [iOSMediaRowItem] {
        items.map {
            iOSMediaRowItem(
                id: $0.id,
                title: $0.title,
                posterURL: ImageURLBuilder.posterURL(for: $0.posterPath, config: appState.apiConfiguration, idealWidth: 342),
                rating: $0.voteAverage,
                releaseYear: $0.releaseDate.map { String(Calendar.current.component(.year, from: $0)) },
                isTVSeries: false,
                progress: nil
            )
        }
    }

    private func mapTV(_ items: [TVSeriesListItem]) -> [iOSMediaRowItem] {
        items.map {
            iOSMediaRowItem(
                id: $0.id,
                title: $0.name,
                posterURL: ImageURLBuilder.posterURL(for: $0.posterPath, config: appState.apiConfiguration, idealWidth: 342),
                rating: $0.voteAverage,
                releaseYear: $0.firstAirDate.map { String(Calendar.current.component(.year, from: $0)) },
                isTVSeries: true,
                progress: nil
            )
        }
    }
}
#endif
