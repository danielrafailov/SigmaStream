//
//  TVCategoryListView.swift
//  SigmaStream
//
//  Full list view for a TV category (e.g. See All for Popular).
//

import SwiftUI
import TMDb

struct TVCategoryListView: View {
    let category: TVCategory
    @Environment(AppState.self) private var appState
    @State private var tvSeries: [TVSeriesListItem] = []
    @State private var currentPage = 1
    @State private var filter = MediaFilter.default
    @State private var genres: [Genre] = []
    @State private var showFilter = false
    @State private var isFilterActive = false
    @State private var hasMore = true
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var selectedSeries: TVSeriesSelection?

    private func formatYear(_ date: Date) -> String {
        Calendar.current.component(.year, from: date).description
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                ContentUnavailableView(
                    "Couldn't load \(category.rawValue)",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 220, maximum: 260), spacing: 24)
                    ], spacing: 24) {
                        ForEach(Array(tvSeries.enumerated()), id: \.element.id) { index, series in
                            Button {
                                selectedSeries = TVSeriesSelection(id: series.id)
                            } label: {
                                MediaCard(
                                    posterPath: series.posterPath,
                                    title: series.name,
                                    subtitle: series.firstAirDate.map { formatYear($0) },
                                    config: appState.apiConfiguration
                                )
                            }
                            .buttonStyle(.plain)
                            .hoverEffect(.lift)
                            .contextMenu {
                                Button(appState.myListManager.isSeriesInList(series.id) ? "Remove from My List" : "Add to My List") {
                                    appState.myListManager.toggleSeries(series.id)
                                }
                            }
                            .onAppear {
                                if index >= tvSeries.count - 3 && hasMore && !isLoadingMore {
                                    Task { await loadMore() }
                                }
                            }
                        }
                        if isLoadingMore {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(category.rawValue)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await loadGenres() }
                    showFilter = true
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .sheet(isPresented: $showFilter) {
            TVSeriesFilterSheet(
                filter: $filter,
                genres: genres,
                onApply: {
                    isFilterActive = true
                    Task { await loadInitial() }
                    showFilter = false
                },
                onClear: {
                    filter = MediaFilter.default
                    isFilterActive = false
                    Task { await loadInitial() }
                    showFilter = false
                }
            )
        }
        .navigationDestination(item: $selectedSeries) { selection in
            TVSeriesDetailView(seriesId: selection.id)
        }
        .task {
            await loadInitial()
        }
    }

    private func loadGenres() async {
        do {
            genres = try await appState.tmdbService.tvSeriesGenres()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadInitial() async {
        isLoading = true
        errorMessage = nil
        currentPage = 1
        hasMore = true
        do {
            if isFilterActive {
                let items = try await appState.tmdbService.discoverTVSeries(
                    filter: filter.toDiscoverTVSeriesFilter(),
                    sortedBy: filter.sortOption.tvSort,
                    page: 1
                )
                tvSeries = items
                hasMore = items.count >= 20
            } else {
                let result = try await appState.tmdbService.tvSeriesPaginated(for: category, page: 1)
                tvSeries = result.items
                hasMore = result.hasMore
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func loadMore() async {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        let nextPage = currentPage + 1
        do {
            if isFilterActive {
                let items = try await appState.tmdbService.discoverTVSeries(
                    filter: filter.toDiscoverTVSeriesFilter(),
                    sortedBy: filter.sortOption.tvSort,
                    page: nextPage
                )
                tvSeries.append(contentsOf: items)
                hasMore = items.count >= 20
                currentPage = nextPage
            } else {
                let result = try await appState.tmdbService.tvSeriesPaginated(for: category, page: nextPage)
                tvSeries.append(contentsOf: result.items)
                hasMore = result.hasMore
                currentPage = nextPage
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingMore = false
    }
}
