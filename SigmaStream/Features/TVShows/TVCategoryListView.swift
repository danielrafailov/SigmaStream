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
    @State private var hasMore = true
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var selectedSeries: TVSeriesSelection?
    @State private var hasLoadedOnce = false
    @FocusState private var focusedSeriesId: Int?

    private let columns = 5
    private let gridSpacing: CGFloat = mediaPosterSpacing

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
                GeometryReader { geo in
                    let availableWidth = geo.size.width - 32
                    let posterWidth = (availableWidth - CGFloat(columns - 1) * gridSpacing) / CGFloat(columns)
                    let posterHeight = posterWidth * (3.0 / 2.0)

                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(posterWidth), spacing: gridSpacing), count: columns), spacing: gridSpacing) {
                            ForEach(Array(tvSeries.enumerated()), id: \.element.id) { index, series in
                                let isFocused = focusedSeriesId == series.id
                                Button {
                                    selectedSeries = TVSeriesSelection(id: series.id)
                                } label: {
                                    MediaCard(
                                        posterPath: series.posterPath,
                                        backdropPath: series.backdropPath,
                                        config: appState.apiConfiguration,
                                        idealWidth: Int(posterWidth),
                                        isFocused: isFocused,
                                        alwaysPoster: true
                                    )
                                    .frame(width: posterWidth, height: posterHeight)
                                }
                                .buttonStyle(.plain)
                                .hoverEffectDisabled(true)
                                .focused($focusedSeriesId, equals: series.id)
                                .accessibilityLabel(series.name)
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
                        .padding(16)
                    }
                }
            }
        }
        .defaultFocus($focusedSeriesId, tvSeries.first?.id)
        .navigationTitle("")
        .navigationDestination(item: $selectedSeries) { selection in
            TVSeriesDetailView(seriesId: selection.id)
        }
        .task {
            guard !hasLoadedOnce else { return }
            hasLoadedOnce = true
            await loadInitial()
        }
    }

    private func loadInitial() async {
        isLoading = true
        errorMessage = nil
        currentPage = 1
        hasMore = true
        do {
            let result = try await appState.tmdbService.tvSeriesPaginated(for: category, page: 1)
            tvSeries = result.items
            hasMore = result.hasMore
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
            let result = try await appState.tmdbService.tvSeriesPaginated(for: category, page: nextPage)
            tvSeries.append(contentsOf: result.items)
            hasMore = result.hasMore
            currentPage = nextPage
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingMore = false
    }
}
