//
//  MoviesView.swift
//  SigmaStream
//
//  Created by Daniel Rafailov on 2026-03-16.
//

import SwiftUI
import TMDb

/// Wrapper for navigation to category See All (Identifiable, Hashable for navigationDestination).
private struct MovieCategorySeeAll: Identifiable, Hashable {
    let id = UUID()
    let category: MovieCategory

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: MovieCategorySeeAll, rhs: MovieCategorySeeAll) -> Bool { lhs.id == rhs.id }
}

struct MoviesView: View {
    var shouldLoad: Bool = true
    var onLoadComplete: (() -> Void)? = nil

    @Environment(AppState.self) private var appState
    @State private var trending: [MovieListItem] = []
    @State private var popular: [MovieListItem] = []
    @State private var topRated: [MovieListItem] = []
    @State private var nowPlaying: [MovieListItem] = []
    @State private var upcoming: [MovieListItem] = []
    @State private var documentaries: [MovieListItem] = []
    @State private var action: [MovieListItem] = []
    @State private var comedy: [MovieListItem] = []
    @State private var drama: [MovieListItem] = []
    @State private var horror: [MovieListItem] = []
    @State private var romance: [MovieListItem] = []
    @State private var sciFi: [MovieListItem] = []
    @State private var thriller: [MovieListItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedMovie: MovieSelection?
    @State private var categoryForSeeAll: MovieCategorySeeAll?

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 48) {
                    if let error = errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .padding()
                    }

                    if isLoading && trending.isEmpty {
                        ProgressView("Loading...")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                    } else {
                        MovieMediaRow(
                            title: "Trending Today",
                            movies: trending,
                            config: appState.apiConfiguration,
                            onSelect: { movie in selectedMovie = MovieSelection(id: movie.id) },
                            onSeeAll: { categoryForSeeAll = MovieCategorySeeAll(category: .trendingToday) }
                        )

                        MovieMediaRow(
                            title: "Popular",
                            movies: popular,
                            config: appState.apiConfiguration,
                            onSelect: { movie in selectedMovie = MovieSelection(id: movie.id) },
                            onSeeAll: { categoryForSeeAll = MovieCategorySeeAll(category: .popular) }
                        )

                        MovieMediaRow(
                            title: "Top Rated",
                            movies: topRated,
                            config: appState.apiConfiguration,
                            onSelect: { movie in selectedMovie = MovieSelection(id: movie.id) },
                            onSeeAll: { categoryForSeeAll = MovieCategorySeeAll(category: .topRated) }
                        )

                        MovieMediaRow(
                            title: "Now Playing",
                            movies: nowPlaying,
                            config: appState.apiConfiguration,
                            onSelect: { movie in selectedMovie = MovieSelection(id: movie.id) },
                            onSeeAll: { categoryForSeeAll = MovieCategorySeeAll(category: .nowPlaying) }
                        )

                        MovieMediaRow(
                            title: "Upcoming",
                            movies: upcoming,
                            config: appState.apiConfiguration,
                            onSelect: { movie in selectedMovie = MovieSelection(id: movie.id) },
                            onSeeAll: { categoryForSeeAll = MovieCategorySeeAll(category: .upcoming) }
                        )

                        MovieMediaRow(
                            title: "Documentaries",
                            movies: documentaries,
                            config: appState.apiConfiguration,
                            onSelect: { movie in selectedMovie = MovieSelection(id: movie.id) },
                            onSeeAll: { categoryForSeeAll = MovieCategorySeeAll(category: .documentaries) }
                        )

                        MovieMediaRow(
                            title: "Action",
                            movies: action,
                            config: appState.apiConfiguration,
                            onSelect: { movie in selectedMovie = MovieSelection(id: movie.id) },
                            onSeeAll: { categoryForSeeAll = MovieCategorySeeAll(category: .action) }
                        )
                        MovieMediaRow(
                            title: "Comedy",
                            movies: comedy,
                            config: appState.apiConfiguration,
                            onSelect: { movie in selectedMovie = MovieSelection(id: movie.id) },
                            onSeeAll: { categoryForSeeAll = MovieCategorySeeAll(category: .comedy) }
                        )
                        MovieMediaRow(
                            title: "Drama",
                            movies: drama,
                            config: appState.apiConfiguration,
                            onSelect: { movie in selectedMovie = MovieSelection(id: movie.id) },
                            onSeeAll: { categoryForSeeAll = MovieCategorySeeAll(category: .drama) }
                        )
                        MovieMediaRow(
                            title: "Horror",
                            movies: horror,
                            config: appState.apiConfiguration,
                            onSelect: { movie in selectedMovie = MovieSelection(id: movie.id) },
                            onSeeAll: { categoryForSeeAll = MovieCategorySeeAll(category: .horror) }
                        )
                        MovieMediaRow(
                            title: "Romance",
                            movies: romance,
                            config: appState.apiConfiguration,
                            onSelect: { movie in selectedMovie = MovieSelection(id: movie.id) },
                            onSeeAll: { categoryForSeeAll = MovieCategorySeeAll(category: .romance) }
                        )
                        MovieMediaRow(
                            title: "Sci-Fi",
                            movies: sciFi,
                            config: appState.apiConfiguration,
                            onSelect: { movie in selectedMovie = MovieSelection(id: movie.id) },
                            onSeeAll: { categoryForSeeAll = MovieCategorySeeAll(category: .sciFi) }
                        )
                        MovieMediaRow(
                            title: "Thriller",
                            movies: thriller,
                            config: appState.apiConfiguration,
                            onSelect: { movie in selectedMovie = MovieSelection(id: movie.id) },
                            onSeeAll: { categoryForSeeAll = MovieCategorySeeAll(category: .thriller) }
                        )
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("")
            .navigationDestination(item: $selectedMovie) { selection in
                MovieDetailView(movieId: selection.id)
            }
            .navigationDestination(item: $categoryForSeeAll) { wrapper in
                MovieCategoryListView(category: wrapper.category)
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
            // Phase 1: Load first 3 lists so user sees content quickly
            async let trendingTask = appState.tmdbService.trendingMovies()
            async let popularTask = appState.tmdbService.popularMovies()
            async let topRatedTask = appState.tmdbService.topRatedMovies()

            trending = try await trendingTask
            popular = try await popularTask
            topRated = try await topRatedTask
            isLoading = false

            // Phase 2: Load next batch in background
            async let nowPlayingTask = appState.tmdbService.nowPlayingMovies()
            async let upcomingTask = appState.tmdbService.upcomingMovies()
            async let documentariesTask = appState.tmdbService.documentaryMovies()

            nowPlaying = try await nowPlayingTask
            upcoming = try await upcomingTask
            documentaries = try await documentariesTask

            // Phase 3: Load genre lists in background
            async let actionTask = appState.tmdbService.moviesPaginated(for: .action, page: 1)
            async let comedyTask = appState.tmdbService.moviesPaginated(for: .comedy, page: 1)
            async let dramaTask = appState.tmdbService.moviesPaginated(for: .drama, page: 1)
            async let horrorTask = appState.tmdbService.moviesPaginated(for: .horror, page: 1)
            async let romanceTask = appState.tmdbService.moviesPaginated(for: .romance, page: 1)
            async let sciFiTask = appState.tmdbService.moviesPaginated(for: .sciFi, page: 1)
            async let thrillerTask = appState.tmdbService.moviesPaginated(for: .thriller, page: 1)

            action = try await actionTask.items
            comedy = try await comedyTask.items
            drama = try await dramaTask.items
            horror = try await horrorTask.items
            romance = try await romanceTask.items
            sciFi = try await sciFiTask.items
            thriller = try await thrillerTask.items
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }

        onLoadComplete?()
    }

}

#Preview {
    MoviesView(shouldLoad: true)
        .environment(AppState(apiKey: "placeholder"))
}
