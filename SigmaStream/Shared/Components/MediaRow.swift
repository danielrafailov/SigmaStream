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
    @FocusState private var focusedKey: String?
    @State private var scrollPosition = ScrollPosition(idType: String.self)
    @State private var hasInitializedFocus = false

    private var firstMovieKey: String? {
        movies.first.map { "\(title)_\($0.id)" }
    }
    private var lastMovieKey: String? {
        movies.last.map { "\(title)_\($0.id)" }
    }
    private var wrapLeftKey: String { "\(title)_wrapLeft" }
    private var wrapRightKey: String { "\(title)_wrapRight" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                if let onSeeAll {
                    let seeAllKey = "\(title)_seeAll"
                    Button {
                        onSeeAll()
                    } label: {
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

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 20) {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .focused($focusedKey, equals: wrapLeftKey)
                        .id(wrapLeftKey)

                    ForEach(movies, id: \.id) { movie in
                        let focusKey = "\(title)_\(movie.id)"
                        let isFocused = focusedKey == focusKey
                        HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                onSelect(movie)
                            } label: {
                                MediaCard(
                                    posterPath: movie.posterPath,
                                    backdropPath: movie.backdropPath,
                                    config: config,
                                    isFocused: isFocused
                                )
                            }
                            .buttonStyle(.plain)
                            .hoverEffectDisabled(true)
                            .focused($focusedKey, equals: focusKey)
                            .accessibilityLabel(movie.title)
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

                            if isFocused {
                                MediaCardMetadata(
                                    title: movie.title,
                                    date: movie.releaseDate,
                                    overview: movie.overview
                                )
                                .frame(maxWidth: mediaCardBackdropWidth, minHeight: 180, alignment: .topLeading)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                                .animation(.easeInOut(duration: 0.2), value: focusedKey)
                            }
                        }
                            if isFocused {
                                Color.clear.frame(width: 32)
                            }
                        }
                        .id(focusKey)
                    }

                    Color.clear
                        .frame(width: 1, height: 1)
                        .focused($focusedKey, equals: wrapRightKey)
                        .id(wrapRightKey)
                }
                .scrollTargetLayout()
                .padding(.horizontal)
            }
            .scrollPosition($scrollPosition, anchor: .leading)
            .onChange(of: focusedKey) { oldKey, newKey in
                guard let key = newKey else { return }
                if key == wrapRightKey, let first = firstMovieKey {
                    Task { @MainActor in
                        scrollPosition.scrollTo(id: first, anchor: .leading)
                        focusedKey = first
                    }
                } else if key == wrapLeftKey {
                    let cameFromSeeAll = oldKey == "\(title)_seeAll"
                    let target = (cameFromSeeAll ? firstMovieKey : lastMovieKey) ?? firstMovieKey
                    if let t = target {
                        Task { @MainActor in
                            if t == lastMovieKey {
                                scrollPosition.scrollTo(id: t, anchor: .trailing)
                            } else {
                                scrollPosition.scrollTo(id: t, anchor: .leading)
                            }
                            focusedKey = t
                        }
                    }
                } else if key != wrapLeftKey && key != wrapRightKey {
                    scrollPosition.scrollTo(id: key, anchor: .leading)
                }
            }
            .onAppear {
                if !hasInitializedFocus, let first = firstMovieKey {
                    hasInitializedFocus = true
                    scrollPosition.scrollTo(id: first, anchor: .leading)
                    focusedKey = first
                }
            }
            .defaultFocus($focusedKey, firstMovieKey ?? wrapLeftKey)
        }
        .focusSection()
        .padding(.bottom, 16)
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
    @FocusState private var focusedKey: String?
    @State private var scrollPosition = ScrollPosition(idType: String.self)
    @State private var hasInitializedFocus = false

    private var firstSeriesKey: String? {
        tvSeries.first.map { "\(title)_\($0.id)" }
    }
    private var lastSeriesKey: String? {
        tvSeries.last.map { "\(title)_\($0.id)" }
    }
    private var wrapLeftKey: String { "\(title)_wrapLeft" }
    private var wrapRightKey: String { "\(title)_wrapRight" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                if let onSeeAll {
                    let seeAllKey = "\(title)_seeAll"
                    Button {
                        onSeeAll()
                    } label: {
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

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 20) {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .focused($focusedKey, equals: wrapLeftKey)
                        .id(wrapLeftKey)

                    ForEach(tvSeries, id: \.id) { series in
                        let focusKey = "\(title)_\(series.id)"
                        let isFocused = focusedKey == focusKey
                        HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                onSelect(series)
                            } label: {
                                MediaCard(
                                    posterPath: series.posterPath,
                                    backdropPath: series.backdropPath,
                                    config: config,
                                    isFocused: isFocused
                                )
                            }
                            .buttonStyle(.plain)
                            .hoverEffectDisabled(true)
                            .focused($focusedKey, equals: focusKey)
                            .accessibilityLabel(series.name)
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

                            if isFocused {
                                MediaCardMetadata(
                                    title: series.name,
                                    date: series.firstAirDate,
                                    overview: series.overview
                                )
                                .frame(maxWidth: mediaCardBackdropWidth, minHeight: 180, alignment: .topLeading)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                                .animation(.easeInOut(duration: 0.2), value: focusedKey)
                            }
                        }
                            if isFocused {
                                Color.clear.frame(width: 32)
                            }
                        }
                        .id(focusKey)
                    }

                    Color.clear
                        .frame(width: 1, height: 1)
                        .focused($focusedKey, equals: wrapRightKey)
                        .id(wrapRightKey)
                }
                .scrollTargetLayout()
                .padding(.horizontal)
            }
            .scrollPosition($scrollPosition, anchor: .leading)
            .onChange(of: focusedKey) { oldKey, newKey in
                guard let key = newKey else { return }
                if key == wrapRightKey, let first = firstSeriesKey {
                    Task { @MainActor in
                        scrollPosition.scrollTo(id: first, anchor: .leading)
                        focusedKey = first
                    }
                } else if key == wrapLeftKey {
                    let cameFromSeeAll = oldKey == "\(title)_seeAll"
                    let target = (cameFromSeeAll ? firstSeriesKey : lastSeriesKey) ?? firstSeriesKey
                    if let t = target {
                        Task { @MainActor in
                            if t == lastSeriesKey {
                                scrollPosition.scrollTo(id: t, anchor: .trailing)
                            } else {
                                scrollPosition.scrollTo(id: t, anchor: .leading)
                            }
                            focusedKey = t
                        }
                    }
                } else if key != wrapLeftKey && key != wrapRightKey {
                    scrollPosition.scrollTo(id: key, anchor: .leading)
                }
            }
            .onAppear {
                if !hasInitializedFocus, let first = firstSeriesKey {
                    hasInitializedFocus = true
                    scrollPosition.scrollTo(id: first, anchor: .leading)
                    focusedKey = first
                }
            }
            .defaultFocus($focusedKey, firstSeriesKey ?? wrapLeftKey)
        }
        .focusSection()
        .padding(.bottom, 16)
    }
}

// MARK: - Metadata Panel

/// Netflix-style metadata shown below a focused card.
struct MediaCardMetadata: View {
    let title: String
    let date: Date?
    let overview: String?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
                .lineLimit(1)

            if let date {
                Text(date, formatter: Self.dateFormatter)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let overview, !overview.isEmpty {
                Text(overview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: mediaCardBackdropWidth, minHeight: 140, alignment: .topLeading)
            }
        }
    }
}
