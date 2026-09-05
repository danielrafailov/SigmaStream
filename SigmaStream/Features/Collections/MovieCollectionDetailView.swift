//
//  MovieCollectionDetailView.swift
//  SigmaStream
//
//  Movies in a TMDb collection, sorted by release date.
//

import SwiftUI
import TMDb

struct MovieCollectionDetailView: View {
    let collectionId: Int
    let fallbackTitle: String
    @Environment(AppState.self) private var appState
    @State private var detail: MovieCollectionDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedMovie: MovieSelection?
    @FocusState private var focusedMovieId: Int?

    private let columns = 5
    private let gridSpacing: CGFloat = mediaPosterSpacing

    private var displayTitle: String {
        if let name = detail?.name, !name.isEmpty { return name }
        return fallbackTitle
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                collectionErrorView(message: error)
            } else if let detail {
                collectionContentView(detail: detail)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("")
        .navigationDestination(item: $selectedMovie) { selection in
            MovieDetailView(movieId: selection.id)
        }
        .task {
            await loadDetail()
        }
    }

    @ViewBuilder
    private func collectionErrorView(message: String) -> some View {
        ContentUnavailableView(
            "Couldn't load collection",
            systemImage: "exclamationmark.triangle",
            description: Text(message)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func collectionContentView(detail: MovieCollectionDetail) -> some View {
        GeometryReader { geo in
            let availableWidth = geo.size.width - 32
            let posterWidth = (availableWidth - CGFloat(columns - 1) * gridSpacing) / CGFloat(columns)
            let posterHeight = posterWidth * (3.0 / 2.0)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: gridSpacing) {
                    Text(displayTitle)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    LazyVGrid(
                        columns: Array(repeating: GridItem(.fixed(posterWidth), spacing: gridSpacing), count: columns),
                        spacing: gridSpacing
                    ) {
                        ForEach(detail.movies, id: \.id) { movie in
                            let isFocused = focusedMovieId == movie.id
                            Button {
                                selectedMovie = MovieSelection(id: movie.id)
                            } label: {
                                MediaCard(
                                    posterPath: movie.posterPath,
                                    backdropPath: movie.backdropPath,
                                    config: appState.apiConfiguration,
                                    idealWidth: Int(posterWidth),
                                    isFocused: isFocused,
                                    alwaysPoster: true
                                )
                                .frame(width: posterWidth, height: posterHeight)
                            }
                            .buttonStyle(.plain)
                            .hoverEffectDisabled(true)
                            .focused($focusedMovieId, equals: movie.id)
                            .accessibilityLabel(movie.title)
                            .contextMenu {
                                Button(appState.myListManager.isMovieInList(movie.id) ? "Remove from My List" : "Add to My List") {
                                    appState.myListManager.toggleMovie(movie.id)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 24)
            }
        }
    }

    private func loadDetail() async {
        isLoading = true
        errorMessage = nil
        do {
            let catalogEntry = MovieCollectionCategory.allCases
                .flatMap(\.collections)
                .first { $0.id == collectionId }
            detail = try await appState.tmdbService.movieCollectionDetails(
                collectionId: collectionId,
                additionalMovieIds: catalogEntry?.additionalMovieIds ?? [],
                curatedTitle: catalogEntry?.title ?? fallbackTitle
            )
            if detail?.movies.isEmpty == true {
                errorMessage = "This collection has no playable movies."
            }
        } catch {
            if let tmdb = error as? TMDbServiceError {
                errorMessage = tmdb.errorDescription
            } else {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }
}
