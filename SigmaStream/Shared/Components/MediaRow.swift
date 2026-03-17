//
//  MediaRow.swift
//  SigmaStream
//
//  Created by Daniel Rafailov on 2026-03-16.
//

import SwiftUI
import TMDb

/// Horizontal scrolling row of movie cards.
struct MovieMediaRow: View {
    let title: String
    let movies: [MovieListItem]
    let config: APIConfiguration?
    let onSelect: (MovieListItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(movies, id: \.id) { movie in
                        Button {
                            onSelect(movie)
                        } label: {
                            MediaCard(
                                posterPath: movie.posterPath,
                                title: movie.title,
                                subtitle: movie.releaseDate.map { formatYear($0) } ?? movie.voteAverage.map { String(format: "%.1f", $0) + "/10" },
                                config: config
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
        .focusSection()
    }

    private func formatYear(_ date: Date) -> String {
        Calendar.current.component(.year, from: date).description
    }
}

/// Horizontal scrolling row of TV series cards.
struct TVSeriesMediaRow: View {
    let title: String
    let tvSeries: [TVSeriesListItem]
    let config: APIConfiguration?
    let onSelect: (TVSeriesListItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(tvSeries, id: \.id) { series in
                        Button {
                            onSelect(series)
                        } label: {
                            MediaCard(
                                posterPath: series.posterPath,
                                title: series.name,
                                subtitle: series.firstAirDate.map { formatYear($0) } ?? series.voteAverage.map { String(format: "%.1f", $0) + "/10" },
                                config: config
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
        .focusSection()
    }

    private func formatYear(_ date: Date) -> String {
        Calendar.current.component(.year, from: date).description
    }
}
