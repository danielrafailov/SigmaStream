//
//  HomeView.swift
//  SigmaStream
//
//  Home: My List / Liked rows plus Movies and TV catalog shelves. (Continue Watching and Because you watched live under For You only.)
//

import SwiftUI
import TMDb

struct HomeView: View {
    var shouldLoad: Bool = true
    var onLoadComplete: (() -> Void)? = nil

    @Environment(AppState.self) private var appState

    // MARK: - Personal (Home tab: My List + Liked only)

    @State private var myListMovies: [MovieListItem] = []
    @State private var myListSeries: [TVSeriesListItem] = []
    @State private var likedMovies: [MovieListItem] = []
    @State private var likedSeries: [TVSeriesListItem] = []

    // MARK: - Movies tab catalog

    @State private var trendingMovies: [MovieListItem] = []
    @State private var popularMovies: [MovieListItem] = []
    @State private var acclaimedMovies: [MovieListItem] = []
    @State private var newMovies: [MovieListItem] = []
    @State private var millennialMovies: [MovieListItem] = []
    @State private var genZMovies: [MovieListItem] = []
    @State private var genXMovies: [MovieListItem] = []
    @State private var nowPlayingMovies: [MovieListItem] = []
    @State private var movieExtraSections: [(MovieCategory, [MovieListItem])] = []

    // MARK: - TV tab catalog

    @State private var trendingTV: [TVSeriesListItem] = []
    @State private var popularTV: [TVSeriesListItem] = []
    @State private var acclaimedTV: [TVSeriesListItem] = []
    @State private var newTV: [TVSeriesListItem] = []
    @State private var millennialTV: [TVSeriesListItem] = []
    @State private var genZTV: [TVSeriesListItem] = []
    @State private var genXTV: [TVSeriesListItem] = []
    @State private var tvExtraSections: [(TVCategory, [TVSeriesListItem])] = []

    @State private var isLoading = false
    /// When true, core catalog shelves (trending/popular/…) may render even while genre rows or personal data still load.
    @State private var catalogFirstPaintReady = false
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

                    if !catalogFirstPaintReady && errorMessage == nil {
                        ProgressView("Loading...")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                    } else {
                        personalBlock

                        movieCatalogRow(title: "Trending Movies", movies: trendingMovies, category: .trendingToday)
                        movieCatalogRow(title: MovieCategory.popular.rawValue, movies: popularMovies, category: .popular)
                        movieCatalogRow(title: MovieCategory.newReleases.rawValue, movies: newMovies, category: .newReleases)
                        movieCatalogRow(title: MovieCategory.criticallyAcclaimed.rawValue, movies: acclaimedMovies, category: .criticallyAcclaimed)
                        movieCatalogRow(title: MovieCategory.millennialFavorites.rawValue, movies: millennialMovies, category: .millennialFavorites)
                        movieCatalogRow(title: MovieCategory.genZPicks.rawValue, movies: genZMovies, category: .genZPicks)
                        movieCatalogRow(title: MovieCategory.genXClassics.rawValue, movies: genXMovies, category: .genXClassics)
                        movieCatalogRow(title: MovieCategory.nowPlaying.rawValue, movies: nowPlayingMovies, category: .nowPlaying)

                        ForEach(movieExtraSections, id: \.0) { cat, items in
                            if !items.isEmpty {
                                movieCatalogRow(title: cat.rawValue, movies: items, category: cat)
                            }
                        }

                        tvCatalogRow(title: "Trending TV", series: trendingTV, category: .trendingToday)
                        tvCatalogRow(title: TVCategory.popular.rawValue, series: popularTV, category: .popular)
                        tvCatalogRow(title: TVCategory.newReleases.rawValue, series: newTV, category: .newReleases)
                        tvCatalogRow(title: TVCategory.criticallyAcclaimed.rawValue, series: acclaimedTV, category: .criticallyAcclaimed)
                        tvCatalogRow(title: TVCategory.millennialFavorites.rawValue, series: millennialTV, category: .millennialFavorites)
                        tvCatalogRow(title: TVCategory.genZPicks.rawValue, series: genZTV, category: .genZPicks)
                        tvCatalogRow(title: TVCategory.genXClassics.rawValue, series: genXTV, category: .genXClassics)

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
            .background(Color.black.ignoresSafeArea())
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
        catalogFirstPaintReady = false
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
            async let moviesMillennial = appState.tmdbService.moviesPaginated(for: .millennialFavorites, page: 1).items
            async let moviesGenZ = appState.tmdbService.moviesPaginated(for: .genZPicks, page: 1).items
            async let moviesGenX = appState.tmdbService.moviesPaginated(for: .genXClassics, page: 1).items
            async let tvMillennial = appState.tmdbService.tvSeriesPaginated(for: .millennialFavorites, page: 1).items
            async let tvGenZ = appState.tmdbService.tvSeriesPaginated(for: .genZPicks, page: 1).items
            async let tvGenX = appState.tmdbService.tvSeriesPaginated(for: .genXClassics, page: 1).items
            async let moviesNowPlaying = appState.tmdbService.nowPlayingMovies()

            let (
                tM, tTV, pM, pTV,
                aM, aTV, nM, nTV,
                millennialM, genZM, genXM,
                millennialTVRows, genZTVRows, genXTVRows,
                npM
            ) = try await (
                moviesTrending, tvTrending, moviesPopular, tvPopular,
                moviesAcclaimed, tvAcclaimed, moviesNew, tvNew,
                moviesMillennial, moviesGenZ, moviesGenX,
                tvMillennial, tvGenZ, tvGenX,
                moviesNowPlaying
            )

            trendingMovies = tM
            trendingTV = tTV
            popularMovies = pM
            popularTV = pTV
            acclaimedMovies = aM
            acclaimedTV = aTV
            newMovies = nM
            newTV = nTV
            millennialMovies = millennialM
            genZMovies = genZM
            genXMovies = genXM
            millennialTV = millennialTVRows
            genZTV = genZTVRows
            genXTV = genXTVRows
            nowPlayingMovies = npM

            catalogFirstPaintReady = true

            let (movieList, tvList, _) = await PerformanceSignposts.interval(log: PerformanceSignposts.homeLoad, name: "ExtrasAndPersonal") {
                async let movieExtrasRows = ConcurrentCatalogDiscoverFetch.mapLimited(
                    items: MovieCategory.catalogDiscoverRows,
                    name: "HomeMovieDiscover"
                ) { cat in
                    let items = (try? await appState.tmdbService.moviesPaginated(for: cat, page: 1).items) ?? []
                    return (cat, items)
                }
                async let tvExtrasRows = ConcurrentCatalogDiscoverFetch.mapLimited(
                    items: TVCategory.catalogDiscoverRows,
                    name: "HomeTVDiscover"
                ) { cat in
                    let items = (try? await appState.tmdbService.tvSeriesPaginated(for: cat, page: 1).items) ?? []
                    return (cat, items)
                }
                async let personalVoid: Void = refreshPersonalContent()
                return await (movieExtrasRows, tvExtrasRows, personalVoid)
            }

            movieExtraSections = MovieCategory.catalogDiscoverRows.compactMap { c in movieList.first { $0.0 == c } }
            tvExtraSections = TVCategory.catalogDiscoverRows.compactMap { c in tvList.first { $0.0 == c } }
        } catch {
            errorMessage = error.localizedDescription
            catalogFirstPaintReady = true
        }

        isLoading = false
        onLoadComplete?()
    }

    private func refreshPersonalContent() async {
        await loadMyListMapped()
        await loadLikedMapped()
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

    private static func tvSeriesListItem(from series: TVSeries) -> TVSeriesListItem {
        TVSeriesListItem(
            id: series.id,
            name: series.name,
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
