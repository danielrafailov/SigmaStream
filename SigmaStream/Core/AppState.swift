//
//  AppState.swift
//  SigmaStream
//
//  Created by Daniel Rafailov on 2026-03-16.
//

import SwiftUI
import TMDb

/// Holds app-wide services and cached configuration.
@Observable
final class AppState {
    let tmdbService: TMDbService
    let streamingService: StreamingService
    let myListManager: MyListManager
    let likedManager: LikedManager
    let watchProgressManager: WatchProgressManager
    private(set) var apiConfiguration: APIConfiguration?

    init(apiKey: String = Secrets.tmdbApiKey, streamingBaseURL: String = Secrets.streamingServerBaseURL) {
        self.tmdbService = TMDbService(apiKey: apiKey)
        self.streamingService = StreamingService(baseURL: streamingBaseURL)
        self.myListManager = MyListManager()
        self.likedManager = LikedManager()
        self.watchProgressManager = WatchProgressManager()
    }

    func loadConfiguration() async {
        do {
            apiConfiguration = try await tmdbService.apiConfiguration()
        } catch {
            // Configuration will remain nil; views can handle missing config
        }
    }
}
