//
//  iOSHomeView.swift
//  SigmaStream-iOS
//
//  Created by Daniel Rafailov on 2026-09-01.
//

import SwiftUI
import TMDb

#if os(iOS)
struct iOSHomeView: View {
    @Environment(AppState.self) private var appState

    @State private var heroItems: [MediaListItem] = []
    @State private var trendingMovies: [iOSMediaRowItem] = []
    @State private var popularTVShows: [iOSMediaRowItem] = []
    @State private var topRatedMovies: [iOSMediaRowItem] = []
    @State private var continueWatchingItems: [iOSMediaRowItem] = []
    @State private var isLoading = true
    @State private var selectedHeroIndex = 0

    // Detail Navigation
    @State private var selectedMovieId: Int?
    @State private var selectedTVSeriesId: Int?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // 1. Hero Carousel
                    if !heroItems.isEmpty {
                        heroCarousel
                    }

                    // 2. Continue Watching Row
                    if !continueWatchingItems.isEmpty {
                        iOSMediaRow(
                            title: "Continue Watching",
                            items: continueWatchingItems
                        ) { item in
                            if item.isTVSeries {
                                selectedTVSeriesId = item.id
                            } else {
                                selectedMovieId = item.id
                            }
                        }
                    }

                    // 3. Trending Movies
                    if !trendingMovies.isEmpty {
                        iOSMediaRow(
                            title: "Trending Movies",
                            items: trendingMovies
                        ) { item in
                            selectedMovieId = item.id
                        }
                    }

                    // 4. Popular TV Shows
                    if !popularTVShows.isEmpty {
                        iOSMediaRow(
                            title: "Popular TV Shows",
                            items: popularTVShows
                        ) { item in
                            selectedTVSeriesId = item.id
                        }
                    }

                    // 5. Top Rated Movies
                    if !topRatedMovies.isEmpty {
                        iOSMediaRow(
                            title: "Top Rated Movies",
                            items: topRatedMovies
                        ) { item in
                            selectedMovieId = item.id
                        }
                    }
                }
                .padding(.bottom, 40)
            }
            .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            .navigationTitle("SigmaStream")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: Binding(
                get: { selectedMovieId != nil },
                set: { if !$0 { selectedMovieId = nil } }
            )) {
                if let movieId = selectedMovieId {
                    iOSMovieDetailView(movieId: movieId)
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { selectedTVSeriesId != nil },
                set: { if !$0 { selectedTVSeriesId = nil } }
            )) {
                if let tvId = selectedTVSeriesId {
                    iOSTVSeriesDetailView(seriesId: tvId)
                }
            }
            .task {
                await loadFeedData()
            }
            .refreshable {
                await loadFeedData()
            }
        }
    }

    // Hero Backdrop Carousel
    private var heroCarousel: some View {
        TabView(selection: $selectedHeroIndex) {
            ForEach(Array(heroItems.enumerated()), id: \.offset) { index, item in
                ZStack(alignment: .bottomLeading) {
                    // Backdrop Image
                    if let posterURL = item.posterURL {
                        AsyncImage(url: posterURL) { phase in
                            if let img = phase.image {
                                img
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } else {
                                Color.white.opacity(0.08)
                            }
                        }
                    }

                    // Gradient Scrim
                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.7), Color.black.opacity(0.95)],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    // Details & Quick Action
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.title)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        HStack(spacing: 12) {
                            if let year = item.releaseYear {
                                Text(year)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            if let rating = item.rating, rating > 0 {
                                HStack(spacing: 3) {
                                    Image(systemName: "star.fill")
                                        .font(.caption)
                                        .foregroundStyle(.yellow)
                                    Text(String(format: "%.1f", rating))
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.white)
                                }
                            }
                        }

                        // Play Button
                        Button {
                            if item.isTVSeries {
                                selectedTVSeriesId = item.id
                            } else {
                                selectedMovieId = item.id
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "play.fill")
                                Text("Watch Now")
                            }
                            .font(.subheadline.bold())
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.white)
                            .foregroundStyle(.black)
                            .clipShape(Capsule())
                        }
                        .padding(.top, 4)
                    }
                    .padding(20)
                }
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .frame(height: 380)
    }

    private func loadFeedData() async {
        isLoading = true
        defer { isLoading = false }

        // 1. Trending Movies
        if let trending = try? await appState.tmdbService.trendingMovies(page: 1) {
            self.trendingMovies = trending.results.map {
                iOSMediaRowItem(
                    id: $0.id,
                    title: $0.title,
                    posterURL: ImageURLBuilder.posterURL(path: $0.posterPath, size: .w342),
                    rating: $0.voteAverage,
                    releaseYear: $0.releaseDate.map { String(Calendar.current.component(.year, from: $0)) },
                    isTVSeries: false,
                    progress: nil
                )
            }

            // Set top 5 trending as Hero Banner items
            self.heroItems = trending.results.prefix(5).map {
                MediaListItem(
                    id: $0.id,
                    title: $0.title,
                    posterURL: ImageURLBuilder.backdropURL(path: $0.backdropPath, size: .w780) ?? ImageURLBuilder.posterURL(path: $0.posterPath, size: .w780),
                    rating: $0.voteAverage,
                    releaseYear: $0.releaseDate.map { String(Calendar.current.component(.year, from: $0)) },
                    isTVSeries: false
                )
            }
        }

        // 2. Popular TV Shows
        if let tv = try? await appState.tmdbService.popularTVSeries(page: 1) {
            self.popularTVShows = tv.results.map {
                iOSMediaRowItem(
                    id: $0.id,
                    title: $0.name,
                    posterURL: ImageURLBuilder.posterURL(path: $0.posterPath, size: .w342),
                    rating: $0.voteAverage,
                    releaseYear: $0.firstAirDate.map { String(Calendar.current.component(.year, from: $0)) },
                    isTVSeries: true,
                    progress: nil
                )
            }
        }

        // 3. Top Rated Movies
        if let top = try? await appState.tmdbService.topRatedMovies(page: 1) {
            self.topRatedMovies = top.results.map {
                iOSMediaRowItem(
                    id: $0.id,
                    title: $0.title,
                    posterURL: ImageURLBuilder.posterURL(path: $0.posterPath, size: .w342),
                    rating: $0.voteAverage,
                    releaseYear: $0.releaseDate.map { String(Calendar.current.component(.year, from: $0)) },
                    isTVSeries: false,
                    progress: nil
                )
            }
        }
    }
}
#endif
