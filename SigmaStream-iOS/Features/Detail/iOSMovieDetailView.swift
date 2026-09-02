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

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Hero Backdrop with Z-stacked Back Button
                    ZStack(alignment: .topLeading) {
                        // Backdrop Image strictly bounded to screen width
                        ZStack(alignment: .bottomLeading) {
                            if let backdropPath = movie?.backdropPath {
                                let backdropURL = ImageURLBuilder.backdropURL(for: backdropPath, config: appState.apiConfiguration, idealWidth: 780)
                                AsyncImage(url: backdropURL) { phase in
                                    if let image = phase.image {
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: geometry.size.width, height: 320)
                                            .clipped()
                                    } else {
                                        Color.white.opacity(0.05)
                                    }
                                }
                            } else {
                                Color.white.opacity(0.05)
                            }

                            // Gradient Scrim
                            LinearGradient(
                                colors: [Color.clear, Color(uiColor: .systemBackground).opacity(0.8), Color(uiColor: .systemBackground)],
                                startPoint: .center,
                                endPoint: .bottom
                            )
                        }
                        .frame(width: geometry.size.width, height: 320)
                        .clipped()

                        // Floating Back Button placed on top of poster preview
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
                    .frame(width: geometry.size.width, height: 320)
                    .clipped()

                    // Content Details strictly constrained to screen width with horizontal margins
                    VStack(alignment: .leading, spacing: 18) {
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
                                        .font(.caption)
                                        .foregroundStyle(.yellow)
                                    Text(String(format: "%.1f", rating))
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.white)
                                }
                            }
                        }

                        // Genres
                        if let genres = movie?.genres, !genres.isEmpty {
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

                        // Primary Play Buttons
                        VStack(spacing: 10) {
                            Button {
                                startPlayMovie(fromBeginning: false)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "play.fill")
                                        .font(.headline)
                                    Text(hasResumePosition ? "Resume Movie" : "Play Movie")
                                        .font(.headline.bold())
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.white)
                                .foregroundStyle(.black)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }

                            if hasResumePosition {
                                Button {
                                    startPlayMovie(fromBeginning: true)
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "arrow.counterclockwise")
                                        Text("Play from Beginning")
                                    }
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.white.opacity(0.12))
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }
                        }
                        .padding(.top, 4)

                        // Overview Description
                        if let overview = movie?.overview, !overview.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Overview")
                                    .font(.headline)
                                    .foregroundStyle(.white)

                                Text(overview)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineSpacing(4)
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

                        // Cast Section
                        if !cast.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Cast & Crew")
                                    .font(.headline)
                                    .foregroundStyle(.white)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    LazyHStack(spacing: 14) {
                                        ForEach(cast) { member in
                                            VStack(spacing: 6) {
                                                ZStack {
                                                    Color.white.opacity(0.08)
                                                    if let path = member.profilePath {
                                                        let url = ImageURLBuilder.posterURL(for: path, config: appState.apiConfiguration, idealWidth: 185)
                                                        AsyncImage(url: url) { phase in
                                                            if let img = phase.image {
                                                                img.resizable().aspectRatio(contentMode: .fill)
                                                            }
                                                        }
                                                    } else {
                                                        Image(systemName: "person.fill")
                                                            .foregroundStyle(.secondary)
                                                    }
                                                }
                                                .frame(width: 70, height: 70)
                                                .clipShape(Circle())

                                                Text(member.name)
                                                    .font(.caption2.bold())
                                                    .foregroundStyle(.white)
                                                    .lineLimit(1)

                                                Text(member.character)
                                                    .font(.system(size: 10))
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                            .frame(width: 80)
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
                            .padding(.top, 8)

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
                                                iOSMovieDetailView(movieId: rec.id)
                                            } label: {
                                                iOSMediaCard(
                                                    id: rec.id,
                                                    title: rec.title,
                                                    posterPath: ImageURLBuilder.posterURL(for: rec.posterPath, config: appState.apiConfiguration, idealWidth: 342),
                                                    rating: rec.voteAverage,
                                                    releaseYear: rec.releaseDate.map { String(Calendar.current.component(.year, from: $0)) },
                                                    isTVSeries: false,
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
                    .frame(width: geometry.size.width, alignment: .leading)
                    .padding(.bottom, 40)
                }
                .frame(width: geometry.size.width)
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
            await loadMovieDetails()
            scheduleMoviePrefetchIfReleased()
        }
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
