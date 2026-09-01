//
//  MainTabView.swift
//  SigmaStream-iOS
//
//  Created by Daniel Rafailov on 2026-09-01.
//

import SwiftUI

#if os(iOS)
struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            iOSHomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)

            iOSSearchView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .tag(1)

            iOSMyListView()
                .tabItem {
                    Label("My List", systemImage: "bookmark.fill")
                }
                .tag(2)

            iOSSettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(3)
        }
        .tint(.white)
    }
}

#Preview {
    MainTabView()
        .environment(AppState(apiKey: "placeholder"))
}
#endif
