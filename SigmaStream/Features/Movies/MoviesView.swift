//
//  MoviesView.swift
//  SigmaStream
//
//  Created by Daniel Rafailov on 2026-03-16.
//

import SwiftUI
import TMDb

struct MoviesView: View {
    @Environment(AppState.self) private var appState
    @State private var trending: [MovieListItem] = []
    @State private var popular: [MovieListItem] = []
    @State private var topRated: [MovieListItem] = []
    @State private var filtered: [MovieListItem]?
    @State private var movieFilter = MediaFilter.default
    @State private var movieGenres: [Genre] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showFilter = false
    @State private var selectedMovie: MovieSelection?
    @State private var isFilterActive = false

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
                        if let filteredList = filtered, isFilterActive {
                            MovieMediaRow(
                                title: "Filtered Results",
                                movies: filteredList,
                                config: appState.apiConfiguration
                            ) { movie in
                                selectedMovie = MovieSelection(id: movie.id)
                            }
                        }

                        MovieMediaRow(
                            title: "Trending Today",
                            movies: trending,
                            config: appState.apiConfiguration
                        ) { movie in
                            selectedMovie = MovieSelection(id: movie.id)
                        }

                        MovieMediaRow(
                            title: "Popular",
                            movies: popular,
                            config: appState.apiConfiguration
                        ) { movie in
                            selectedMovie = MovieSelection(id: movie.id)
                        }

                        MovieMediaRow(
                            title: "Top Rated",
                            movies: topRated,
                            config: appState.apiConfiguration
                        ) { movie in
                            selectedMovie = MovieSelection(id: movie.id)
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Movies")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showFilter = true
                        Task { await loadGenres() }
                    } label: {
                        Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .navigationDestination(item: $selectedMovie) { selection in
                MovieDetailView(movieId: selection.id)
            }
            .sheet(isPresented: $showFilter) {
                MovieFilterSheet(
                    filter: $movieFilter,
                    genres: movieGenres,
                    onApply: {
                        isFilterActive = true
                        Task { await applyFilter() }
                        showFilter = false
                    },
                    onClear: {
                        movieFilter = MediaFilter.default
                        isFilterActive = false
                        filtered = nil
                        showFilter = false
                    }
                )
            }
            .task {
                await loadData()
            }
        }
    }

    private func loadData() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            async let trendingTask = appState.tmdbService.trendingMovies()
            async let popularTask = appState.tmdbService.popularMovies()
            async let topRatedTask = appState.tmdbService.topRatedMovies()

            trending = try await trendingTask
            popular = try await popularTask
            topRated = try await topRatedTask
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func loadGenres() async {
        do {
            movieGenres = try await appState.tmdbService.movieGenres()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyFilter() async {
        guard movieFilter.hasAnyFilter else {
            filtered = nil
            return
        }

        do {
            let filter = movieFilter.toDiscoverMovieFilter()
            filtered = try await appState.tmdbService.discoverMovies(
                filter: filter,
                sortedBy: movieFilter.sortOption.movieSort,
                page: 1
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    MoviesView()
        .environment(AppState(apiKey: "placeholder"))
}
