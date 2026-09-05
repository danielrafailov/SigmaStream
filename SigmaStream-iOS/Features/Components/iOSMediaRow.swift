//
//  iOSMediaRow.swift
//  SigmaStream-iOS
//
//  Created by Daniel Rafailov on 2026-09-01.
//

import SwiftUI
import TMDb

#if os(iOS)
struct iOSMediaRowItem: Identifiable {
    let id: Int
    let title: String
    let posterURL: URL?
    let rating: Double?
    let releaseYear: String?
    let isTVSeries: Bool
    let progress: Double?
}

struct iOSMediaRow: View {
    let title: String
    let items: [iOSMediaRowItem]
    var onSeeAll: (() -> Void)? = nil
    let onSelect: (iOSMediaRowItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)

                Spacer()

                if let onSeeAll {
                    Button(action: onSeeAll) {
                        HStack(spacing: 3) {
                            Text("See All")
                                .font(.system(size: 13, weight: .medium))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(Color.blue)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)

            // Horizontal Swipeable Cards
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(items) { item in
                        Button {
                            onSelect(item)
                        } label: {
                            iOSMediaCard(
                                id: item.id,
                                title: item.title,
                                posterPath: item.posterURL,
                                rating: item.rating,
                                releaseYear: item.releaseYear,
                                isTVSeries: item.isTVSeries,
                                progress: item.progress,
                                cardWidth: 108,
                                cardHeight: 162
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}
#endif
