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

private struct ContinueWatchingMovieItem: Identifiable {
    let id: Int
    let title: String
    let posterPath: URL?
    let releaseDate: Date?
}

struct MoviesView: View {
    var shouldLoad: Bool = true
    var onLoadComplete: (() -> Void)? = nil

    @Environment(AppState.self) private var appState
    @State private var continueWatching: [ContinueWatchingMovieItem] = []
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
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
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
                        if !continueWatching.isEmpty {
                            continueWatchingSection
                        }

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
            .navigationTitle("Movies")
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
            .onAppear {
                guard shouldLoad else { return }
                Task { await loadContinueWatching() }
            }
            .onReceive(NotificationCenter.default.publisher(for: WatchProgressManager.continueWatchingDidChange)) { _ in
                Task { await loadContinueWatching() }
            }
        }
    }

    @ViewBuilder
    private var continueWatchingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Continue Watching")
                .font(.title2)
                .fontWeight(.semibold)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(continueWatching) { movie in
                        Button {
                            selectedMovie = MovieSelection(id: movie.id)
                        } label: {
                            MediaCard(
                                posterPath: movie.posterPath,
                                title: movie.title,
                                subtitle: movie.releaseDate.map { Calendar.current.component(.year, from: $0).description },
                                config: appState.apiConfiguration
                            )
                        }
                        .buttonStyle(.plain)
                        .hoverEffect(.lift)
                        .contextMenu {
                            Button("Remove from Continue Watching", role: .destructive) {
                                appState.watchProgressManager.removeMovie(movie.id)
                                Task { await loadContinueWatching() }
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .focusSection()
    }

    private func loadContinueWatching() async {
        let ids = appState.watchProgressManager.watchedMovies.map(\.movieId)
        var items: [ContinueWatchingMovieItem] = []
        for id in ids {
            if let movie = try? await appState.tmdbService.movieDetails(forMovieId: id) {
                items.append(ContinueWatchingMovieItem(
                    id: movie.id,
                    title: movie.title,
                    posterPath: movie.posterPath,
                    releaseDate: movie.releaseDate
                ))
            }
        }
        continueWatching = items
    }

    private func loadData() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            async let trendingTask = appState.tmdbService.trendingMovies()
            async let popularTask = appState.tmdbService.popularMovies()
            async let topRatedTask = appState.tmdbService.topRatedMovies()
            async let nowPlayingTask = appState.tmdbService.nowPlayingMovies()
            async let upcomingTask = appState.tmdbService.upcomingMovies()
            async let documentariesTask = appState.tmdbService.documentaryMovies()
            async let actionTask = appState.tmdbService.moviesPaginated(for: .action, page: 1)
            async let comedyTask = appState.tmdbService.moviesPaginated(for: .comedy, page: 1)
            async let dramaTask = appState.tmdbService.moviesPaginated(for: .drama, page: 1)
            async let horrorTask = appState.tmdbService.moviesPaginated(for: .horror, page: 1)
            async let romanceTask = appState.tmdbService.moviesPaginated(for: .romance, page: 1)
            async let sciFiTask = appState.tmdbService.moviesPaginated(for: .sciFi, page: 1)
            async let thrillerTask = appState.tmdbService.moviesPaginated(for: .thriller, page: 1)

            trending = try await trendingTask
            popular = try await popularTask
            topRated = try await topRatedTask
            nowPlaying = try await nowPlayingTask
            upcoming = try await upcomingTask
            documentaries = try await documentariesTask
            action = try await actionTask.items
            comedy = try await comedyTask.items
            drama = try await dramaTask.items
            horror = try await horrorTask.items
            romance = try await romanceTask.items
            sciFi = try await sciFiTask.items
            thriller = try await thrillerTask.items
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
        onLoadComplete?()
    }

}

#Preview {
    MoviesView(shouldLoad: true)
        .environment(AppState(apiKey: "placeholder"))
}
