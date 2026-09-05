//
//  iOSCategoryListView.swift
//  SigmaStream-iOS
//
//  Created by Daniel Rafailov on 2026-09-02.
//

import SwiftUI
import TMDb

#if os(iOS)
// MARK: - iOS Movie Category List View
struct iOSMovieCategoryListView: View {
    let category: MovieCategory
    @Environment(AppState.self) private var appState

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var movies: [MovieListItem] = []
    @State private var currentPage = 1
    @State private var hasMore = true
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var selectedMovieId: Int?

    private var columns: [GridItem] {
        if horizontalSizeClass == .regular {
            [GridItem(.adaptive(minimum: 140, maximum: 185), spacing: 16)]
        } else {
            [
                GridItem(.flexible(), spacing: 14),
                GridItem(.flexible(), spacing: 14),
                GridItem(.flexible(), spacing: 14)
            ]
        }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading \(category.rawValue)...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                ContentUnavailableView(
                    "Couldn't load \(category.rawValue)",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if movies.isEmpty {
                ContentUnavailableView(
                    "No Movies Found",
                    systemImage: "film",
                    description: Text("Check back later for new additions.")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(Array(movies.enumerated()), id: \.element.id) { index, movie in
                            Button {
                                selectedMovieId = movie.id
                            } label: {
                                iOSMediaCard(
                                    id: movie.id,
                                    title: movie.title,
                                    posterPath: ImageURLBuilder.posterURL(for: movie.posterPath, config: appState.apiConfiguration, idealWidth: 342),
                                    rating: movie.voteAverage,
                                    releaseYear: movie.releaseDate.map { String(Calendar.current.component(.year, from: $0)) },
                                    isTVSeries: false,
                                    progress: nil
                                )
                            }
                            .buttonStyle(.plain)
                            .onAppear {
                                if index >= movies.count - 4 && hasMore && !isLoadingMore {
                                    Task { await loadMore() }
                                }
                            }
                        }

                        if isLoadingMore {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .navigationTitle(category.rawValue)
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(isPresented: Binding(
            get: { selectedMovieId != nil },
            set: { if !$0 { selectedMovieId = nil } }
        )) {
            if let movieId = selectedMovieId {
                iOSMovieDetailView(movieId: movieId)
            }
        }
        .task {
            if movies.isEmpty {
                await loadInitial()
            }
        }
        .refreshable {
            await loadInitial()
        }
    }

    private func loadInitial() async {
        isLoading = true
        errorMessage = nil
        currentPage = 1
        do {
            let result = try await appState.tmdbService.moviesPaginated(for: category, page: 1)
            self.movies = result.items
            self.hasMore = result.hasMore
            self.isLoading = false
        } catch {
            self.errorMessage = error.localizedDescription
            self.isLoading = false
        }
    }

    private func loadMore() async {
        guard !isLoadingMore, hasMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        let nextPage = currentPage + 1
        do {
            let result = try await appState.tmdbService.moviesPaginated(for: category, page: nextPage)
            self.movies.append(contentsOf: result.items)
            self.currentPage = nextPage
            self.hasMore = result.hasMore
        } catch {}
    }
}

// MARK: - iOS TV Category List View
struct iOSTVCategoryListView: View {
    let category: TVCategory
    @Environment(AppState.self) private var appState

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var shows: [TVSeriesListItem] = []
    @State private var currentPage = 1
    @State private var hasMore = true
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var selectedSeriesId: Int?

    private var columns: [GridItem] {
        if horizontalSizeClass == .regular {
            [GridItem(.adaptive(minimum: 140, maximum: 185), spacing: 16)]
        } else {
            [
                GridItem(.flexible(), spacing: 14),
                GridItem(.flexible(), spacing: 14),
                GridItem(.flexible(), spacing: 14)
            ]
        }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading \(category.rawValue)...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                ContentUnavailableView(
                    "Couldn't load \(category.rawValue)",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if shows.isEmpty {
                ContentUnavailableView(
                    "No TV Shows Found",
                    systemImage: "tv",
                    description: Text("Check back later for new series.")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(Array(shows.enumerated()), id: \.element.id) { index, show in
                            Button {
                                selectedSeriesId = show.id
                            } label: {
                                iOSMediaCard(
                                    id: show.id,
                                    title: show.name,
                                    posterPath: ImageURLBuilder.posterURL(for: show.posterPath, config: appState.apiConfiguration, idealWidth: 342),
                                    rating: show.voteAverage,
                                    releaseYear: show.firstAirDate.map { String(Calendar.current.component(.year, from: $0)) },
                                    isTVSeries: true,
                                    progress: nil
                                )
                            }
                            .buttonStyle(.plain)
                            .onAppear {
                                if index >= shows.count - 4 && hasMore && !isLoadingMore {
                                    Task { await loadMore() }
                                }
                            }
                        }

                        if isLoadingMore {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .navigationTitle(category.rawValue)
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(isPresented: Binding(
            get: { selectedSeriesId != nil },
            set: { if !$0 { selectedSeriesId = nil } }
        )) {
            if let seriesId = selectedSeriesId {
                iOSTVSeriesDetailView(seriesId: seriesId)
            }
        }
        .task {
            if shows.isEmpty {
                await loadInitial()
            }
        }
        .refreshable {
            await loadInitial()
        }
    }

    private func loadInitial() async {
        isLoading = true
        errorMessage = nil
        currentPage = 1
        do {
            let result = try await appState.tmdbService.tvSeriesPaginated(for: category, page: 1)
            self.shows = result.items
            self.hasMore = result.hasMore
            self.isLoading = false
        } catch {
            self.errorMessage = error.localizedDescription
            self.isLoading = false
        }
    }

    private func loadMore() async {
        guard !isLoadingMore, hasMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        let nextPage = currentPage + 1
        do {
            let result = try await appState.tmdbService.tvSeriesPaginated(for: category, page: nextPage)
            self.shows.append(contentsOf: result.items)
            self.currentPage = nextPage
            self.hasMore = result.hasMore
        } catch {}
    }
}
#endif
