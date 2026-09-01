//
//  iOSTVSeriesDetailView.swift
//  SigmaStream-iOS
//
//  Created by Daniel Rafailov on 2026-09-01.
//

import SwiftUI
import TMDb

#if os(iOS)
struct iOSTVSeriesDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let seriesId: Int

    @State private var series: TVSeries?
    @State private var selectedSeasonNumber: Int = 1
    @State private var loadedSeason: TVSeason?
    @State private var isLoading = true
    @State private var isLoadingSeason = false
    @State private var isResolvingStream = false
    @State private var streamError: String?
    @State private var playableContent: PlayableContent?
    @State private var streamQuality: String?
    @State private var streamResolutionTask: Task<Void, Never>?
    @State private var episodePrefetchTask: Task<Void, Never>?
    @State private var prefetchedEpisodePlayback: (urls: [URL], quality: String?)?
    @State private var prefetchedEpisodeKey: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Hero Backdrop
                ZStack(alignment: .bottomLeading) {
                    if let backdropPath = series?.backdropPath {
                        let backdropURL = ImageURLBuilder.backdropURL(path: backdropPath, size: .w780)
                        AsyncImage(url: backdropURL) { phase in
                            if let image = phase.image {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } else {
                                Color.white.opacity(0.05)
                            }
                        }
                    } else {
                        Color.white.opacity(0.05)
                    }

                    // Gradient Scrim
                    LinearGradient(
                        colors: [Color.clear, Color(uiColor: .systemBackground).opacity(0.9), Color(uiColor: .systemBackground)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                }
                .frame(height: 260)
                .clipped()

                // Content Details
                VStack(alignment: .leading, spacing: 16) {
                    // Title
                    Text(series?.name ?? "TV Show Details")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)

                    // Metadata Row
                    HStack(spacing: 12) {
                        if let count = series?.numberOfSeasons {
                            Text("\(count) Season\(count > 1 ? "s" : "")")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        if let date = series?.firstAirDate {
                            Text(String(Calendar.current.component(.year, from: date)))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        if let rating = series?.voteAverage, rating > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "star.fill")
                                    .font(.caption)
                                    .foregroundStyle(.yellow)
                                Text(String(format: "%.1f", rating))
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.white)
                            }
                        }
                    }

                    // Genres
                    if let genres = series?.genres, !genres.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(genres, id: \.id) { genre in
                                    Text(genre.name)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.white.opacity(0.85))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.white.opacity(0.12))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }

                    // Quick Action Icons
                    HStack(spacing: 24) {
                        Button {
                            toggleMyList()
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: isInMyList ? "checkmark" : "plus")
                                    .font(.title3)
                                Text(isInMyList ? "In List" : "My List")
                                    .font(.caption2)
                            }
                            .foregroundStyle(.white)
                        }

                        Button {
                            toggleLiked()
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: isLiked ? "heart.fill" : "heart")
                                    .font(.title3)
                                    .foregroundStyle(isLiked ? .red : .white)
                                Text(isLiked ? "Liked" : "Like")
                                    .font(.caption2)
                                    .foregroundStyle(.white)
                            }
                        }

                        Spacer()
                    }
                    .padding(.vertical, 4)

                    // Error Message (if any)
                    if let streamError, !streamError.isEmpty {
                        Text(streamError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    // Synopsis
                    if let overview = series?.overview, !overview.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Overview")
                                .font(.headline)
                                .foregroundStyle(.white)
                            Text(overview)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineSpacing(3)
                        }
                    }

                    Divider()
                        .background(Color.white.opacity(0.15))
                        .padding(.vertical, 8)

                    // Season Selector
                    if let seasons = series?.seasons?.filter({ $0.seasonNumber > 0 }), !seasons.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("Episodes")
                                    .font(.title3.bold())
                                    .foregroundStyle(.white)

                                Spacer()

                                Menu {
                                    ForEach(seasons, id: \.id) { s in
                                        Button("Season \(s.seasonNumber)") {
                                            selectedSeasonNumber = s.seasonNumber
                                            Task { await loadSeason(s.seasonNumber) }
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Text("Season \(selectedSeasonNumber)")
                                            .font(.subheadline.bold())
                                        Image(systemName: "chevron.down")
                                            .font(.caption.bold())
                                    }
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.white.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                            }

                            // Episode Cards
                            if isLoadingSeason {
                                ProgressView()
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(40)
                            } else if let episodes = loadedSeason?.episodes, !episodes.isEmpty {
                                VStack(spacing: 16) {
                                    ForEach(episodes, id: \.id) { ep in
                                        episodeRow(ep)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .fullScreenCover(item: $playableContent) { content in
            iOSTouchPlayerView(playableContent: content)
        }
        .task {
            await loadSeriesDetails()
            if let firstSeason = series?.seasons?.first(where: { $0.seasonNumber > 0 })?.seasonNumber {
                selectedSeasonNumber = firstSeason
                await loadSeason(firstSeason)
            }
        }
    }

    @ViewBuilder
    private func episodeRow(_ ep: TVEpisode) -> some View {
        Button {
            startResolveEpisode(season: ep.seasonNumber, episode: ep.episodeNumber, title: ep.name)
        } label: {
            HStack(alignment: .top, spacing: 14) {
                // Thumbnail
                ZStack(alignment: .center) {
                    if let stillPath = ep.stillPath {
                        let stillURL = ImageURLBuilder.stillURL(path: stillPath, size: .w300)
                        AsyncImage(url: stillURL) { phase in
                            if let img = phase.image {
                                img.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                Color.white.opacity(0.08)
                            }
                        }
                    } else {
                        Color.white.opacity(0.08)
                    }

                    Image(systemName: "play.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .frame(width: 120, height: 75)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                // Metadata
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(ep.episodeNumber). \(ep.name)")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if let runtime = ep.runtime, runtime > 0 {
                        Text("\(runtime)m")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if let overview = ep.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private var isInMyList: Bool {
        appState.myListManager.contains(id: seriesId, type: .tvSeries)
    }

    private var isLiked: Bool {
        appState.likedManager.isLiked(id: seriesId, type: .tvSeries)
    }

    private func toggleMyList() {
        if isInMyList {
            appState.myListManager.remove(id: seriesId, type: .tvSeries)
        } else {
            appState.myListManager.add(id: seriesId, type: .tvSeries)
        }
    }

    private func toggleLiked() {
        appState.likedManager.toggleLiked(id: seriesId, type: .tvSeries)
    }

    private func loadSeriesDetails() async {
        isLoading = true
        defer { isLoading = false }
        do {
            self.series = try await appState.tmdbService.tvSeriesDetails(forTVSeriesId: seriesId)
        } catch {}
    }

    private func loadSeason(_ seasonNumber: Int) async {
        isLoadingSeason = true
        defer { isLoadingSeason = false }
        do {
            self.loadedSeason = try await appState.tmdbService.tvSeasonDetails(seriesId: seriesId, seasonNumber: seasonNumber)
        } catch {}
    }

    private func startResolveEpisode(season: Int, episode: Int, title: String) {
        guard !isResolvingStream else { return }
        streamResolutionTask?.cancel()
        streamResolutionTask = Task { @MainActor in
            isResolvingStream = true
            streamError = nil
            defer {
                isResolvingStream = false
                streamResolutionTask = nil
            }
            do {
                try Task.checkCancellation()
                let (urls, quality) = try await appState.streamingService.playableURLsAndQualityForEpisode(seriesId: seriesId, season: season, episode: episode)
                try Task.checkCancellation()
                guard !urls.isEmpty else {
                    streamError = "No stream was found."
                    return
                }
                if let quality { streamQuality = quality }
                let resumeTime = appState.watchProgressManager.resumeTimeForEpisode(seriesId: seriesId, season: season, episode: episode)
                playableContent = PlayableContent(
                    urls: urls,
                    title: "\(series?.name ?? "Show") - S\(season) E\(episode) \(title)",
                    quality: quality,
                    startTime: resumeTime,
                    tvSeriesId: seriesId,
                    season: season,
                    episode: episode
                )
            } catch is CancellationError {
                streamError = nil
            } catch {
                if Task.isCancelled {
                    streamError = nil
                    return
                }
                let msg = userFacingStreamingErrorMessage(for: error)
                streamError = msg.isEmpty ? nil : msg
            }
        }
    }
}
#endif
