//
//  iOSMovieDetailView.swift
//  SigmaStream-iOS
//
//  Created by Daniel Rafailov on 2026-09-01.
//

import SwiftUI
import TMDb

#if os(iOS)
struct iOSMovieDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let movieId: Int

    @State private var movie: Movie?
    @State private var cast: [CastMember] = []
    @State private var isLoading = true
    @State private var isResolvingStream = false
    @State private var streamError: String?
    @State private var playableContent: PlayableContent?
    @State private var showPlayer = false
    @State private var streamQuality: String?
    @State private var streamResolutionTask: Task<Void, Never>?
    @State private var moviePrefetchTask: Task<Void, Never>?
    @State private var prefetchedMoviePlayback: (urls: [URL], quality: String?)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Hero Backdrop
                ZStack(alignment: .bottomLeading) {
                    if let backdropPath = movie?.backdropPath {
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
                    Text(movie?.title ?? "Movie Details")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)

                    // Metadata Row (Year, Runtime, Rating)
                    HStack(spacing: 12) {
                        if let date = movie?.releaseDate {
                            Text(String(Calendar.current.component(.year, from: date)))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
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
                            startResolveStream(fromBeginning: false)
                        } label: {
                            HStack(spacing: 8) {
                                if isResolvingStream {
                                    ProgressView()
                                        .tint(.black)
                                } else {
                                    Image(systemName: "play.fill")
                                        .font(.headline)
                                }
                                Text(hasResumePosition ? "Resume Movie" : "Play Movie")
                                    .font(.headline.bold())
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white)
                            .foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .disabled(isResolvingStream)

                        if hasResumePosition {
                            Button {
                                startResolveStream(fromBeginning: true)
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

                    // Action Icons (My List, Like, Quality)
                    HStack(spacing: 24) {
                        // My List Button
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

                        // Like Button
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

                    // Stream Error Message (if any)
                    if let streamError, !streamError.isEmpty {
                        Text(streamError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    // Synopsis
                    if let overview = movie?.overview, !overview.isEmpty {
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

                    // Cast Section
                    if !cast.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Top Cast")
                                .font(.headline)
                                .foregroundStyle(.white)

                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 12) {
                                    ForEach(cast.prefix(12), id: \.id) { member in
                                        VStack(alignment: .center, spacing: 6) {
                                            ZStack {
                                                Color.white.opacity(0.08)
                                                if let path = member.profilePath {
                                                    let url = ImageURLBuilder.profileURL(path: path, size: .w185)
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
            await loadMovieDetails()
            scheduleMoviePrefetchIfReleased()
        }
    }

    private var hasResumePosition: Bool {
        appState.watchProgressManager.hasResumePositionForMovie(movieId)
    }

    private var isInMyList: Bool {
        appState.myListManager.contains(id: movieId, type: .movie)
    }

    private var isLiked: Bool {
        appState.likedManager.isLiked(id: movieId, type: .movie)
    }

    private func toggleMyList() {
        if isInMyList {
            appState.myListManager.remove(id: movieId, type: .movie)
        } else {
            appState.myListManager.add(id: movieId, type: .movie)
        }
    }

    private func toggleLiked() {
        appState.likedManager.toggleLiked(id: movieId, type: .movie)
    }

    private func loadMovieDetails() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let movieFetch = appState.tmdbService.movieDetails(forMovieId: movieId)
            async let creditsFetch = appState.tmdbService.movieCredits(forMovieId: movieId)
            let (m, c) = try await (movieFetch, creditsFetch)
            self.movie = m
            self.cast = c.cast
        } catch {
            // Error handling
        }
    }

    private func scheduleMoviePrefetchIfReleased() {
        guard let movie else { return }
        if let date = movie.releaseDate, date > Calendar.current.startOfDay(for: Date()) { return }
        moviePrefetchTask?.cancel()
        prefetchedMoviePlayback = nil
        moviePrefetchTask = Task {
            do {
                let pair = try await appState.streamingService.playableURLsAndQualityForMovie(tmdbId: movieId)
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self.prefetchedMoviePlayback = pair
                }
            } catch {}
        }
    }

    private func startResolveStream(fromBeginning: Bool) {
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
                if let cached = prefetchedMoviePlayback {
                    prefetchedMoviePlayback = nil
                    moviePrefetchTask?.cancel()
                    moviePrefetchTask = nil
                    guard !cached.urls.isEmpty else {
                        streamError = "No stream was found."
                        return
                    }
                    if let q = cached.quality { streamQuality = q }
                    playableContent = makePlayableContent(urls: cached.urls, quality: cached.quality, fromBeginning: fromBeginning)
                    return
                }

                let (urls, quality) = try await appState.streamingService.playableURLsAndQualityForMovie(tmdbId: movieId)
                try Task.checkCancellation()
                guard !urls.isEmpty else {
                    streamError = "No stream was found."
                    return
                }
                if let quality { streamQuality = quality }
                playableContent = makePlayableContent(urls: urls, quality: quality, fromBeginning: fromBeginning)
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

    private func makePlayableContent(urls: [URL], quality: String?, fromBeginning: Bool) -> PlayableContent {
        if fromBeginning {
            appState.watchProgressManager.clearMoviePlaybackPosition(movieId)
        }
        let startTime = fromBeginning ? nil : appState.watchProgressManager.resumeTimeForMovie(movieId)
        return PlayableContent(
            urls: urls,
            title: movie?.title ?? "Movie",
            quality: quality,
            startTime: startTime,
            movieId: movieId
        )
    }
}
#endif
