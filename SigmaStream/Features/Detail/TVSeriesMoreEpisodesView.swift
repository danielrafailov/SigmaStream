//
//  TVSeriesMoreEpisodesView.swift
//  SigmaStream
//
//  Episode picker: series info and seasons on the left, episode posters and details on the right.
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
        series?.playableSeasonNumbers ?? [1]
    }

    private var displayTitle: String {
        series?.name ?? seriesName
    }

    var body: some View {
        Group {
            if series == nil {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.background)
            } else {
                mainContent
            }
        }
        .background(AppTheme.background)
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
            VideoPlayerView(content: content, watchProgress: appState.watchProgressManager) {
                if let sid = content.tvSeriesId,
                   let s = content.season,
                   let e = content.episode {
                    appState.watchProgressManager.removeEpisode(seriesId: sid, season: s, episode: e)
                }
            }
        }
        .task {
            if series == nil {
                series = try? await appState.tmdbService.tvSeriesDetails(forSeriesId: seriesId)
                selectedSeason = series?.defaultPlayableSeason ?? 1
            }
            await loadSeason(selectedSeason, pinSeasonFocus: selectedSeason)
            focusedSeasonNum = selectedSeason
        }
        .onChange(of: selectedSeason) { _, newValue in
            let pinSeason = focusedSeasonNum
            Task { await loadSeason(newValue, pinSeasonFocus: pinSeason) }
        }
        .onChange(of: focusedSeasonNum) { _, newNum in
            guard let newNum, newNum != selectedSeason else { return }
            selectedSeason = newNum
        }
        .onChange(of: focusedEpisodeId) { _, newId in
            if let id = newId {
                scrollPositionEpisodeId = id
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        GeometryReader { geo in
            let leftWidth = geo.size.width * 7 / 20
            let rightWidth = geo.size.width * 13 / 20
            let rightTrailingInset: CGFloat = 72
            let posterWidth = rightWidth * 0.4
            let detailWidth = max(0, rightWidth - posterWidth - 20 - rightTrailingInset)

            HStack(alignment: .top, spacing: 0) {
                leftPanel(width: leftWidth)
                rightPanel(posterWidth: posterWidth, detailWidth: detailWidth)
                    .frame(width: rightWidth)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(AppTheme.background)
        }
    }

    private func leftPanel(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 36) {
            seriesHeader

            VStack(alignment: .leading, spacing: 4) {
                ForEach(seasonNumbers.reversed(), id: \.self) { num in
                    seasonRow(num: num, width: width - 48)
                }
            }
            .focusSection()

            if let streamErr = streamError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                    Text(streamErr)
                        .foregroundStyle(.red)
                        .font(.subheadline)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(width: width, alignment: .leading)
        .padding(.leading, 60)
        .padding(.trailing, 24)
        .padding(.top, 48)
        .padding(.bottom, 48)
    }

    private var seriesHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SERIES")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(AppTheme.secondaryText)
                .tracking(1.5)

            Text(displayTitle)
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                if let date = series?.firstAirDate {
                    Text(String(Calendar.current.component(.year, from: date)))
                }
                if seasonNumbers.count > 0 {
                    if series?.firstAirDate != nil {
                        Text("•")
                    }
                    Text("\(seasonNumbers.count) Season\(seasonNumbers.count == 1 ? "" : "s")")
                }
            }
            .font(.subheadline)
            .foregroundStyle(AppTheme.secondaryText)
        }
    }

    private func seasonRow(num: Int, width: CGFloat) -> some View {
        let isFocused = focusedSeasonNum == num

        return Button {
            focusedSeasonNum = num
        } label: {
            HStack(alignment: .firstTextBaseline) {
                Text("Season \(num)")
                    .font(.callout)
                    .fontWeight(isFocused ? .semibold : .regular)
                Spacer(minLength: 16)
                if let count = episodeCount(for: num) {
                    Text("\(count) Episode\(count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
            .foregroundStyle(AppTheme.primaryText)
            .frame(width: width, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(AppTheme.focusBorder, lineWidth: 3)
                }
            }
        }
        .buttonStyle(.plain)
        .hoverEffectDisabled(true)
        .focused($focusedSeasonNum, equals: num)
    }

    @ViewBuilder
    private func rightPanel(posterWidth: CGFloat, detailWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text("Season \(selectedSeason)")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppTheme.primaryText)
            }
            .padding(.top, 48)

            episodesSection(posterWidth: posterWidth, detailWidth: detailWidth)
        }
        .focusSection()
        .padding(.trailing, 72)
    }

    @ViewBuilder
    private func episodesSection(posterWidth: CGFloat, detailWidth: CGFloat) -> some View {
        ZStack {
            if let season = loadedSeason {
                let episodes = TVEpisodeFilter.releasedEpisodes(from: season.episodes)
                if !episodes.isEmpty {
                    episodeScrollView(episodes: episodes, posterWidth: posterWidth, detailWidth: detailWidth)
                        .opacity(isLoadingSeason ? 0.55 : 1)
                        .allowsHitTesting(!isLoadingSeason)
                } else if !isLoadingSeason {
                    Text("No episodes available")
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            } else if !isLoadingSeason {
                Text("No episodes available")
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }

            if isLoadingSeason && loadedSeason == nil {
                ProgressView()
            }
        }
    }

    private func episodeScrollView(episodes: [TVEpisode], posterWidth: CGFloat, detailWidth: CGFloat) -> some View {
        let posterHeight = posterWidth * 9 / 16

        return ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ForEach(episodes, id: \.id) { episode in
                    episodeRow(
                        episode: episode,
                        posterWidth: posterWidth,
                        posterHeight: posterHeight,
                        detailWidth: detailWidth
                    )
                }
            }
            .scrollTargetLayout()
            .padding(.bottom, 48)
        }
        .scrollPosition(id: $scrollPositionEpisodeId, anchor: .center)
    }

    private func episodeRow(
        episode: TVEpisode,
        posterWidth: CGFloat,
        posterHeight: CGFloat,
        detailWidth: CGFloat
    ) -> some View {
        let isFocused = focusedEpisodeId == episode.id
        let stillURL = ImageURLBuilder.stillURL(for: episode.stillPath, config: appState.apiConfiguration)
        let progress = episodeProgressFraction(for: episode)

        return Button {
            let fromBeginning = !appState.watchProgressManager.canResumeEpisode(
                seriesId: seriesId,
                season: selectedSeason,
                episode: episode.episodeNumber
            )
            Task { await playEpisode(season: selectedSeason, episode: episode.episodeNumber, title: episode.name, fromBeginning: fromBeginning) }
        } label: {
            HStack(alignment: .top, spacing: 20) {
                episodePoster(
                    stillURL: stillURL,
                    episodeNumber: episode.episodeNumber,
                    isFocused: isFocused,
                    width: posterWidth,
                    height: posterHeight,
                    progress: progress
                )

                episodeDetails(episode: episode, width: detailWidth)
            }
            .frame(maxWidth: posterWidth + detailWidth + 20, alignment: .leading)
        }
        .buttonStyle(.plain)
        .hoverEffectDisabled(true)
        .buttonBorderShape(.roundedRectangle(radius: 4))
        .focused($focusedEpisodeId, equals: episode.id)
        .disabled(isResolvingStream)
        .contextMenu {
            if appState.watchProgressManager.canResumeEpisode(seriesId: seriesId, season: selectedSeason, episode: episode.episodeNumber) {
                Button("Play from Beginning") {
                    Task { await playEpisode(season: selectedSeason, episode: episode.episodeNumber, title: episode.name, fromBeginning: true) }
                }
            }
            Button("Choose Stream") {
                Task { await showStreamPicker(season: selectedSeason, episode: episode.episodeNumber, title: episode.name) }
            }
        }
    }

    private func episodePoster(
        stillURL: URL?,
        episodeNumber: Int,
        isFocused: Bool,
        width: CGFloat,
        height: CGFloat,
        progress: Double?
    ) -> some View {
        ZStack(alignment: .bottom) {
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
            .frame(width: width, height: height)
            .clipped()

            if let progress, progress > 0 {
                GeometryReader { geo in
                    Rectangle()
                        .fill(AppTheme.progressTint)
                        .frame(width: geo.size.width * min(progress, 1), height: 3)
                }
                .frame(height: 3)
            }
        }
        .frame(width: width, height: height)
        .overlay {
            RoundedRectangle(cornerRadius: 2)
                .stroke(isFocused ? AppTheme.focusBorder : Color.clear, lineWidth: 3)
        }
        .overlay(alignment: .bottomLeading) {
            Text("\(episodeNumber)")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.7), radius: 2, x: 0, y: 1)
                .padding(8)
        }
    }

    private func episodeDetails(episode: TVEpisode, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(episode.name)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            if let overview = episode.overview, !overview.isEmpty {
                Text(overviewWithLength(overview, episode: episode))
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineSpacing(3)
                    .lineLimit(5)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let length = formattedEpisodeLength(for: episode) {
                Text(length)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .frame(maxWidth: width, alignment: .topLeading)
        .padding(.top, 4)
        .padding(.trailing, 8)
    }

    private func overviewWithLength(_ overview: String, episode: TVEpisode) -> String {
        if let length = formattedEpisodeLength(for: episode) {
            return "\(overview) \(length)"
        }
        return overview
    }

    private var thumbnailPlaceholder: some View {
        Rectangle()
            .fill(AppTheme.placeholderFill)
            .overlay {
                Image(systemName: "film")
                    .font(.title2)
                    .foregroundStyle(AppTheme.secondaryText)
            }
    }

    private func episodeCount(for seasonNum: Int) -> Int? {
        if seasonNum == selectedSeason, let episodes = loadedSeason?.episodes {
            let count = TVEpisodeFilter.releasedEpisodes(from: episodes).count
            return count > 0 ? count : nil
        }
        if let episodes = series?.seasons?.first(where: { $0.seasonNumber == seasonNum })?.episodes {
            let count = TVEpisodeFilter.releasedEpisodes(from: episodes).count
            return count > 0 ? count : nil
        }
        return nil
    }

    private func formattedEpisodeLength(for episode: TVEpisode) -> String? {
        guard let minutes = episodeDurationMinutes(for: episode) else { return nil }
        return "(\(minutes)m)"
    }

    private func episodeDurationMinutes(for episode: TVEpisode) -> Int? {
        if let entry = appState.watchProgressManager.watchedEpisodes.first(where: {
            $0.seriesId == seriesId && $0.season == selectedSeason && $0.episode == episode.episodeNumber
        }), let duration = entry.durationSeconds, duration > 0 {
            return max(1, Int((duration / 60).rounded()))
        }
        if let minutes = series?.episodeRunTime?.first, minutes > 0 {
            return minutes
        }
        return nil
    }

    private func episodeProgressFraction(for episode: TVEpisode) -> Double? {
        guard let entry = appState.watchProgressManager.watchedEpisodes.first(where: {
            $0.seriesId == seriesId && $0.season == selectedSeason && $0.episode == episode.episodeNumber
        }),
        let progress = entry.progressSeconds,
        let duration = entry.durationSeconds,
        duration > 0 else { return nil }
        return progress / duration
    }

    private func loadSeason(_ seasonNumber: Int, pinSeasonFocus: Int? = nil) async {
        let wasCached = await appState.tmdbService.isTVSeasonCached(seriesId: seriesId, seasonNumber: seasonNumber)
        if !wasCached {
            isLoadingSeason = true
        }
        streamError = nil
        defer { isLoadingSeason = false }

        do {
            let season = try await appState.tmdbService.tvSeasonDetails(seriesId: seriesId, seasonNumber: seasonNumber)
            await MainActor.run {
                loadedSeason = season
                scrollPositionEpisodeId = TVEpisodeFilter.releasedEpisodes(from: season.episodes).first?.id
                if let pinSeasonFocus {
                    focusedEpisodeId = nil
                    focusedSeasonNum = pinSeasonFocus
                }
            }
        } catch {
            await MainActor.run {
                loadedSeason = nil
                streamError = error.localizedDescription
                if let pinSeasonFocus {
                    focusedEpisodeId = nil
                    focusedSeasonNum = pinSeasonFocus
                }
            }
        }
    }

    private func playEpisode(season: Int, episode: Int, title: String, fromBeginning: Bool) async {
        guard !isResolvingStream else { return }
        isResolvingStream = true
        streamError = nil
        defer { isResolvingStream = false }

        do {
            let (urls, quality) = try await appState.streamingService.playableURLsAndQualityForEpisode(seriesId: seriesId, season: season, episode: episode)
            guard !urls.isEmpty else {
                streamError = "No stream was found (none marked playable)."
                return
            }
            await MainActor.run {
                playableContent = makeEpisodePlayableContent(
                    urls: urls,
                    quality: quality,
                    season: season,
                    episode: episode,
                    title: title,
                    fromBeginning: fromBeginning
                )
            }
        } catch {
            let msg = userFacingStreamingErrorMessage(for: error)
            streamError = msg.isEmpty ? "Could not load streams" : msg
        }
    }

    private func makeEpisodePlayableContent(
        urls: [URL],
        quality: String?,
        season: Int,
        episode: Int,
        title: String,
        fromBeginning: Bool
    ) -> PlayableContent {
        if fromBeginning {
            appState.watchProgressManager.clearEpisodePlaybackPosition(seriesId: seriesId, season: season, episode: episode)
        }
        let startTime = fromBeginning
            ? nil
            : appState.watchProgressManager.resumeTimeForEpisode(seriesId: seriesId, season: season, episode: episode)
        return PlayableContent(
            urls: urls,
            title: "\(seriesName) - \(title)",
            quality: quality,
            startTime: startTime,
            tvSeriesId: seriesId,
            season: season,
            episode: episode
        )
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
                streamError = "No stream was found (none marked playable)."
                return
            }
            await MainActor.run {
                streamPickerSources = playable
                streamPickerEpisode = (season, episode, title)
                showStreamPicker = true
            }
        } catch {
            let msg = userFacingStreamingErrorMessage(for: error)
            streamError = msg.isEmpty ? "Could not load streams" : msg
        }
    }

    private func playSource(_ source: OMSSSource, season: Int, episode: Int, title: String) async {
        guard let url = await appState.streamingService.playableURL(for: source) else {
            streamError = "Could not load stream"
            return
        }
        await MainActor.run {
            playableContent = makeEpisodePlayableContent(
                urls: [url],
                quality: source.quality,
                season: season,
                episode: episode,
                title: title,
                fromBeginning: true
            )
        }
    }
}
