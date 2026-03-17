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
    private(set) var apiConfiguration: APIConfiguration?

    init(apiKey: String = Secrets.tmdbApiKey) {
        self.tmdbService = TMDbService(apiKey: apiKey)
    }

    func loadConfiguration() async {
        do {
            apiConfiguration = try await tmdbService.apiConfiguration()
        } catch {
            // Configuration will remain nil; views can handle missing config
        }
    }
}
