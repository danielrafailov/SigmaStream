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

            TVShowsView(
                shouldLoad: selectedTab == 3 && !tvDataLoaded,
                onLoadComplete: { tvDataLoaded = true }
            )
            .tabItem {
                Label("Shows", systemImage: "tv.fill")
            }
            .tag(3)

            CollectionsView(
                shouldLoad: selectedTab == 4 && !collectionsDataLoaded,
                onLoadComplete: { collectionsDataLoaded = true }
            )
            .tabItem {
                Label("Collections", systemImage: "square.stack.3d.up.fill")
            }
            .tag(4)

            ForYouView()
                .tabItem {
                    Label("For You", systemImage: "heart.fill")
                }
                .tag(5)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(6)
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
        .environment(AppState(apiKey: "placeholder"))
}
