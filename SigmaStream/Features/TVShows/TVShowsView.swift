//
//  TVShowsView.swift
//  SigmaStream
//
//  Created by Daniel Rafailov on 2026-03-16.
//

import SwiftUI
import TMDb

/// Wrapper for navigation to TV category See All (Identifiable, Hashable for navigationDestination).
private struct TVCategorySeeAll: Identifiable, Hashable {
    let id = UUID()
    let category: TVCategory

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: TVCategorySeeAll, rhs: TVCategorySeeAll) -> Bool { lhs.id == rhs.id }
}

private struct ContinueWatchingEpisodeItem: Identifiable {
    let seriesId: Int
    let season: Int
    let episode: Int
    let seriesName: String
    let posterPath: URL?
    let firstAirDate: Date?
    var id: String { "\(seriesId)-\(season)-\(episode)" }
}

struct TVShowsView: View {
    @Environment(AppState.self) private var appState
    @State private var continueWatching: [ContinueWatchingEpisodeItem] = []
    @State private var trending: [TVSeriesListItem] = []
    @State private var popular: [TVSeriesListItem] = []
    @State private var topRated: [TVSeriesListItem] = []
    @State private var documentaries: [TVSeriesListItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedSeries: TVSeriesSelection?
    @State private var categoryForSeeAll: TVCategorySeeAll?

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

                        TVSeriesMediaRow(
                            title: "Trending Today",
                            tvSeries: trending,
                            config: appState.apiConfiguration,
                            onSelect: { series in selectedSeries = TVSeriesSelection(id: series.id) },
                            onSeeAll: { categoryForSeeAll = TVCategorySeeAll(category: .trendingToday) }
                        )

                        TVSeriesMediaRow(
                            title: "Popular",
                            tvSeries: popular,
                            config: appState.apiConfiguration,
                            onSelect: { series in selectedSeries = TVSeriesSelection(id: series.id) },
                            onSeeAll: { categoryForSeeAll = TVCategorySeeAll(category: .popular) }
                        )

                        TVSeriesMediaRow(
                            title: "Top Rated",
                            tvSeries: topRated,
                            config: appState.apiConfiguration,
                            onSelect: { series in selectedSeries = TVSeriesSelection(id: series.id) },
                            onSeeAll: { categoryForSeeAll = TVCategorySeeAll(category: .topRated) }
                        )

                        TVSeriesMediaRow(
                            title: "Documentaries",
                            tvSeries: documentaries,
                            config: appState.apiConfiguration,
                            onSelect: { series in selectedSeries = TVSeriesSelection(id: series.id) },
                            onSeeAll: { categoryForSeeAll = TVCategorySeeAll(category: .documentaries) }
                        )
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("TV Shows")
            .navigationDestination(item: $selectedSeries) { selection in
                TVSeriesDetailView(seriesId: selection.id)
            }
            .navigationDestination(item: $categoryForSeeAll) { wrapper in
                TVCategoryListView(category: wrapper.category)
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
                    ForEach(continueWatching) { item in
                        Button {
                            selectedSeries = TVSeriesSelection(id: item.seriesId)
                        } label: {
                            MediaCard(
                                posterPath: item.posterPath,
                                title: item.seriesName,
                                subtitle: "S\(item.season) E\(item.episode)",
                                config: appState.apiConfiguration
                            )
                        }
                        .buttonStyle(.plain)
                        .hoverEffect(.lift)
                        .contextMenu {
                            Button("Remove from Continue Watching", role: .destructive) {
                                appState.watchProgressManager.removeEpisode(seriesId: item.seriesId, season: item.season, episode: item.episode)
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
        let episodes = appState.watchProgressManager.watchedEpisodes
        var items: [ContinueWatchingEpisodeItem] = []
        for ep in episodes {
            if let series = try? await appState.tmdbService.tvSeriesDetails(forSeriesId: ep.seriesId) {
                items.append(ContinueWatchingEpisodeItem(
                    seriesId: ep.seriesId,
                    season: ep.season,
                    episode: ep.episode,
                    seriesName: series.name,
                    posterPath: series.posterPath,
                    firstAirDate: series.firstAirDate
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
            async let trendingTask = appState.tmdbService.trendingTVSeries()
            async let popularTask = appState.tmdbService.popularTVSeries()
            async let topRatedTask = appState.tmdbService.topRatedTVSeries()
            async let documentariesTask = appState.tmdbService.documentaryTVSeries()

            trending = try await trendingTask
            popular = try await popularTask
            topRated = try await topRatedTask
            documentaries = try await documentariesTask
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

#Preview {
    TVShowsView()
        .environment(AppState(apiKey: "placeholder"))
}
