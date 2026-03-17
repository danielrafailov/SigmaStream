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

    init(apiKey: String) {
        self.client = TMDbClient(apiKey: apiKey)
    }

    /// Fetch popular movies
    func popularMovies() async throws -> [MovieListItem] {
        let response = try await client.discover.movies(
            sortedBy: .popularity(descending: true)
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

    /// Get movie details
    func movieDetails(forMovieId movieId: Int) async throws -> Movie {
        try await client.movies.details(forMovie: movieId)
    }

    /// Get TV series details
    func tvSeriesDetails(forSeriesId seriesId: Int) async throws -> TVSeries {
        try await client.tvSeries.details(forTVSeries: seriesId)
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
}
