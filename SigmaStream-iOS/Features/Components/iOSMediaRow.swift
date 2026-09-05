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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let title: String
    let items: [iOSMediaRowItem]
    var onSeeAll: (() -> Void)? = nil
    let onSelect: (iOSMediaRowItem) -> Void

    private var isIPad: Bool {
        horizontalSizeClass == .regular
    }

    private var cardWidth: CGFloat {
        isIPad ? 144 : 108
    }

    private var cardHeight: CGFloat {
        isIPad ? 216 : 162
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isIPad ? 12 : 10) {
            // Header
            HStack {
                Text(title)
                    .font(.system(size: isIPad ? 22 : 18, weight: .bold))
                    .foregroundStyle(.white)

                Spacer()

                if let onSeeAll {
                    Button(action: onSeeAll) {
                        HStack(spacing: 3) {
                            Text("See All")
                                .font(.system(size: isIPad ? 15 : 13, weight: .medium))
                            Image(systemName: "chevron.right")
                                .font(.system(size: isIPad ? 13 : 11, weight: .semibold))
                        }
                        .foregroundStyle(Color.blue)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, isIPad ? 24 : 16)

            // Horizontal Swipeable Cards
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: isIPad ? 16 : 12) {
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
                                cardWidth: cardWidth,
                                cardHeight: cardHeight
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, isIPad ? 24 : 16)
            }
        }
    }
}
#endif
