//
//  SearchView.swift
//  SigmaStream
//
//  Created by Daniel Rafailov on 2026-03-16.
//

import SwiftUI
import TMDb

struct SearchView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""
    @State private var movies: [MovieListItem] = []
    @State private var tvSeries: [TVSeriesListItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var selectedMovie: MovieSelection?
    @State private var selectedSeries: TVSeriesSelection?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    if let error = errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .padding()
                    }

                    if isLoading && searchText.count >= 2 {
                        ProgressView("Searching...")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                    } else if searchText.count >= 2 {
                        if movies.isEmpty && tvSeries.isEmpty && !isLoading {
                            ContentUnavailableView(
                                "No results",
                                systemImage: "magnifyingglass",
                                description: Text("Try a different search term")
                            )
                            .padding(.vertical, 60)
                        } else {
                            if !movies.isEmpty {
                                MovieMediaRow(
                                    title: "Movies",
                                    movies: movies,
                                    config: appState.apiConfiguration,
                                    onSelect: { movie in selectedMovie = MovieSelection(id: movie.id) }
                                )
                            }

                            if !tvSeries.isEmpty {
                                TVSeriesMediaRow(
                                    title: "TV Shows",
                                    tvSeries: tvSeries,
                                    config: appState.apiConfiguration,
                                    onSelect: { series in selectedSeries = TVSeriesSelection(id: series.id) }
                                )
                            }
                        }
                    } else if !searchText.isEmpty {
                        Text("Enter at least 2 characters to search")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 60)
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical)
            }
            .navigationTitle("")
            .searchable(text: $searchText, prompt: "")
            .onChange(of: searchText) { _, newValue in
                searchTask?.cancel()
                movies = []
                tvSeries = []
                errorMessage = nil

                guard newValue.count >= 2 else { return }

                let query = newValue
                searchTask = Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled else { return }
                    await performSearch(query: query)
                }
            }
            .navigationDestination(item: $selectedMovie) { selection in
                MovieDetailView(movieId: selection.id)
            }
            .navigationDestination(item: $selectedSeries) { selection in
                TVSeriesDetailView(seriesId: selection.id)
            }
            .task {
                await appState.loadConfiguration()
            }
        }
    }

    private func performSearch(query: String) async {
        guard !query.isEmpty else { return }
        isLoading = true
        errorMessage = nil

        do {
            async let moviesTask = appState.tmdbService.searchMovies(query: query)
            async let tvTask = appState.tmdbService.searchTVSeries(query: query)

            movies = try await moviesTask
            tvSeries = try await tvTask
        } catch {
            if !Task.isCancelled {
                errorMessage = error.localizedDescription
            }
        }

        isLoading = false
    }
}

#Preview {
    SearchView()
        .environment(AppState(apiKey: "placeholder"))
}
