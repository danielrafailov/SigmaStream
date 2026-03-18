//
//  ContentView.swift
//  SigmaStream
//
//  Created by Daniel Rafailov on 2026-03-16.
//

import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab = 0
    @State private var moviesDataLoaded = false
    @State private var tvDataLoaded = false

    var body: some View {
        TabView(selection: $selectedTab) {
            MoviesView(
                shouldLoad: selectedTab == 0 && !moviesDataLoaded,
                onLoadComplete: { moviesDataLoaded = true }
            )
            .tabItem {
                Label("Movies", systemImage: "film.fill")
            }
            .tag(0)

            TVShowsView(
                shouldLoad: selectedTab == 1 && !tvDataLoaded,
                onLoadComplete: { tvDataLoaded = true }
            )
            .tabItem {
                Label("TV Shows", systemImage: "tv.fill")
            }
            .tag(1)

            SearchView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
            .tag(2)

            MyListView()
                .tabItem {
                    Label("My List", systemImage: "plus.circle.fill")
                }
            .tag(3)
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState(apiKey: "placeholder"))
}
