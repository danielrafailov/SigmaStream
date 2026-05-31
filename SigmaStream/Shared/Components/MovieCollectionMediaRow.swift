//
//  MovieCollectionMediaRow.swift
//  SigmaStream
//
//  Horizontal row of franchise collection cards (poster-only; no backdrop focus expansion).
//

import SwiftUI
import TMDb

struct MovieCollectionMediaRow: View {
    let title: String
    let collections: [MovieCollectionSummary]
    let config: APIConfiguration?
    let onSelect: (MovieCollectionSummary) -> Void
    var onSeeAll: (() -> Void)? = nil

    @FocusState private var focusedKey: String?
    @State private var scrollPositionId: String?

    private var firstKey: String? {
        collections.first.map { focusKey(for: $0, segment: 0) }
    }

    private func focusKey(for collection: MovieCollectionSummary, segment: Int) -> String {
        "\(title)_\(collection.id)_\(segment)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                if let onSeeAll {
                    let seeAllKey = "\(title)_seeAll"
                    Button(action: onSeeAll) {
                        HStack(spacing: 6) {
                            Text("See All")
                                .font(.subheadline)
                            Image(systemName: "chevron.right")
                                .font(.subheadline)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .focused($focusedKey, equals: seeAllKey)
                    .id(seeAllKey)
                }
            }
            .focusSection()
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: mediaPosterSpacing) {
                    ForEach(collections) { collection in
                        let key = focusKey(for: collection, segment: 0)
                        let isFocused = focusedKey == key
                        Button {
                            onSelect(collection)
                        } label: {
                            Color.clear
                                .frame(width: mediaCardPosterWidth, height: mediaCardPosterDisplayHeight)
                                .overlay(alignment: .topLeading) {
                                    MediaCard(
                                        posterPath: collection.posterPath,
                                        backdropPath: collection.backdropPath,
                                        config: config,
                                        isFocused: isFocused,
                                        alwaysPoster: true
                                    )
                                }
                        }
                        .buttonStyle(.plain)
                        .hoverEffectDisabled(true)
                        .focused($focusedKey, equals: key)
                        .accessibilityLabel(collection.title)
                        .frame(width: mediaCardPosterWidth, alignment: .topLeading)
                        .zIndex(isFocused ? 1 : 0)
                        .id(key)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal)
            }
            .scrollClipDisabled()
            .scrollPosition(id: Binding(
                get: { scrollPositionId ?? firstKey },
                set: { scrollPositionId = $0 }
            ), anchor: .leading)
            .onChange(of: focusedKey) { oldKey, newKey in
                if newKey == nil {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(100))
                        scrollPositionId = nil
                    }
                    return
                }
                guard let key = newKey else { return }
                let seeAllKey = "\(title)_seeAll"
                if key != seeAllKey {
                    if let first = firstKey, oldKey == seeAllKey {
                        scrollPositionId = first
                        focusedKey = first
                        return
                    }
                    // Entering this row from another shelf: start at the first poster, not a column-aligned middle item.
                    if oldKey == nil, let first = firstKey, key != first {
                        scrollPositionId = first
                        focusedKey = first
                        return
                    }
                }
                if key != seeAllKey {
                    scrollPositionId = key
                }
            }
            .onAppear {
                if let first = firstKey {
                    scrollPositionId = first
                }
            }
        }
        .defaultFocus($focusedKey, firstKey, priority: .userInitiated)
        .focusSection()
        .padding(.bottom, 16)
    }
}
