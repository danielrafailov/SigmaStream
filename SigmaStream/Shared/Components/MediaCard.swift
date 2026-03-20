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

    private var imageURL: URL? {
        if alwaysPoster {
            return ImageURLBuilder.posterURL(for: posterPath, config: config, idealWidth: idealWidth)
        }
        if isFocused, let backdrop = backdropPath {
            return ImageURLBuilder.backdropURL(for: backdrop, config: config, idealWidth: Int(backdropWidth))
        }
        let width = isFocused ? 500 : idealWidth
        return ImageURLBuilder.posterURL(for: posterPath, config: config, idealWidth: width)
    }

    private var useBackdrop: Bool {
        !alwaysPoster && isFocused && backdropPath != nil
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
            if let url = imageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(useBackdrop ? 16/9 : 2/3, contentMode: .fill)
                    case .failure:
                        posterPlaceholder
                    case .empty:
                        posterPlaceholder
                            .overlay {
                                ProgressView()
                            }
                    @unknown default:
                        posterPlaceholder
                    }
                }
                .id(url)
                .transition(.opacity)
            } else {
                posterPlaceholder
            }
        }
        .modifier(CardFrameModifier(alwaysPoster: alwaysPoster, useBackdrop: useBackdrop, backdropWidth: backdropWidth, posterWidth: posterWidth, posterHeight: posterHeight))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            if isFocused {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white, lineWidth: 3)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: imageURL)
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
