//
//  TVShowsView.swift
//  SigmaStream
//
//  Created by Daniel Rafailov on 2026-03-16.
//

import SwiftUI
import TMDb

struct TVShowsView: View {
    @Environment(AppState.self) private var appState
    @State private var trending: [TVSeriesListItem] = []
    @State private var popular: [TVSeriesListItem] = []
    @State private var topRated: [TVSeriesListItem] = []
    @State private var filtered: [TVSeriesListItem]?
    @State private var tvFilter = MediaFilter.default
    @State private var tvGenres: [Genre] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showFilter = false
    @State private var selectedSeries: TVSeriesSelection?
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
                            TVSeriesMediaRow(
                                title: "Filtered Results",
                                tvSeries: filteredList,
                                config: appState.apiConfiguration
                            ) { series in
                                selectedSeries = TVSeriesSelection(id: series.id)
                            }
                        }

                        TVSeriesMediaRow(
                            title: "Trending Today",
                            tvSeries: trending,
                            config: appState.apiConfiguration
                        ) { series in
                            selectedSeries = TVSeriesSelection(id: series.id)
                        }

                        TVSeriesMediaRow(
                            title: "Popular",
                            tvSeries: popular,
                            config: appState.apiConfiguration
                        ) { series in
                            selectedSeries = TVSeriesSelection(id: series.id)
                        }

                        TVSeriesMediaRow(
                            title: "Top Rated",
                            tvSeries: topRated,
                            config: appState.apiConfiguration
                        ) { series in
                            selectedSeries = TVSeriesSelection(id: series.id)
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("TV Shows")
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
            .navigationDestination(item: $selectedSeries) { selection in
                TVSeriesDetailView(seriesId: selection.id)
            }
            .sheet(isPresented: $showFilter) {
                TVSeriesFilterSheet(
                    filter: $tvFilter,
                    genres: tvGenres,
                    onApply: {
                        isFilterActive = true
                        Task { await applyFilter() }
                        showFilter = false
                    },
                    onClear: {
                        tvFilter = MediaFilter.default
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
            async let trendingTask = appState.tmdbService.trendingTVSeries()
            async let popularTask = appState.tmdbService.popularTVSeries()
            async let topRatedTask = appState.tmdbService.topRatedTVSeries()

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
            tvGenres = try await appState.tmdbService.tvSeriesGenres()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyFilter() async {
        guard tvFilter.hasAnyFilter else {
            filtered = nil
            return
        }

        do {
            let filter = tvFilter.toDiscoverTVSeriesFilter()
            filtered = try await appState.tmdbService.discoverTVSeries(
                filter: filter,
                sortedBy: tvFilter.sortOption.tvSort,
                page: 1
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    TVShowsView()
        .environment(AppState(apiKey: "placeholder"))
}
