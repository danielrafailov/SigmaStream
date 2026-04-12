//
//  CategorySection.swift
//  SigmaStream
//
//  Defines category types for Movies and TV Shows with their loaders.
//

import Foundation
import TMDb

/// Represents a category section for movies (e.g. Trending, Popular, genres, discover filters).
enum MovieCategory: String, CaseIterable {
    case trendingToday = "Trending"
    case popular = "Popular"
    case criticallyAcclaimed = "Critically Acclaimed"
    case newReleases = "New & Noteworthy"
    case nowPlaying = "Now Playing"
    case upcoming = "Upcoming"
    case documentaries = "Documentaries"
    case action = "Action"
    case comedy = "Comedy"
    case drama = "Drama"
    case horror = "Horror"
    case sciFi = "Sci-Fi"
    case thriller = "Thriller"
    case crime = "Crime"
    case animation = "Animation"
    case family = "Family"
    case mystery = "Mystery"
    case fantasy = "Fantasy"
    case war = "War"
    case western = "Western"
    case history = "History"
    case basedOnBooks = "Based on Books"

    /// TMDb genre ID for genre-based categories; nil for discover/trending/list categories.
    var genreId: Genre.ID? {
        switch self {
        case .documentaries: return 99
        case .action: return 28
        case .comedy: return 35
        case .drama: return 18
        case .horror: return 27
        case .sciFi: return 878
        case .thriller: return 53
        case .crime: return 80
        case .animation: return 16
        case .family: return 10751
        case .mystery: return 9648
        case .fantasy: return 14
        case .war: return 10752
        case .western: return 37
        case .history: return 36
        default: return nil
        }
    }

    /// Genre / keyword discover rows (same order on Movies tab and Home).
    static let catalogDiscoverRows: [MovieCategory] = [
        .documentaries, .action, .comedy, .drama, .horror, .sciFi, .thriller,
        .crime, .animation, .family, .mystery, .fantasy, .war, .western, .history, .basedOnBooks
    ]
}

/// Represents a category section for TV series.
enum TVCategory: String, CaseIterable {
    case trendingToday = "Trending"
    case popular = "Popular"
    case criticallyAcclaimed = "Critically Acclaimed"
    case newReleases = "New & Noteworthy"
    case documentaries = "Documentaries"
    case actionAdventure = "Action & Adventure"
    case comedy = "Comedy"
    case drama = "Drama"
    case horror = "Horror"
    case sciFiFantasy = "Sci-Fi & Fantasy"
    case thriller = "Thriller"
    case crime = "Crime"
    case animation = "Animation"
    case family = "Family"
    case kids = "Kids"
    case mystery = "Mystery"
    case basedOnBooks = "Based on Books"

    var genreId: Genre.ID? {
        switch self {
        case .documentaries: return 99
        case .actionAdventure: return 10759
        case .comedy: return 35
        case .drama: return 18
        case .horror: return 27
        case .sciFiFantasy: return 10765
        case .thriller: return 53
        case .crime: return 80
        case .animation: return 16
        case .family: return 10751
        case .kids: return 10762
        case .mystery: return 9648
        default: return nil
        }
    }

    static let catalogDiscoverRows: [TVCategory] = [
        .documentaries, .actionAdventure, .comedy, .drama, .horror, .sciFiFantasy, .thriller,
        .crime, .animation, .family, .kids, .mystery, .basedOnBooks
    ]
}
