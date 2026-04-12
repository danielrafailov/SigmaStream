//
//  MediaCard.swift
//  SigmaStream
//
//  Created by Daniel Rafailov on 2026-03-16.
//

import SwiftUI
import TMDb

/// Poster height used for both poster and backdrop (locked ratio scaling).
/// ~1/2 of 1080p screen height for larger posters.
private let posterHeight: CGFloat = 540

/// Full width of the wide poster (backdrop). Use for metadata panel width.
let mediaCardBackdropWidth: CGFloat = posterHeight * (16.0 / 9.0)

/// Poster width for 2:3 ratio. Exported for layout calculations.
let mediaCardPosterWidth: CGFloat = posterHeight * (2.0 / 3.0)

/// Extended description width: wide poster + spacing + one poster (aligns with 2nd poster).
let mediaCardExtendedDescriptionWidth: CGFloat = mediaCardBackdropWidth + 20 + mediaCardPosterWidth

/// Gap between adjacent posters in horizontal rows and category grids (Netflix-style).
let mediaPosterSpacing: CGFloat = 10

private let mediaPosterCornerRadius: CGFloat = 10

/// Poster-only card for movies and TV shows (Netflix-style).
/// When focused: shows wider backdrop (16:9) with height locked to poster height. When unfocused: shows poster (2:3).
struct MediaCard: View {
    let posterPath: URL?
    let backdropPath: URL?
    let config: APIConfiguration?
    var idealWidth: Int = 342
    var isFocused: Bool = false
    /// When true, always show poster (2:3) even when focused. Used for See All grid.
    var alwaysPoster: Bool = false

    @State private var backdropOpacity: CGFloat = 0

    init(posterPath: URL?, backdropPath: URL? = nil, config: APIConfiguration?, idealWidth: Int = 342, isFocused: Bool = false, alwaysPoster: Bool = false) {
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.config = config
        self.idealWidth = idealWidth
        self.isFocused = isFocused
        self.alwaysPoster = alwaysPoster
    }

    /// Legacy initializer for backward compatibility (title/subtitle ignored, poster-only display).
    init(posterPath: URL?, title: String, subtitle: String? = nil, config: APIConfiguration?) {
        self.posterPath = posterPath
        self.backdropPath = nil
        self.config = config
        self.idealWidth = 342
        self.isFocused = false
        self.alwaysPoster = false
    }

    private var useBackdrop: Bool {
        !alwaysPoster && isFocused && backdropPath != nil
    }

    /// Poster URL for the always-visible layer (matches unfocused size when widening to backdrop).
    private var basePosterURL: URL? {
        if alwaysPoster {
            return ImageURLBuilder.posterURL(for: posterPath, config: config, idealWidth: idealWidth)
        }
        if useBackdrop {
            return ImageURLBuilder.posterURL(for: posterPath, config: config, idealWidth: idealWidth)
        }
        let width = isFocused ? 500 : idealWidth
        return ImageURLBuilder.posterURL(for: posterPath, config: config, idealWidth: width)
    }

    private var backdropURL: URL? {
        guard useBackdrop, let backdropPath else { return nil }
        return ImageURLBuilder.backdropURL(for: backdropPath, config: config, idealWidth: Int(backdropWidth))
    }

    /// Drives frame animation (same intent as previous `imageURL` animation).
    private var layoutAnimationID: String {
        if alwaysPoster { return "poster_\(idealWidth)" }
        if useBackdrop { return "backdrop" }
        let width = isFocused ? 500 : idealWidth
        return "poster_\(width)"
    }

    /// Backdrop width to maintain 16:9 with height = posterHeight.
    private var backdropWidth: CGFloat {
        posterHeight * (16.0 / 9.0)
    }

    /// Poster width for 2:3 ratio.
    private var posterWidth: CGFloat {
        posterHeight * (2.0 / 3.0)
    }

    var body: some View {
        Group {
            if useBackdrop, let bURL = backdropURL {
                ZStack {
                    if let pURL = basePosterURL {
                        // Fit full poster inside 16:9 (fill was over-cropping / too zoomed).
                        posterAsync(url: pURL, aspect: 2 / 3, contentMode: .fit, showProgressOnEmpty: false)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background {
                                Rectangle()
                                    .fill(.black.opacity(0.35))
                            }
                    } else {
                        posterPlaceholder
                    }
                    backdropAsync(url: bURL)
                }
            } else if let pURL = basePosterURL {
                posterAsync(url: pURL, aspect: 2 / 3, contentMode: .fill, showProgressOnEmpty: true)
            } else {
                posterPlaceholder
            }
        }
        .modifier(CardFrameModifier(alwaysPoster: alwaysPoster, useBackdrop: useBackdrop, backdropWidth: backdropWidth, posterWidth: posterWidth, posterHeight: posterHeight))
        .clipShape(RoundedRectangle(cornerRadius: mediaPosterCornerRadius, style: .continuous))
        .overlay {
            if isFocused {
                RoundedRectangle(cornerRadius: mediaPosterCornerRadius, style: .continuous)
                    .stroke(Color.white, lineWidth: 3)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: layoutAnimationID)
        .onChange(of: useBackdrop) { _, new in
            if !new { backdropOpacity = 0 }
        }
        .onChange(of: backdropURL?.absoluteString) { _, _ in
            backdropOpacity = 0
        }
    }

    @ViewBuilder
    private func posterAsync(url: URL, aspect: CGFloat, contentMode: ContentMode, showProgressOnEmpty: Bool) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(aspect, contentMode: contentMode)
            case .failure:
                posterPlaceholder
            case .empty:
                posterPlaceholder
                    .overlay {
                        if showProgressOnEmpty {
                            ProgressView()
                        }
                    }
            @unknown default:
                posterPlaceholder
            }
        }
    }

    @ViewBuilder
    private func backdropAsync(url: URL) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(16 / 9, contentMode: .fill)
                    .opacity(backdropOpacity)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            backdropOpacity = 1
                        }
                    }
            case .failure:
                EmptyView()
            case .empty:
                EmptyView()
            @unknown default:
                EmptyView()
            }
        }
    }

    private var posterPlaceholder: some View {
        Rectangle()
            .fill(.quaternary)
            .overlay {
                Image(systemName: "film")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
            }
    }
}

private struct CardFrameModifier: ViewModifier {
    let alwaysPoster: Bool
    let useBackdrop: Bool
    let backdropWidth: CGFloat
    let posterWidth: CGFloat
    let posterHeight: CGFloat

    func body(content: Content) -> some View {
        if alwaysPoster {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .aspectRatio(2/3, contentMode: .fill)
        } else {
            content
                .frame(width: useBackdrop ? backdropWidth : posterWidth, height: posterHeight)
        }
    }
}
