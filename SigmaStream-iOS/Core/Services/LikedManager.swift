//
//  LikedManager.swift
//
//  Persists user's "Liked" items (movies and TV series) via UserDefaults.
//  Used when user taps thumbs up on a movie/show in the detail view.
//

import Foundation
import SwiftUI

/// Manages Liked items (movies and TV series). Persisted to UserDefaults.
@Observable
final class LikedManager {
    private let moviesKey = "liked.movieIds"
    private let seriesKey = "liked.seriesIds"

    private(set) var movieIds: Set<Int> = []
    private(set) var seriesIds: Set<Int> = []

    init() {
        load()
    }

    func isMovieLiked(_ id: Int) -> Bool {
        movieIds.contains(id)
    }

    func isSeriesLiked(_ id: Int) -> Bool {
        seriesIds.contains(id)
    }

    func toggleMovie(_ id: Int) {
        if movieIds.contains(id) {
            movieIds.remove(id)
        } else {
            movieIds.insert(id)
        }
        saveMovies()
    }

    func toggleSeries(_ id: Int) {
        if seriesIds.contains(id) {
            seriesIds.remove(id)
        } else {
            seriesIds.insert(id)
        }
        saveSeries()
    }

    func setMovieLiked(_ id: Int, liked: Bool) {
        if liked {
            movieIds.insert(id)
        } else {
            movieIds.remove(id)
        }
        saveMovies()
    }

    func setSeriesLiked(_ id: Int, liked: Bool) {
        if liked {
            seriesIds.insert(id)
        } else {
            seriesIds.remove(id)
        }
        saveSeries()
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: moviesKey),
           let decoded = try? JSONDecoder().decode([Int].self, from: data) {
            movieIds = Set(decoded)
        }
        if let data = UserDefaults.standard.data(forKey: seriesKey),
           let decoded = try? JSONDecoder().decode([Int].self, from: data) {
            seriesIds = Set(decoded)
        }
    }

    private func saveMovies() {
        let array = Array(movieIds)
        if let data = try? JSONEncoder().encode(array) {
            UserDefaults.standard.set(data, forKey: moviesKey)
        }
    }

    private func saveSeries() {
        let array = Array(seriesIds)
        if let data = try? JSONEncoder().encode(array) {
            UserDefaults.standard.set(data, forKey: seriesKey)
        }
    }
}
