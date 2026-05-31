//
//  MovieCollectionCategoryListView.swift
//  SigmaStream
//
//  Grid of franchise collections for one category (e.g. Action Franchises).
//

import SwiftUI
import TMDb

private struct MovieCollectionSelectionNav: Identifiable, Hashable {
    let id: Int
    let title: String
}

struct MovieCollectionCategoryListView: View {
    let category: MovieCollectionCategory
    @Environment(AppState.self) private var appState
    @State private var collections: [MovieCollectionSummary] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedCollection: MovieCollectionSelectionNav?
    @FocusState private var focusedCollectionId: Int?

    private let columns = 5
    private let gridSpacing: CGFloat = mediaPosterSpacing

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                ContentUnavailableView(
                    "Couldn't load collections",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if collections.isEmpty {
                ContentUnavailableView(
                    "No collections",
                    systemImage: "square.stack.3d.up.slash",
                    description: Text("Nothing to show in this category.")
                )
            } else {
                GeometryReader { geo in
                    let availableWidth = geo.size.width - 32
                    let cardWidth = (availableWidth - CGFloat(columns - 1) * gridSpacing) / CGFloat(columns)
                    let cardHeight = cardWidth * (3.0 / 2.0)

                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: gridSpacing) {
                            Text(category.rawValue)
                                .font(.title2)
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            LazyVGrid(
                                columns: Array(repeating: GridItem(.fixed(cardWidth), spacing: gridSpacing), count: columns),
                                spacing: gridSpacing
                            ) {
                            ForEach(collections) { collection in
                                let isFocused = focusedCollectionId == collection.id
                                Button {
                                    selectedCollection = MovieCollectionSelectionNav(id: collection.id, title: collection.title)
                                } label: {
                                    MediaCard(
                                        posterPath: collection.posterPath,
                                        backdropPath: collection.backdropPath,
                                        config: appState.apiConfiguration,
                                        idealWidth: Int(cardWidth),
                                        isFocused: isFocused,
                                        alwaysPoster: true
                                    )
                                    .frame(width: cardWidth, height: cardHeight)
                                }
                                .buttonStyle(.plain)
                                .hoverEffectDisabled(true)
                                .focused($focusedCollectionId, equals: collection.id)
                            }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 24)
                    }
                }
            }
        }
        .navigationTitle("")
        .navigationDestination(item: $selectedCollection) { selection in
            MovieCollectionDetailView(collectionId: selection.id, fallbackTitle: selection.title)
        }
        .task {
            await loadCollections()
        }
    }

    private func loadCollections() async {
        isLoading = true
        errorMessage = nil
        collections = await appState.tmdbService.movieCollectionSummaries(for: category.collections)
        if collections.isEmpty {
            errorMessage = "No collections could be loaded."
        }
        isLoading = false
    }
}
