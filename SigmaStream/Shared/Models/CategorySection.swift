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
    case newReleases = "New & Noteworthy"
    case criticallyAcclaimed = "Critically Acclaimed"
    case millennialFavorites = "Millennial Favorites"
    case genZPicks = "Gen Z Picks"
    case genXClassics = "Gen X Classics"
    case nowPlaying = "Now Playing"
    case upcoming = "Upcoming"
    case action = "Action"
    case comedy = "Comedy"
    case drama = "Drama"
    case thriller = "Thriller"
    case sciFi = "Sci-Fi"
    case crime = "Crime"
    case family = "Family"
    case animation = "Animation"
    case documentaries = "Documentaries"
    case horror = "Horror"
    case fantasy = "Fantasy"
    case mystery = "Mystery"
    case history = "History"
    case war = "War"
    case western = "Western"
    case racing = "Racing"
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
        .action, .comedy, .drama, .thriller, .sciFi,
        .crime, .family, .animation, .documentaries, .horror,
        .fantasy, .mystery, .history, .war, .western, .racing, .basedOnBooks
    ]
}

/// Represents a category section for TV series.
enum TVCategory: String, CaseIterable {
    case trendingToday = "Trending"
    case popular = "Popular"
    case newReleases = "New & Noteworthy"
    case criticallyAcclaimed = "Critically Acclaimed"
    case millennialFavorites = "Millennial Favorites"
    case genZPicks = "Gen Z Picks"
    case genXClassics = "Gen X Classics"
    case actionAdventure = "Action & Adventure"
    case comedy = "Comedy"
    case drama = "Drama"
    case thriller = "Thriller"
    case sciFiFantasy = "Sci-Fi & Fantasy"
    case crime = "Crime"
    case family = "Family"
    case animation = "Animation"
    case documentaries = "Documentaries"
    case horror = "Horror"
    case kids = "Kids"
    case mystery = "Mystery"
    case racing = "Racing"
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
        .actionAdventure, .comedy, .drama, .thriller, .sciFiFantasy,
        .crime, .family, .animation, .documentaries, .horror,
        .kids, .mystery, .racing, .basedOnBooks
    ]
}
