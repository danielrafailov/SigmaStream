//
//  WatchProgressManager.swift
//
//  Tracks recently watched content and playback position for resume. Persisted via UserDefaults.
//

import Foundation
import SwiftUI

/// A movie the user has started watching.
struct WatchedMovie: Identifiable, Codable {
    let movieId: Int
    var lastWatchedAt: Date
    var progressSeconds: Double?
    var durationSeconds: Double?

    var id: Int { movieId }
}

/// A TV episode the user has started watching.
struct WatchedEpisode: Identifiable, Codable {
    let seriesId: Int
    let season: Int
    let episode: Int
    var lastWatchedAt: Date
    var progressSeconds: Double?
    var durationSeconds: Double?

    var id: String { "\(seriesId)-\(season)-\(episode)" }
}

enum WatchProgressPolicy {
    /// Minimum watched time before showing Resume (any brief playback counts).
    static let minResumeSeconds: TimeInterval = 1
    /// Fraction watched that counts as completed (clears resume).
    static let completionFraction: Double = 0.90
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

    // MARK: - Movies

    func canResumeMovie(_ movieId: Int) -> Bool {
        guard let entry = watchedMovies.first(where: { $0.movieId == movieId }),
              let position = entry.progressSeconds,
              position >= WatchProgressPolicy.minResumeSeconds else {
            return false
        }
        if let duration = entry.durationSeconds, duration > 0 {
            return position < duration * WatchProgressPolicy.completionFraction
        }
        return true
    }

    func resumeTimeForMovie(_ movieId: Int) -> TimeInterval? {
        guard canResumeMovie(movieId) else { return nil }
        return watchedMovies.first(where: { $0.movieId == movieId })?.progressSeconds
    }

    func recordMovie(_ movieId: Int) {
        let existingProgress = watchedMovies.first(where: { $0.movieId == movieId })?.progressSeconds
        let existingDuration = watchedMovies.first(where: { $0.movieId == movieId })?.durationSeconds
        watchedMovies.removeAll { $0.movieId == movieId }
        watchedMovies.insert(WatchedMovie(
            movieId: movieId,
            lastWatchedAt: Date(),
            progressSeconds: existingProgress,
            durationSeconds: existingDuration
        ), at: 0)
        trimMovies()
        saveMovies()
        postChange()
    }

    func updateMovieProgress(movieId: Int, position: TimeInterval, duration: TimeInterval) {
        if duration > 0, position >= duration * WatchProgressPolicy.completionFraction {
            removeMovie(movieId)
            return
        }
        if let idx = watchedMovies.firstIndex(where: { $0.movieId == movieId }) {
            watchedMovies[idx].progressSeconds = max(0, position)
            if duration > 0 { watchedMovies[idx].durationSeconds = duration }
            watchedMovies[idx].lastWatchedAt = Date()
            bumpMovieToFront(at: idx)
        } else {
            watchedMovies.insert(WatchedMovie(
                movieId: movieId,
                lastWatchedAt: Date(),
                progressSeconds: max(0, position),
                durationSeconds: duration > 0 ? duration : nil
            ), at: 0)
            trimMovies()
        }
        saveMovies()
        postChange()
    }

    func clearMoviePlaybackPosition(_ movieId: Int) {
        guard let idx = watchedMovies.firstIndex(where: { $0.movieId == movieId }) else { return }
        watchedMovies[idx].progressSeconds = nil
        watchedMovies[idx].durationSeconds = nil
        saveMovies()
    }

    func removeMovie(_ movieId: Int) {
        watchedMovies.removeAll { $0.movieId == movieId }
        saveMovies()
        postChange()
    }

    // MARK: - Episodes

    func canResumeEpisode(seriesId: Int, season: Int, episode: Int) -> Bool {
        guard let entry = watchedEpisodes.first(where: {
            $0.seriesId == seriesId && $0.season == season && $0.episode == episode
        }),
              let position = entry.progressSeconds,
              position >= WatchProgressPolicy.minResumeSeconds else {
            return false
        }
        if let duration = entry.durationSeconds, duration > 0 {
            return position < duration * WatchProgressPolicy.completionFraction
        }
        return true
    }

    func resumeTimeForEpisode(seriesId: Int, season: Int, episode: Int) -> TimeInterval? {
        guard canResumeEpisode(seriesId: seriesId, season: season, episode: episode) else { return nil }
        return watchedEpisodes.first(where: {
            $0.seriesId == seriesId && $0.season == season && $0.episode == episode
        })?.progressSeconds
    }

    func recordEpisode(seriesId: Int, season: Int, episode: Int) {
        let existing = watchedEpisodes.first(where: {
            $0.seriesId == seriesId && $0.season == season && $0.episode == episode
        })
        watchedEpisodes.removeAll { $0.seriesId == seriesId && $0.season == season && $0.episode == episode }
        watchedEpisodes.removeAll { $0.seriesId == seriesId }
        watchedEpisodes.insert(WatchedEpisode(
            seriesId: seriesId,
            season: season,
            episode: episode,
            lastWatchedAt: Date(),
            progressSeconds: existing?.progressSeconds,
            durationSeconds: existing?.durationSeconds
        ), at: 0)
        trimEpisodes()
        saveEpisodes()
        postChange()
    }

    func updateEpisodeProgress(seriesId: Int, season: Int, episode: Int, position: TimeInterval, duration: TimeInterval) {
        if duration > 0, position >= duration * WatchProgressPolicy.completionFraction {
            removeEpisode(seriesId: seriesId, season: season, episode: episode)
            return
        }
        if let idx = watchedEpisodes.firstIndex(where: {
            $0.seriesId == seriesId && $0.season == season && $0.episode == episode
        }) {
            watchedEpisodes[idx].progressSeconds = max(0, position)
            if duration > 0 { watchedEpisodes[idx].durationSeconds = duration }
            watchedEpisodes[idx].lastWatchedAt = Date()
            bumpEpisodeToFront(at: idx)
        } else {
            watchedEpisodes.insert(WatchedEpisode(
                seriesId: seriesId,
                season: season,
                episode: episode,
                lastWatchedAt: Date(),
                progressSeconds: max(0, position),
                durationSeconds: duration > 0 ? duration : nil
            ), at: 0)
            trimEpisodes()
        }
        saveEpisodes()
        postChange()
    }

    func clearEpisodePlaybackPosition(seriesId: Int, season: Int, episode: Int) {
        guard let idx = watchedEpisodes.firstIndex(where: {
            $0.seriesId == seriesId && $0.season == season && $0.episode == episode
        }) else { return }
        watchedEpisodes[idx].progressSeconds = nil
        watchedEpisodes[idx].durationSeconds = nil
        saveEpisodes()
    }

    func removeEpisode(seriesId: Int, season: Int, episode: Int) {
        watchedEpisodes.removeAll { $0.seriesId == seriesId && $0.season == season && $0.episode == episode }
        saveEpisodes()
        postChange()
    }

    // MARK: - Persistence

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

    private func pruneToLatestEpisodePerSeries(_ episodes: [WatchedEpisode]) -> [WatchedEpisode] {
        var latest: [Int: WatchedEpisode] = [:]
        for ep in episodes.sorted(by: { $0.lastWatchedAt > $1.lastWatchedAt }) {
            if latest[ep.seriesId] == nil { latest[ep.seriesId] = ep }
        }
        return latest.values.sorted { $0.lastWatchedAt > $1.lastWatchedAt }
    }

    private func bumpMovieToFront(at index: Int) {
        let item = watchedMovies.remove(at: index)
        watchedMovies.insert(item, at: 0)
    }

    private func bumpEpisodeToFront(at index: Int) {
        let item = watchedEpisodes.remove(at: index)
        watchedEpisodes.insert(item, at: 0)
    }

    private func trimMovies() {
        if watchedMovies.count > maxMovies {
            watchedMovies = Array(watchedMovies.prefix(maxMovies))
        }
    }

    private func trimEpisodes() {
        if watchedEpisodes.count > maxEpisodes {
            watchedEpisodes = Array(watchedEpisodes.prefix(maxEpisodes))
        }
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

    private func postChange() {
        NotificationCenter.default.post(name: Self.continueWatchingDidChange, object: nil)
    }
}
