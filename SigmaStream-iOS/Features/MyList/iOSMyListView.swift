//
//  iOSMyListView.swift
//  SigmaStream-iOS
//
//  Created by Daniel Rafailov on 2026-09-01.
//

import SwiftUI
import TMDb

#if os(iOS)
struct iOSMyListView: View {
    @Environment(AppState.self) private var appState

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var selectedTab = 0 // 0: My List, 1: Liked
    @State private var myListItems: [MediaListItem] = []
    @State private var likedItems: [MediaListItem] = []
    @State private var isLoading = false

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
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Category", selection: $selectedTab) {
                    Text("My List (\(appState.myListManager.movieIds.count + appState.myListManager.seriesIds.count))").tag(0)
                    Text("Liked (\(appState.likedManager.movieIds.count + appState.likedManager.seriesIds.count))").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                let currentItems = selectedTab == 0 ? myListItems : likedItems

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if currentItems.isEmpty {
                    ContentUnavailableView(
                        selectedTab == 0 ? "Your List is Empty" : "No Liked Titles",
                        systemImage: selectedTab == 0 ? "bookmark" : "heart",
                        description: Text(selectedTab == 0 ? "Add movies and TV shows to your list to watch later." : "Tap the heart icon on any movie or TV show to save it here.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(currentItems) { item in
                                NavigationLink {
                                    if item.isTVSeries {
                                        iOSTVSeriesDetailView(seriesId: item.id)
                                    } else {
                                        iOSMovieDetailView(movieId: item.id)
                                    }
                                } label: {
                                    iOSMediaCard(
                                        id: item.id,
                                        title: item.title,
                                        posterPath: item.posterURL,
                                        rating: item.rating,
                                        releaseYear: item.releaseYear,
                                        isTVSeries: item.isTVSeries,
                                        progress: nil
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle(selectedTab == 0 ? "My List" : "Liked")
            .task {
                await loadItems()
            }
            .onChange(of: appState.myListManager.movieIds) { _, _ in
                Task { await loadItems() }
            }
            .onChange(of: appState.myListManager.seriesIds) { _, _ in
                Task { await loadItems() }
            }
            .onChange(of: appState.likedManager.movieIds) { _, _ in
                Task { await loadItems() }
            }
            .onChange(of: appState.likedManager.seriesIds) { _, _ in
                Task { await loadItems() }
            }
        }
    }

    private func loadItems() async {
        isLoading = true
        defer { isLoading = false }

        // 1. Load My List
        var myResults: [MediaListItem] = []
        for id in appState.myListManager.movieIds {
            if let m = try? await appState.tmdbService.movieDetails(forMovieId: id) {
                myResults.append(MediaListItem(
                    id: m.id,
                    title: m.title,
                    posterURL: ImageURLBuilder.posterURL(for: m.posterPath, config: appState.apiConfiguration, idealWidth: 342),
                    rating: m.voteAverage,
                    releaseYear: m.releaseDate.map { String(Calendar.current.component(.year, from: $0)) },
                    isTVSeries: false
                ))
            }
        }
        for id in appState.myListManager.seriesIds {
            if let s = try? await appState.tmdbService.tvSeriesDetails(forSeriesId: id) {
                myResults.append(MediaListItem(
                    id: s.id,
                    title: s.name,
                    posterURL: ImageURLBuilder.posterURL(for: s.posterPath, config: appState.apiConfiguration, idealWidth: 342),
                    rating: s.voteAverage,
                    releaseYear: s.firstAirDate.map { String(Calendar.current.component(.year, from: $0)) },
                    isTVSeries: true
                ))
            }
        }
        self.myListItems = myResults

        // 2. Load Liked List
        var likedResults: [MediaListItem] = []
        for id in appState.likedManager.movieIds {
            if let m = try? await appState.tmdbService.movieDetails(forMovieId: id) {
                likedResults.append(MediaListItem(
                    id: m.id,
                    title: m.title,
                    posterURL: ImageURLBuilder.posterURL(for: m.posterPath, config: appState.apiConfiguration, idealWidth: 342),
                    rating: m.voteAverage,
                    releaseYear: m.releaseDate.map { String(Calendar.current.component(.year, from: $0)) },
                    isTVSeries: false
                ))
            }
        }
        for id in appState.likedManager.seriesIds {
            if let s = try? await appState.tmdbService.tvSeriesDetails(forSeriesId: id) {
                likedResults.append(MediaListItem(
                    id: s.id,
                    title: s.name,
                    posterURL: ImageURLBuilder.posterURL(for: s.posterPath, config: appState.apiConfiguration, idealWidth: 342),
                    rating: s.voteAverage,
                    releaseYear: s.firstAirDate.map { String(Calendar.current.component(.year, from: $0)) },
                    isTVSeries: true
                ))
            }
        }
        self.likedItems = likedResults
    }
}
#endif
