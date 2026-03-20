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
    @State private var streamError: String?
    @FocusState private var focusedEpisodeId: Int?

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

    var body: some View {
        Group {
            if series == nil {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geo in
                    let contentWidth = geo.size.width * 0.45
                    ZStack(alignment: .leading) {
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

                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                if !descriptionText.isEmpty {
                                    Text(descriptionText)
                                        .font(.body)
                                        .frame(maxWidth: contentWidth, alignment: .leading)
                                        .lineLimit(4)
                                }

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

                                if isLoadingSeason {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 48)
                                } else if let season = loadedSeason, let episodes = season.episodes, !episodes.isEmpty {
                                    VStack(alignment: .leading, spacing: 12) {
                                        ForEach(episodes, id: \.id) { episode in
                                            let isFocused = focusedEpisodeId == episode.id
                                            Button {
                                                Task { await resolveStream(season: selectedSeason, episode: episode.episodeNumber, title: episode.name) }
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
                                                            .lineLimit(2)
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
                                                .padding()
                                                .background(isFocused ? Color.white.opacity(0.2) : Color.white.opacity(0.1))
                                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                            }
                                            .buttonStyle(.plain)
                                            .focused($focusedEpisodeId, equals: episode.id)
                                            .disabled(isResolvingStream)
                                        }
                                    }
                                } else {
                                    Text("No episodes available")
                                        .foregroundStyle(.secondary)
                                        .padding(.vertical, 48)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .frame(maxWidth: contentWidth, alignment: .leading)
                            .padding(48)
                        }
                    }
                }
            }
        }
        .navigationTitle("More Episodes")
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

    private func resolveStream(season: Int, episode: Int, title: String) async {
        guard !isResolvingStream else { return }
        isResolvingStream = true
        streamError = nil
        defer { isResolvingStream = false }

        do {
            let urls = try await appState.streamingService.playableURLsForEpisode(seriesId: seriesId, season: season, episode: episode)
            guard !urls.isEmpty else {
                streamError = "No stream was found"
                return
            }
            playableContent = PlayableContent(urls: urls, title: "\(seriesName) - \(title)", tvSeriesId: seriesId, season: season, episode: episode)
            appState.watchProgressManager.recordEpisode(seriesId: seriesId, season: season, episode: episode)
        } catch {
            streamError = "No stream was found"
        }
    }
}
