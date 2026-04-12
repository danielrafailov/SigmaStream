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
    var onFocusEnter: (() -> Void)? = nil
    var showMyListContextMenu: Bool = true

    @Environment(AppState.self) private var appState
    @FocusState private var focusedKey: String?
    @State private var scrollPositionId: String?
    @State private var neighborPrefetchTask: Task<Void, Never>?

    private struct CarouselItem {
        let movie: MovieListItem
        let segment: Int
        let title: String
        var focusKey: String { "\(title)_\(movie.id)_\(segment)" }
    }

    private static let carouselMinCount = 6

    private var useCarousel: Bool {
        movies.count >= Self.carouselMinCount
    }

    private var carouselMovieItems: [CarouselItem] {
        guard !movies.isEmpty else { return [] }
        if useCarousel {
            return (0..<2).flatMap { seg in movies.map { CarouselItem(movie: $0, segment: seg, title: title) } }
        }
        return movies.map { CarouselItem(movie: $0, segment: 0, title: title) }
    }

    private var firstMovieKey: String? {
        movies.first.map { "\(title)_\($0.id)_0" }
    }
    private var wrapRightKey: String { "\(title)_wrapRight" }

    private func firstCopyKey(for key: String) -> String? {
        guard key.hasSuffix("_1") else { return nil }
        return String(key.dropLast(2)) + "_0"
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
            .focusSection()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: mediaPosterSpacing) {
                    ForEach(carouselMovieItems, id: \.focusKey) { item in
                        let movie = item.movie
                        let focusKey = item.focusKey
                        let isFocused = focusedKey == focusKey
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                onSelect(movie)
                            } label: {
                                Color.clear
                                    .frame(width: mediaCardPosterWidth, height: mediaCardPosterDisplayHeight)
                                    .overlay(alignment: .topLeading) {
                                        MediaCard(
                                            posterPath: movie.posterPath,
                                            backdropPath: movie.backdropPath,
                                            config: config,
                                            isFocused: isFocused
                                        )
                                    }
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
                                    overview: movie.overview,
                                    maxDescriptionWidth: mediaCardBackdropWidth
                                )
                                .frame(maxWidth: mediaCardBackdropWidth, minHeight: 180, alignment: .topLeading)
                                .transition(.opacity)
                                .animation(.easeOut(duration: 0.12), value: isFocused)
                            }
                        }
                        .frame(width: isFocused ? mediaCardBackdropWidth : mediaCardPosterWidth, alignment: .topLeading)
                        .zIndex(isFocused ? 1 : 0)
                        .id(focusKey)
                    }

                    if useCarousel {
                        Color.clear
                            .frame(width: 80, height: 60)
                            .contentShape(Rectangle())
                            .focused($focusedKey, equals: wrapRightKey)
                            .id(wrapRightKey)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal)
            }
            .scrollClipDisabled()
            .scrollPosition(id: Binding(
                get: { scrollPositionId ?? firstMovieKey },
                set: { scrollPositionId = $0 }
            ), anchor: .leading)
            .onChange(of: focusedKey) { oldKey, newKey in
                if newKey == nil {
                    neighborPrefetchTask?.cancel()
                    neighborPrefetchTask = nil
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(100))
                        scrollPositionId = nil
                    }
                    return
                }
                guard let key = newKey else { return }
                let seeAllKey = "\(title)_seeAll"
                if key != seeAllKey && key != wrapRightKey {
                    onFocusEnter?()
                    if let first = firstMovieKey, oldKey == seeAllKey {
                        scrollPositionId = first
                        focusedKey = first
                        scheduleNeighborPrefetch(focusKey: first)
                        return
                    }
                }
                if useCarousel {
                    if key == wrapRightKey, let first = firstMovieKey {
                        scrollPositionId = first
                        focusedKey = first
                        scheduleNeighborPrefetch(focusKey: first)
                    } else if let firstCopy = firstCopyKey(for: key) {
                        scrollPositionId = firstCopy
                        focusedKey = firstCopy
                        scheduleNeighborPrefetch(focusKey: firstCopy)
                    } else if key != wrapRightKey, key != seeAllKey {
                        scrollPositionId = key
                        scheduleNeighborPrefetch(focusKey: key)
                    }
                } else if key != wrapRightKey, key != seeAllKey {
                    scrollPositionId = key
                    scheduleNeighborPrefetch(focusKey: key)
                }
            }
            .onAppear {
                if let first = firstMovieKey {
                    scrollPositionId = first
                }
                prefetchMovieRowImages()
            }
            .onDisappear {
                neighborPrefetchTask?.cancel()
                neighborPrefetchTask = nil
            }
        }
        .defaultFocus($focusedKey, firstMovieKey ?? (useCarousel ? wrapRightKey : nil), priority: .userInitiated)
        .focusSection()
        .padding(.bottom, 16)
    }

    private func prefetchMovieRowImages() {
        guard let config else { return }
        let backdropW = Int(mediaCardBackdropWidth)
        var urls: [URL] = []
        for m in movies.prefix(22) {
            if let u = ImageURLBuilder.posterURL(for: m.posterPath, config: config, idealWidth: 342) {
                urls.append(u)
            }
            if let u = ImageURLBuilder.backdropURL(for: m.backdropPath, config: config, idealWidth: backdropW) {
                urls.append(u)
            }
        }
        ImagePrefetcher.prefetch(urls: urls)
    }

    private func scheduleNeighborPrefetch(focusKey key: String) {
        neighborPrefetchTask?.cancel()
        neighborPrefetchTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            prefetchNeighborMovieImages(focusKey: key)
        }
    }

    private func prefetchNeighborMovieImages(focusKey key: String) {
        let seeAllKey = "\(title)_seeAll"
        guard key != seeAllKey, key != wrapRightKey else { return }
        guard let idx = carouselMovieItems.firstIndex(where: { $0.focusKey == key }) else { return }
        guard let config else { return }
        let backdropW = Int(mediaCardBackdropWidth)
        let lo = max(0, idx - 1)
        let hi = min(carouselMovieItems.count - 1, idx + 1)
        var urls: [URL] = []
        for i in lo...hi {
            let m = carouselMovieItems[i].movie
            if let u = ImageURLBuilder.posterURL(for: m.posterPath, config: config, idealWidth: 342) {
                urls.append(u)
            }
            if let u = ImageURLBuilder.backdropURL(for: m.backdropPath, config: config, idealWidth: backdropW) {
                urls.append(u)
            }
        }
        ImagePrefetcher.prefetch(urls: urls)
    }
}

/// Horizontal scrolling row of TV series cards.
struct TVSeriesMediaRow: View {
    let title: String
    let tvSeries: [TVSeriesListItem]
    let config: APIConfiguration?
    let onSelect: (TVSeriesListItem) -> Void
    var onSeeAll: (() -> Void)? = nil
    var onFocusEnter: (() -> Void)? = nil
    var showMyListContextMenu: Bool = true

    @Environment(AppState.self) private var appState
    @FocusState private var focusedKey: String?
    @State private var scrollPositionId: String?
    @State private var neighborPrefetchTask: Task<Void, Never>?

    private struct TVCarouselItem {
        let series: TVSeriesListItem
        let segment: Int
        let title: String
        var focusKey: String { "\(title)_\(series.id)_\(segment)" }
    }

    private static let carouselMinCount = 6

    private var useCarousel: Bool {
        tvSeries.count >= Self.carouselMinCount
    }

    private var carouselSeriesItems: [TVCarouselItem] {
        guard !tvSeries.isEmpty else { return [] }
        if useCarousel {
            return (0..<2).flatMap { seg in tvSeries.map { TVCarouselItem(series: $0, segment: seg, title: title) } }
        }
        return tvSeries.map { TVCarouselItem(series: $0, segment: 0, title: title) }
    }

    private var firstSeriesKey: String? {
        tvSeries.first.map { "\(title)_\($0.id)_0" }
    }
    private var wrapRightKey: String { "\(title)_wrapRight" }

    private func firstCopyKey(for key: String) -> String? {
        guard key.hasSuffix("_1") else { return nil }
        return String(key.dropLast(2)) + "_0"
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
            .focusSection()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: mediaPosterSpacing) {
                    ForEach(carouselSeriesItems, id: \.focusKey) { item in
                        let series = item.series
                        let focusKey = item.focusKey
                        let isFocused = focusedKey == focusKey
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                onSelect(series)
                            } label: {
                                Color.clear
                                    .frame(width: mediaCardPosterWidth, height: mediaCardPosterDisplayHeight)
                                    .overlay(alignment: .topLeading) {
                                        MediaCard(
                                            posterPath: series.posterPath,
                                            backdropPath: series.backdropPath,
                                            config: config,
                                            isFocused: isFocused
                                        )
                                    }
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
                                    overview: series.overview,
                                    maxDescriptionWidth: mediaCardBackdropWidth
                                )
                                .frame(maxWidth: mediaCardBackdropWidth, minHeight: 180, alignment: .topLeading)
                                .transition(.opacity)
                                .animation(.easeOut(duration: 0.12), value: isFocused)
                            }
                        }
                        .frame(width: isFocused ? mediaCardBackdropWidth : mediaCardPosterWidth, alignment: .topLeading)
                        .zIndex(isFocused ? 1 : 0)
                        .id(focusKey)
                    }

                    if useCarousel {
                        Color.clear
                            .frame(width: 80, height: 60)
                            .contentShape(Rectangle())
                            .focused($focusedKey, equals: wrapRightKey)
                            .id(wrapRightKey)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal)
            }
            .scrollClipDisabled()
            .scrollPosition(id: Binding(
                get: { scrollPositionId ?? firstSeriesKey },
                set: { scrollPositionId = $0 }
            ), anchor: .leading)
            .onChange(of: focusedKey) { oldKey, newKey in
                if newKey == nil {
                    neighborPrefetchTask?.cancel()
                    neighborPrefetchTask = nil
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(100))
                        scrollPositionId = nil
                    }
                    return
                }
                guard let key = newKey else { return }
                let seeAllKey = "\(title)_seeAll"
                if key != seeAllKey && key != wrapRightKey {
                    onFocusEnter?()
                    if let first = firstSeriesKey, oldKey == seeAllKey {
                        scrollPositionId = first
                        focusedKey = first
                        scheduleNeighborTVPrefetch(focusKey: first)
                        return
                    }
                }
                if useCarousel {
                    if key == wrapRightKey, let first = firstSeriesKey {
                        scrollPositionId = first
                        focusedKey = first
                        scheduleNeighborTVPrefetch(focusKey: first)
                    } else if let firstCopy = firstCopyKey(for: key) {
                        scrollPositionId = firstCopy
                        focusedKey = firstCopy
                        scheduleNeighborTVPrefetch(focusKey: firstCopy)
                    } else if key != wrapRightKey, key != seeAllKey {
                        scrollPositionId = key
                        scheduleNeighborTVPrefetch(focusKey: key)
                    }
                } else if key != wrapRightKey, key != seeAllKey {
                    scrollPositionId = key
                    scheduleNeighborTVPrefetch(focusKey: key)
                }
            }
            .onAppear {
                if let first = firstSeriesKey {
                    scrollPositionId = first
                }
                prefetchTVRowImages()
            }
            .onDisappear {
                neighborPrefetchTask?.cancel()
                neighborPrefetchTask = nil
            }
        }
        .defaultFocus($focusedKey, firstSeriesKey ?? (useCarousel ? wrapRightKey : nil), priority: .userInitiated)
        .focusSection()
        .padding(.bottom, 16)
    }

    private func prefetchTVRowImages() {
        guard let config else { return }
        let backdropW = Int(mediaCardBackdropWidth)
        var urls: [URL] = []
        for s in tvSeries.prefix(22) {
            if let u = ImageURLBuilder.posterURL(for: s.posterPath, config: config, idealWidth: 342) {
                urls.append(u)
            }
            if let u = ImageURLBuilder.backdropURL(for: s.backdropPath, config: config, idealWidth: backdropW) {
                urls.append(u)
            }
        }
        ImagePrefetcher.prefetch(urls: urls)
    }

    private func scheduleNeighborTVPrefetch(focusKey key: String) {
        neighborPrefetchTask?.cancel()
        neighborPrefetchTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            prefetchNeighborTVImages(focusKey: key)
        }
    }

    private func prefetchNeighborTVImages(focusKey key: String) {
        let seeAllKey = "\(title)_seeAll"
        guard key != seeAllKey, key != wrapRightKey else { return }
        guard let idx = carouselSeriesItems.firstIndex(where: { $0.focusKey == key }) else { return }
        guard let config else { return }
        let backdropW = Int(mediaCardBackdropWidth)
        let lo = max(0, idx - 1)
        let hi = min(carouselSeriesItems.count - 1, idx + 1)
        var urls: [URL] = []
        for i in lo...hi {
            let s = carouselSeriesItems[i].series
            if let u = ImageURLBuilder.posterURL(for: s.posterPath, config: config, idealWidth: 342) {
                urls.append(u)
            }
            if let u = ImageURLBuilder.backdropURL(for: s.backdropPath, config: config, idealWidth: backdropW) {
                urls.append(u)
            }
        }
        ImagePrefetcher.prefetch(urls: urls)
    }
}

// MARK: - Metadata Panel

/// Netflix-style metadata shown below a focused card.
struct MediaCardMetadata: View {
    let title: String
    let date: Date?
    let overview: String?
    /// When nil, uses mediaCardBackdropWidth.
    var maxDescriptionWidth: CGFloat? = nil

    private var effectiveMaxWidth: CGFloat {
        maxDescriptionWidth ?? mediaCardBackdropWidth
    }

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
                    .frame(maxWidth: effectiveMaxWidth - 48, minHeight: 140, alignment: .topLeading)
            }
        }
    }
}
