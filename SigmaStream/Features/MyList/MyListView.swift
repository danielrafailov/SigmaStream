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
    let releaseDate: Date?
}

private struct MyListSeriesItem: Identifiable {
    let id: Int
    let name: String
    let posterPath: URL?
    let firstAirDate: Date?
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
                    ScrollView {
                        VStack(alignment: .leading, spacing: 32) {
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
            .navigationTitle("My List")
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

    @ViewBuilder
    private var myListMoviesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Movies")
                .font(.title2)
                .fontWeight(.semibold)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(listMovies) { movie in
                        Button {
                            selectedMovie = MovieSelection(id: movie.id)
                        } label: {
                            MediaCard(
                                posterPath: movie.posterPath,
                                title: movie.title,
                                subtitle: movie.releaseDate.map { Calendar.current.component(.year, from: $0).description },
                                config: appState.apiConfiguration
                            )
                        }
                        .buttonStyle(.plain)
                        .hoverEffect(.lift)
                        .contextMenu {
                            Button("Remove from My List", role: .destructive) {
                                appState.myListManager.toggleMovie(movie.id)
                                Task { await loadMyList() }
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .focusSection()
    }

    @ViewBuilder
    private var myListSeriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TV Shows")
                .font(.title2)
                .fontWeight(.semibold)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(listSeries) { series in
                        Button {
                            selectedSeries = TVSeriesSelection(id: series.id)
                        } label: {
                            MediaCard(
                                posterPath: series.posterPath,
                                title: series.name,
                                subtitle: series.firstAirDate.map { Calendar.current.component(.year, from: $0).description },
                                config: appState.apiConfiguration
                            )
                        }
                        .buttonStyle(.plain)
                        .hoverEffect(.lift)
                        .contextMenu {
                            Button("Remove from My List", role: .destructive) {
                                appState.myListManager.toggleSeries(series.id)
                                Task { await loadMyList() }
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .focusSection()
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
                        releaseDate: movie.releaseDate
                    ))
                }
            }

            for id in seriesIds {
                if let s = try? await appState.tmdbService.tvSeriesDetails(forSeriesId: id) {
                    series.append(MyListSeriesItem(
                        id: s.id,
                        name: s.name,
                        posterPath: s.posterPath,
                        firstAirDate: s.firstAirDate
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
