//
//  ContentView.swift
//  SigmaStream
//
//  Created by Daniel Rafailov on 2026-03-16.
//

import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            MoviesView()
                .tabItem {
                    Label("Movies", systemImage: "film.fill")
                }
            TVShowsView()
                .tabItem {
                    Label("TV Shows", systemImage: "tv.fill")
                }
            SearchView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState(apiKey: "placeholder"))
}
