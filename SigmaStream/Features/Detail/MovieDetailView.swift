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
    @State private var streamQuality: String?
    @State private var showStreamPicker = false
    @State private var streamPickerSources: [OMSSSource] = []
    @State private var pendingStreamSelection: OMSSSource?
    @State private var trailerYouTubeKey: String?
    @State private var trailerAlertMessage: String?
    @State private var streamResolutionTask: Task<Void, Never>?
    @State private var moviePrefetchTask: Task<Void, Never>?
    @State private var prefetchedMoviePlayback: (urls: [URL], quality: String?)?
    @FocusState private var focusedButtonId: String?
    @FocusState private var focusedThumbId: String?

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
                GeometryReader { geo in
                    let contentWidth = geo.size.width * 0.45
                    ZStack(alignment: .leading) {
                        if let backdropURL = ImageURLBuilder.backdropURL(for: movie.backdropPath, config: appState.apiConfiguration) {
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
                            VStack(alignment: .leading, spacing: 24) {
                                Text(movie.title)
                                    .font(.system(size: 48, weight: .bold))

                                metadataRow

                                if let overview = movie.overview, !overview.isEmpty {
                                    Text(overview)
                                        .font(.body)
                                        .frame(maxWidth: contentWidth, alignment: .leading)
                                }

                                thumbsAndButtonsSection(contentWidth: contentWidth)
                                    .padding(.leading, 24)

                                if let streamErr = streamError {
                                    Text(streamErr)
                                        .foregroundStyle(.red)
                                        .font(.subheadline)
                                }
                            }
                            .frame(maxWidth: contentWidth, alignment: .leading)
                            .padding(48)
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
        .sheet(isPresented: $showStreamPicker, onDismiss: {
            if let source = pendingStreamSelection {
                pendingStreamSelection = nil
                Task { await playSource(source) }
            }
        }) {
            StreamPickerView(
                title: movie?.title ?? "Movie",
                sources: streamPickerSources,
                onSelect: { source in
                    pendingStreamSelection = source
                    showStreamPicker = false
                },
                onDismiss: { showStreamPicker = false }
            )
            .environment(appState)
        }
        .fullScreenCover(item: $playableContent) { content in
            VideoPlayerView(content: content, watchProgress: appState.watchProgressManager) {
                if let mid = content.movieId {
                    appState.watchProgressManager.removeMovie(mid)
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("")
        .task {
            await loadMovie()
        }
        .onDisappear {
            moviePrefetchTask?.cancel()
            moviePrefetchTask = nil
            prefetchedMoviePlayback = nil
        }
    }

    private func resolvingStreamsRow(onCancel: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.9)
            Text("Fetching streams...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button("Cancel", action: onCancel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailButton(id: String, icon: String, title: String, action: @escaping () -> Void, disabled: Bool = false) -> some View {
        let isFocused = focusedButtonId == id
        return Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                Text(title)
                    .font(.system(size: 20, weight: .medium))
            }
            .foregroundStyle(isFocused ? .black : .white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 0)
            .padding(.trailing, 24)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .focused($focusedButtonId, equals: id)
        .disabled(disabled)
    }

    private var metadataRow: some View {
        HStack(spacing: 12) {
            if let date = movie?.releaseDate {
                Text(Calendar.current.component(.year, from: date).description)
                    .foregroundStyle(.secondary)
            }
            if let genres = movie?.genres, !genres.isEmpty {
                Text(genres.prefix(2).map(\.name).joined(separator: ", "))
                    .foregroundStyle(.secondary)
            }
            if let runtime = movie?.runtime {
                Text("\(runtime) min")
                    .foregroundStyle(.secondary)
            }
            if let q = streamQuality {
                Text(q)
                    .foregroundStyle(.secondary)
            }
            if let rating = movie?.voteAverage {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.caption)
                    Text(String(format: "%.1f", rating))
                }
                .foregroundStyle(.secondary)
            }
            Image(systemName: "captions.bubble")
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }

    @ViewBuilder
    private func thumbsAndButtonsSection(contentWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            thumbsRow(contentWidth: contentWidth)

            if isReleased {
                if appState.watchProgressManager.canResumeMovie(movieId) {
                    detailButton(id: "resume", icon: "play.fill", title: "Resume") {
                        startResolveStream(fromBeginning: false)
                    }
                    .disabled(isResolvingStream)

                    detailButton(id: "playFromStart", icon: "arrow.counterclockwise", title: "Play from Beginning") {
                        startResolveStream(fromBeginning: true)
                    }
                    .disabled(isResolvingStream)
                } else {
                    detailButton(id: "play", icon: "play.fill", title: "Play") {
                        startResolveStream(fromBeginning: true)
                    }
                    .disabled(isResolvingStream)
                }

                detailButton(id: "chooseStream", icon: "list.bullet", title: "Choose Stream") {
                    startShowStreamPickerFetch()
                }
                .disabled(isResolvingStream)
            } else {
                Text(comingSoonText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let key = trailerYouTubeKey {
                detailButton(id: "trailer", icon: "play.rectangle.fill", title: "Watch Trailer") {
                    openTrailer(key: key)
                }
            }

            detailButton(
                id: "mylist",
                icon: appState.myListManager.isMovieInList(movieId) ? "minus.circle" : "plus.circle",
                title: appState.myListManager.isMovieInList(movieId) ? "Remove from My List" : "Add to My List"
            ) {
                appState.myListManager.toggleMovie(movieId)
            }
        }
        .frame(maxWidth: contentWidth, alignment: .leading)
        .focusSection()
    }

    private func thumbsRow(contentWidth: CGFloat) -> some View {
        HStack(spacing: 56) {
            Button {
                appState.likedManager.toggleMovie(movieId)
            } label: {
                Image(systemName: appState.likedManager.isMovieLiked(movieId) ? "hand.thumbsup.fill" : "hand.thumbsup")
                    .foregroundStyle(focusedThumbId == "up" ? .black : (appState.likedManager.isMovieLiked(movieId) ? .white : .secondary))
                    .font(.system(size: 20))
                    .frame(width: 60, height: 60)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focused($focusedThumbId, equals: "up")
        }
        .frame(maxWidth: contentWidth, alignment: .leading)
    }

    private var isReleased: Bool {
        guard let date = movie?.releaseDate else { return true }
        return date <= Calendar.current.startOfDay(for: Date())
    }

    private var comingSoonText: String {
        guard let date = movie?.releaseDate else { return "Coming Soon" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return "Coming \(formatter.string(from: date))"
    }

    private func openTrailer(key: String) {
        let youtubeURL = URL(string: "youtube://watch/\(key)")
        let httpsURL = URL(string: "https://www.youtube.com/watch?v=\(key)")!
        let canOpenYouTube = youtubeURL.map { UIApplication.shared.canOpenURL($0) } ?? false
        let urlToOpen = (canOpenYouTube && youtubeURL != nil) ? youtubeURL! : httpsURL

        UIApplication.shared.open(urlToOpen) { success in
            if !success {
                trailerAlertMessage = "You need the YouTube app to view trailers. Install it from the App Store if you haven't already."
            }
        }
    }

    private func cancelStreamResolution() {
        streamResolutionTask?.cancel()
        streamError = nil
    }

    private func startResolveStream(fromBeginning: Bool) {
        if let cached = prefetchedMoviePlayback, !cached.urls.isEmpty {
            prefetchedMoviePlayback = nil
            moviePrefetchTask?.cancel()
            moviePrefetchTask = nil
            if let q = cached.quality { streamQuality = q }
            playableContent = makeMoviePlayableContent(urls: cached.urls, quality: cached.quality, fromBeginning: fromBeginning)
            return
        }
        // Immediately present fullscreen VideoPlayerView with dynamic stream resolution
        playableContent = makeMoviePlayableContent(urls: [], quality: streamQuality, fromBeginning: fromBeginning)
    }

    private func makeMoviePlayableContent(urls: [URL], quality: String?, fromBeginning: Bool) -> PlayableContent {
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

    private func startShowStreamPickerFetch() {
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
                let sources = try await appState.streamingService.sourcesForMovie(tmdbId: movieId)
                try Task.checkCancellation()
                let playable = sources.filter { $0.isPlayable }
                guard !playable.isEmpty else {
                    streamError = "No stream was found (none marked playable)."
                    return
                }
                if let q = playable.first?.quality { streamQuality = q }
                streamPickerSources = playable
                showStreamPicker = true
            } catch is CancellationError {
                streamError = nil
                return
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

    private func playSource(_ source: OMSSSource) async {
        guard let url = await appState.streamingService.playableURL(for: source) else {
            streamError = "Could not load stream"
            return
        }
        if let q = source.quality { streamQuality = q }
        await MainActor.run {
            playableContent = makeMoviePlayableContent(urls: [url], quality: source.quality, fromBeginning: true)
        }
    }

    private func loadMovie() async {
        scheduleMoviePrefetchIfReleased()
        do {
            movie = try await appState.tmdbService.movieDetails(forMovieId: movieId)
            trailerYouTubeKey = try? await appState.tmdbService.movieTrailerYouTubeKey(movieId: movieId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Warm OMSS cache while the user reads metadata so Play can snap open after aggregated scrape finishes.
    private func scheduleMoviePrefetchIfReleased() {
        moviePrefetchTask?.cancel()
        moviePrefetchTask = Task {
            do {
                let pair = try await appState.streamingService.playableURLsAndQualityForMovie(tmdbId: movieId)
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    prefetchedMoviePlayback = pair
                }
            } catch {}
        }
    }
}

#Preview {
    NavigationStack {
        MovieDetailView(movieId: 550)
            .environment(AppState(apiKey: "placeholder"))
    }
}
