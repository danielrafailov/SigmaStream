//
//  MyListManager.swift
//
//  Persists user's "My List" (movies and TV series) via UserDefaults.
//

import Foundation
import SwiftUI

/// Manages My List items (movies and TV series). Persisted to UserDefaults.
@Observable
final class MyListManager {
    private let moviesKey = "mylist.movieIds"
    private let seriesKey = "mylist.seriesIds"

    private(set) var movieIds: Set<Int> = []
    private(set) var seriesIds: Set<Int> = []

    init() {
        load()
    }

    func isMovieInList(_ id: Int) -> Bool {
        movieIds.contains(id)
    }

    func isSeriesInList(_ id: Int) -> Bool {
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
