//
//  HomeView.swift
//  SigmaStream
//
//  Aggregates For You (personal), Movies tab rows, and TV Shows tab rows.
//

import SwiftUI
import TMDb

struct HomeView: View {
    var shouldLoad: Bool = true
    var onLoadComplete: (() -> Void)? = nil

    @Environment(AppState.self) private var appState

    // MARK: - For You (personal)

    @State private var becauseYouWatchedTitle: String?
    @State private var becauseYouWatchedMovies: [MovieListItem] = []
    @State private var becauseYouWatchedSeries: [TVSeriesListItem] = []
    @State private var becauseYouWatchedIsMovie = false
    @State private var myListMovies: [MovieListItem] = []
    @State private var myListSeries: [TVSeriesListItem] = []
    @State private var continueWatchingMovies: [MovieListItem] = []
    @State private var continueWatchingTV: [TVSeriesListItem] = []
    @State private var likedMovies: [MovieListItem] = []
    @State private var likedSeries: [TVSeriesListItem] = []

    // MARK: - Movies tab catalog

    @State private var trendingMovies: [MovieListItem] = []
    @State private var popularMovies: [MovieListItem] = []
    @State private var acclaimedMovies: [MovieListItem] = []
    @State private var newMovies: [MovieListItem] = []
    @State private var upcomingMovies: [MovieListItem] = []
    @State private var nowPlayingMovies: [MovieListItem] = []
    @State private var movieExtraSections: [(MovieCategory, [MovieListItem])] = []

    // MARK: - TV tab catalog

    @State private var trendingTV: [TVSeriesListItem] = []
    @State private var popularTV: [TVSeriesListItem] = []
    @State private var acclaimedTV: [TVSeriesListItem] = []
    @State private var newTV: [TVSeriesListItem] = []
    @State private var tvExtraSections: [(TVCategory, [TVSeriesListItem])] = []

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedMovie: MovieSelection?
    @State private var selectedSeries: TVSeriesSelection?
    @State private var movieCategoryForSeeAll: MovieCategorySeeAll?
    @State private var tvCategoryForSeeAll: TVCategorySeeAll?

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 48) {
                    if let error = errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .padding()
                    }

                    if trendingMovies.isEmpty && errorMessage == nil {
                        ProgressView("Loading...")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                    } else {
                        personalBlock

                        movieCatalogRow(title: "Trending Movies", movies: trendingMovies, category: .trendingToday)
                        movieCatalogRow(title: MovieCategory.popular.rawValue, movies: popularMovies, category: .popular)
                        movieCatalogRow(title: MovieCategory.criticallyAcclaimed.rawValue, movies: acclaimedMovies, category: .criticallyAcclaimed)
                        movieCatalogRow(title: MovieCategory.newReleases.rawValue, movies: newMovies, category: .newReleases)
                        movieCatalogRow(title: MovieCategory.upcoming.rawValue, movies: upcomingMovies, category: .upcoming)
                        movieCatalogRow(title: MovieCategory.nowPlaying.rawValue, movies: nowPlayingMovies, category: .nowPlaying)

                        ForEach(movieExtraSections, id: \.0) { cat, items in
                            if !items.isEmpty {
                                movieCatalogRow(title: cat.rawValue, movies: items, category: cat)
                            }
                        }

                        tvCatalogRow(title: "Trending TV", series: trendingTV, category: .trendingToday)
                        tvCatalogRow(title: TVCategory.popular.rawValue, series: popularTV, category: .popular)
                        tvCatalogRow(title: TVCategory.criticallyAcclaimed.rawValue, series: acclaimedTV, category: .criticallyAcclaimed)
                        tvCatalogRow(title: TVCategory.newReleases.rawValue, series: newTV, category: .newReleases)

                        ForEach(tvExtraSections, id: \.0) { cat, items in
                            if !items.isEmpty {
                                tvCatalogRow(title: cat.rawValue, series: items, category: cat)
                            }
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical)
            }
            .navigationTitle("")
            .navigationDestination(item: $selectedMovie) { selection in
                MovieDetailView(movieId: selection.id)
            }
            .navigationDestination(item: $selectedSeries) { selection in
                TVSeriesDetailView(seriesId: selection.id)
            }
            .navigationDestination(item: $movieCategoryForSeeAll) { wrapper in
                MovieCategoryListView(category: wrapper.category)
            }
            .navigationDestination(item: $tvCategoryForSeeAll) { wrapper in
                TVCategoryListView(category: wrapper.category)
            }
            .task(id: shouldLoad) {
                guard shouldLoad else { return }
                await loadData()
            }
            .onReceive(NotificationCenter.default.publisher(for: WatchProgressManager.continueWatchingDidChange)) { _ in
                Task { await refreshPersonalContent() }
            }
            .onChange(of: appState.myListManager.movieIds.count) { _, _ in
                Task { await refreshPersonalContent() }
            }
            .onChange(of: appState.myListManager.seriesIds.count) { _, _ in
                Task { await refreshPersonalContent() }
            }
            .onChange(of: appState.likedManager.movieIds.count) { _, _ in
                Task { await refreshPersonalContent() }
            }
            .onChange(of: appState.likedManager.seriesIds.count) { _, _ in
                Task { await refreshPersonalContent() }
            }
        }
    }

    // MARK: - Personal UI

    @ViewBuilder
    private var personalBlock: some View {
        Group {
            becauseYouWatchedBlock

            if !myListMovies.isEmpty {
                MovieMediaRow(
                    title: "My List",
                    movies: myListMovies,
                    config: appState.apiConfiguration,
                    onSelect: { selectedMovie = MovieSelection(id: $0.id) }
                )
            }
            if !myListSeries.isEmpty {
                TVSeriesMediaRow(
                    title: "My List (TV)",
                    tvSeries: myListSeries,
                    config: appState.apiConfiguration,
                    onSelect: { selectedSeries = TVSeriesSelection(id: $0.id) }
                )
            }
            if !continueWatchingMovies.isEmpty {
                MovieMediaRow(
                    title: "Continue Watching",
                    movies: continueWatchingMovies,
                    config: appState.apiConfiguration,
                    onSelect: { selectedMovie = MovieSelection(id: $0.id) }
                )
            }
            if !continueWatchingTV.isEmpty {
                TVSeriesMediaRow(
                    title: "Continue Watching (TV)",
                    tvSeries: continueWatchingTV,
                    config: appState.apiConfiguration,
                    onSelect: { selectedSeries = TVSeriesSelection(id: $0.id) }
                )
            }
            if !likedMovies.isEmpty {
                MovieMediaRow(
                    title: "Liked Movies",
                    movies: likedMovies,
                    config: appState.apiConfiguration,
                    onSelect: { selectedMovie = MovieSelection(id: $0.id) }
                )
            }
            if !likedSeries.isEmpty {
                TVSeriesMediaRow(
                    title: "Liked TV",
                    tvSeries: likedSeries,
                    config: appState.apiConfiguration,
                    onSelect: { selectedSeries = TVSeriesSelection(id: $0.id) }
                )
            }
        }
    }

    @ViewBuilder
    private var becauseYouWatchedBlock: some View {
        if let title = becauseYouWatchedTitle {
            if becauseYouWatchedIsMovie, !becauseYouWatchedMovies.isEmpty {
                MovieMediaRow(
                    title: "Because you watched \(title)",
                    movies: becauseYouWatchedMovies,
                    config: appState.apiConfiguration,
                    onSelect: { selectedMovie = MovieSelection(id: $0.id) }
                )
            } else if !becauseYouWatchedIsMovie, !becauseYouWatchedSeries.isEmpty {
                TVSeriesMediaRow(
                    title: "Because you watched \(title)",
                    tvSeries: becauseYouWatchedSeries,
                    config: appState.apiConfiguration,
                    onSelect: { selectedSeries = TVSeriesSelection(id: $0.id) }
                )
            }
        }
    }

    @ViewBuilder
    private func movieCatalogRow(title: String, movies: [MovieListItem], category: MovieCategory) -> some View {
        MovieMediaRow(
            title: title,
            movies: movies,
            config: appState.apiConfiguration,
            onSelect: { selectedMovie = MovieSelection(id: $0.id) },
            onSeeAll: { movieCategoryForSeeAll = MovieCategorySeeAll(category: category) }
        )
    }

    @ViewBuilder
    private func tvCatalogRow(title: String, series: [TVSeriesListItem], category: TVCategory) -> some View {
        TVSeriesMediaRow(
            title: title,
            tvSeries: series,
            config: appState.apiConfiguration,
            onSelect: { selectedSeries = TVSeriesSelection(id: $0.id) },
            onSeeAll: { tvCategoryForSeeAll = TVCategorySeeAll(category: category) }
        )
    }

    // MARK: - Loading

    private func loadData() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            async let moviesTrending = appState.tmdbService.trendingMovies(inTimeWindow: .day)
            async let tvTrending = appState.tmdbService.trendingTVSeries(inTimeWindow: .day)
            async let moviesPopular = appState.tmdbService.popularMovies()
            async let tvPopular = appState.tmdbService.popularTVSeries()
            async let moviesAcclaimed = appState.tmdbService.criticallyAcclaimedMovies()
            async let tvAcclaimed = appState.tmdbService.criticallyAcclaimedTVSeries()
            async let moviesNew = appState.tmdbService.recentReleaseMovies()
            async let tvNew = appState.tmdbService.recentReleaseTVSeries()
            async let moviesUpcoming = appState.tmdbService.upcomingMovies()
            async let moviesNowPlaying = appState.tmdbService.nowPlayingMovies()

            trendingMovies = try await moviesTrending
            trendingTV = try await tvTrending
            popularMovies = try await moviesPopular
            popularTV = try await tvPopular
            acclaimedMovies = try await moviesAcclaimed
            acclaimedTV = try await tvAcclaimed
            newMovies = try await moviesNew
            newTV = try await tvNew
            upcomingMovies = try await moviesUpcoming
            nowPlayingMovies = try await moviesNowPlaying

            var moviePairs: [(MovieCategory, [MovieListItem])] = []
            await withTaskGroup(of: (MovieCategory, [MovieListItem]).self) { group in
                for cat in MovieCategory.catalogDiscoverRows {
                    group.addTask {
                        let items = (try? await appState.tmdbService.moviesPaginated(for: cat, page: 1).items) ?? []
                        return (cat, items)
                    }
                }
                for await p in group { moviePairs.append(p) }
            }
            movieExtraSections = MovieCategory.catalogDiscoverRows.compactMap { c in moviePairs.first { $0.0 == c } }

            var tvPairs: [(TVCategory, [TVSeriesListItem])] = []
            await withTaskGroup(of: (TVCategory, [TVSeriesListItem]).self) { group in
                for cat in TVCategory.catalogDiscoverRows {
                    group.addTask {
                        let items = (try? await appState.tmdbService.tvSeriesPaginated(for: cat, page: 1).items) ?? []
                        return (cat, items)
                    }
                }
                for await p in group { tvPairs.append(p) }
            }
            tvExtraSections = TVCategory.catalogDiscoverRows.compactMap { c in tvPairs.first { $0.0 == c } }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
        await refreshPersonalContent()
        onLoadComplete?()
    }

    private func refreshPersonalContent() async {
        await loadBecauseYouWatched()
        await loadMyListMapped()
        await loadContinueWatchingMapped()
        await loadLikedMapped()
    }

    private func loadBecauseYouWatched() async {
        becauseYouWatchedTitle = nil
        becauseYouWatchedMovies = []
        becauseYouWatchedSeries = []

        let lastMovie = appState.watchProgressManager.watchedMovies.first
        let lastEpisode = appState.watchProgressManager.watchedEpisodes.first

        var sourceId = 0
        var sourceTitle: String?
        var isMovie = false

        if let movie = lastMovie, let episode = lastEpisode {
            if movie.lastWatchedAt >= episode.lastWatchedAt {
                guard let details = try? await appState.tmdbService.movieDetails(forMovieId: movie.movieId) else { return }
                sourceId = movie.movieId
                sourceTitle = details.title
                isMovie = true
            } else {
                guard let details = try? await appState.tmdbService.tvSeriesDetails(forSeriesId: episode.seriesId) else { return }
                sourceId = episode.seriesId
                sourceTitle = details.name
                isMovie = false
            }
        } else if let movie = lastMovie,
                  let details = try? await appState.tmdbService.movieDetails(forMovieId: movie.movieId) {
            sourceId = movie.movieId
            sourceTitle = details.title
            isMovie = true
        } else if let episode = lastEpisode,
                  let details = try? await appState.tmdbService.tvSeriesDetails(forSeriesId: episode.seriesId) {
            sourceId = episode.seriesId
            sourceTitle = details.name
            isMovie = false
        } else {
            return
        }

        guard let title = sourceTitle, !title.isEmpty else { return }

        do {
            if isMovie {
                let items = try await appState.tmdbService.movieRecommendations(forMovieId: sourceId)
                becauseYouWatchedTitle = title
                becauseYouWatchedMovies = Array(items.prefix(12))
                becauseYouWatchedIsMovie = true
            } else {
                let items = try await appState.tmdbService.tvSeriesRecommendations(forSeriesId: sourceId)
                becauseYouWatchedTitle = title
                becauseYouWatchedSeries = Array(items.prefix(12))
                becauseYouWatchedIsMovie = false
            }
        } catch {}
    }

    private func loadMyListMapped() async {
        var movies: [MovieListItem] = []
        for id in appState.myListManager.movieIds {
            if let m = try? await appState.tmdbService.movieDetails(forMovieId: id) {
                movies.append(Self.movieListItem(from: m))
            }
        }
        myListMovies = movies

        var series: [TVSeriesListItem] = []
        for id in appState.myListManager.seriesIds {
            if let s = try? await appState.tmdbService.tvSeriesDetails(forSeriesId: id) {
                series.append(Self.tvSeriesListItem(from: s))
            }
        }
        myListSeries = series
    }

    private func loadContinueWatchingMapped() async {
        var movies: [MovieListItem] = []
        for id in appState.watchProgressManager.watchedMovies.map(\.movieId) {
            if let m = try? await appState.tmdbService.movieDetails(forMovieId: id) {
                movies.append(Self.movieListItem(from: m))
            }
        }
        continueWatchingMovies = movies

        var tvRows: [TVSeriesListItem] = []
        for ep in appState.watchProgressManager.watchedEpisodes {
            if let s = try? await appState.tmdbService.tvSeriesDetails(forSeriesId: ep.seriesId) {
                tvRows.append(Self.tvSeriesListItem(from: s, progressLabel: "S\(ep.season)E\(ep.episode)"))
            }
        }
        continueWatchingTV = tvRows
    }

    private func loadLikedMapped() async {
        var movies: [MovieListItem] = []
        for id in appState.likedManager.movieIds {
            if let m = try? await appState.tmdbService.movieDetails(forMovieId: id) {
                movies.append(Self.movieListItem(from: m))
            }
        }
        likedMovies = movies

        var series: [TVSeriesListItem] = []
        for id in appState.likedManager.seriesIds {
            if let s = try? await appState.tmdbService.tvSeriesDetails(forSeriesId: id) {
                series.append(Self.tvSeriesListItem(from: s))
            }
        }
        likedSeries = series
    }

    private static func movieListItem(from movie: Movie) -> MovieListItem {
        MovieListItem(
            id: movie.id,
            title: movie.title,
            originalTitle: movie.originalTitle ?? movie.title,
            originalLanguage: movie.originalLanguage ?? "en",
            overview: movie.overview ?? "",
            genreIDs: (movie.genres ?? []).map(\.id),
            releaseDate: movie.releaseDate,
            posterPath: movie.posterPath,
            backdropPath: movie.backdropPath,
            popularity: movie.popularity,
            voteAverage: movie.voteAverage,
            voteCount: movie.voteCount,
            hasVideo: movie.hasVideo,
            isAdultOnly: movie.isAdultOnly
        )
    }

    private static func tvSeriesListItem(from series: TVSeries, progressLabel: String? = nil) -> TVSeriesListItem {
        let displayName: String = {
            guard let progressLabel else { return series.name }
            return "\(series.name) · \(progressLabel)"
        }()
        return TVSeriesListItem(
            id: series.id,
            name: displayName,
            originalName: series.originalName ?? series.name,
            originalLanguage: series.originalLanguage ?? "en",
            overview: series.overview ?? "",
            genreIDs: (series.genres ?? []).map(\.id),
            firstAirDate: series.firstAirDate,
            originCountries: series.originCountry ?? [],
            posterPath: series.posterPath,
            backdropPath: series.backdropPath,
            popularity: series.popularity,
            voteAverage: series.voteAverage,
            voteCount: series.voteCount,
            isAdultOnly: series.isAdultOnly
        )
    }
}

private struct MovieCategorySeeAll: Identifiable, Hashable {
    let id = UUID()
    let category: MovieCategory
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: MovieCategorySeeAll, rhs: MovieCategorySeeAll) -> Bool { lhs.id == rhs.id }
}

private struct TVCategorySeeAll: Identifiable, Hashable {
    let id = UUID()
    let category: TVCategory
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: TVCategorySeeAll, rhs: TVCategorySeeAll) -> Bool { lhs.id == rhs.id }
}

#Preview {
    HomeView(shouldLoad: true)
        .environment(AppState(apiKey: "placeholder"))
}
