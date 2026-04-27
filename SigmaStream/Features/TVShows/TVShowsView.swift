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
    @State private var criticallyAcclaimed: [TVSeriesListItem] = []
    @State private var newReleases: [TVSeriesListItem] = []
    @State private var millennialFavorites: [TVSeriesListItem] = []
    @State private var genZPicks: [TVSeriesListItem] = []
    @State private var genXClassics: [TVSeriesListItem] = []
    @State private var extraSections: [(TVCategory, [TVSeriesListItem])] = []
    @State private var isLoading = false
    @State private var catalogCoreReady = false
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

                    if !catalogCoreReady && errorMessage == nil {
                        ProgressView("Loading...")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                    } else {
                        tvRow(title: TVCategory.trendingToday.rawValue, series: trending, category: .trendingToday)
                        tvRow(title: TVCategory.popular.rawValue, series: popular, category: .popular)
                        tvRow(title: TVCategory.newReleases.rawValue, series: newReleases, category: .newReleases)
                        tvRow(title: TVCategory.criticallyAcclaimed.rawValue, series: criticallyAcclaimed, category: .criticallyAcclaimed)
                        tvRow(title: TVCategory.millennialFavorites.rawValue, series: millennialFavorites, category: .millennialFavorites)
                        tvRow(title: TVCategory.genZPicks.rawValue, series: genZPicks, category: .genZPicks)
                        tvRow(title: TVCategory.genXClassics.rawValue, series: genXClassics, category: .genXClassics)

                        ForEach(extraSections, id: \.0) { cat, items in
                            if !items.isEmpty {
                                tvRow(title: cat.rawValue, series: items, category: cat)
                            }
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
            }
        }
    }

    @ViewBuilder
    private func tvRow(title: String, series: [TVSeriesListItem], category: TVCategory) -> some View {
        TVSeriesMediaRow(
            title: title,
            tvSeries: series,
            config: appState.apiConfiguration,
            onSelect: { s in selectedSeries = TVSeriesSelection(id: s.id) },
            onSeeAll: { categoryForSeeAll = TVCategorySeeAll(category: category) }
        )
    }

    private func loadData() async {
        guard !isLoading else { return }
        isLoading = true
        catalogCoreReady = false
        errorMessage = nil

        do {
            async let trendingTask = appState.tmdbService.trendingTVSeries(inTimeWindow: .day)
            async let popularTask = appState.tmdbService.popularTVSeries()
            async let acclaimedTask = appState.tmdbService.criticallyAcclaimedTVSeries()
            async let newTask = appState.tmdbService.recentReleaseTVSeries()
            async let millennialTask = appState.tmdbService.tvSeriesPaginated(for: .millennialFavorites, page: 1).items
            async let genZTask = appState.tmdbService.tvSeriesPaginated(for: .genZPicks, page: 1).items
            async let genXTask = appState.tmdbService.tvSeriesPaginated(for: .genXClassics, page: 1).items

            let (t, p, a, n, millennial, genZ, genX) = try await (trendingTask, popularTask, acclaimedTask, newTask, millennialTask, genZTask, genXTask)

            trending = t
            popular = p
            criticallyAcclaimed = a
            newReleases = n
            millennialFavorites = millennial
            genZPicks = genZ
            genXClassics = genX
            catalogCoreReady = true

            let pairs = await PerformanceSignposts.interval(log: PerformanceSignposts.tvTabLoad, name: "TVTabDiscover") {
                await ConcurrentCatalogDiscoverFetch.mapLimited(
                    items: TVCategory.catalogDiscoverRows,
                    name: "TVTabDiscover"
                ) { cat in
                    let items = (try? await appState.tmdbService.tvSeriesPaginated(for: cat, page: 1).items) ?? []
                    return (cat, items)
                }
            }
            extraSections = TVCategory.catalogDiscoverRows.compactMap { c in pairs.first { $0.0 == c } }
        } catch {
            errorMessage = error.localizedDescription
            catalogCoreReady = true
        }
        isLoading = false
        onLoadComplete?()
    }
}

#Preview {
    TVShowsView()
        .environment(AppState(apiKey: "placeholder"))
}
