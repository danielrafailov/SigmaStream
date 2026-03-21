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
        VStack(alignment: .leading, spacing: 16) {
            ScrollView {
                Text(descriptionText)
                    .font(.body)
                    .frame(maxWidth: contentWidth, alignment: .topLeading)
            }
            .frame(maxWidth: contentWidth, minHeight: 240, maxHeight: 240)

            Picker("Season", selection: $selectedSeason) {
                ForEach(seasonNumbers, id: \.self) { num in
                    Text("Season \(num)").tag(num)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: contentWidth, alignment: .leading)

            if let streamErr = streamError {
                Text(streamErr)
                    .foregroundStyle(.red)
                    .font(.subheadline)
            }

            episodesSection(contentWidth: episodeRowWidth)
        }
        .frame(maxWidth: contentWidth, alignment: .leading)
        .padding(.horizontal, 48)
        .padding(.top, 24)
        .padding(.bottom, 48)
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
            VStack(alignment: .leading, spacing: 12) {
                ForEach(episodes, id: \.id) { episode in
                    episodeRow(episode: episode, contentWidth: contentWidth)
                }
            }
            .scrollTargetLayout()
        }
        .scrollPosition(id: $scrollPositionEpisodeId, anchor: .center)
        .frame(maxHeight: 420)
    }

    private func episodeRow(episode: TVEpisode, contentWidth: CGFloat) -> some View {
        let isFocused = focusedEpisodeId == episode.id
        return Button {
            Task { await playEpisode(season: selectedSeason, episode: episode.episodeNumber, title: episode.name) }
        } label: {
            HStack(alignment: .top, spacing: 24) {
                Text("\(episode.episodeNumber)")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)

                VStack(alignment: .leading, spacing: 4) {
                    Text(episode.name)
                        .font(.headline)
                        .lineLimit(4)
                    if let date = episode.airDate {
                        Text(Calendar.current.component(.year, from: date).description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "play.circle.fill")
                    .font(.title2)
            }
            .frame(maxWidth: contentWidth, alignment: .leading)
            .padding(.vertical, 20)
            .padding(.horizontal, 16)
            .background(isFocused ? Color.white.opacity(0.2) : Color.white.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .buttonBorderShape(.roundedRectangle(radius: 12))
        .focused($focusedEpisodeId, equals: episode.id)
        .disabled(isResolvingStream)
        .contextMenu {
            Button("Choose Stream") {
                Task { await showStreamPicker(season: selectedSeason, episode: episode.episodeNumber, title: episode.name) }
            }
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
