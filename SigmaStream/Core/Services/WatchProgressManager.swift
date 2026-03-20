//
//  WatchProgressManager.swift
//
//  Tracks recently watched content for Continue Watching. Persisted via UserDefaults.
//

import Foundation
import SwiftUI

/// A movie the user has started watching.
struct WatchedMovie: Identifiable, Codable {
    let movieId: Int
    var lastWatchedAt: Date

    var id: Int { movieId }
}

/// A TV episode the user has started watching.
struct WatchedEpisode: Identifiable, Codable {
    let seriesId: Int
    let season: Int
    let episode: Int
    var lastWatchedAt: Date

    var id: String { "\(seriesId)-\(season)-\(episode)" }
}

/// Manages continue-watching state. Persisted to UserDefaults.
@Observable
final class WatchProgressManager {
    /// Posted when movies or episodes are removed so Continue Watching sections can refresh.
    static let continueWatchingDidChange = Notification.Name("WatchProgressManager.continueWatchingDidChange")

    private let moviesKey = "watchprogress.movies"
    private let episodesKey = "watchprogress.episodes"
    private let maxMovies = 20
    private let maxEpisodes = 30

    private(set) var watchedMovies: [WatchedMovie] = []
    private(set) var watchedEpisodes: [WatchedEpisode] = []

    init() {
        load()
    }

    func recordMovie(_ movieId: Int) {
        watchedMovies.removeAll { $0.movieId == movieId }
        watchedMovies.insert(WatchedMovie(movieId: movieId, lastWatchedAt: Date()), at: 0)
        if watchedMovies.count > maxMovies {
            watchedMovies = Array(watchedMovies.prefix(maxMovies))
        }
        saveMovies()
        NotificationCenter.default.post(name: Self.continueWatchingDidChange, object: nil)
    }

    func removeMovie(_ movieId: Int) {
        watchedMovies.removeAll { $0.movieId == movieId }
        saveMovies()
        NotificationCenter.default.post(name: Self.continueWatchingDidChange, object: nil)
    }

    func recordEpisode(seriesId: Int, season: Int, episode: Int) {
        watchedEpisodes.removeAll { $0.seriesId == seriesId && $0.season == season && $0.episode == episode }
        watchedEpisodes.removeAll { $0.seriesId == seriesId }
        watchedEpisodes.insert(WatchedEpisode(
            seriesId: seriesId,
            season: season,
            episode: episode,
            lastWatchedAt: Date()
        ), at: 0)
        if watchedEpisodes.count > maxEpisodes {
            watchedEpisodes = Array(watchedEpisodes.prefix(maxEpisodes))
        }
        saveEpisodes()
        NotificationCenter.default.post(name: Self.continueWatchingDidChange, object: nil)
    }

    func removeEpisode(seriesId: Int, season: Int, episode: Int) {
        watchedEpisodes.removeAll { $0.seriesId == seriesId && $0.season == season && $0.episode == episode }
        saveEpisodes()
        NotificationCenter.default.post(name: Self.continueWatchingDidChange, object: nil)
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: moviesKey),
           let decoded = try? JSONDecoder().decode([WatchedMovie].self, from: data) {
            watchedMovies = decoded
        }
        if let data = UserDefaults.standard.data(forKey: episodesKey),
           let decoded = try? JSONDecoder().decode([WatchedEpisode].self, from: data) {
            watchedEpisodes = pruneToLatestEpisodePerSeries(decoded)
            if watchedEpisodes.count != decoded.count { saveEpisodes() }
        }
    }

    /// Keep only the most recently watched episode per series; remove older entries.
    private func pruneToLatestEpisodePerSeries(_ episodes: [WatchedEpisode]) -> [WatchedEpisode] {
        var latest: [Int: WatchedEpisode] = [:]
        for ep in episodes.sorted(by: { $0.lastWatchedAt > $1.lastWatchedAt }) {
            if latest[ep.seriesId] == nil { latest[ep.seriesId] = ep }
        }
        return latest.values.sorted { $0.lastWatchedAt > $1.lastWatchedAt }
    }

    private func saveMovies() {
        if let data = try? JSONEncoder().encode(watchedMovies) {
            UserDefaults.standard.set(data, forKey: moviesKey)
        }
    }

    private func saveEpisodes() {
        if let data = try? JSONEncoder().encode(watchedEpisodes) {
            UserDefaults.standard.set(data, forKey: episodesKey)
        }
    }
}
