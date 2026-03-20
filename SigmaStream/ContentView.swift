//
//  ContentView.swift
//  SigmaStream
//
//  Created by Daniel Rafailov on 2026-03-16.
//

import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab = 1
    @State private var homeDataLoaded = false
    @State private var moviesDataLoaded = false
    @State private var tvDataLoaded = false

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

            TVShowsView(
                shouldLoad: selectedTab == 2 && !tvDataLoaded,
                onLoadComplete: { tvDataLoaded = true }
            )
            .tabItem {
                Label("Shows", systemImage: "tv.fill")
            }
            .tag(2)

            MoviesView(
                shouldLoad: selectedTab == 3 && !moviesDataLoaded,
                onLoadComplete: { moviesDataLoaded = true }
            )
            .tabItem {
                Label("Movies", systemImage: "film.fill")
            }
            .tag(3)

            ForYouView()
                .tabItem {
                    Label("For You", systemImage: "heart.fill")
                }
                .tag(4)
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState(apiKey: "placeholder"))
}
