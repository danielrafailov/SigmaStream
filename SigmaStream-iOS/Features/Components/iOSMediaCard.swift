//
//  iOSMediaCard.swift
//  SigmaStream-iOS
//
//  Created by Daniel Rafailov on 2026-09-01.
//

import SwiftUI
import TMDb

#if os(iOS)
struct iOSMediaCard: View {
    @Environment(AppState.self) private var appState
    let id: Int
    let title: String
    let posterPath: URL?
    let rating: Double?
    let releaseYear: String?
    let isTVSeries: Bool
    let progress: Double? // 0.0 to 1.0 if partially watched
    var showLabels: Bool = false
    var cardWidth: CGFloat? = nil
    var cardHeight: CGFloat? = nil

    @State private var isPressing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let cardWidth, let cardHeight {
                // Fixed-size card for horizontal rows
                ZStack(alignment: .bottom) {
                    posterImage
                        .frame(width: cardWidth, height: cardHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                        )
                        .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 2)

                    progressBar
                    tvBadge
                }
                .frame(width: cardWidth, height: cardHeight)
            } else {
                // Flexible responsive card for 3-column grids
                ZStack(alignment: .bottom) {
                    Color.clear
                        .aspectRatio(2/3, contentMode: .fit)
                        .overlay(
                            posterImage
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                        )
                        .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 2)

                    progressBar
                    tvBadge
                }
                .aspectRatio(2/3, contentMode: .fit)
                .frame(minWidth: 0, maxWidth: .infinity)
            }

            // Title & Metadata (Only shown if showLabels is true)
            if showLabels {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if let releaseYear, !releaseYear.isEmpty {
                            Text(releaseYear)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        if let rating, rating > 0 {
                            HStack(spacing: 2) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.yellow)
                                Text(String(format: "%.1f", rating))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(maxWidth: cardWidth ?? .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: cardWidth ?? .infinity)
        .scaleEffect(isPressing ? 0.96 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressing)
    }

    @ViewBuilder
    private var posterImage: some View {
        ZStack {
            Color.white.opacity(0.06)

            if let posterPath {
                AsyncImage(url: posterPath) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        Image(systemName: "film")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    case .empty:
                        ProgressView()
                            .tint(.white.opacity(0.5))
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                Image(systemName: isTVSeries ? "tv" : "film")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var progressBar: some View {
        if let progress, progress > 0.02 {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.black.opacity(0.6))
                        .frame(height: 4)

                    Rectangle()
                        .fill(Color.red)
                        .frame(width: geo.size.width * CGFloat(min(1.0, progress)), height: 4)
                }
            }
            .frame(height: 4)
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8))
        }
    }

    @ViewBuilder
    private var tvBadge: some View {
        if isTVSeries {
            HStack {
                Spacer()
                Text("TV")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2.5)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .padding(5)
            }
            .frame(maxHeight: .infinity, alignment: .topTrailing)
        }
    }
}
#endif
