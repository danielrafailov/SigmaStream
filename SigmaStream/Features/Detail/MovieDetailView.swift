//
//  MovieDetailView.swift
//  SigmaStream
//
//  Created by Daniel Rafailov on 2026-03-16.
//

import SwiftUI
import TMDb

struct MovieDetailView: View {
    let movieId: Int
    @Environment(AppState.self) private var appState
    @State private var movie: Movie?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isResolvingStream = false
    @State private var streamError: String?
    @State private var playableContent: PlayableContent?
    @State private var trailerYouTubeKey: String?
    @State private var trailerAlertMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                ContentUnavailableView(
                    "Couldn't load movie",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if let movie {
                ZStack {
                    if let backdropURL = ImageURLBuilder.backdropURL(for: movie.backdropPath, config: appState.apiConfiguration) {
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
                                Text(movie.title)
                                    .font(.largeTitle)
                                    .fontWeight(.bold)

                                if let date = movie.releaseDate {
                                    Text(Calendar.current.component(.year, from: date).description)
                                        .font(.title3)
                                        .foregroundStyle(.secondary)
                                }

                                if let rating = movie.voteAverage {
                                    Label(String(format: "%.1f/10", rating), systemImage: "star.fill")
                                        .font(.title3)
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 12) {
                                        Button {
                                            Task { await resolveStream() }
                                        } label: {
                                            Label("Watch", systemImage: "play.fill")
                                        }
                                        .disabled(isResolvingStream)

                                        if let key = trailerYouTubeKey {
                                            Button {
                                                openTrailer(key: key)
                                            } label: {
                                                Label("Watch Trailer", systemImage: "play.rectangle.fill")
                                            }
                                        }
                                    }

                                    Button {
                                        appState.myListManager.toggleMovie(movieId)
                                    } label: {
                                        Label(
                                            appState.myListManager.isMovieInList(movieId) ? "Remove from List" : "Add to List",
                                            systemImage: appState.myListManager.isMovieInList(movieId) ? "minus.circle" : "plus.circle"
                                        )
                                    }
                                }
                                .padding(.top, 8)
                            }
                            Spacer()
                        }
                        .padding()

                        if let streamErr = streamError {
                            Text(streamErr)
                                .foregroundStyle(.red)
                                .font(.subheadline)
                                .padding(.horizontal)
                        }

                        if let overview = movie.overview, !overview.isEmpty {
                            Text(overview)
                                .font(.body)
                                .padding(.horizontal)
                        }
                        }
                    }
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
                    if let mid = content.movieId {
                        appState.watchProgressManager.removeMovie(mid)
                    }
                }
            )
        }
        .task {
            await loadMovie()
        }
    }

    private func openTrailer(key: String) {
        let youtubeURL = URL(string: "youtube://watch/\(key)")
        let httpsURL = URL(string: "https://www.youtube.com/watch?v=\(key)")!
        let canOpenYouTube = youtubeURL.map { UIApplication.shared.canOpenURL($0) } ?? false
        let urlToOpen = (canOpenYouTube && youtubeURL != nil) ? youtubeURL! : httpsURL

        #if DEBUG
        print("[MovieDetail] Trailer key=\(key), youtubeURL=\(youtubeURL?.absoluteString ?? "nil"), canOpenYouTube=\(canOpenYouTube), opening=\(urlToOpen.absoluteString)")
        #endif

        UIApplication.shared.open(urlToOpen) { success in
            #if DEBUG
            print("[MovieDetail] Trailer open success=\(success)")
            #endif
            if !success {
                trailerAlertMessage = "You need the YouTube app to view trailers. Install it from the App Store if you haven't already."
            }
        }
    }

    private func resolveStream() async {
        guard !isResolvingStream else { return }
        isResolvingStream = true
        streamError = nil
        defer { isResolvingStream = false }

        do {
            let urls = try await appState.streamingService.playableURLsForMovie(tmdbId: movieId)
            guard !urls.isEmpty else {
                #if DEBUG
                print("[MovieDetail] Stream resolve returned empty URLs for movie \(movieId)")
                #endif
                streamError = "No stream was found"
                return
            }
            let content = PlayableContent(urls: urls, title: movie?.title ?? "Movie", movieId: movieId)
            playableContent = content
            appState.watchProgressManager.recordMovie(movieId)
        } catch {
            #if DEBUG
            print("[MovieDetail] Stream resolve failed: \(error)")
            #endif
            streamError = "No stream was found"
        }
    }

    @ViewBuilder
    private var posterSection: some View {
        if let url = ImageURLBuilder.posterURL(for: movie?.posterPath, config: appState.apiConfiguration, idealWidth: 500) {
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
                Image(systemName: "film")
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)
            }
    }

    private func loadMovie() async {
        do {
            movie = try await appState.tmdbService.movieDetails(forMovieId: movieId)
            trailerYouTubeKey = try? await appState.tmdbService.movieTrailerYouTubeKey(movieId: movieId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

#Preview {
    NavigationStack {
        MovieDetailView(movieId: 550)
            .environment(AppState(apiKey: "placeholder"))
    }
}
