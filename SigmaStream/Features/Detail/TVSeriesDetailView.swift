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
    @State private var isResolvingStream = false
    @State private var streamError: String?
    @State private var trailerYouTubeKey: String?
    @State private var trailerAlertMessage: String?

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
                ZStack {
                    if let backdropURL = ImageURLBuilder.backdropURL(for: series.backdropPath, config: appState.apiConfiguration) {
                        AsyncImage(url: backdropURL) { phase in
                            if case .success(let image) = phase {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .blur(radius: 24)
                        .overlay(Color.black.opacity(0.55))
                        .ignoresSafeArea()
                    }

                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            HStack(alignment: .top, spacing: 24) {
                            posterSection
                            VStack(alignment: .leading, spacing: 8) {
                                Text(series.name)
                                    .font(.largeTitle)
                                    .fontWeight(.bold)

                                if let date = series.firstAirDate {
                                    Text(formatYear(date))
                                        .font(.title3)
                                        .foregroundStyle(.secondary)
                                }

                                if let rating = series.voteAverage {
                                    Label(String(format: "%.1f/10", rating), systemImage: "star.fill")
                                        .font(.title3)
                                }

                                if let key = trailerYouTubeKey {
                                    Button {
                                        openTrailer(key: key)
                                    } label: {
                                        Label("Watch Trailer", systemImage: "play.rectangle.fill")
                                    }
                                    .padding(.top, 8)
                                }
                            }
                            Spacer()
                        }
                        .padding()

                        if let overview = series.overview, !overview.isEmpty {
                            Text(overview)
                                .font(.body)
                                .padding(.horizontal)
                        }

                        if let streamErr = streamError {
                            Text(streamErr)
                                .foregroundStyle(.red)
                                .font(.subheadline)
                                .padding(.horizontal)
                        }

                        seasonsSection
                        episodesSection
                        }
                    }
                }
            }
        }
        .navigationTitle(series?.name ?? "TV Series")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    appState.myListManager.toggleSeries(seriesId)
                } label: {
                    Image(systemName: appState.myListManager.isSeriesInList(seriesId) ? "plus.circle.fill" : "plus.circle")
                }
            }
        }
        .alert("Trailer", isPresented: Binding(
            get: { trailerAlertMessage != nil },
            set: { if !$0 { trailerAlertMessage = nil } }
        )) {
            Button("OK") { trailerAlertMessage = nil }
        } message: {
            Text(trailerAlertMessage ?? "")
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
            await loadSeries()
        }
        .onChange(of: selectedSeason) { _, newValue in
            Task { await loadSeason(newValue) }
        }
    }

    @ViewBuilder
    private var posterSection: some View {
        if let url = ImageURLBuilder.posterURL(for: series?.posterPath, config: appState.apiConfiguration, idealWidth: 500) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(2/3, contentMode: .fill)
                default:
                    posterPlaceholder
                }
            }
            .frame(width: 300, height: 450)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        } else {
            posterPlaceholder
        }
    }

    private var posterPlaceholder: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(.quaternary)
            .frame(width: 300, height: 450)
            .overlay {
                Image(systemName: "tv")
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)
            }
    }

    @ViewBuilder
    private var seasonsSection: some View {
        if !seasonNumbers.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Season")
                    .font(.title2)
                    .fontWeight(.semibold)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(seasonNumbers, id: \.self) { num in
                            Button {
                                selectedSeason = num
                            } label: {
                                Text("Season \(num)")
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(selectedSeason == num ? Color.accentColor : Color.clear)
                                    .foregroundStyle(selectedSeason == num ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private var episodesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Episodes")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.horizontal)

            if isLoadingSeason {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else if let season = loadedSeason, let episodes = season.episodes, !episodes.isEmpty {
                ForEach(episodes, id: \.id) { episode in
                    Button {
                        Task { await resolveStream(season: selectedSeason, episode: episode.episodeNumber, title: episode.name) }
                    } label: {
                        HStack(spacing: 16) {
                            Text("\(episode.episodeNumber)")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .leading)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(episode.name)
                                    .font(.headline)
                                    .lineLimit(2)
                                if let date = episode.airDate {
                                    Text(formatYear(date))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "play.circle.fill")
                                .font(.title2)
                        }
                        .padding()
                        .background(.ultraThinMaterial.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(isResolvingStream)
                }
                .padding(.horizontal)
            } else {
                Text("No episodes available")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical)
    }

    private func formatYear(_ date: Date) -> String {
        Calendar.current.component(.year, from: date).description
    }

    private func openTrailer(key: String) {
        let youtubeURL = URL(string: "youtube://watch/\(key)")
        let httpsURL = URL(string: "https://www.youtube.com/watch?v=\(key)")!
        let canOpenYouTube = youtubeURL.map { UIApplication.shared.canOpenURL($0) } ?? false
        let urlToOpen = (canOpenYouTube && youtubeURL != nil) ? youtubeURL! : httpsURL

        #if DEBUG
        print("[TVSeriesDetail] Trailer key=\(key), youtubeURL=\(youtubeURL?.absoluteString ?? "nil"), canOpenYouTube=\(canOpenYouTube), opening=\(urlToOpen.absoluteString)")
        #endif

        UIApplication.shared.open(urlToOpen) { success in
            #if DEBUG
            print("[TVSeriesDetail] Trailer open success=\(success)")
            #endif
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
                #if DEBUG
                print("[TVSeriesDetail] Stream resolve returned empty URLs for S\(season)E\(episode)")
                #endif
                streamError = "No stream was found"
                return
            }
            playableContent = PlayableContent(urls: urls, title: "\(series?.name ?? "Episode") - \(title)", tvSeriesId: seriesId, season: season, episode: episode)
            appState.watchProgressManager.recordEpisode(seriesId: seriesId, season: season, episode: episode)
        } catch {
            #if DEBUG
            print("[TVSeriesDetail] Stream resolve failed: \(error)")
            #endif
            streamError = "No stream was found"
        }
    }
}

#Preview {
    NavigationStack {
        TVSeriesDetailView(seriesId: 1399)
            .environment(AppState(apiKey: "placeholder"))
    }
}
