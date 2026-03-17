//
//  CategorySection.swift
//  SigmaStream
//
//  Defines category types for Movies and TV Shows with their loaders.
//

import Foundation
import TMDb

/// Represents a category section for movies (e.g. Trending, Popular, Documentaries, Genres).
enum MovieCategory: String, CaseIterable {
    case trendingToday = "Trending Today"
    case popular = "Popular"
    case topRated = "Top Rated"
    case nowPlaying = "Now Playing"
    case upcoming = "Upcoming"
    case documentaries = "Documentaries"
    case action = "Action"
    case comedy = "Comedy"
    case drama = "Drama"
    case horror = "Horror"
    case romance = "Romance"
    case sciFi = "Sci-Fi"
    case thriller = "Thriller"

    /// TMDb genre ID for genre-based categories; nil for non-genre categories.
    var genreId: Genre.ID? {
        switch self {
        case .documentaries: return 99
        case .action: return 28
        case .comedy: return 35
        case .drama: return 18
        case .horror: return 27
        case .romance: return 10749
        case .sciFi: return 878
        case .thriller: return 53
        default: return nil
        }
    }
}

/// Represents a category section for TV series.
enum TVCategory: String, CaseIterable {
    case trendingToday = "Trending Today"
    case popular = "Popular"
    case topRated = "Top Rated"
    case documentaries = "Documentaries"
    case actionAdventure = "Action & Adventure"
    case comedy = "Comedy"
    case drama = "Drama"
    case horror = "Horror"
    case romance = "Romance"
    case sciFiFantasy = "Sci-Fi & Fantasy"
    case thriller = "Thriller"

    /// TMDb genre ID for genre-based categories; nil for non-genre categories.
    var genreId: Genre.ID? {
        switch self {
        case .documentaries: return 99
        case .actionAdventure: return 10759
        case .comedy: return 35
        case .drama: return 18
        case .horror: return 27
        case .romance: return 10749
        case .sciFiFantasy: return 10765
        case .thriller: return 53
        default: return nil
        }
    }
}
