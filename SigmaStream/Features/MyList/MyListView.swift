//
//  MyListView.swift
//
//  Displays user's My List (movies and TV series).
//

import SwiftUI
import TMDb

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

struct MyListView: View {
    @Environment(AppState.self) private var appState
    @State private var listMovies: [MyListMovieItem] = []
    @State private var listSeries: [MyListSeriesItem] = []
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
                        "Couldn't load My List",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                } else if listMovies.isEmpty && listSeries.isEmpty {
                    ContentUnavailableView(
                        "Your List is Empty",
                        systemImage: "plus.circle",
                        description: Text("Long press on a movie or TV show to add it to your list.")
                    )
                } else {
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 48) {
                            if !listMovies.isEmpty {
                                myListMoviesSection
                            }

                            if !listSeries.isEmpty {
                                myListSeriesSection
                            }
                        }
                        .padding(.vertical)
                    }
                }
            }
            .navigationTitle("")
            .navigationDestination(item: $selectedMovie) { selection in
                MovieDetailView(movieId: selection.id)
            }
            .navigationDestination(item: $selectedSeries) { selection in
                TVSeriesDetailView(seriesId: selection.id)
            }
            .task {
                await loadMyList()
            }
            .onAppear {
                Task { await loadMyList() }
            }
        }
    }

    @FocusState private var focusedMovieId: Int?
    @FocusState private var focusedSeriesId: Int?
    @State private var moviesScrollPosition = ScrollPosition(idType: Int.self)
    @State private var seriesScrollPosition = ScrollPosition(idType: Int.self)

    @ViewBuilder
    private var myListMoviesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Movies")
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
                                    Task { await loadMyList() }
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
                                .animation(.easeInOut(duration: 0.2), value: focusedMovieId)
                            }
                        }
                            if isFocused {
                                Color.clear.frame(width: 32)
                            }
                        }
                        .id(movie.id)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal)
            }
            .scrollPosition($moviesScrollPosition, anchor: .leading)
            .onChange(of: focusedMovieId) { _, newId in
                if let id = newId {
                    moviesScrollPosition.scrollTo(id: id, anchor: .leading)
                }
            }
            .focusSection()
        }
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var myListSeriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TV Shows")
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
                                    Task { await loadMyList() }
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
                                .animation(.easeInOut(duration: 0.2), value: focusedSeriesId)
                            }
                        }
                            if isFocused {
                                Color.clear.frame(width: 32)
                            }
                        }
                        .id(series.id)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal)
            }
            .scrollPosition($seriesScrollPosition, anchor: .leading)
            .onChange(of: focusedSeriesId) { _, newId in
                if let id = newId {
                    seriesScrollPosition.scrollTo(id: id, anchor: .leading)
                }
            }
            .focusSection()
        }
        .padding(.bottom, 16)
    }

    private func loadMyList() async {
        isLoading = true
        errorMessage = nil

        do {
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
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

#Preview {
    MyListView()
        .environment(AppState(apiKey: "placeholder"))
}
