//
//  TVSeriesMoreEpisodesView.swift
//  SigmaStream
//
//  More Episodes page: description top-left, backdrop right, season dropdown, episodes below.
//

import SwiftUI
import TMDb

struct TVSeriesMoreEpisodesView: View {
    let seriesId: Int
    let seriesName: String
    @Environment(AppState.self) private var appState
    @State private var series: TVSeries?
    @State private var selectedSeason = 1
    @State private var loadedSeason: TVSeason?
    @State private var isLoadingSeason = false
    @State private var playableContent: PlayableContent?
    @State private var isResolvingStream = false
    @State private var showStreamPicker = false
    @State private var streamPickerSources: [OMSSSource] = []
    @State private var streamPickerEpisode: (season: Int, episode: Int, title: String)?
    @State private var pendingStreamSelection: (source: OMSSSource, season: Int, episode: Int, title: String)?
    @State private var streamError: String?
    @FocusState private var focusedEpisodeId: Int?
    @FocusState private var focusedSeasonNum: Int?
    @State private var scrollPositionEpisodeId: Int?

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

    private var descriptionText: String {
        if let focusedId = focusedEpisodeId,
           let episodes = loadedSeason?.episodes,
           let ep = episodes.first(where: { $0.id == focusedId }),
           let overview = ep.overview, !overview.isEmpty {
            return overview
        }
        return series?.overview ?? ""
    }

    @ViewBuilder
    private var mainContent: some View {
        GeometryReader { geo in
            let contentWidth = geo.size.width * 0.45
            let episodeRowWidth = geo.size.width * 0.6
            ZStack(alignment: .leading) {
                backdropView
                contentStack(contentWidth: contentWidth, episodeRowWidth: episodeRowWidth)
            }
        }
    }

    @ViewBuilder
    private var backdropView: some View {
        if let backdropURL = ImageURLBuilder.backdropURL(for: series?.backdropPath, config: appState.apiConfiguration) {
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
    }

    @ViewBuilder
    private func contentStack(contentWidth: CGFloat, episodeRowWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            ScrollView {
                Text(descriptionText)
                    .font(.body)
                    .lineSpacing(4)
                    .frame(maxWidth: contentWidth, alignment: .topLeading)
            }
            .frame(maxWidth: contentWidth, minHeight: 200, maxHeight: 200)

            seasonSelector(contentWidth: contentWidth)

            if let streamErr = streamError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                    Text(streamErr)
                        .foregroundStyle(.red)
                        .font(.subheadline)
                }
            }

            if let season = loadedSeason, let episodes = season.episodes, !episodes.isEmpty {
                Text("Episodes")
                    .font(.title3)
                    .fontWeight(.semibold)
            }

            episodesSection(contentWidth: episodeRowWidth)
        }
        .frame(maxWidth: contentWidth, alignment: .leading)
        .padding(.horizontal, 48)
        .padding(.top, 24)
        .padding(.bottom, 48)
    }

    private func seasonSelector(contentWidth: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(seasonNumbers, id: \.self) { num in
                    seasonButton(num: num)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxWidth: contentWidth, alignment: .leading)
    }

    private func seasonButton(num: Int) -> some View {
        let isFocused = focusedSeasonNum == num
        let isSelected = selectedSeason == num
        let fillColor: Color = isSelected ? .white : (isFocused ? Color.white.opacity(0.5) : Color.white.opacity(0.25))
        let textColor: Color = (isSelected || isFocused) ? .black : .white

        return Button {
            selectedSeason = num
        } label: {
            Text("Season \(num)")
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(textColor)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Capsule().fill(fillColor))
        }
        .buttonStyle(.plain)
        .hoverEffectDisabled(true)
        .focused($focusedSeasonNum, equals: num)
    }

    @ViewBuilder
    private func episodesSection(contentWidth: CGFloat) -> some View {
        if isLoadingSeason {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
        } else if let season = loadedSeason, let episodes = season.episodes, !episodes.isEmpty {
            episodeScrollView(episodes: episodes, contentWidth: contentWidth)
        } else {
            Text("No episodes available")
                .foregroundStyle(.secondary)
                .padding(.vertical, 48)
                .frame(maxWidth: .infinity)
        }
    }

    private func episodeScrollView(episodes: [TVEpisode], contentWidth: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(episodes, id: \.id) { episode in
                    episodeRow(episode: episode, contentWidth: contentWidth)
                }
            }
            .scrollTargetLayout()
        }
        .scrollPosition(id: $scrollPositionEpisodeId, anchor: .center)
        .frame(maxHeight: 460)
    }

    private func isEpisodeWatched(season: Int, episode: Int) -> Bool {
        appState.watchProgressManager.watchedEpisodes.contains {
            $0.seriesId == seriesId && $0.season == season && $0.episode == episode
        }
    }

    private func episodeRow(episode: TVEpisode, contentWidth: CGFloat) -> some View {
        let isFocused = focusedEpisodeId == episode.id
        let watched = isEpisodeWatched(season: selectedSeason, episode: episode.episodeNumber)
        let stillURL = ImageURLBuilder.stillURL(for: episode.stillPath, config: appState.apiConfiguration)
        let cardBackground = isFocused ? Color.white.opacity(0.22) : Color.white.opacity(0.08)
        let cardStroke = isFocused ? Color.white.opacity(0.4) : Color.clear

        return Button {
            Task { await playEpisode(season: selectedSeason, episode: episode.episodeNumber, title: episode.name) }
        } label: {
            episodeRowContent(
                episode: episode,
                contentWidth: contentWidth,
                isFocused: isFocused,
                watched: watched,
                stillURL: stillURL,
                cardBackground: cardBackground,
                cardStroke: cardStroke
            )
        }
        .buttonStyle(.plain)
        .hoverEffectDisabled(true)
        .buttonBorderShape(.roundedRectangle(radius: 14))
        .focused($focusedEpisodeId, equals: episode.id)
        .disabled(isResolvingStream)
        .contextMenu {
            Button("Choose Stream") {
                Task { await showStreamPicker(season: selectedSeason, episode: episode.episodeNumber, title: episode.name) }
            }
        }
    }

    private func episodeRowContent(
        episode: TVEpisode,
        contentWidth: CGFloat,
        isFocused: Bool,
        watched: Bool,
        stillURL: URL?,
        cardBackground: Color,
        cardStroke: Color
    ) -> some View {
        HStack(alignment: .center, spacing: 20) {
            episodeThumbnail(stillURL: stillURL, episodeNumber: episode.episodeNumber, isFocused: isFocused)
            episodeMetadata(episode: episode, watched: watched)
            Image(systemName: "play.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(isFocused ? .white : .white.opacity(0.8))
                .symbolRenderingMode(.hierarchical)
        }
        .frame(maxWidth: contentWidth, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(cardBackground))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(cardStroke, lineWidth: 2))
    }

    private func episodeMetadata(episode: TVEpisode, watched: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text(episode.name)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if watched {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.green.opacity(0.9))
                }
            }
            episodeMetadataRow(episode: episode)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func episodeMetadataRow(episode: TVEpisode) -> some View {
        HStack(spacing: 8) {
            Text("E\(episode.episodeNumber)")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            if let date = episode.airDate {
                Text("•")
                    .foregroundStyle(.secondary)
                Text(date, format: .dateTime.month().year())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func episodeThumbnail(stillURL: URL?, episodeNumber: Int, isFocused: Bool) -> some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let url = stillURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure:
                            thumbnailPlaceholder
                        case .empty:
                            thumbnailPlaceholder
                                .overlay { ProgressView() }
                        @unknown default:
                            thumbnailPlaceholder
                        }
                    }
                } else {
                    thumbnailPlaceholder
                }
            }
            .frame(width: 160, height: 90)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Text("\(episodeNumber)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 2, x: 0, y: 1)
                .padding(6)
        }
    }

    private var thumbnailPlaceholder: some View {
        Rectangle()
            .fill(.quaternary.opacity(0.5))
            .overlay {
                Image(systemName: "film")
                    .font(.title2)
                    .foregroundStyle(.secondary.opacity(0.6))
            }
    }

    var body: some View {
        Group {
            if series == nil {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                mainContent
            }
        }
        .navigationTitle("")
        .sheet(isPresented: $showStreamPicker, onDismiss: {
            if let pending = pendingStreamSelection {
                pendingStreamSelection = nil
                Task { await playSource(pending.source, season: pending.season, episode: pending.episode, title: pending.title) }
            }
        }) {
            StreamPickerView(
                title: streamPickerEpisode.map { "\(seriesName) - \($0.title)" } ?? seriesName,
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
        .task {
            if series == nil {
                series = try? await appState.tmdbService.tvSeriesDetails(forSeriesId: seriesId)
                let seasons = (series?.seasons ?? []).map(\.seasonNumber).sorted()
                selectedSeason = seasons.first ?? (series?.numberOfSeasons ?? 1)
            }
            await loadSeason(selectedSeason)
        }
        .onChange(of: selectedSeason) { _, newValue in
            Task { await loadSeason(newValue) }
        }
        .onChange(of: focusedEpisodeId) { _, newId in
            if let id = newId {
                scrollPositionEpisodeId = id
            }
        }
    }

    private func loadSeason(_ seasonNumber: Int) async {
        isLoadingSeason = true
        streamError = nil
        defer { isLoadingSeason = false }

        do {
            loadedSeason = try await appState.tmdbService.tvSeasonDetails(seriesId: seriesId, seasonNumber: seasonNumber)
        } catch {
            streamError = error.localizedDescription
        }
    }

    private func playEpisode(season: Int, episode: Int, title: String) async {
        guard !isResolvingStream else { return }
        isResolvingStream = true
        streamError = nil
        defer { isResolvingStream = false }

        do {
            let (urls, quality) = try await appState.streamingService.playableURLsAndQualityForEpisode(seriesId: seriesId, season: season, episode: episode)
            guard !urls.isEmpty else {
                streamError = "No stream was found"
                return
            }
            let content = PlayableContent(urls: urls, title: "\(seriesName) - \(title)", quality: quality, tvSeriesId: seriesId, season: season, episode: episode)
            await MainActor.run {
                playableContent = content
                appState.watchProgressManager.recordEpisode(seriesId: seriesId, season: season, episode: episode)
            }
        } catch {
            streamError = "No stream was found"
        }
    }

    private func showStreamPicker(season: Int, episode: Int, title: String) async {
        guard !isResolvingStream else { return }
        isResolvingStream = true
        streamError = nil
        defer { isResolvingStream = false }

        do {
            let sources = try await appState.streamingService.sourcesForEpisode(seriesId: seriesId, season: season, episode: episode)
            let playable = sources.filter { $0.isPlayable }
            guard !playable.isEmpty else {
                streamError = "No stream was found"
                return
            }
            await MainActor.run {
                streamPickerSources = playable
                streamPickerEpisode = (season, episode, title)
                showStreamPicker = true
            }
        } catch {
            streamError = "No stream was found"
        }
    }

    private func playSource(_ source: OMSSSource, season: Int, episode: Int, title: String) async {
        guard let url = await appState.streamingService.playableURL(for: source) else {
            streamError = "Could not load stream"
            return
        }
        let content = PlayableContent(urls: [url], title: "\(seriesName) - \(title)", quality: source.quality, tvSeriesId: seriesId, season: season, episode: episode)
        await MainActor.run {
            playableContent = content
            appState.watchProgressManager.recordEpisode(seriesId: seriesId, season: season, episode: episode)
        }
    }
}
