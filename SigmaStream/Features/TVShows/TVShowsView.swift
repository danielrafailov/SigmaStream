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

struct TVShowsView: View {
    var shouldLoad: Bool = true
    var onLoadComplete: (() -> Void)? = nil

    @Environment(AppState.self) private var appState
    @State private var trending: [TVSeriesListItem] = []
    @State private var popular: [TVSeriesListItem] = []
    @State private var topRated: [TVSeriesListItem] = []
    @State private var documentaries: [TVSeriesListItem] = []
    @State private var actionAdventure: [TVSeriesListItem] = []
    @State private var comedy: [TVSeriesListItem] = []
    @State private var drama: [TVSeriesListItem] = []
    @State private var horror: [TVSeriesListItem] = []
    @State private var romance: [TVSeriesListItem] = []
    @State private var sciFiFantasy: [TVSeriesListItem] = []
    @State private var thriller: [TVSeriesListItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedSeries: TVSeriesSelection?
    @State private var categoryForSeeAll: TVCategorySeeAll?

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 48) {
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

                        if !documentaries.isEmpty {
                            TVSeriesMediaRow(
                                title: "Documentaries",
                                tvSeries: documentaries,
                                config: appState.apiConfiguration,
                                onSelect: { series in selectedSeries = TVSeriesSelection(id: series.id) },
                                onSeeAll: { categoryForSeeAll = TVCategorySeeAll(category: .documentaries) }
                            )
                        }
                        if !actionAdventure.isEmpty {
                            TVSeriesMediaRow(
                                title: "Action & Adventure",
                                tvSeries: actionAdventure,
                                config: appState.apiConfiguration,
                                onSelect: { series in selectedSeries = TVSeriesSelection(id: series.id) },
                                onSeeAll: { categoryForSeeAll = TVCategorySeeAll(category: .actionAdventure) }
                            )
                        }
                        if !comedy.isEmpty {
                            TVSeriesMediaRow(
                                title: "Comedy",
                                tvSeries: comedy,
                                config: appState.apiConfiguration,
                                onSelect: { series in selectedSeries = TVSeriesSelection(id: series.id) },
                                onSeeAll: { categoryForSeeAll = TVCategorySeeAll(category: .comedy) }
                            )
                        }
                        if !drama.isEmpty {
                            TVSeriesMediaRow(
                                title: "Drama",
                                tvSeries: drama,
                                config: appState.apiConfiguration,
                                onSelect: { series in selectedSeries = TVSeriesSelection(id: series.id) },
                                onSeeAll: { categoryForSeeAll = TVCategorySeeAll(category: .drama) }
                            )
                        }
                        if !horror.isEmpty {
                            TVSeriesMediaRow(
                                title: "Horror",
                                tvSeries: horror,
                                config: appState.apiConfiguration,
                                onSelect: { series in selectedSeries = TVSeriesSelection(id: series.id) },
                                onSeeAll: { categoryForSeeAll = TVCategorySeeAll(category: .horror) }
                            )
                        }
                        if !romance.isEmpty {
                            TVSeriesMediaRow(
                                title: "Romance",
                                tvSeries: romance,
                                config: appState.apiConfiguration,
                                onSelect: { series in selectedSeries = TVSeriesSelection(id: series.id) },
                                onSeeAll: { categoryForSeeAll = TVCategorySeeAll(category: .romance) }
                            )
                        }
                        if !sciFiFantasy.isEmpty {
                            TVSeriesMediaRow(
                                title: "Sci-Fi & Fantasy",
                                tvSeries: sciFiFantasy,
                                config: appState.apiConfiguration,
                                onSelect: { series in selectedSeries = TVSeriesSelection(id: series.id) },
                                onSeeAll: { categoryForSeeAll = TVCategorySeeAll(category: .sciFiFantasy) }
                            )
                        }
                        if !thriller.isEmpty {
                            TVSeriesMediaRow(
                                title: "Thriller",
                                tvSeries: thriller,
                                config: appState.apiConfiguration,
                                onSelect: { series in selectedSeries = TVSeriesSelection(id: series.id) },
                                onSeeAll: { categoryForSeeAll = TVCategorySeeAll(category: .thriller) }
                            )
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical)
            }
            .navigationTitle("")
            .navigationDestination(item: $selectedSeries) { selection in
                TVSeriesDetailView(seriesId: selection.id)
            }
            .navigationDestination(item: $categoryForSeeAll) { wrapper in
                TVCategoryListView(category: wrapper.category)
            }
            .task(id: shouldLoad) {
                guard shouldLoad else { return }
                await loadData()
                onLoadComplete?()
            }
        }
    }

    private func loadData() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            // Phase 1: Load first 3 lists so user sees content quickly
            async let trendingTask = appState.tmdbService.trendingTVSeries()
            async let popularTask = appState.tmdbService.popularTVSeries()
            async let topRatedTask = appState.tmdbService.topRatedTVSeries()

            trending = try await trendingTask
            popular = try await popularTask
            topRated = try await topRatedTask
            isLoading = false

            // Phase 2: Load documentaries in background
            documentaries = try await appState.tmdbService.documentaryTVSeries()

            // Phase 3: Load genre lists in background
            async let actionAdventureTask = appState.tmdbService.tvSeriesPaginated(for: .actionAdventure, page: 1)
            async let comedyTask = appState.tmdbService.tvSeriesPaginated(for: .comedy, page: 1)
            async let dramaTask = appState.tmdbService.tvSeriesPaginated(for: .drama, page: 1)
            async let horrorTask = appState.tmdbService.tvSeriesPaginated(for: .horror, page: 1)
            async let romanceTask = appState.tmdbService.tvSeriesPaginated(for: .romance, page: 1)
            async let sciFiFantasyTask = appState.tmdbService.tvSeriesPaginated(for: .sciFiFantasy, page: 1)
            async let thrillerTask = appState.tmdbService.tvSeriesPaginated(for: .thriller, page: 1)

            actionAdventure = try await actionAdventureTask.items
            comedy = try await comedyTask.items
            drama = try await dramaTask.items
            horror = try await horrorTask.items
            romance = try await romanceTask.items
            sciFiFantasy = try await sciFiFantasyTask.items
            thriller = try await thrillerTask.items
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}

#Preview {
    TVShowsView()
        .environment(AppState(apiKey: "placeholder"))
}
