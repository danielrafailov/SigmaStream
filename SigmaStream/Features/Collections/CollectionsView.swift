//
//  CollectionsView.swift
//  SigmaStream
//
//  Browse curated movie franchises by category.
//

import SwiftUI

private struct MovieCollectionCategorySeeAll: Identifiable, Hashable {
    let id = UUID()
    let category: MovieCollectionCategory

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: MovieCollectionCategorySeeAll, rhs: MovieCollectionCategorySeeAll) -> Bool { lhs.id == rhs.id }
}

private struct MovieCollectionDetailNav: Identifiable, Hashable {
    let id: Int
    let title: String
}

struct CollectionsView: View {
    var shouldLoad: Bool = true
    var onLoadComplete: (() -> Void)? = nil

    @Environment(AppState.self) private var appState
    @State private var summariesByCategory: [MovieCollectionCategory: [MovieCollectionSummary]] = [:]
    @State private var isLoading = false
    @State private var catalogReady = false
    @State private var errorMessage: String?
    @State private var categoryForSeeAll: MovieCollectionCategorySeeAll?
    @State private var selectedCollection: MovieCollectionDetailNav?

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 48) {
                    if let error = errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 48)
                    }

                    if !catalogReady && errorMessage == nil {
                        ProgressView("Loading collections...")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                    } else {
                        ForEach(MovieCollectionCategory.allCases) { category in
                            let items = summariesByCategory[category] ?? []
                            if !items.isEmpty {
                                MovieCollectionMediaRow(
                                    title: category.rawValue,
                                    collections: items,
                                    config: appState.apiConfiguration,
                                    onSelect: { summary in
                                        selectedCollection = MovieCollectionDetailNav(id: summary.id, title: summary.title)
                                    },
                                    onSeeAll: {
                                        categoryForSeeAll = MovieCollectionCategorySeeAll(category: category)
                                    }
                                )
                            }
                        }
                    }
                }
                .padding(.vertical)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("")
            .navigationDestination(item: $categoryForSeeAll) { wrapper in
                MovieCollectionCategoryListView(category: wrapper.category)
            }
            .navigationDestination(item: $selectedCollection) { selection in
                MovieCollectionDetailView(collectionId: selection.id, fallbackTitle: selection.title)
            }
            .task(id: shouldLoad) {
                guard shouldLoad else { return }
                await loadData()
            }
        }
    }

    private func loadData() async {
        guard !isLoading else { return }
        isLoading = true
        catalogReady = false
        errorMessage = nil
        summariesByCategory = [:]

        await appState.loadConfiguration()

        await withTaskGroup(of: (MovieCollectionCategory, [MovieCollectionSummary]).self) { group in
            for category in MovieCollectionCategory.allCases {
                group.addTask {
                    let summaries = await appState.tmdbService.movieCollectionSummaries(for: category.collections)
                    return (category, summaries)
                }
            }
            for await (category, summaries) in group {
                if !summaries.isEmpty {
                    summariesByCategory[category] = summaries
                }
            }
        }

        if summariesByCategory.isEmpty {
            errorMessage = "Could not load any collections. Check your network and TMDb API key."
        }
        catalogReady = true
        isLoading = false
        onLoadComplete?()
    }
}

#Preview {
    CollectionsView()
        .environment(AppState(apiKey: "placeholder"))
}
