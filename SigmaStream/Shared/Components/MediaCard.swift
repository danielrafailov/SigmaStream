//
//  MediaCard.swift
//  SigmaStream
//
//  Created by Daniel Rafailov on 2026-03-16.
//

import SwiftUI
import TMDb

/// Reusable poster card for movies and TV shows.
struct MediaCard: View {
    let posterPath: URL?
    let title: String
    let subtitle: String?
    let config: APIConfiguration?

    init(posterPath: URL?, title: String, subtitle: String? = nil, config: APIConfiguration?) {
        self.posterPath = posterPath
        self.title = title
        self.subtitle = subtitle
        self.config = config
    }

    private var posterURL: URL? {
        ImageURLBuilder.posterURL(for: posterPath, config: config, idealWidth: 400)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let url = posterURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(2/3, contentMode: .fill)
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
                } else {
                    posterPlaceholder
                }
            }
            .frame(width: 220, height: 330)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(title.formattedAsTitleCase)
                .font(.headline)
                .lineLimit(1)

            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 220)
        .padding(8)
        .background(.ultraThinMaterial.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 16))
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
