//
//  ContentView.swift
//  SigmaStream
//
//  Created by Daniel Rafailov on 2026-03-16.
//

import SwiftUI

#if os(tvOS)
struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab = 1
    @State private var homeDataLoaded = false
    @State private var moviesDataLoaded = false
    @State private var tvDataLoaded = false
    @State private var collectionsDataLoaded = false

    var body: some View {
        TabView(selection: $selectedTab) {
            SearchView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .tag(0)

            HomeView(
                shouldLoad: selectedTab == 1 && !homeDataLoaded,
                onLoadComplete: { homeDataLoaded = true }
            )
            .tabItem {
                Label("Home", systemImage: "house.fill")
            }
            .tag(1)

            MoviesView(
                shouldLoad: selectedTab == 2 && !moviesDataLoaded,
                onLoadComplete: { moviesDataLoaded = true }
            )
            .tabItem {
                Label("Movies", systemImage: "film.fill")
            }
            .tag(2)

            TVSeriesView(
                shouldLoad: selectedTab == 3 && !tvDataLoaded,
                onLoadComplete: { tvDataLoaded = true }
            )
            .tabItem {
                Label("TV Shows", systemImage: "tv.fill")
            }
            .tag(3)

            CollectionsView(
                shouldLoad: selectedTab == 4 && !collectionsDataLoaded,
                onLoadComplete: { collectionsDataLoaded = true }
            )
            .tabItem {
                Label("Collections", systemImage: "square.grid.2x2.fill")
            }
            .tag(4)

            VoiceAssistantView()
                .tabItem {
                    Label("AI Assistant", systemImage: "waveform.circle.fill")
                }
                .tag(5)

            MyListView()
                .tabItem {
                    Label("My List", systemImage: "bookmark.fill")
                }
                .tag(6)

            LikedView()
                .tabItem {
                    Label("Liked", systemImage: "heart.fill")
                }
                .tag(7)
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState(apiKey: "placeholder"))
}
#endif
