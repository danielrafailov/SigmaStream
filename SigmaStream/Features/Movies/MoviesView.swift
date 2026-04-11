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
    @State private var criticallyAcclaimed: [MovieListItem] = []
    @State private var newReleases: [MovieListItem] = []
    @State private var nowPlaying: [MovieListItem] = []
    @State private var upcoming: [MovieListItem] = []
    @State private var extraSections: [(MovieCategory, [MovieListItem])] = []
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

                    if trending.isEmpty && errorMessage == nil {
                        ProgressView("Loading...")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                    } else {
                        movieRow(title: MovieCategory.trendingToday.rawValue, movies: trending, category: .trendingToday)
                        movieRow(title: MovieCategory.popular.rawValue, movies: popular, category: .popular)
                        movieRow(title: MovieCategory.criticallyAcclaimed.rawValue, movies: criticallyAcclaimed, category: .criticallyAcclaimed)
                        movieRow(title: MovieCategory.newReleases.rawValue, movies: newReleases, category: .newReleases)
                        movieRow(title: MovieCategory.upcoming.rawValue, movies: upcoming, category: .upcoming)
                        movieRow(title: MovieCategory.nowPlaying.rawValue, movies: nowPlaying, category: .nowPlaying)

                        ForEach(extraSections, id: \.0) { cat, items in
                            if !items.isEmpty {
                                movieRow(title: cat.rawValue, movies: items, category: cat)
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
            .navigationDestination(item: $categoryForSeeAll) { wrapper in
                MovieCategoryListView(category: wrapper.category)
            }
            .task(id: shouldLoad) {
                guard shouldLoad else { return }
                await loadData()
            }
        }
    }

    @ViewBuilder
    private func movieRow(title: String, movies: [MovieListItem], category: MovieCategory) -> some View {
        MovieMediaRow(
            title: title,
            movies: movies,
            config: appState.apiConfiguration,
            onSelect: { movie in selectedMovie = MovieSelection(id: movie.id) },
            onSeeAll: { categoryForSeeAll = MovieCategorySeeAll(category: category) }
        )
    }

    private func loadData() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            async let trendingTask = appState.tmdbService.trendingMovies(inTimeWindow: .day)
            async let popularTask = appState.tmdbService.popularMovies()
            async let acclaimedTask = appState.tmdbService.criticallyAcclaimedMovies()
            async let newTask = appState.tmdbService.recentReleaseMovies()
            async let upcomingTask = appState.tmdbService.upcomingMovies()
            async let nowPlayingTask = appState.tmdbService.nowPlayingMovies()

            trending = try await trendingTask
            popular = try await popularTask
            criticallyAcclaimed = try await acclaimedTask
            newReleases = try await newTask
            upcoming = try await upcomingTask
            nowPlaying = try await nowPlayingTask
            isLoading = false

            var pairs: [(MovieCategory, [MovieListItem])] = []
            await withTaskGroup(of: (MovieCategory, [MovieListItem]).self) { group in
                for cat in MovieCategory.catalogDiscoverRows {
                    group.addTask {
                        let items = (try? await appState.tmdbService.moviesPaginated(for: cat, page: 1).items) ?? []
                        return (cat, items)
                    }
                }
                for await p in group {
                    pairs.append(p)
                }
            }
            extraSections = MovieCategory.catalogDiscoverRows.compactMap { c in pairs.first { $0.0 == c } }
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
