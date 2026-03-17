//
//  MediaFilter.swift
//  SigmaStream
//
//  Created by Daniel Rafailov on 2026-03-16.
//

import Foundation
import TMDb

/// Represents filter state for movies or TV series discovery.
struct MediaFilter {

    var genreIDs: [Genre.ID]?
    var sortOption: SortOption
    var primaryReleaseYear: Int?  // Movies only

    enum SortOption: String, CaseIterable {
        case popularity = "Popularity"
        case releaseDate = "Release Date"
        case rating = "Rating"

        var movieSort: MovieSort {
            switch self {
            case .popularity: .popularity(descending: true)
            case .releaseDate: .releaseDate(descending: true)
            case .rating: .voteAverage(descending: true)
            }
        }

        var tvSort: TVSeriesSort {
            switch self {
            case .popularity: .popularity(descending: true)
            case .releaseDate: .firstAirDate(descending: true)
            case .rating: .voteAverage(descending: true)
            }
        }
    }

    static let `default` = MediaFilter(
        genreIDs: nil,
        sortOption: .popularity,
        primaryReleaseYear: nil
    )

    var hasAnyFilter: Bool {
        (genreIDs?.isEmpty == false) || (primaryReleaseYear != nil)
    }

    func toDiscoverMovieFilter() -> DiscoverMovieFilter? {
        var yearFilter: DiscoverMovieFilter.PrimaryReleaseYearFilter?
        if let year = primaryReleaseYear {
            yearFilter = .on(year)
        }
        guard genreIDs != nil || yearFilter != nil else { return nil }
        return DiscoverMovieFilter(
            genres: genreIDs,
            primaryReleaseYear: yearFilter
        )
    }

    func toDiscoverTVSeriesFilter() -> DiscoverTVSeriesFilter? {
        guard let ids = genreIDs, !ids.isEmpty else { return nil }
        return DiscoverTVSeriesFilter(genres: ids)
    }
}
