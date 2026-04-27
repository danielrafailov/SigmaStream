//
//  TVSeriesDetailView.swift
//  SigmaStream
//
//  Created by Daniel Rafailov on 2026-03-16.
//

import SwiftUI
import TMDb

struct TVSeriesDetailView: View {
    let seriesId: Int
    @Environment(AppState.self) private var appState
    @State private var series: TVSeries?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedSeason = 1
    @State private var loadedSeason: TVSeason?
    @State private var isLoadingSeason = false
    @State private var playableContent: PlayableContent?
    @State private var streamQuality: String?
    @State private var isResolvingStream = false
    @State private var showStreamPicker = false
    @State private var streamPickerSources: [OMSSSource] = []
    @State private var streamPickerEpisode: (season: Int, episode: Int, title: String)?
    @State private var pendingStreamSelection: (source: OMSSSource, season: Int, episode: Int, title: String)?
    @State private var streamError: String?
    @State private var trailerYouTubeKey: String?
    @State private var trailerAlertMessage: String?
    @State private var moreEpisodesSeries: TVSeries?
    @State private var streamResolutionTask: Task<Void, Never>?
    @State private var streamLookupOverlayMessage: String?
    @FocusState private var focusedButtonId: String?
    @FocusState private var focusedThumbId: String?

    private var seasonNumbers: [Int] {
        guard let s = series else { return [1] }
        if let seasons = s.seasons, !seasons.isEmpty {
            return seasons.map(\.seasonNumber).sorted()
        }
        if let n = s.numberOfSeasons, n > 0 {
            return Array(1...n)
        }
        return [1]
    }

    private var firstEpisode: (season: Int, episode: TVEpisode)? {
        guard let season = loadedSeason, let episodes = season.episodes, !episodes.isEmpty else { return nil }
        let ep = episodes.first!
        return (selectedSeason, ep)
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                ContentUnavailableView(
                    "Couldn't load TV series",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if let series {
                GeometryReader { geo in
                    let contentWidth = geo.size.width * 0.45
                    ZStack(alignment: .leading) {
                        if let backdropURL = ImageURLBuilder.backdropURL(for: series.backdropPath, config: appState.apiConfiguration) {
                            AsyncImage(url: backdropURL) { phase in
                                if case .success(let image) = phase {
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .ignoresSafeArea()

                            AsyncImage(url: backdropURL) { phase in
                                if case .success(let image) = phase {
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .blur(radius: 24)
                            .overlay(Color.black.opacity(0.5))
                            .mask(
                                LinearGradient(
                                    colors: [.black, .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .ignoresSafeArea()
                        }

                        ScrollView {
                            VStack(alignment: .leading, spacing: 24) {
                                Text(series.name)
                                    .font(.system(size: 48, weight: .bold))

                                metadataRow

                                if let overview = series.overview, !overview.isEmpty {
                                    Text(overview)
                                        .font(.body)
                                        .frame(maxWidth: contentWidth, alignment: .leading)
                                }

                                thumbsAndButtonsSection(contentWidth: contentWidth)
                                    .padding(.leading, 24)

                                if let streamErr = streamError {
                                    Text(streamErr)
                                        .foregroundStyle(.red)
                                        .font(.subheadline)
                                }
                            }
                            .frame(maxWidth: contentWidth, alignment: .leading)
                            .padding(48)
                        }
                    }
                }
            }
        }
        .navigationTitle("")
        .navigationDestination(item: $moreEpisodesSeries) { s in
            TVSeriesMoreEpisodesView(seriesId: s.id, seriesName: s.name)
                .environment(appState)
        }
        .alert("Trailer", isPresented: Binding(
            get: { trailerAlertMessage != nil },
            set: { if !$0 { trailerAlertMessage = nil } }
        )) {
            Button("OK") { trailerAlertMessage = nil }
        } message: {
            Text(trailerAlertMessage ?? "")
        }
        .sheet(isPresented: $showStreamPicker, onDismiss: {
            if let pending = pendingStreamSelection {
                pendingStreamSelection = nil
                Task { await playSource(pending.source, season: pending.season, episode: pending.episode, title: pending.title) }
            }
        }) {
            StreamPickerView(
                title: streamPickerEpisode.map { "\(series?.name ?? "Episode") - \($0.title)" } ?? (series?.name ?? "Episode"),
                sources: streamPickerSources,
                onSelect: { source in
                    if let ep = streamPickerEpisode {
                        pendingStreamSelection = (source, ep.season, ep.episode, ep.title)
                    }
                    showStreamPicker = false
                },
                onDismiss: { showStreamPicker = false }
            )
            .environment(appState)
        }
        .fullScreenCover(item: $playableContent) { content in
            VideoPlayerView(
                urls: content.urls,
                title: content.title,
                onPlaybackEnded: {
                    if let sid = content.tvSeriesId,
                       let s = content.season,
                       let e = content.episode {
                        appState.watchProgressManager.removeEpisode(seriesId: sid, season: s, episode: e)
                    }
                }
            )
        }
        .overlay {
            if streamLookupOverlayMessage != nil {
                StreamLookupBlockingOverlay(
                    headline: "Finding a stream",
                    message: streamLookupOverlayMessage ?? "",
                    onCancel: cancelStreamResolution
                )
                .allowsHitTesting(true)
                .zIndex(1000)
            }
        }
        .task {
            await loadSeries()
        }
        .onChange(of: selectedSeason) { _, newValue in
            Task { await loadSeason(newValue) }
        }
    }

    private func detailButton(id: String, icon: String, title: String, action: @escaping () -> Void, disabled: Bool = false) -> some View {
        let isFocused = focusedButtonId == id
        return Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                Text(title)
                    .font(.system(size: 20, weight: .medium))
            }
            .foregroundStyle(isFocused ? .black : .white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 0)
            .padding(.trailing, 24)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .focused($focusedButtonId, equals: id)
        .disabled(disabled)
    }

    private var metadataRow: some View {
        HStack(spacing: 12) {
            if let date = series?.firstAirDate {
                Text(Calendar.current.component(.year, from: date).description)
                    .foregroundStyle(.secondary)
            }
            if let genres = series?.genres, !genres.isEmpty {
                Text(genres.prefix(2).map(\.name).joined(separator: ", "))
                    .foregroundStyle(.secondary)
            }
            if let n = series?.numberOfSeasons, n > 0 {
                Text("\(n) Season\(n == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
            }
            if let q = streamQuality {
                Text(q)
                    .foregroundStyle(.secondary)
            }
            if let rating = series?.voteAverage {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.caption)
                    Text(String(format: "%.1f", rating))
                }
                .foregroundStyle(.secondary)
            }
            Image(systemName: "captions.bubble")
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }

    @ViewBuilder
    private func thumbsAndButtonsSection(contentWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            thumbsRow(contentWidth: contentWidth)

            if let first = firstEpisode {
                detailButton(id: "play", icon: "play.fill", title: "Play Episode") {
                    startResolveStream(season: first.season, episode: first.episode.episodeNumber, title: first.episode.name)
                }
                .disabled(isResolvingStream)

                detailButton(id: "chooseStream", icon: "list.bullet", title: "Choose Stream") {
                    startShowStreamPickerFetch(season: first.season, episode: first.episode.episodeNumber, title: first.episode.name)
                }
                .disabled(isResolvingStream)
            }

            detailButton(id: "more", icon: "list.bullet", title: "More Episodes") {
                moreEpisodesSeries = series
            }

            if let key = trailerYouTubeKey {
                detailButton(id: "trailer", icon: "play.rectangle.fill", title: "Watch Trailer") {
                    openTrailer(key: key)
                }
            }

            detailButton(
                id: "mylist",
                icon: appState.myListManager.isSeriesInList(seriesId) ? "minus.circle" : "plus.circle",
                title: appState.myListManager.isSeriesInList(seriesId) ? "Remove from My List" : "Add to My List"
            ) {
                appState.myListManager.toggleSeries(seriesId)
            }
        }
        .frame(maxWidth: contentWidth, alignment: .leading)
        .focusSection()
    }

    private func thumbsRow(contentWidth: CGFloat) -> some View {
        HStack(spacing: 56) {
            Button {
                appState.likedManager.toggleSeries(seriesId)
            } label: {
                Image(systemName: appState.likedManager.isSeriesLiked(seriesId) ? "hand.thumbsup.fill" : "hand.thumbsup")
                    .foregroundStyle(focusedThumbId == "up" ? .black : (appState.likedManager.isSeriesLiked(seriesId) ? .white : .secondary))
                    .font(.system(size: 20))
                    .frame(width: 60, height: 60)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focused($focusedThumbId, equals: "up")
        }
        .frame(maxWidth: contentWidth, alignment: .leading)
    }

    private func openTrailer(key: String) {
        let youtubeURL = URL(string: "youtube://watch/\(key)")
        let httpsURL = URL(string: "https://www.youtube.com/watch?v=\(key)")!
        let canOpenYouTube = youtubeURL.map { UIApplication.shared.canOpenURL($0) } ?? false
        let urlToOpen = (canOpenYouTube && youtubeURL != nil) ? youtubeURL! : httpsURL

        UIApplication.shared.open(urlToOpen) { success in
            if !success {
                trailerAlertMessage = "You need the YouTube app to view trailers. Install it from the App Store if you haven't already."
            }
        }
    }

    private func loadSeries() async {
        do {
            let result = try await appState.tmdbService.tvSeriesDetails(forSeriesId: seriesId)
            series = result
            trailerYouTubeKey = try? await appState.tmdbService.tvSeriesTrailerYouTubeKey(seriesId: seriesId)
            let seasons = (result.seasons ?? []).map(\.seasonNumber).sorted()
            selectedSeason = seasons.first ?? (result.numberOfSeasons ?? 1)
            await loadSeason(selectedSeason)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func loadSeason(_ seasonNumber: Int) async {
        isLoadingSeason = true
        streamError = nil
        defer { isLoadingSeason = false }

        do {
            loadedSeason = try await appState.tmdbService.tvSeasonDetails(seriesId: seriesId, seasonNumber: seasonNumber)
        } catch {
            loadedSeason = nil
            streamError = error.localizedDescription
        }
    }

    private func cancelStreamResolution() {
        streamResolutionTask?.cancel()
    }

    private func startResolveStream(season: Int, episode: Int, title: String) {
        guard !isResolvingStream else { return }
        streamResolutionTask?.cancel()
        streamResolutionTask = Task { @MainActor in
            isResolvingStream = true
            streamLookupOverlayMessage = "Searching for streams"
            streamError = nil
            defer {
                isResolvingStream = false
                streamLookupOverlayMessage = nil
                streamResolutionTask = nil
            }
            do {
                try Task.checkCancellation()
                let (urls, quality) = try await appState.streamingService.playableURLsAndQualityForEpisode(seriesId: seriesId, season: season, episode: episode)
                try Task.checkCancellation()
                guard !urls.isEmpty else {
                    streamError = "No stream was found"
                    return
                }
                if let quality { streamQuality = quality }
                playableContent = PlayableContent(urls: urls, title: "\(series?.name ?? "Episode") - \(title)", quality: quality, tvSeriesId: seriesId, season: season, episode: episode)
                appState.watchProgressManager.recordEpisode(seriesId: seriesId, season: season, episode: episode)
            } catch is CancellationError {
                return
            } catch {
                streamError = "No stream was found"
            }
        }
    }

    private func startShowStreamPickerFetch(season: Int, episode: Int, title: String) {
        guard !isResolvingStream else { return }
        streamResolutionTask?.cancel()
        streamResolutionTask = Task { @MainActor in
            isResolvingStream = true
            streamLookupOverlayMessage = "Searching for streams"
            streamError = nil
            defer {
                isResolvingStream = false
                streamLookupOverlayMessage = nil
                streamResolutionTask = nil
            }
            do {
                try Task.checkCancellation()
                let sources = try await appState.streamingService.sourcesForEpisode(seriesId: seriesId, season: season, episode: episode)
                try Task.checkCancellation()
                let playable = sources.filter { $0.isPlayable }
                guard !playable.isEmpty else {
                    streamError = "No stream was found"
                    return
                }
                if let q = playable.first?.quality { streamQuality = q }
                streamPickerSources = playable
                streamPickerEpisode = (season, episode, title)
                showStreamPicker = true
            } catch is CancellationError {
                return
            } catch {
                streamError = "No stream was found"
            }
        }
    }

    private func playSource(_ source: OMSSSource, season: Int, episode: Int, title: String) async {
        guard let url = await appState.streamingService.playableURL(for: source) else {
            streamError = "Could not load stream"
            return
        }
        if let q = source.quality { streamQuality = q }
        let content = PlayableContent(urls: [url], title: "\(series?.name ?? "Episode") - \(title)", quality: source.quality, tvSeriesId: seriesId, season: season, episode: episode)
        await MainActor.run {
            playableContent = content
            appState.watchProgressManager.recordEpisode(seriesId: seriesId, season: season, episode: episode)
        }
    }
}

#Preview {
    NavigationStack {
        TVSeriesDetailView(seriesId: 1399)
            .environment(AppState(apiKey: "placeholder"))
    }
}
