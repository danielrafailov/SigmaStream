//
//  MovieCategoryListView.swift
//  SigmaStream
//
//  Full list view for a movie category (e.g. See All for Popular).
//

import SwiftUI
import TMDb

struct MovieCategoryListView: View {
    let category: MovieCategory
    @Environment(AppState.self) private var appState
    @State private var movies: [MovieListItem] = []
    @State private var currentPage = 1
    @State private var hasMore = true
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var selectedMovie: MovieSelection?
    @State private var hasLoadedOnce = false
    @FocusState private var focusedMovieId: Int?

    private let columns = 5
    private let gridSpacing: CGFloat = mediaPosterSpacing

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                ContentUnavailableView(
                    "Couldn't load \(category.rawValue)",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else {
                GeometryReader { geo in
                    let availableWidth = geo.size.width - 32
                    let posterWidth = (availableWidth - CGFloat(columns - 1) * gridSpacing) / CGFloat(columns)
                    let posterHeight = posterWidth * (3.0 / 2.0)

                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(posterWidth), spacing: gridSpacing), count: columns), spacing: gridSpacing) {
                            ForEach(Array(movies.enumerated()), id: \.element.id) { index, movie in
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
                                .onAppear {
                                    if index >= movies.count - 3 && hasMore && !isLoadingMore {
                                        Task { await loadMore() }
                                    }
                                }
                            }
                            if isLoadingMore {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 24)
                            }
                        }
                        .padding(16)
                    }
                }
            }
        }
        .defaultFocus($focusedMovieId, movies.first?.id)
        .navigationTitle("")
        .navigationDestination(item: $selectedMovie) { selection in
            MovieDetailView(movieId: selection.id)
        }
        .task {
            guard !hasLoadedOnce else { return }
            hasLoadedOnce = true
            await loadInitial()
        }
    }

    private func loadInitial() async {
        isLoading = true
        errorMessage = nil
        currentPage = 1
        hasMore = true
        do {
            let result = try await appState.tmdbService.moviesPaginated(for: category, page: 1)
            var seen = Set<Int>()
            movies = result.items.filter { seen.insert($0.id).inserted }
            hasMore = result.hasMore
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func loadMore() async {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        let nextPage = currentPage + 1
        do {
            let result = try await appState.tmdbService.moviesPaginated(for: category, page: nextPage)
            let newItems = result.items.filter { m in !movies.contains(where: { $0.id == m.id }) }
            movies.append(contentsOf: newItems)
            hasMore = result.hasMore
            currentPage = nextPage
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingMore = false
    }
}
