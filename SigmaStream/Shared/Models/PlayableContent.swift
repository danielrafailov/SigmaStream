//
//  PlayableContent.swift
//
//  Identifiable wrapper for presenting video player. Includes content IDs for watch progress tracking.
//

import Foundation

struct PlayableContent: Identifiable {
    let id = UUID()
    let url: URL
    let title: String

    /// For movies: tmdbId. For TV: nil.
    let movieId: Int?
    /// For TV episodes: (seriesId, season, episode). For movies: nil.
    let tvSeriesId: Int?
    let season: Int?
    let episode: Int?

    init(url: URL, title: String, movieId: Int? = nil, tvSeriesId: Int? = nil, season: Int? = nil, episode: Int? = nil) {
        self.url = url
        self.title = title
        self.movieId = movieId
        self.tvSeriesId = tvSeriesId
        self.season = season
        self.episode = episode
    }
}
