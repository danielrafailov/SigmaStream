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
    @State private var movies: [MovieListItem] = []
    @State private var tvSeries: [TVSeriesListItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var selectedMovie: MovieSelection?
    @State private var selectedSeries: TVSeriesSelection?
    @State private var displayedQuery = ""

    var body: some View {
        SearchableNavigationHost(
            movies: movies,
            tvSeries: tvSeries,
            isLoading: isLoading,
            errorMessage: errorMessage,
            displayedQuery: displayedQuery,
            apiConfiguration: appState.apiConfiguration,
            selectedMovie: $selectedMovie,
            selectedSeries: $selectedSeries,
            onSearch: handleSearch
        )
    }

    private func handleSearch(query: String) {
        searchTask?.cancel()

        guard query.count >= 2 else {
            movies = []
            tvSeries = []
            displayedQuery = ""
            errorMessage = nil
            isLoading = false
            return
        }

        searchTask = Task { @MainActor in
            await performSearch(query: query)
        }
    }

    @MainActor
    private func performSearch(query: String) async {
        isLoading = true
        errorMessage = nil

        do {
            let result = try await appState.tmdbService.searchMoviesTVIncludingPersonCast(query: query)
            guard !Task.isCancelled else { return }
            movies = result.movies
            tvSeries = result.tvSeries
            displayedQuery = query
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

/// Owns the native `.searchable` draft text so keystrokes do not rebuild the parent results state.
private struct SearchableNavigationHost: View {
    @State private var draftText = ""

    let movies: [MovieListItem]
    let tvSeries: [TVSeriesListItem]
    let isLoading: Bool
    let errorMessage: String?
    let displayedQuery: String
    let apiConfiguration: APIConfiguration?
    @Binding var selectedMovie: MovieSelection?
    @Binding var selectedSeries: TVSeriesSelection?
    let onSearch: (String) -> Void

    private var trimmedDraft: String {
        draftText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                SearchResultsContent(
                    movies: movies,
                    tvSeries: tvSeries,
                    isLoading: isLoading,
                    errorMessage: errorMessage,
                    displayedQuery: displayedQuery,
                    apiConfiguration: apiConfiguration,
                    selectedMovie: $selectedMovie,
                    selectedSeries: $selectedSeries
                )
                .scrollTargetLayout()
                .padding(.vertical)
            }
            .focusSection()
            .navigationTitle("")
            .searchable(text: $draftText, prompt: "Movies & TV Shows")
            .onSubmit(of: .search) {
                onSearch(trimmedDraft)
            }
            .navigationDestination(item: $selectedMovie) { selection in
                MovieDetailView(movieId: selection.id)
            }
            .navigationDestination(item: $selectedSeries) { selection in
                TVSeriesDetailView(seriesId: selection.id)
            }
        }
    }
}

private struct SearchResultsContent: View {
    let movies: [MovieListItem]
    let tvSeries: [TVSeriesListItem]
    let isLoading: Bool
    let errorMessage: String?
    let displayedQuery: String
    let apiConfiguration: APIConfiguration?
    @Binding var selectedMovie: MovieSelection?
    @Binding var selectedSeries: TVSeriesSelection?

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            if isLoading {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Searching...")
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
            } else if !displayedQuery.isEmpty {
                if movies.isEmpty && tvSeries.isEmpty {
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
                            config: apiConfiguration,
                            onSelect: { movie in selectedMovie = MovieSelection(id: movie.id) }
                        )
                    }

                    if !tvSeries.isEmpty {
                        TVSeriesMediaRow(
                            title: "TV Shows",
                            tvSeries: tvSeries,
                            config: apiConfiguration,
                            onSelect: { series in selectedSeries = TVSeriesSelection(id: series.id) }
                        )
                    }
                }
            }
        }
    }
}

#Preview {
    SearchView()
        .environment(AppState(apiKey: "placeholder"))
}
