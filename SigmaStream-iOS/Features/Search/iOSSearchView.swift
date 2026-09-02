//
//  iOSSearchView.swift
//  SigmaStream-iOS
//
//  Created by Daniel Rafailov on 2026-09-01.
//

import SwiftUI
import TMDb

#if os(iOS)
struct iOSSearchView: View {
    @Environment(AppState.self) private var appState

    @State private var searchText = ""
    @State private var selectedFilter = 0 // 0: All, 1: Movies, 2: TV Shows
    @State private var searchResults: [MediaListItem] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    // Adaptive grid: 3 columns on iPhone, 5-6 columns on iPad
    private let columns = [
        GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 14)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter Chips
                Picker("Filter", selection: $selectedFilter) {
                    Text("All").tag(0)
                    Text("Movies").tag(1)
                    Text("TV Shows").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .onChange(of: selectedFilter) { _, _ in
                    performSearch()
                }

                // Results Grid
                if isSearching {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if searchResults.isEmpty && !searchText.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else if searchResults.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("Search Movies & TV Shows")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(searchResults) { item in
                                NavigationLink {
                                    if item.isTVSeries {
                                        iOSTVSeriesDetailView(seriesId: item.id)
                                    } else {
                                        iOSMovieDetailView(movieId: item.id)
                                    }
                                } label: {
                                    iOSMediaCard(
                                        id: item.id,
                                        title: item.title,
                                        posterPath: item.posterURL,
                                        rating: item.rating,
                                        releaseYear: item.releaseYear,
                                        isTVSeries: item.isTVSeries,
                                        progress: nil
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Search")
            .searchable(text: $searchText, prompt: "Search titles, actors, genres...")
            .onChange(of: searchText) { _, newValue in
                performSearch()
            }
        }
    }

    private func performSearch() {
        searchTask?.cancel()
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            guard !Task.isCancelled else { return }

            await MainActor.run { isSearching = true }

            do {
                var results: [MediaListItem] = []
                if selectedFilter == 0 || selectedFilter == 1 {
                    let movies = try await appState.tmdbService.searchMovies(query: query)
                    let movieItems = movies.map {
                        MediaListItem(
                            id: $0.id,
                            title: $0.title,
                            posterURL: ImageURLBuilder.posterURL(for: $0.posterPath, config: appState.apiConfiguration, idealWidth: 342),
                            rating: $0.voteAverage,
                            releaseYear: $0.releaseDate.map { String(Calendar.current.component(.year, from: $0)) },
                            isTVSeries: false
                        )
                    }
                    results.append(contentsOf: movieItems)
                }

                if selectedFilter == 0 || selectedFilter == 2 {
                    let tvSeries = try await appState.tmdbService.searchTVSeries(query: query)
                    let tvItems = tvSeries.map {
                        MediaListItem(
                            id: $0.id,
                            title: $0.name,
                            posterURL: ImageURLBuilder.posterURL(for: $0.posterPath, config: appState.apiConfiguration, idealWidth: 342),
                            rating: $0.voteAverage,
                            releaseYear: $0.firstAirDate.map { String(Calendar.current.component(.year, from: $0)) },
                            isTVSeries: true
                        )
                    }
                    results.append(contentsOf: tvItems)
                }

                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.searchResults = results
                    self.isSearching = false
                }
            } catch {
                await MainActor.run { self.isSearching = false }
            }
        }
    }
}

struct MediaListItem: Identifiable {
    let id: Int
    let title: String
    let posterURL: URL?
    let rating: Double?
    let releaseYear: String?
    let isTVSeries: Bool
}
#endif
