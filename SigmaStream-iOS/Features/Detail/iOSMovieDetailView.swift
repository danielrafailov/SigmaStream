//
//  iOSMovieDetailView.swift
//  SigmaStream-iOS
//
//  Created by Daniel Rafailov on 2026-09-01.
//

import SwiftUI
import TMDb

#if os(iOS)
enum DetailSubTab: String, CaseIterable, Identifiable {
    case moreLikeThis = "More Like This"
    case trailersAndMore = "Trailers & More"

    var id: String { rawValue }
}

struct iOSMovieDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(AppState.self) private var appState

    let movieId: Int

    @State private var movie: Movie?
    @State private var cast: [CastMember] = []
    @State private var ageRating: String?
    @State private var recommendations: [MovieListItem] = []
    @State private var trailers: [TMDbVideo] = []
    @State private var selectedTab: DetailSubTab = .moreLikeThis

    @State private var isLoading = true
    @State private var playableContent: PlayableContent?
    @State private var prefetchedMoviePlayback: (urls: [URL], quality: String?)?

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
                            Text(movie?.title ?? "Movie Details")
                                .font(.system(size: 26, weight: .bold))
                                .foregroundStyle(.white)
                                .fixedSize(horizontal: false, vertical: true)

                            // Metadata Row: [Year] [Age Rating] [Length] [Rating]
                            HStack(spacing: 10) {
                                if let date = movie?.releaseDate {
                                    Text(String(Calendar.current.component(.year, from: date)))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                // Age Rating in between year and length
                                if let ageRating, !ageRating.isEmpty {
                                    Text(ageRating)
                                        .font(.caption2.bold())
                                        .foregroundStyle(.white.opacity(0.9))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.white.opacity(0.18))
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                }

                                if let runtime = movie?.runtime, runtime > 0 {
                                    Text("\(runtime / 60)h \(runtime % 60)m")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                if let rating = movie?.voteAverage, rating > 0 {
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

                            // Play Movie Button
                            Button {
                                startPlayMovie(fromBeginning: false)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: hasResumePosition ? "play.fill" : "play.fill")
                                        .font(.system(size: 16, weight: .bold))
                                    Text(hasResumePosition ? "Resume Movie" : "Play Movie")
                                        .font(.system(size: 16, weight: .bold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.white)
                                .foregroundStyle(.black)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .padding(.top, 4)

                            // Overview description
                            if let overview = movie?.overview, !overview.isEmpty {
                                Text(overview)
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.85))
                                    .lineSpacing(4)
                            }

                            // Action Buttons: + My List & Like (Thumbs Up) placed BELOW description
                            HStack(spacing: 40) {
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        toggleMyList()
                                    }
                                } label: {
                                    VStack(spacing: 6) {
                                        Image(systemName: isInMyList ? "checkmark" : "plus")
                                            .font(.system(size: 20, weight: .bold))
                                        Text("My List")
                                            .font(.caption2)
                                    }
                                    .foregroundStyle(.white)
                                }

                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        toggleLiked()
                                    }
                                } label: {
                                    VStack(spacing: 6) {
                                        Image(systemName: isLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
                                            .font(.system(size: 20, weight: .bold))
                                        Text("Like")
                                            .font(.caption2)
                                    }
                                    .foregroundStyle(.white)
                                }

                                Spacer()
                            }
                            .padding(.top, 2)

                            // Cast & Crew Row
                            if !cast.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Cast")
                                        .font(.headline.bold())
                                        .foregroundStyle(.white)

                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 12) {
                                            ForEach(cast.prefix(10)) { member in
                                                VStack(spacing: 6) {
                                                    if let path = member.profilePath {
                                                        let url = ImageURLBuilder.profileURL(for: path, config: appState.apiConfiguration, idealWidth: 185)
                                                        AsyncImage(url: url) { phase in
                                                            if let img = phase.image {
                                                                img.resizable().aspectRatio(contentMode: .fill)
                                                            } else {
                                                                Color.white.opacity(0.1)
                                                            }
                                                        }
                                                        .frame(width: 65, height: 65)
                                                        .clipShape(Circle())
                                                    } else {
                                                        Circle()
                                                            .fill(Color.white.opacity(0.1))
                                                            .frame(width: 65, height: 65)
                                                            .overlay(
                                                                Image(systemName: "person.fill")
                                                                    .foregroundStyle(.secondary)
                                                            )
                                                    }

                                                    Text(member.name)
                                                        .font(.caption2)
                                                        .foregroundStyle(.white)
                                                        .lineLimit(1)
                                                        .frame(width: 70)
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Sub-Tabs: "More Like This" & "Trailers & More"
                            VStack(alignment: .leading, spacing: 14) {
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
                                                    iOSMovieDetailView(movieId: item.id)
                                                } label: {
                                                    iOSMediaCard(
                                                        id: item.id,
                                                        title: item.title,
                                                        posterPath: ImageURLBuilder.posterURL(for: item.posterPath, config: appState.apiConfiguration, idealWidth: 342),
                                                        rating: item.voteAverage,
                                                        releaseYear: item.releaseDate.map { String(Calendar.current.component(.year, from: $0)) },
                                                        isTVSeries: false,
                                                        progress: nil,
                                                        showLabels: false
                                                    )
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                        .padding(.horizontal, 4)
                                        .padding(.top, 4)
                                    }
                                } else {
                                    // Trailers & More
                                    if trailers.isEmpty {
                                        Text("No trailers available.")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .padding(.vertical, 16)
                                    } else {
                                        VStack(spacing: 16) {
                                            ForEach(trailers, id: \.id) { video in
                                                Button {
                                                    if let ytAppURL = video.youtubeAppURL, UIApplication.shared.canOpenURL(ytAppURL) {
                                                        UIApplication.shared.open(ytAppURL)
                                                    } else if let ytURL = video.youtubeWatchURL {
                                                        UIApplication.shared.open(ytURL)
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
                .frame(width: geometry.size.width, height: geometry.size.height)

                // Layer 2: Fixed Top Backdrop Poster Header (Sits on top in Z-index)
                ZStack(alignment: .topLeading) {
                    ZStack(alignment: .bottom) {
                        let backdropURL = movie?.backdropPath.flatMap {
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
            // 1. Parallel Stream Resolution for 0s instantaneous playback on tap
            Task {
                if let pair = try? await appState.streamingService.playableURLsAndQualityForMovie(tmdbId: movieId) {
                    await MainActor.run {
                        self.prefetchedMoviePlayback = pair
                    }
                }
            }
            // 2. Load Details, Trailers, and Recommendations
            await loadMovieDetails()
        }
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

    private var hasResumePosition: Bool {
        appState.watchProgressManager.canResumeMovie(movieId)
    }

    private var isInMyList: Bool {
        appState.myListManager.isMovieInList(movieId)
    }

    private var isLiked: Bool {
        appState.likedManager.isMovieLiked(movieId)
    }

    private func toggleMyList() {
        appState.myListManager.toggleMovie(movieId)
    }

    private func toggleLiked() {
        appState.likedManager.toggleMovie(movieId)
    }

    private func loadMovieDetails() async {
        isLoading = true
        defer { isLoading = false }
        do {
            self.movie = try await appState.tmdbService.movieDetails(forMovieId: movieId)
            // Fetch Age Rating (Certification)
            self.ageRating = await appState.tmdbService.movieCertification(forMovieId: movieId)
            // Fetch Recommendations
            self.recommendations = (try? await appState.tmdbService.movieRecommendations(forMovieId: movieId)) ?? []
            // Fetch Trailers
            self.trailers = await appState.tmdbService.movieVideosList(forMovieId: movieId)
        } catch {}
    }

    private func scheduleMoviePrefetchIfReleased() {
        guard let movie else { return }
        if let date = movie.releaseDate, date > Calendar.current.startOfDay(for: Date()) { return }
        Task {
            if let pair = try? await appState.streamingService.playableURLsAndQualityForMovie(tmdbId: movieId) {
                await MainActor.run {
                    self.prefetchedMoviePlayback = pair
                }
            }
        }
    }

    private func startPlayMovie(fromBeginning: Bool) {
        if fromBeginning {
            appState.watchProgressManager.clearMoviePlaybackPosition(movieId)
        }
        let startTime = fromBeginning ? nil : appState.watchProgressManager.resumeTimeForMovie(movieId)
        // Immediately opens the loader screen and searches for streams inside iOSTouchPlayerView
        playableContent = PlayableContent(
            urls: prefetchedMoviePlayback?.urls ?? [],
            title: movie?.title ?? "Movie",
            quality: prefetchedMoviePlayback?.quality,
            startTime: startTime,
            movieId: movieId
        )
    }
}
#endif
