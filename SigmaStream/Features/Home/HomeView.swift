//
//  HomeView.swift
//  SigmaStream
//
//  Combined home: trending movies + TV, popular, top rated.
//

import SwiftUI
import TMDb

struct HomeView: View {
    var shouldLoad: Bool = true
    var onLoadComplete: (() -> Void)? = nil

    @Environment(AppState.self) private var appState
    @State private var trendingMovies: [MovieListItem] = []
    @State private var trendingTV: [TVSeriesListItem] = []
    @State private var popularMovies: [MovieListItem] = []
    @State private var popularTV: [TVSeriesListItem] = []
    @State private var topRatedMovies: [MovieListItem] = []
    @State private var topRatedTV: [TVSeriesListItem] = []
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
                        MovieMediaRow(
                            title: "Trending Movies",
                            movies: trendingMovies,
                            config: appState.apiConfiguration,
                            onSelect: { movie in selectedMovie = MovieSelection(id: movie.id) },
                            onSeeAll: { movieCategoryForSeeAll = MovieCategorySeeAll(category: .trendingToday) }
                        )

                        TVSeriesMediaRow(
                            title: "Trending TV",
                            tvSeries: trendingTV,
                            config: appState.apiConfiguration,
                            onSelect: { series in selectedSeries = TVSeriesSelection(id: series.id) },
                            onSeeAll: { tvCategoryForSeeAll = TVCategorySeeAll(category: .trendingToday) }
                        )

                        MovieMediaRow(
                            title: "Popular Movies",
                            movies: popularMovies,
                            config: appState.apiConfiguration,
                            onSelect: { movie in selectedMovie = MovieSelection(id: movie.id) },
                            onSeeAll: { movieCategoryForSeeAll = MovieCategorySeeAll(category: .popular) }
                        )

                        TVSeriesMediaRow(
                            title: "Popular TV",
                            tvSeries: popularTV,
                            config: appState.apiConfiguration,
                            onSelect: { series in selectedSeries = TVSeriesSelection(id: series.id) },
                            onSeeAll: { tvCategoryForSeeAll = TVCategorySeeAll(category: .popular) }
                        )

                        MovieMediaRow(
                            title: "Top Rated Movies",
                            movies: topRatedMovies,
                            config: appState.apiConfiguration,
                            onSelect: { movie in selectedMovie = MovieSelection(id: movie.id) },
                            onSeeAll: { movieCategoryForSeeAll = MovieCategorySeeAll(category: .topRated) }
                        )

                        TVSeriesMediaRow(
                            title: "Top Rated TV",
                            tvSeries: topRatedTV,
                            config: appState.apiConfiguration,
                            onSelect: { series in selectedSeries = TVSeriesSelection(id: series.id) },
                            onSeeAll: { tvCategoryForSeeAll = TVCategorySeeAll(category: .topRated) }
                        )
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
                onLoadComplete?()
            }
        }
    }

    private func loadData() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            async let moviesTrending = appState.tmdbService.trendingMovies()
            async let tvTrending = appState.tmdbService.trendingTVSeries()
            async let moviesPopular = appState.tmdbService.popularMovies()
            async let tvPopular = appState.tmdbService.popularTVSeries()
            async let moviesTopRated = appState.tmdbService.topRatedMovies()
            async let tvTopRated = appState.tmdbService.topRatedTVSeries()

            trendingMovies = try await moviesTrending
            trendingTV = try await tvTrending
            popularMovies = try await moviesPopular
            popularTV = try await tvPopular
            topRatedMovies = try await moviesTopRated
            topRatedTV = try await tvTopRated
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
        onLoadComplete?()
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
