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
    @State private var ageRating: String?
    @State private var selectedSeasonNumber: Int = 1
    @State private var loadedSeason: TVSeason?
    @State private var recommendations: [TVSeriesListItem] = []
    @State private var trailers: [TMDbVideo] = []
    @State private var selectedTab: DetailSubTab = .moreLikeThis

    @State private var isLoading = true
    @State private var isLoadingSeason = false
    @State private var playableContent: PlayableContent?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                // Fixed Top Backdrop Poster (stays pinned at top during scroll)
                ZStack(alignment: .bottomLeading) {
                    if let backdropPath = series?.backdropPath {
                        let backdropURL = ImageURLBuilder.backdropURL(for: backdropPath, config: appState.apiConfiguration, idealWidth: 780)
                        AsyncImage(url: backdropURL) { phase in
                            if let image = phase.image {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: geometry.size.width, height: 260)
                                    .clipped()
                            } else {
                                Color.white.opacity(0.05)
                            }
                        }
                    } else {
                        Color.white.opacity(0.05)
                    }

                    // Gradient Scrim into background
                    LinearGradient(
                        colors: [Color.clear, Color(uiColor: .systemBackground).opacity(0.5), Color(uiColor: .systemBackground)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .frame(width: geometry.size.width, height: 260)
                .clipped()
                .ignoresSafeArea(edges: .top)

                // Scrollable Content Over Fixed Poster
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Spacer allowing user to initially view the top poster clearly
                        Color.clear
                            .frame(height: 200)

                        // Content Details strictly constrained to screen width with horizontal margins
                        VStack(alignment: .leading, spacing: 18) {
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

                            if let count = series?.numberOfSeasons {
                                Text("\(count) Season\(count > 1 ? "s" : "")")
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
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        // Action Icons (My List + Thumbs Up Like below description)
                        HStack(spacing: 36) {
                            // My List Button
                            Button {
                                toggleMyList()
                            } label: {
                                VStack(spacing: 5) {
                                    Image(systemName: isInMyList ? "checkmark" : "plus")
                                        .font(.title3.bold())
                                    Text(isInMyList ? "In List" : "My List")
                                        .font(.caption2.bold())
                                }
                                .foregroundStyle(isInMyList ? Color.blue : Color.white)
                            }
                            .buttonStyle(.plain)

                            // Like Button (Thumbs Up, fills white on click)
                            Button {
                                toggleLiked()
                            } label: {
                                VStack(spacing: 5) {
                                    Image(systemName: isLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
                                        .font(.title3.bold())
                                    Text("Like")
                                        .font(.caption2.bold())
                                }
                                .foregroundStyle(isLiked ? Color.white : Color.white.opacity(0.7))
                            }
                            .buttonStyle(.plain)

                            Spacer()
                        }
                        .padding(.vertical, 4)

                        Divider()
                            .background(Color.white.opacity(0.15))
                            .padding(.vertical, 4)

                        // Season Selector & Episodes
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

                        // Sub-Tabs Header: "More Like This" & "Trailers & More"
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 24) {
                                Button {
                                    selectedTab = .moreLikeThis
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
                                    selectedTab = .trailersAndMore
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
                            .padding(.top, 12)

                            // Tab Content: More Like This
                            if selectedTab == .moreLikeThis {
                                if recommendations.isEmpty {
                                    Text("No similar titles found.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .padding(.vertical, 16)
                                } else {
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 105, maximum: 140), spacing: 12)], spacing: 14) {
                                        ForEach(recommendations) { rec in
                                            NavigationLink {
                                                iOSTVSeriesDetailView(seriesId: rec.id)
                                            } label: {
                                                iOSMediaCard(
                                                    id: rec.id,
                                                    title: rec.name,
                                                    posterPath: ImageURLBuilder.posterURL(for: rec.posterPath, config: appState.apiConfiguration, idealWidth: 342),
                                                    rating: rec.voteAverage,
                                                    releaseYear: rec.firstAirDate.map { String(Calendar.current.component(.year, from: $0)) },
                                                    isTVSeries: true,
                                                    progress: nil,
                                                    showLabels: false
                                                )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.top, 4)
                                }
                            } else {
                                // Tab Content: Trailers & More
                                if trailers.isEmpty {
                                    Text("No trailers available.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .padding(.vertical, 16)
                                } else {
                                    VStack(spacing: 16) {
                                        ForEach(trailers, id: \.id) { video in
                                            Button {
                                                if let ytURL = video.youtubeWatchURL {
                                                    UIApplication.shared.open(ytURL)
                                                }
                                            } label: {
                                                VStack(alignment: .leading, spacing: 8) {
                                                    ZStack(alignment: .center) {
                                                        if let thumbURL = video.youtubeThumbnailURL {
                                                            AsyncImage(url: thumbURL) { phase in
                                                                if let img = phase.image {
                                                                    img.resizable().aspectRatio(contentMode: .fill)
                                                                } else {
                                                                    Color.white.opacity(0.08)
                                                                }
                                                            }
                                                        } else {
                                                            Color.white.opacity(0.08)
                                                        }

                                                        Image(systemName: "play.circle.fill")
                                                            .font(.system(size: 46))
                                                            .foregroundStyle(.white)
                                                            .shadow(color: .black.opacity(0.7), radius: 6)
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
                        .background(
                            Color(uiColor: .systemBackground)
                                .shadow(color: .black.opacity(0.4), radius: 10, y: -5)
                        )
                        .frame(width: geometry.size.width, alignment: .leading)
                        .padding(.bottom, 40)
                    }
                    .frame(width: geometry.size.width)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)

                // Floating Back Button pinned at top-left
                HStack {
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
                    Spacer()
                }
                .padding(.leading, 18)
                .padding(.top, 50)
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
        } catch {}
    }

    private func playEpisode(season: Int, episode: Int, title: String) {
        let resumeTime = appState.watchProgressManager.resumeTimeForEpisode(seriesId: seriesId, season: season, episode: episode)
        // Immediately opens loader screen and searches for stream inside iOSTouchPlayerView
        playableContent = PlayableContent(
            urls: [],
            title: "\(series?.name ?? "Show") - S\(season) E\(episode) \(title)",
            startTime: resumeTime,
            tvSeriesId: seriesId,
            season: season,
            episode: episode
        )
    }
}
#endif
