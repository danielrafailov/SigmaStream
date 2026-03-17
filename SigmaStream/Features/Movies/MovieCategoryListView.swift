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

    private func formatYear(_ date: Date) -> String {
        Calendar.current.component(.year, from: date).description
    }

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
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 220, maximum: 260), spacing: 24)
                    ], spacing: 24) {
                        ForEach(Array(movies.enumerated()), id: \.element.id) { index, movie in
                            Button {
                                selectedMovie = MovieSelection(id: movie.id)
                            } label: {
                                MediaCard(
                                    posterPath: movie.posterPath,
                                    title: movie.title,
                                    subtitle: movie.releaseDate.map { formatYear($0) },
                                    config: appState.apiConfiguration
                                )
                            }
                            .buttonStyle(.plain)
                            .hoverEffect(.lift)
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
                    .padding()
                }
            }
        }
        .navigationTitle(category.rawValue)
        .navigationDestination(item: $selectedMovie) { selection in
            MovieDetailView(movieId: selection.id)
        }
        .task {
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
            movies = result.items
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
            movies.append(contentsOf: result.items)
            hasMore = result.hasMore
            currentPage = nextPage
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingMore = false
    }
}

