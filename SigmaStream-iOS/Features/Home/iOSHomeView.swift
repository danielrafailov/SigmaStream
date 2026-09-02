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

    // Detail Navigation
    @State private var selectedMovieId: Int?
    @State private var selectedTVSeriesId: Int?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top Category Toggle Bar (Movies / TV Shows)
                Picker("Category", selection: $selectedSection) {
                    Text("🎬 Movies").tag(HomeTabSection.movies)
                    Text("📺 TV Shows").tag(HomeTabSection.tvShows)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 8)

                ScrollView {
                    VStack(spacing: 24) {
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
            .navigationTitle("SigmaStream")
            .navigationBarTitleDisplayMode(.inline)
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
            .task {
                await loadFeedData()
            }
        }
    }

    // MARK: - Movies Catalog
    @ViewBuilder
    private var moviesCatalogView: some View {
        // Hero Carousel
        if !movieHeroItems.isEmpty {
            heroCarousel(items: movieHeroItems, isTV: false)
        }

        // Core Shelves
        if !trendingMovies.isEmpty {
            iOSMediaRow(title: "Trending Movies", items: trendingMovies) { item in
                selectedMovieId = item.id
            }
        }

        if !popularMovies.isEmpty {
            iOSMediaRow(title: MovieCategory.popular.rawValue, items: popularMovies) { item in
                selectedMovieId = item.id
            }
        }

        if !newMovies.isEmpty {
            iOSMediaRow(title: MovieCategory.newReleases.rawValue, items: newMovies) { item in
                selectedMovieId = item.id
            }
        }

        if !acclaimedMovies.isEmpty {
            iOSMediaRow(title: MovieCategory.criticallyAcclaimed.rawValue, items: acclaimedMovies) { item in
                selectedMovieId = item.id
            }
        }

        if !millennialMovies.isEmpty {
            iOSMediaRow(title: MovieCategory.millennialFavorites.rawValue, items: millennialMovies) { item in
                selectedMovieId = item.id
            }
        }

        if !genZMovies.isEmpty {
            iOSMediaRow(title: MovieCategory.genZPicks.rawValue, items: genZMovies) { item in
                selectedMovieId = item.id
            }
        }

        if !genXMovies.isEmpty {
            iOSMediaRow(title: MovieCategory.genXClassics.rawValue, items: genXMovies) { item in
                selectedMovieId = item.id
            }
        }

        if !nowPlayingMovies.isEmpty {
            iOSMediaRow(title: MovieCategory.nowPlaying.rawValue, items: nowPlayingMovies) { item in
                selectedMovieId = item.id
            }
        }

        // Extra Genre Discover Shelves
        ForEach(movieExtraSections, id: \.0) { cat, items in
            if !items.isEmpty {
                iOSMediaRow(title: cat.rawValue, items: items) { item in
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

        // Core TV Shelves
        if !trendingTV.isEmpty {
            iOSMediaRow(title: "Trending TV Shows", items: trendingTV) { item in
                selectedTVSeriesId = item.id
            }
        }

        if !popularTV.isEmpty {
            iOSMediaRow(title: TVCategory.popular.rawValue, items: popularTV) { item in
                selectedTVSeriesId = item.id
            }
        }

        if !newTV.isEmpty {
            iOSMediaRow(title: TVCategory.newReleases.rawValue, items: newTV) { item in
                selectedTVSeriesId = item.id
            }
        }

        if !acclaimedTV.isEmpty {
            iOSMediaRow(title: TVCategory.criticallyAcclaimed.rawValue, items: acclaimedTV) { item in
                selectedTVSeriesId = item.id
            }
        }

        if !millennialTV.isEmpty {
            iOSMediaRow(title: TVCategory.millennialFavorites.rawValue, items: millennialTV) { item in
                selectedTVSeriesId = item.id
            }
        }

        if !genZTV.isEmpty {
            iOSMediaRow(title: TVCategory.genZPicks.rawValue, items: genZTV) { item in
                selectedTVSeriesId = item.id
            }
        }

        if !genXTV.isEmpty {
            iOSMediaRow(title: TVCategory.genXClassics.rawValue, items: genXTV) { item in
                selectedTVSeriesId = item.id
            }
        }

        // Extra TV Discover Shelves
        ForEach(tvExtraSections, id: \.0) { cat, items in
            if !items.isEmpty {
                iOSMediaRow(title: cat.rawValue, items: items) { item in
                    selectedTVSeriesId = item.id
                }
            }
        }
    }

    // MARK: - Hero Backdrop Carousel
    private func heroCarousel(items: [MediaListItem], isTV: Bool) -> some View {
        TabView(selection: $selectedHeroIndex) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                ZStack(alignment: .bottomLeading) {
                    // Backdrop Image
                    if let posterURL = item.posterURL {
                        AsyncImage(url: posterURL) { phase in
                            if let img = phase.image {
                                img
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } else {
                                Color.white.opacity(0.08)
                            }
                        }
                    }

                    // Gradient Scrim
                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.7), Color.black.opacity(0.95)],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    // Details & Quick Action
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.title)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        HStack(spacing: 12) {
                            if let year = item.releaseYear {
                                Text(year)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            if let rating = item.rating, rating > 0 {
                                HStack(spacing: 3) {
                                    Image(systemName: "star.fill")
                                        .font(.caption)
                                        .foregroundStyle(.yellow)
                                    Text(String(format: "%.1f", rating))
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.white)
                                }
                            }
                        }

                        // Play Button
                        Button {
                            if isTV {
                                selectedTVSeriesId = item.id
                            } else {
                                selectedMovieId = item.id
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "play.fill")
                                Text(isTV ? "View Show" : "Watch Now")
                            }
                            .font(.subheadline.bold())
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.white)
                            .foregroundStyle(.black)
                            .clipShape(Capsule())
                        }
                        .padding(.top, 4)
                    }
                    .padding(20)
                }
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .frame(height: 360)
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

            // Movie Hero Banner
            self.movieHeroItems = tM.prefix(5).map {
                MediaListItem(
                    id: $0.id,
                    title: $0.title,
                    posterURL: ImageURLBuilder.backdropURL(for: $0.backdropPath, config: appState.apiConfiguration, idealWidth: 780) ?? ImageURLBuilder.posterURL(for: $0.posterPath, config: appState.apiConfiguration, idealWidth: 780),
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

            // TV Hero Banner
            self.tvHeroItems = tTV.prefix(5).map {
                MediaListItem(
                    id: $0.id,
                    title: $0.name,
                    posterURL: ImageURLBuilder.backdropURL(for: $0.backdropPath, config: appState.apiConfiguration, idealWidth: 780) ?? ImageURLBuilder.posterURL(for: $0.posterPath, config: appState.apiConfiguration, idealWidth: 780),
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
