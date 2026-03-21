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
        .navigationTitle("")
        .task {
            await loadMovie()
        }
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
            Text(streamQuality ?? "HD")
                .foregroundStyle(.secondary)
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
                detailButton(id: "play", icon: "play.fill", title: "Play") {
                    Task { await resolveStream() }
                }
                .disabled(isResolvingStream)

                detailButton(id: "chooseStream", icon: "list.bullet", title: "Choose Stream") {
                    Task { await showStreamPicker() }
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

    private func resolveStream() async {
        guard !isResolvingStream else { return }
        isResolvingStream = true
        streamError = nil
        defer { isResolvingStream = false }

        do {
            let (urls, quality) = try await appState.streamingService.playableURLsAndQualityForMovie(tmdbId: movieId)
            guard !urls.isEmpty else {
                streamError = "No stream was found"
                return
            }
            if let quality { streamQuality = quality }
            let content = PlayableContent(urls: urls, title: movie?.title ?? "Movie", quality: quality, movieId: movieId)
            playableContent = content
            appState.watchProgressManager.recordMovie(movieId)
        } catch {
            streamError = "No stream was found"
        }
    }

    private func showStreamPicker() async {
        guard !isResolvingStream else { return }
        isResolvingStream = true
        streamError = nil
        defer { isResolvingStream = false }

        do {
            let sources = try await appState.streamingService.sourcesForMovie(tmdbId: movieId)
            let playable = sources.filter { $0.isPlayable }
            guard !playable.isEmpty else {
                streamError = "No stream was found"
                return
            }
            if let q = playable.first?.quality { streamQuality = q }
            await MainActor.run {
                streamPickerSources = playable
                showStreamPicker = true
            }
        } catch {
            streamError = "No stream was found"
        }
    }

    private func playSource(_ source: OMSSSource) async {
        guard let url = await appState.streamingService.playableURL(for: source) else {
            streamError = "Could not load stream"
            return
        }
        if let q = source.quality { streamQuality = q }
        let content = PlayableContent(urls: [url], title: movie?.title ?? "Movie", quality: source.quality, movieId: movieId)
        await MainActor.run {
            playableContent = content
            appState.watchProgressManager.recordMovie(movieId)
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
