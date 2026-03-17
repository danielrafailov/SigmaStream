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
    var onSeeAll: (() -> Void)? = nil
    var showMyListContextMenu: Bool = true

    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                if let onSeeAll {
                    Button("See All") {
                        onSeeAll()
                    }
                    .font(.subheadline)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(movies, id: \.id) { movie in
                        Button {
                            onSelect(movie)
                        } label: {
                            MediaCard(
                                posterPath: movie.posterPath,
                                title: movie.title,
                                subtitle: movie.releaseDate.map { formatYear($0) },
                                config: config
                            )
                        }
                        .buttonStyle(.plain)
                        .hoverEffect(.lift)
                        .contextMenu {
                            if showMyListContextMenu {
                                if appState.myListManager.isMovieInList(movie.id) {
                                    Button("Remove from My List", role: .destructive) {
                                        appState.myListManager.toggleMovie(movie.id)
                                    }
                                } else {
                                    Button("Add to My List") {
                                        appState.myListManager.toggleMovie(movie.id)
                                    }
                                }
                            }
                        }
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
    var onSeeAll: (() -> Void)? = nil
    var showMyListContextMenu: Bool = true

    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                if let onSeeAll {
                    Button("See All") {
                        onSeeAll()
                    }
                    .font(.subheadline)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(tvSeries, id: \.id) { series in
                        Button {
                            onSelect(series)
                        } label: {
                            MediaCard(
                                posterPath: series.posterPath,
                                title: series.name,
                                subtitle: series.firstAirDate.map { formatYear($0) },
                                config: config
                            )
                        }
                        .buttonStyle(.plain)
                        .hoverEffect(.lift)
                        .contextMenu {
                            if showMyListContextMenu {
                                if appState.myListManager.isSeriesInList(series.id) {
                                    Button("Remove from My List", role: .destructive) {
                                        appState.myListManager.toggleSeries(series.id)
                                    }
                                } else {
                                    Button("Add to My List") {
                                        appState.myListManager.toggleSeries(series.id)
                                    }
                                }
                            }
                        }
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
