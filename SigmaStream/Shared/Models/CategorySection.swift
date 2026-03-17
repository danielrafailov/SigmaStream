//
//  CategorySection.swift
//  SigmaStream
//
//  Defines category types for Movies and TV Shows with their loaders.
//

import Foundation
import TMDb

/// Represents a category section for movies (e.g. Trending, Popular, Documentaries).
enum MovieCategory: String, CaseIterable {
    case trendingToday = "Trending Today"
    case popular = "Popular"
    case topRated = "Top Rated"
    case nowPlaying = "Now Playing"
    case upcoming = "Upcoming"
    case documentaries = "Documentaries"
}

/// Represents a category section for TV series.
enum TVCategory: String, CaseIterable {
    case trendingToday = "Trending Today"
    case popular = "Popular"
    case topRated = "Top Rated"
    case documentaries = "Documentaries"
}
