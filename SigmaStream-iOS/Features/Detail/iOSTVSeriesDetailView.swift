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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(AppState.self) private var appState

    let seriesId: Int

    @State private var series: TVSeries?
    @State private var ageRating: String?
    @State private var selectedSeasonNumber: Int = 1
    @State private var loadedSeason: TVSeason?
    @State private var recommendations: [TVSeriesListItem] = []
    @State private var trailers: [TMDbVideo] = []
    @State private var cast: [CastMember] = []
    @State private var selectedTab: DetailSubTab = .moreLikeThis

    @State private var isLoading = true
    @State private var isLoadingSeason = false
    @State private var playableContent: PlayableContent?
    @State private var prefetchedEpisodePlayback: (urls: [URL], quality: String?)?
    @State private var prefetchedEpisodeKey: String?

    private var isIPad: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        GeometryReader { geometry in
            let headerHeight: CGFloat = isIPad ? 400 : 260

            ZStack(alignment: .top) {
                // Layer 1: Scrollable Content (Slides UNDER the fixed header in Z-axis)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Spacer matching top header height so content starts below poster
                        Color.clear
                            .frame(height: headerHeight)

                        // Content Details strictly constrained to screen width with horizontal margins
                        VStack(alignment: .leading, spacing: isIPad ? 22 : 18) {
                            // Title (forced to wrap within phone bounds)
                            Text(series?.name ?? "TV Show Details")
                                .font(.system(size: 26, weight: .bold))
                                .foregroundStyle(.white)
                                .fixedSize(horizontal: false, vertical: true)

                            // Metadata Row: [Year] [Age Rating] [Seasons] [Rating]
                            HStack(spacing: 10) {
                                if let date = series?.firstAirDate {
                                    Text(String(Calendar.current.component(.year, from: date)))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                // Age Rating in between year and seasons
                                if let ageRating, !ageRating.isEmpty {
                                    Text(ageRating)
                                        .font(.caption2.bold())
                                        .foregroundStyle(.white.opacity(0.9))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.white.opacity(0.18))
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                }

                                if let count = series?.numberOfSeasons, count > 0 {
                                    Text("\(count) Season\(count > 1 ? "s" : "")")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                if let rating = series?.voteAverage, rating > 0 {
                                    HStack(spacing: 3) {
                                        Image(systemName: "star.fill")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.yellow)
                                        Text(String(format: "%.1f", rating))
                                            .font(.subheadline.bold())
                                            .foregroundStyle(.white)
                                    }
                                }
                            }

                            // Play / Resume Button
                            Button {
                                playFirstOrResumeEpisode()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 16, weight: .bold))
                                    Text(hasResumePosition ? "Resume Episode" : "Play Episode 1")
                                        .font(.headline)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.white)
                                .foregroundStyle(.black)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)

                            // Secondary Actions Row: My List, Liked, Share
                            HStack(spacing: 28) {
                                Button {
                                    toggleMyList()
                                } label: {
                                    VStack(spacing: 6) {
                                        Image(systemName: isInMyList ? "checkmark" : "plus")
                                            .font(.system(size: 20, weight: .semibold))
                                        Text("My List")
                                            .font(.caption2)
                                    }
                                    .foregroundStyle(isInMyList ? Color.red : Color.white)
                                }
                                .buttonStyle(.plain)

                                Button {
                                    toggleLiked()
                                } label: {
                                    VStack(spacing: 6) {
                                        Image(systemName: isLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
                                            .font(.system(size: 20, weight: .semibold))
                                        Text("Rate")
                                            .font(.caption2)
                                    }
                                    .foregroundStyle(isLiked ? Color.blue : Color.white)
                                }
                                .buttonStyle(.plain)

                                Spacer()
                            }
                            .padding(.top, 4)

                            // Overview / Synopsis
                            if let overview = series?.overview, !overview.isEmpty {
                                Text(overview)
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.85))
                                    .lineSpacing(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            // Cast & Creators
                            VStack(alignment: .leading, spacing: 6) {
                                if !cast.isEmpty {
                                    Text("Starring: \(cast.prefix(4).map(\.name).joined(separator: ", "))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }

                                if let creators = series?.createdBy, !creators.isEmpty {
                                    Text("Created by: \(creators.map(\.name).joined(separator: ", "))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }

                            // Season Selector & Episode List Section
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Text("Episodes")
                                        .font(.title3.bold())
                                        .foregroundStyle(.white)

                                    Spacer()

                                    // Season Picker Dropdown Menu
                                    if let seasons = series?.seasons?.filter({ $0.seasonNumber > 0 }), seasons.count > 1 {
                                        Menu {
                                            ForEach(seasons) { season in
                                                Button {
                                                    selectedSeasonNumber = season.seasonNumber
                                                    Task {
                                                        await loadSeason(season.seasonNumber)
                                                    }
                                                } label: {
                                                    HStack {
                                                        Text("Season \(season.seasonNumber)")
                                                        if selectedSeasonNumber == season.seasonNumber {
                                                            Image(systemName: "checkmark")
                                                        }
                                                    }
                                                }
                                            }
                                        } label: {
                                            HStack(spacing: 6) {
                                                Text("Season \(selectedSeasonNumber)")
                                                    .font(.subheadline.bold())
                                                    .foregroundStyle(.white)
                                                Image(systemName: "chevron.down")
                                                    .font(.caption2.bold())
                                                    .foregroundStyle(.secondary)
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(Color(uiColor: .secondarySystemBackground))
                                            .clipShape(Capsule())
                                        }
                                    }
                                }

                                if isLoadingSeason {
                                    HStack {
                                        Spacer()
                                        ProgressView()
                                            .padding(.vertical, 20)
                                        Spacer()
                                    }
                                } else if let episodes = loadedSeason?.episodes, !episodes.isEmpty {
                                    LazyVStack(spacing: 16) {
                                        ForEach(episodes) { ep in
                                            episodeRow(ep)
                                        }
                                    }
                                } else {
                                    Text("No episodes available for Season \(selectedSeasonNumber).")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .padding(.vertical, 12)
                                }
                            }
                            .padding(.top, 8)

                            // Sub-Tabs: [More Like This] [Trailers & More]
                            VStack(alignment: .leading, spacing: 16) {
                                HStack(spacing: 24) {
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            selectedTab = .moreLikeThis
                                        }
                                    } label: {
                                        VStack(spacing: 6) {
                                            Text("More Like This")
                                                .font(.subheadline.bold())
                                                .foregroundStyle(selectedTab == .moreLikeThis ? .white : .secondary)

                                            Rectangle()
                                                .fill(selectedTab == .moreLikeThis ? Color.red : Color.clear)
                                                .frame(height: 3)
                                        }
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            selectedTab = .trailersAndMore
                                        }
                                    } label: {
                                        VStack(spacing: 6) {
                                            Text("Trailers & More")
                                                .font(.subheadline.bold())
                                                .foregroundStyle(selectedTab == .trailersAndMore ? .white : .secondary)

                                            Rectangle()
                                                .fill(selectedTab == .trailersAndMore ? Color.red : Color.clear)
                                                .frame(height: 3)
                                        }
                                    }
                                    .buttonStyle(.plain)

                                    Spacer()
                                }
                                .padding(.top, 8)

                                // Sub-Tab Contents
                                if selectedTab == .moreLikeThis {
                                    if recommendations.isEmpty {
                                        Text("No similar titles found.")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .padding(.vertical, 16)
                                    } else {
                                        let columns = isIPad ? [
                                            GridItem(.adaptive(minimum: 140, maximum: 185), spacing: 16)
                                        ] : [
                                            GridItem(.flexible(), spacing: 14),
                                            GridItem(.flexible(), spacing: 14),
                                            GridItem(.flexible(), spacing: 14)
                                        ]
                                        LazyVGrid(columns: columns, spacing: 16) {
                                            ForEach(recommendations) { item in
                                                NavigationLink {
                                                    iOSTVSeriesDetailView(seriesId: item.id)
                                                } label: {
                                                    iOSMediaCard(
                                                        id: item.id,
                                                        title: item.name,
                                                        posterPath: ImageURLBuilder.posterURL(for: item.posterPath, config: appState.apiConfiguration, idealWidth: 342),
                                                        rating: item.voteAverage,
                                                        releaseYear: item.firstAirDate.map { String(Calendar.current.component(.year, from: $0)) },
                                                        isTVSeries: true,
                                                        progress: nil,
                                                        showLabels: false
                                                    )
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                    }
                                } else {
                                    if trailers.isEmpty {
                                        Text("No trailers available.")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .padding(.vertical, 16)
                                    } else {
                                        LazyVStack(spacing: 16) {
                                            ForEach(trailers, id: \.id) { video in
                                                Button {
                                                    if let appURL = video.youtubeAppURL, UIApplication.shared.canOpenURL(appURL) {
                                                        UIApplication.shared.open(appURL)
                                                    } else if let watchURL = video.youtubeWatchURL {
                                                        UIApplication.shared.open(watchURL)
                                                    }
                                                } label: {
                                                    VStack(alignment: .leading, spacing: 8) {
                                                        ZStack(alignment: .center) {
                                                            if let thumbURL = video.youtubeThumbnailURL {
                                                                AsyncImage(url: thumbURL) { phase in
                                                                    if let img = phase.image {
                                                                        img
                                                                            .resizable()
                                                                            .aspectRatio(contentMode: .fill)
                                                                    } else {
                                                                        Color.white.opacity(0.08)
                                                                    }
                                                                }
                                                            } else {
                                                                Color.white.opacity(0.08)
                                                            }

                                                            Image(systemName: "play.fill")
                                                                .font(.title2)
                                                                .foregroundStyle(.white)
                                                                .padding(14)
                                                                .background(.ultraThinMaterial)
                                                                .clipShape(Circle())
                                                        }
                                                        .frame(height: 180)
                                                        .frame(maxWidth: .infinity)
                                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                                                        Text(video.name)
                                                            .font(.subheadline.bold())
                                                            .foregroundStyle(.white)
                                                            .lineLimit(2)
                                                    }
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                        .padding(.top, 4)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 16)
                        .frame(width: geometry.size.width, alignment: .leading)
                        .padding(.bottom, 40)
                    }
                    .frame(width: geometry.size.width)
                }
                .frame(width: geometry.size.width)

                // Layer 2: Fixed Top Backdrop Poster Header (Sits on top in Z-index)
                ZStack(alignment: .topLeading) {
                    ZStack(alignment: .bottom) {
                        let backdropURL = series?.backdropPath.flatMap {
                            ImageURLBuilder.backdropURL(for: $0, config: appState.apiConfiguration, idealWidth: 780)
                        }

                        if let bestTrailerKey {
                            HeaderVideoPreviewView(
                                videoKey: bestTrailerKey,
                                fallbackImageURL: backdropURL,
                                height: headerHeight
                            )
                        } else if let backdropURL {
                            AsyncImage(url: backdropURL) { phase in
                                if let image = phase.image {
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: geometry.size.width, height: headerHeight)
                                        .clipped()
                                } else {
                                    Color.black
                                }
                            }
                        } else {
                            Color.black
                        }

                        // Gradient Scrim at bottom of fixed poster
                        LinearGradient(
                            colors: [Color.clear, Color(uiColor: .systemBackground).opacity(0.6), Color(uiColor: .systemBackground)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 48)
                        .allowsHitTesting(false)
                    }
                    .frame(width: geometry.size.width, height: headerHeight)
                    .clipped()

                    // Floating Back Button pinned at top-left
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .padding(.leading, 18)
                    .padding(.top, 50)
                }
                .frame(width: geometry.size.width, height: headerHeight)
                .background(Color(uiColor: .systemBackground))
                .ignoresSafeArea(edges: .top)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea(edges: .top)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
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
            playEpisode(season: ep.seasonNumber, episode: ep.episodeNumber, title: ep.name)
        } label: {
            HStack(alignment: .top, spacing: 14) {
                // Thumbnail
                ZStack(alignment: .center) {
                    if let stillPath = ep.stillPath {
                        let stillURL = ImageURLBuilder.stillURL(for: stillPath, config: appState.apiConfiguration, idealWidth: 300)
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

                    if let airDate = ep.airDate {
                        Text(String(Calendar.current.component(.year, from: airDate)))
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
        appState.myListManager.isSeriesInList(seriesId)
    }

    private var isLiked: Bool {
        appState.likedManager.isSeriesLiked(seriesId)
    }

    private func toggleMyList() {
        appState.myListManager.toggleSeries(seriesId)
    }

    private func toggleLiked() {
        appState.likedManager.toggleSeries(seriesId)
    }

    private var bestTrailerKey: String? {
        let yt = trailers.filter { $0.site.lowercased() == "youtube" && !$0.key.isEmpty }
        if let trailer = yt.first(where: { $0.type.lowercased() == "trailer" }) {
            return trailer.key
        }
        if let teaser = yt.first(where: { $0.type.lowercased() == "teaser" }) {
            return teaser.key
        }
        return yt.first?.key
    }

    private func loadSeriesDetails() async {
        isLoading = true
        defer { isLoading = false }
        do {
            self.series = try await appState.tmdbService.tvSeriesDetails(forSeriesId: seriesId)
            // Age Rating
            self.ageRating = await appState.tmdbService.tvSeriesContentRating(forSeriesId: seriesId)
            // Recommendations
            self.recommendations = (try? await appState.tmdbService.tvSeriesRecommendations(forSeriesId: seriesId)) ?? []
            // Trailers
            self.trailers = await appState.tmdbService.tvSeriesVideosList(forSeriesId: seriesId)
        } catch {}
    }

    private func loadSeason(_ seasonNumber: Int) async {
        isLoadingSeason = true
        defer { isLoadingSeason = false }
        do {
            self.loadedSeason = try await appState.tmdbService.tvSeasonDetails(seriesId: seriesId, seasonNumber: seasonNumber)
            prefetchTargetEpisodeIfPossible()
        } catch {}
    }

    private func prefetchTargetEpisodeIfPossible() {
        guard let episodes = loadedSeason?.episodes, !episodes.isEmpty else { return }
        let targetEp = episodes.first {
            (appState.watchProgressManager.resumeTimeForEpisode(seriesId: seriesId, season: $0.seasonNumber, episode: $0.episodeNumber) ?? 0) > 5
        } ?? episodes[0]
        let epKey = "\(seriesId)_\(targetEp.seasonNumber)_\(targetEp.episodeNumber)"
        guard prefetchedEpisodeKey != epKey else { return }
        prefetchedEpisodeKey = epKey
        Task {
            if let pair = try? await appState.streamingService.playableURLsAndQualityForEpisode(seriesId: seriesId, season: targetEp.seasonNumber, episode: targetEp.episodeNumber) {
                await MainActor.run {
                    self.prefetchedEpisodePlayback = pair
                }
            }
        }
    }

    private var hasResumePosition: Bool {
        if let episodes = loadedSeason?.episodes {
            for ep in episodes {
                if (appState.watchProgressManager.resumeTimeForEpisode(seriesId: seriesId, season: ep.seasonNumber, episode: ep.episodeNumber) ?? 0) > 5 {
                    return true
                }
            }
        }
        return false
    }

    private func playFirstOrResumeEpisode() {
        if let episodes = loadedSeason?.episodes, !episodes.isEmpty {
            // Find first episode with resume progress, or the first episode
            let targetEp = episodes.first {
                (appState.watchProgressManager.resumeTimeForEpisode(seriesId: seriesId, season: $0.seasonNumber, episode: $0.episodeNumber) ?? 0) > 5
            } ?? episodes[0]
            playEpisode(season: targetEp.seasonNumber, episode: targetEp.episodeNumber, title: targetEp.name)
        }
    }

    private func playEpisode(season: Int, episode: Int, title: String) {
        let resumeTime = appState.watchProgressManager.resumeTimeForEpisode(seriesId: seriesId, season: season, episode: episode)
        let epKey = "\(seriesId)_\(season)_\(episode)"
        let preUrls = (prefetchedEpisodeKey == epKey) ? (prefetchedEpisodePlayback?.urls ?? []) : []
        let preQual = (prefetchedEpisodeKey == epKey) ? prefetchedEpisodePlayback?.quality : nil
        playableContent = PlayableContent(
            urls: preUrls,
            title: "\(series?.name ?? "Show") - S\(season) E\(episode) \(title)",
            quality: preQual,
            startTime: resumeTime,
            tvSeriesId: seriesId,
            season: season,
            episode: episode
        )
    }
}
#endif
