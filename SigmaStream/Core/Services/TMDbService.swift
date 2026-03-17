//
//  TMDbService.swift
//  SigmaStream
//
//  Created by Daniel Rafailov on 2026-03-16.
//

import Foundation
import TMDb

/// Service layer for TMDb API. Configure with your API key before use.
/// Get a free API key at https://www.themoviedb.org/documentation/api
actor TMDbService {

    private let client: TMDbClient
    private var movieCache: [Int: Movie] = [:]
    private var tvSeriesCache: [Int: TVSeries] = [:]

    init(apiKey: String) {
        self.client = TMDbClient(apiKey: apiKey)
    }

    /// Fetch popular movies
    func popularMovies(page: Int? = nil) async throws -> [MovieListItem] {
        let response = try await client.discover.movies(
            filter: nil,
            sortedBy: .popularity(descending: true),
            page: page,
            language: nil
        )
        return response.results
    }

    /// Fetch trending movies
    func trendingMovies(inTimeWindow: TrendingTimeWindowFilterType = .day) async throws -> [MovieListItem] {
        let response = try await client.trending.movies(inTimeWindow: inTimeWindow)
        return response.results
    }

    /// Search movies by query
    func searchMovies(query: String, page: Int? = nil) async throws -> [MovieListItem] {
        let response = try await client.search.searchMovies(query: query, filter: nil, page: page, language: nil)
        return response.results
    }

    /// Search TV series by query
    func searchTVSeries(query: String, page: Int? = nil) async throws -> [TVSeriesListItem] {
        let response = try await client.search.searchTVSeries(query: query, filter: nil, page: page, language: nil)
        return response.results
    }

    /// Get movie details (cached)
    func movieDetails(forMovieId movieId: Int) async throws -> Movie {
        if let cached = movieCache[movieId] { return cached }
        let movie = try await client.movies.details(forMovie: movieId)
        movieCache[movieId] = movie
        return movie
    }

    /// Get TV series details (cached)
    func tvSeriesDetails(forSeriesId seriesId: Int) async throws -> TVSeries {
        if let cached = tvSeriesCache[seriesId] { return cached }
        let series = try await client.tvSeries.details(forTVSeries: seriesId)
        tvSeriesCache[seriesId] = series
        return series
    }

    /// Get full season details including episodes
    func tvSeasonDetails(seriesId: Int, seasonNumber: Int) async throws -> TVSeason {
        try await client.tvSeasons.details(
            forSeason: seasonNumber,
            inTVSeries: seriesId,
            language: nil
        )
    }

    /// Get API configuration for image URL generation
    func apiConfiguration() async throws -> APIConfiguration {
        try await client.configurations.apiConfiguration()
    }

    /// Discover movies with filters and sort
    func discoverMovies(
        filter: DiscoverMovieFilter? = nil,
        sortedBy: MovieSort? = nil,
        page: Int? = nil
    ) async throws -> [MovieListItem] {
        let response = try await client.discover.movies(
            filter: filter,
            sortedBy: sortedBy ?? .popularity(descending: true),
            page: page,
            language: nil
        )
        return response.results
    }

    /// Discover TV series with filters and sort
    func discoverTVSeries(
        filter: DiscoverTVSeriesFilter? = nil,
        sortedBy: TVSeriesSort? = nil,
        page: Int? = nil
    ) async throws -> [TVSeriesListItem] {
        let response = try await client.discover.tvSeries(
            filter: filter,
            sortedBy: sortedBy ?? .popularity(descending: true),
            page: page,
            language: nil
        )
        return response.results
    }

    /// Fetch top rated movies
    func topRatedMovies(page: Int? = nil) async throws -> [MovieListItem] {
        let response = try await client.movies.topRated(page: page, country: nil, language: nil)
        return response.results
    }

    /// Fetch movie genres
    func movieGenres() async throws -> [Genre] {
        try await client.genres.movieGenres()
    }

    /// Fetch TV series genres
    func tvSeriesGenres() async throws -> [Genre] {
        try await client.genres.tvSeriesGenres()
    }

    /// Fetch trending TV series
    func trendingTVSeries(inTimeWindow: TrendingTimeWindowFilterType = .day) async throws -> [TVSeriesListItem] {
        let response = try await client.trending.tvSeries(inTimeWindow: inTimeWindow)
        return response.results
    }

    /// Fetch popular TV series
    func popularTVSeries(page: Int? = nil) async throws -> [TVSeriesListItem] {
        let response = try await client.tvSeries.popular(page: page, language: nil)
        return response.results
    }

    /// Fetch top rated TV series (via discover with vote average sort)
    func topRatedTVSeries(page: Int? = nil) async throws -> [TVSeriesListItem] {
        let response = try await client.discover.tvSeries(
            filter: nil,
            sortedBy: .voteAverage(descending: true),
            page: page,
            language: nil
        )
        return response.results
    }

    /// Fetch now playing movies (currently in theatres)
    func nowPlayingMovies(page: Int? = nil) async throws -> [MovieListItem] {
        let response = try await client.movies.nowPlaying(page: page, language: nil)
        return response.results
    }

    /// Fetch upcoming movies
    func upcomingMovies(page: Int? = nil) async throws -> [MovieListItem] {
        let response = try await client.movies.upcoming(page: page, language: nil)
        return response.results
    }

    /// Fetch documentary movies (TMDb genre ID 99)
    func documentaryMovies(page: Int? = nil) async throws -> [MovieListItem] {
        let filter = DiscoverMovieFilter(genres: [99])
        return try await discoverMovies(filter: filter, sortedBy: .popularity(descending: true), page: page)
    }

    /// Fetch documentary TV series (TMDb genre ID 99)
    func documentaryTVSeries(page: Int? = nil) async throws -> [TVSeriesListItem] {
        let filter = DiscoverTVSeriesFilter(genres: [99])
        return try await discoverTVSeries(filter: filter, sortedBy: .popularity(descending: true), page: page)
    }

    /// Load movies for a category (used by See All). Returns (items, hasMore) for pagination.
    func moviesPaginated(for category: MovieCategory, page: Int) async throws -> (items: [MovieListItem], hasMore: Bool) {
        switch category {
        case .trendingToday:
            let items = try await trendingMovies()
            return (items, false)
        case .popular:
            let response = try await client.discover.movies(filter: nil, sortedBy: .popularity(descending: true), page: page, language: nil)
            return (response.results, page < (response.totalPages ?? page))
        case .topRated:
            let response = try await client.movies.topRated(page: page, country: nil, language: nil)
            return (response.results, page < (response.totalPages ?? page))
        case .nowPlaying:
            let response = try await client.movies.nowPlaying(page: page, language: nil)
            return (response.results, page < (response.totalPages ?? page))
        case .upcoming:
            let response = try await client.movies.upcoming(page: page, language: nil)
            return (response.results, page < (response.totalPages ?? page))
        case .documentaries:
            let filter = DiscoverMovieFilter(genres: [99])
            let response = try await client.discover.movies(filter: filter, sortedBy: .popularity(descending: true), page: page, language: nil)
            return (response.results, page < (response.totalPages ?? page))
        }
    }

    /// Load TV series for a category (used by See All). Returns (items, hasMore) for pagination.
    func tvSeriesPaginated(for category: TVCategory, page: Int) async throws -> (items: [TVSeriesListItem], hasMore: Bool) {
        switch category {
        case .trendingToday:
            let items = try await trendingTVSeries()
            return (items, false)
        case .popular:
            let response = try await client.tvSeries.popular(page: page, language: nil)
            return (response.results, page < (response.totalPages ?? page))
        case .topRated:
            let response = try await client.discover.tvSeries(filter: nil, sortedBy: .voteAverage(descending: true), page: page, language: nil)
            return (response.results, page < (response.totalPages ?? page))
        case .documentaries:
            let filter = DiscoverTVSeriesFilter(genres: [99])
            let response = try await client.discover.tvSeries(filter: filter, sortedBy: .popularity(descending: true), page: page, language: nil)
            return (response.results, page < (response.totalPages ?? page))
        }
    }
}
