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
    @Environment(AppState.self) private var appState
    @State private var continueWatching: [ContinueWatchingMovieItem] = []
    @State private var trending: [MovieListItem] = []
    @State private var popular: [MovieListItem] = []
    @State private var topRated: [MovieListItem] = []
    @State private var nowPlaying: [MovieListItem] = []
    @State private var upcoming: [MovieListItem] = []
    @State private var documentaries: [MovieListItem] = []
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
            .task {
                await loadData()
            }
            .onAppear {
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

            trending = try await trendingTask
            popular = try await popularTask
            topRated = try await topRatedTask
            nowPlaying = try await nowPlayingTask
            upcoming = try await upcomingTask
            documentaries = try await documentariesTask
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

}

#Preview {
    MoviesView()
        .environment(AppState(apiKey: "placeholder"))
}
