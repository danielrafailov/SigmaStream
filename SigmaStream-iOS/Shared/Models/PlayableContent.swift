//
//  PlayableContent.swift
//
//  Identifiable wrapper for presenting video player. Includes content IDs for watch progress tracking.
//

import Foundation

struct PlayableContent: Identifiable {
    let id = UUID()
    /// All stream URLs to try in order (best quality first). Non-empty.
    let urls: [URL]
    let title: String
    /// Best available quality from API (e.g. "1080p", "4K"). Nil if unknown.
    let quality: String?
    /// When set, AVPlayer seeks here after the stream is ready.
    let startTime: TimeInterval?

    /// For movies: tmdbId. For TV: nil.
    let movieId: Int?
    /// For TV episodes: (seriesId, season, episode). For movies: nil.
    let tvSeriesId: Int?
    let season: Int?
    let episode: Int?

    init(
        urls: [URL],
        title: String,
        quality: String? = nil,
        startTime: TimeInterval? = nil,
        movieId: Int? = nil,
        tvSeriesId: Int? = nil,
        season: Int? = nil,
        episode: Int? = nil
    ) {
        self.urls = urls
        self.title = title
        self.quality = quality
        self.startTime = startTime
        self.movieId = movieId
        self.tvSeriesId = tvSeriesId
        self.season = season
        self.episode = episode
    }
}
