//
//  ForYouView.swift
//  SigmaStream
//
//  Personalized content: My List, Continue Watching (movies + TV).
//

import SwiftUI
import TMDb

private struct ContinueWatchingMovieItem: Identifiable {
    let id: Int
    let title: String
    let posterPath: URL?
    let backdropPath: URL?
    let releaseDate: Date?
    let overview: String?
}

private struct ContinueWatchingEpisodeItem: Identifiable {
    let seriesId: Int
    let season: Int
    let episode: Int
    let seriesName: String
    let posterPath: URL?
    let backdropPath: URL?
    let firstAirDate: Date?
    let overview: String?
    var id: String { "\(seriesId)-\(season)-\(episode)" }
}

private struct MyListMovieItem: Identifiable {
    let id: Int
    let title: String
    let posterPath: URL?
    let backdropPath: URL?
    let releaseDate: Date?
    let overview: String?
}

private struct MyListSeriesItem: Identifiable {
    let id: Int
    let name: String
    let posterPath: URL?
    let backdropPath: URL?
    let firstAirDate: Date?
    let overview: String?
}

struct ForYouView: View {
    @Environment(AppState.self) private var appState
    @State private var continueWatchingMovies: [ContinueWatchingMovieItem] = []
    @State private var continueWatchingTV: [ContinueWatchingEpisodeItem] = []
    @State private var listMovies: [MyListMovieItem] = []
    @State private var listSeries: [MyListSeriesItem] = []
    @State private var likedMovies: [MyListMovieItem] = []
    @State private var likedSeries: [MyListSeriesItem] = []
    @State private var becauseYouWatchedTitle: String?
    @State private var becauseYouWatchedMovies: [MovieListItem] = []
    @State private var becauseYouWatchedSeries: [TVSeriesListItem] = []
    @State private var becauseYouWatchedIsMovie = false
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedMovie: MovieSelection?
    @State private var selectedSeries: TVSeriesSelection?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    ContentUnavailableView(
                        "Couldn't load",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                } else if continueWatchingMovies.isEmpty && continueWatchingTV.isEmpty && listMovies.isEmpty && listSeries.isEmpty && likedMovies.isEmpty && likedSeries.isEmpty {
                    ContentUnavailableView(
                        "Nothing Yet",
                        systemImage: "heart",
                        description: Text("Add movies and TV shows to your list, or start watching something.")
                    )
                } else {
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 48) {
                            if becauseYouWatchedTitle != nil && (!becauseYouWatchedMovies.isEmpty || !becauseYouWatchedSeries.isEmpty) {
                                becauseYouWatchedSection
                            }
                            if !listMovies.isEmpty {
                                myListMoviesSection
                            }
                            if !listSeries.isEmpty {
                                myListSeriesSection
                            }
                            if !continueWatchingMovies.isEmpty {
                                continueWatchingMoviesSection
                            }
                            if !continueWatchingTV.isEmpty {
                                continueWatchingTVSection
                            }
                            if !likedMovies.isEmpty || !likedSeries.isEmpty {
                                likedSection
                            }
                        }
                        .scrollTargetLayout()
                        .padding(.vertical)
                    }
                }
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("")
            .navigationDestination(item: $selectedMovie) { selection in
                MovieDetailView(movieId: selection.id)
            }
            .navigationDestination(item: $selectedSeries) { selection in
                TVSeriesDetailView(seriesId: selection.id)
            }
            .task {
                await loadAll()
            }
            .onAppear {
                Task { await loadAll() }
            }
            .onReceive(NotificationCenter.default.publisher(for: WatchProgressManager.continueWatchingDidChange)) { _ in
                Task { await loadAll() }
            }
            .onChange(of: appState.likedManager.movieIds.count) { _, _ in
                Task { await loadAll() }
            }
            .onChange(of: appState.likedManager.seriesIds.count) { _, _ in
                Task { await loadAll() }
            }
        }
    }

    @FocusState private var continueWatchingMovieFocusedId: Int?
    @FocusState private var continueWatchingTVFocusedId: String?
    @FocusState private var focusedMovieId: Int?
    @FocusState private var focusedSeriesId: Int?
    @FocusState private var likedMovieFocusedId: Int?
    @FocusState private var likedSeriesFocusedId: Int?
    @State private var continueWatchingMovieScrollPosition = ScrollPosition(idType: Int.self)
    @State private var continueWatchingTVScrollPosition = ScrollPosition(idType: String.self)
    @State private var moviesScrollPosition = ScrollPosition(idType: Int.self)
    @State private var seriesScrollPosition = ScrollPosition(idType: Int.self)
    @State private var likedMoviesScrollPosition = ScrollPosition(idType: Int.self)
    @State private var likedSeriesScrollPosition = ScrollPosition(idType: Int.self)

    @ViewBuilder
    private var myListMoviesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("My List")
                .font(.title2)
                .fontWeight(.semibold)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 20) {
                    ForEach(listMovies) { movie in
                        let isFocused = focusedMovieId == movie.id
                        HStack(spacing: 0) {
                            VStack(alignment: .leading, spacing: 8) {
                                Button {
                                    selectedMovie = MovieSelection(id: movie.id)
                                } label: {
                                    MediaCard(
                                        posterPath: movie.posterPath,
                                        backdropPath: movie.backdropPath,
                                        config: appState.apiConfiguration,
                                        isFocused: isFocused
                                    )
                                }
                                .buttonStyle(.plain)
                                .hoverEffectDisabled(true)
                                .focused($focusedMovieId, equals: movie.id)
                                .accessibilityLabel(movie.title)
                                .contextMenu {
                                    Button("Remove from My List", role: .destructive) {
                                        appState.myListManager.toggleMovie(movie.id)
                                        Task { await loadAll() }
                                    }
                                }
                                if isFocused {
                                    MediaCardMetadata(
                                        title: movie.title,
                                        date: movie.releaseDate,
                                        overview: movie.overview
                                    )
                                    .frame(maxWidth: mediaCardBackdropWidth)
                                    .transition(.opacity)
                                    .animation(.easeInOut(duration: 0.2), value: isFocused)
                                }
                            }
                            if isFocused { Color.clear.frame(width: 32) }
                        }
                        .id(movie.id)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal)
            }
            .scrollPosition($moviesScrollPosition, anchor: .leading)
            .onChange(of: focusedMovieId) { _, id in if let id { moviesScrollPosition.scrollTo(id: id, anchor: .leading) } }
            .focusSection()
        }
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var myListSeriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("My List (TV)")
                .font(.title2)
                .fontWeight(.semibold)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 20) {
                    ForEach(listSeries) { series in
                        let isFocused = focusedSeriesId == series.id
                        HStack(spacing: 0) {
                            VStack(alignment: .leading, spacing: 8) {
                                Button {
                                    selectedSeries = TVSeriesSelection(id: series.id)
                                } label: {
                                    MediaCard(
                                        posterPath: series.posterPath,
                                        backdropPath: series.backdropPath,
                                        config: appState.apiConfiguration,
                                        isFocused: isFocused
                                    )
                                }
                                .buttonStyle(.plain)
                                .hoverEffectDisabled(true)
                                .focused($focusedSeriesId, equals: series.id)
                                .accessibilityLabel(series.name)
                                .contextMenu {
                                    Button("Remove from My List", role: .destructive) {
                                        appState.myListManager.toggleSeries(series.id)
                                        Task { await loadAll() }
                                    }
                                }
                                if isFocused {
                                    MediaCardMetadata(
                                        title: series.name,
                                        date: series.firstAirDate,
                                        overview: series.overview
                                    )
                                    .frame(maxWidth: mediaCardBackdropWidth)
                                    .transition(.opacity)
                                    .animation(.easeInOut(duration: 0.2), value: isFocused)
                                }
                            }
                            if isFocused { Color.clear.frame(width: 32) }
                        }
                        .id(series.id)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal)
            }
            .scrollPosition($seriesScrollPosition, anchor: .leading)
            .onChange(of: focusedSeriesId) { _, id in if let id { seriesScrollPosition.scrollTo(id: id, anchor: .leading) } }
            .focusSection()
        }
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var continueWatchingMoviesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Continue Watching")
                .font(.title2)
                .fontWeight(.semibold)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 20) {
                    ForEach(continueWatchingMovies) { movie in
                        let isFocused = continueWatchingMovieFocusedId == movie.id
                        HStack(spacing: 0) {
                            VStack(alignment: .leading, spacing: 8) {
                                Button {
                                    selectedMovie = MovieSelection(id: movie.id)
                                } label: {
                                    MediaCard(
                                        posterPath: movie.posterPath,
                                        backdropPath: movie.backdropPath,
                                        config: appState.apiConfiguration,
                                        isFocused: isFocused
                                    )
                                }
                                .buttonStyle(.plain)
                                .hoverEffectDisabled(true)
                                .focused($continueWatchingMovieFocusedId, equals: movie.id)
                                .accessibilityLabel(movie.title)
                                .contextMenu {
                                    Button("Remove from Continue Watching", role: .destructive) {
                                        appState.watchProgressManager.removeMovie(movie.id)
                                        Task { await loadAll() }
                                    }
                                }
                                if isFocused {
                                    MediaCardMetadata(
                                        title: movie.title,
                                        date: movie.releaseDate,
                                        overview: movie.overview
                                    )
                                    .frame(maxWidth: mediaCardBackdropWidth)
                                    .transition(.opacity)
                                    .animation(.easeInOut(duration: 0.2), value: isFocused)
                                }
                            }
                            if isFocused { Color.clear.frame(width: 32) }
                        }
                        .id(movie.id)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal)
            }
            .scrollPosition($continueWatchingMovieScrollPosition, anchor: .leading)
            .onChange(of: continueWatchingMovieFocusedId) { _, id in if let id { continueWatchingMovieScrollPosition.scrollTo(id: id, anchor: .leading) } }
            .focusSection()
        }
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var continueWatchingTVSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Continue Watching (TV)")
                .font(.title2)
                .fontWeight(.semibold)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 20) {
                    ForEach(continueWatchingTV) { item in
                        let isFocused = continueWatchingTVFocusedId == item.id
                        HStack(spacing: 0) {
                            VStack(alignment: .leading, spacing: 8) {
                                Button {
                                    selectedSeries = TVSeriesSelection(id: item.seriesId)
                                } label: {
                                    MediaCard(
                                        posterPath: item.posterPath,
                                        backdropPath: item.backdropPath,
                                        config: appState.apiConfiguration,
                                        isFocused: isFocused
                                    )
                                }
                                .buttonStyle(.plain)
                                .hoverEffectDisabled(true)
                                .focused($continueWatchingTVFocusedId, equals: item.id)
                                .accessibilityLabel("\(item.seriesName) S\(item.season)E\(item.episode)")
                                .contextMenu {
                                    Button("Remove from Continue Watching", role: .destructive) {
                                        appState.watchProgressManager.removeEpisode(seriesId: item.seriesId, season: item.season, episode: item.episode)
                                        Task { await loadAll() }
                                    }
                                }
                                if isFocused {
                                    MediaCardMetadata(
                                        title: item.seriesName,
                                        date: item.firstAirDate,
                                        overview: item.overview
                                    )
                                    .frame(maxWidth: mediaCardBackdropWidth)
                                    .transition(.opacity)
                                    .animation(.easeInOut(duration: 0.2), value: isFocused)
                                }
                            }
                            if isFocused { Color.clear.frame(width: 32) }
                        }
                        .id(item.id)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal)
            }
            .scrollPosition($continueWatchingTVScrollPosition, anchor: .leading)
            .onChange(of: continueWatchingTVFocusedId) { _, id in if let id { continueWatchingTVScrollPosition.scrollTo(id: id, anchor: .leading) } }
            .focusSection()
        }
        .padding(.bottom, 16)
    }

    private func loadAll() async {
        isLoading = true
        errorMessage = nil

        await loadContinueWatchingMovies()
        await loadContinueWatchingTV()
        await loadBecauseYouWatched()
        await loadMyList()
        await loadLiked()

        isLoading = false
    }

    private func loadContinueWatchingMovies() async {
        let ids = appState.watchProgressManager.watchedMovies
            .filter { appState.watchProgressManager.canResumeMovie($0.movieId) }
            .map(\.movieId)
        var items: [ContinueWatchingMovieItem] = []
        for id in ids {
            if let movie = try? await appState.tmdbService.movieDetails(forMovieId: id) {
                items.append(ContinueWatchingMovieItem(
                    id: movie.id,
                    title: movie.title,
                    posterPath: movie.posterPath,
                    backdropPath: movie.backdropPath,
                    releaseDate: movie.releaseDate,
                    overview: movie.overview
                ))
            }
        }
        continueWatchingMovies = items
    }

    private func loadContinueWatchingTV() async {
        let episodes = appState.watchProgressManager.watchedEpisodes.filter {
            appState.watchProgressManager.canResumeEpisode(seriesId: $0.seriesId, season: $0.season, episode: $0.episode)
        }
        var items: [ContinueWatchingEpisodeItem] = []
        for ep in episodes {
            if let series = try? await appState.tmdbService.tvSeriesDetails(forSeriesId: ep.seriesId) {
                items.append(ContinueWatchingEpisodeItem(
                    seriesId: ep.seriesId,
                    season: ep.season,
                    episode: ep.episode,
                    seriesName: series.name,
                    posterPath: series.posterPath,
                    backdropPath: series.backdropPath,
                    firstAirDate: series.firstAirDate,
                    overview: series.overview
                ))
            }
        }
        continueWatchingTV = items
    }

    private func loadBecauseYouWatched() async {
        becauseYouWatchedTitle = nil
        becauseYouWatchedMovies = []
        becauseYouWatchedSeries = []

        let lastMovie = appState.watchProgressManager.watchedMovies.first {
            appState.watchProgressManager.canResumeMovie($0.movieId)
        }
        let lastEpisode = appState.watchProgressManager.watchedEpisodes.first {
            appState.watchProgressManager.canResumeEpisode(seriesId: $0.seriesId, season: $0.season, episode: $0.episode)
        }

        var sourceId = 0
        var sourceTitle: String?
        var isMovie = false

        if let movie = lastMovie, let episode = lastEpisode {
            if movie.lastWatchedAt >= episode.lastWatchedAt {
                if let details = try? await appState.tmdbService.movieDetails(forMovieId: movie.movieId) {
                    sourceId = movie.movieId
                    sourceTitle = details.title
                    isMovie = true
                } else { return }
            } else {
                if let details = try? await appState.tmdbService.tvSeriesDetails(forSeriesId: episode.seriesId) {
                    sourceId = episode.seriesId
                    sourceTitle = details.name
                    isMovie = false
                } else { return }
            }
        } else if let movie = lastMovie,
                  let details = try? await appState.tmdbService.movieDetails(forMovieId: movie.movieId) {
            sourceId = movie.movieId
            sourceTitle = details.title
            isMovie = true
        } else if let episode = lastEpisode,
                  let details = try? await appState.tmdbService.tvSeriesDetails(forSeriesId: episode.seriesId) {
            sourceId = episode.seriesId
            sourceTitle = details.name
            isMovie = false
        } else {
            return
        }

        guard let title = sourceTitle, !title.isEmpty else { return }

        do {
            if isMovie {
                let items = try await appState.tmdbService.movieRecommendations(forMovieId: sourceId)
                await MainActor.run {
                    becauseYouWatchedTitle = title
                    becauseYouWatchedMovies = Array(items.prefix(12))
                    becauseYouWatchedIsMovie = true
                }
            } else {
                let items = try await appState.tmdbService.tvSeriesRecommendations(forSeriesId: sourceId)
                await MainActor.run {
                    becauseYouWatchedTitle = title
                    becauseYouWatchedSeries = Array(items.prefix(12))
                    becauseYouWatchedIsMovie = false
                }
            }
        } catch {
            // Silently skip if recommendations fail
        }
    }

    @ViewBuilder
    private var becauseYouWatchedSection: some View {
        Group {
            if let title = becauseYouWatchedTitle {
                if becauseYouWatchedIsMovie && !becauseYouWatchedMovies.isEmpty {
                    MovieMediaRow(
                        title: "Because you watched \(title)",
                        movies: becauseYouWatchedMovies,
                        config: appState.apiConfiguration,
                        onSelect: { movie in selectedMovie = MovieSelection(id: movie.id) }
                    )
                } else if !becauseYouWatchedIsMovie && !becauseYouWatchedSeries.isEmpty {
                    TVSeriesMediaRow(
                        title: "Because you watched \(title)",
                        tvSeries: becauseYouWatchedSeries,
                        config: appState.apiConfiguration,
                        onSelect: { series in selectedSeries = TVSeriesSelection(id: series.id) }
                    )
                }
            }
        }
        .padding(.bottom, 16)
    }

    private func loadMyList() async {
        let movieIds = Array(appState.myListManager.movieIds)
        let seriesIds = Array(appState.myListManager.seriesIds)

        var movies: [MyListMovieItem] = []
        var series: [MyListSeriesItem] = []

        for id in movieIds {
            if let movie = try? await appState.tmdbService.movieDetails(forMovieId: id) {
                movies.append(MyListMovieItem(
                    id: movie.id,
                    title: movie.title,
                    posterPath: movie.posterPath,
                    backdropPath: movie.backdropPath,
                    releaseDate: movie.releaseDate,
                    overview: movie.overview
                ))
            }
        }

        for id in seriesIds {
            if let s = try? await appState.tmdbService.tvSeriesDetails(forSeriesId: id) {
                series.append(MyListSeriesItem(
                    id: s.id,
                    name: s.name,
                    posterPath: s.posterPath,
                    backdropPath: s.backdropPath,
                    firstAirDate: s.firstAirDate,
                    overview: s.overview
                ))
            }
        }

        listMovies = movies
        listSeries = series
    }

    private func loadLiked() async {
        let movieIds = Array(appState.likedManager.movieIds)
        let seriesIds = Array(appState.likedManager.seriesIds)

        var movies: [MyListMovieItem] = []
        var series: [MyListSeriesItem] = []

        for id in movieIds {
            if let movie = try? await appState.tmdbService.movieDetails(forMovieId: id) {
                movies.append(MyListMovieItem(
                    id: movie.id,
                    title: movie.title,
                    posterPath: movie.posterPath,
                    backdropPath: movie.backdropPath,
                    releaseDate: movie.releaseDate,
                    overview: movie.overview
                ))
            }
        }

        for id in seriesIds {
            if let s = try? await appState.tmdbService.tvSeriesDetails(forSeriesId: id) {
                series.append(MyListSeriesItem(
                    id: s.id,
                    name: s.name,
                    posterPath: s.posterPath,
                    backdropPath: s.backdropPath,
                    firstAirDate: s.firstAirDate,
                    overview: s.overview
                ))
            }
        }

        likedMovies = movies
        likedSeries = series
    }

    @ViewBuilder
    private var likedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Movies and TV Shows You Liked")
                .font(.title2)
                .fontWeight(.semibold)

            if !likedMovies.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 20) {
                        ForEach(likedMovies) { movie in
                            let isFocused = likedMovieFocusedId == movie.id
                            HStack(spacing: 0) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Button {
                                        selectedMovie = MovieSelection(id: movie.id)
                                    } label: {
                                        MediaCard(
                                            posterPath: movie.posterPath,
                                            backdropPath: movie.backdropPath,
                                            config: appState.apiConfiguration,
                                            isFocused: isFocused
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .hoverEffectDisabled(true)
                                    .focused($likedMovieFocusedId, equals: movie.id)
                                    .accessibilityLabel(movie.title)
                                    .contextMenu {
                                        Button("Remove from Liked", role: .destructive) {
                                            appState.likedManager.toggleMovie(movie.id)
                                            Task { await loadAll() }
                                        }
                                    }
                                    if isFocused {
                                        MediaCardMetadata(
                                            title: movie.title,
                                            date: movie.releaseDate,
                                            overview: movie.overview
                                        )
                                        .frame(maxWidth: mediaCardBackdropWidth, minHeight: 120, alignment: .topLeading)
                                        .transition(.opacity)
                                        .animation(.easeInOut(duration: 0.2), value: isFocused)
                                    }
                                }
                                if isFocused { Color.clear.frame(width: 32) }
                            }
                            .id(movie.id)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal)
                }
                .scrollPosition($likedMoviesScrollPosition, anchor: .leading)
                .onChange(of: likedMovieFocusedId) { _, id in if let id { likedMoviesScrollPosition.scrollTo(id: id, anchor: .leading) } }
                .focusSection()
            }

            if !likedSeries.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 20) {
                        ForEach(likedSeries) { series in
                            let isFocused = likedSeriesFocusedId == series.id
                            HStack(spacing: 0) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Button {
                                        selectedSeries = TVSeriesSelection(id: series.id)
                                    } label: {
                                        MediaCard(
                                            posterPath: series.posterPath,
                                            backdropPath: series.backdropPath,
                                            config: appState.apiConfiguration,
                                            isFocused: isFocused
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .hoverEffectDisabled(true)
                                    .focused($likedSeriesFocusedId, equals: series.id)
                                    .accessibilityLabel(series.name)
                                    .contextMenu {
                                        Button("Remove from Liked", role: .destructive) {
                                            appState.likedManager.toggleSeries(series.id)
                                            Task { await loadAll() }
                                        }
                                    }
                                    if isFocused {
                                        MediaCardMetadata(
                                            title: series.name,
                                            date: series.firstAirDate,
                                            overview: series.overview
                                        )
                                        .frame(maxWidth: mediaCardBackdropWidth, minHeight: 120, alignment: .topLeading)
                                        .transition(.opacity)
                                        .animation(.easeInOut(duration: 0.2), value: isFocused)
                                    }
                                }
                                if isFocused { Color.clear.frame(width: 32) }
                            }
                            .id(series.id)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal)
                }
                .scrollPosition($likedSeriesScrollPosition, anchor: .leading)
                .onChange(of: likedSeriesFocusedId) { _, id in if let id { likedSeriesScrollPosition.scrollTo(id: id, anchor: .leading) } }
                .focusSection()
            }
        }
        .padding(.bottom, 16)
    }
}

#Preview {
    ForYouView()
        .environment(AppState(apiKey: "placeholder"))
}
