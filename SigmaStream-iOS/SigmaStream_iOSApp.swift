//
//  SigmaStream_iOSApp.swift
//  SigmaStream-iOS
//
//  Created by Daniel Rafailov on 2026-09-01.
//

import SwiftUI

#if os(iOS)
@main
struct SigmaStream_iOSApp: App {
    @State private var appState = AppState()

    init() {
        // High-capacity image caching for smooth poster scrolling
        let memoryCapacity = 64 * 1024 * 1024  // 64 MB RAM
        let diskCapacity = 256 * 1024 * 1024   // 256 MB Disk
        URLCache.shared = URLCache(memoryCapacity: memoryCapacity, diskCapacity: diskCapacity)
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(appState)
                .preferredColorScheme(.dark)
                .task {
                    await appState.loadConfiguration()
                }
        }
    }
}
#endif
