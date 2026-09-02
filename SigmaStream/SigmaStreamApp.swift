//
//  SigmaStreamApp.swift
//  SigmaStream
//
//  Created by Daniel Rafailov on 2026-03-16.
//

import SwiftUI

@main
struct SigmaStreamApp: App {
    @State private var appState = AppState()
    @State private var showSplash = true

    init() {
        // Increase URLCache for image caching (AsyncImage uses URLSession)
        let memoryCapacity = 50 * 1024 * 1024  // 50 MB
        let diskCapacity = 200 * 1024 * 1024   // 200 MB
        URLCache.shared = URLCache(memoryCapacity: memoryCapacity, diskCapacity: diskCapacity)
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environment(appState)
                    .task {
                        await appState.loadConfiguration()
                    }

                if showSplash {
                    SigmaSplashView {
                        showSplash = false
                    }
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
        }
    }
}
