//
//  TMDbService.swift
//  SigmaStream
//
//  Created by Daniel Rafailov on 2026-03-16.
//

import Foundation
import TMDb

private struct TMDbErrorResponse: Decodable {
    let statusMessage: String?
    enum CodingKeys: String, CodingKey { case statusMessage = "status_message" }
}

enum TMDbServiceError: Error, LocalizedError {
    case apiError(String)
    var errorDescription: String? { switch self { case .apiError(let m): return m } }
}

/// TMDb paginated list response (discover, popular, trending, etc.)
private struct TMDbPaginatedMovieResponse: Decodable {
    let results: [MovieListItem]
    let page: Int?
    let totalPages: Int?
}

private struct TMDbPaginatedTVResponse: Decodable {
    let results: [TVSeriesListItem]
    let page: Int?
    let totalPages: Int?
}

/// Service layer for TMDb API. Configure with your API key before use.
/// Get a free API key at https://www.themoviedb.org/documentation/api
actor TMDbService {

    private let client: TMDbClient
    private let apiKey: String
    private var movieCache: [Int: Movie] = [:]
    private var tvSeriesCache: [Int: TVSeries] = [:]
    private let diskCache = TMDbCache.shared

    private static var tmdbDecoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        let dateOnlyFormatter = DateFormatter()
        dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
        dateOnlyFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateOnlyFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            guard !dateString.isEmpty else {
                return Date(timeIntervalSince1970: 0)
            }
            if let date = dateOnlyFormatter.date(from: dateString) { return date }
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso.date(from: dateString) { return date }
            iso.formatOptions = [.withInternetDateTime]
            if let date = iso.date(from: dateString) { return date }
            return Date(timeIntervalSince1970: 0)
        }
        return d
    }

    init(apiKey: String) {
        self.apiKey = apiKey
        self.client = TMDbClient(apiKey: apiKey)
    }

    /// Build TMDb URL with api_key
    private func tmdbURL(path: String, queryItems: [String: String] = [:]) -> URL {
        var comps = URLComponents(string: "https://api.themoviedb.org/3" + path)!
        var items = [URLQueryItem(name: "api_key", value: apiKey)]
        items += queryItems.map { URLQueryItem(name: $0.key, value: $0.value) }
        comps.queryItems = items
        return comps.url!
    }

    /// Fetch from cache or network, store raw Data, decode to T. Use for types that are Decodable but not Encodable.
    private func cached<T: Decodable>(_ key: String, url: URL, as type: T.Type) async throws -> T {
        #if DEBUG
        let t0 = CFAbsoluteTimeGetCurrent()
        #endif
        if let data = diskCache.getData(key) {
            do {
                let result = try Self.tmdbDecoder.decode(T.self, from: data)
                #if DEBUG
                let elapsed = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
                print("[TMDbCache] HIT \(key) in \(elapsed)ms")
                #endif
                return result
            } catch {
                diskCache.removeData(key)
            }
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(TMDbErrorResponse.self, from: data))?.statusMessage ?? "Request failed"
            throw TMDbServiceError.apiError(message)
        }
        diskCache.setData(key, data: data)
        let result = try Self.tmdbDecoder.decode(T.self, from: data)
        #if DEBUG
        let elapsed = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
        print("[TMDbCache] MISS \(key) network=\(elapsed)ms")
        #endif
        return result
    }

    /// Fetch movie videos (trailers). Returns first YouTube trailer or nil.
    func movieTrailerYouTubeKey(movieId: Int) async throws -> String? {
        let url = tmdbURL(path: "/movie/\(movieId)/videos")
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(TMDbVideosResponse.self, from: data)
        return (response.results ?? [])
            .first { $0.site.lowercased() == "youtube" && $0.type.lowercased() == "trailer" }?
            .key
    }

    /// Fetch TV series videos (trailers). Returns first YouTube trailer or nil.
    func tvSeriesTrailerYouTubeKey(seriesId: Int) async throws -> String? {
        let url = tmdbURL(path: "/tv/\(seriesId)/videos")
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(TMDbVideosResponse.self, from: data)
        return (response.results ?? [])
            .first { $0.site.lowercased() == "youtube" && $0.type.lowercased() == "trailer" }?
            .key
    }

    /// Fetch popular movies
    func popularMovies(page: Int? = nil) async throws -> [MovieListItem] {
        let p = page ?? 1
        let url = tmdbURL(path: "/discover/movie", queryItems: ["sort_by": "popularity.desc", "page": "\(p)"])
        let response: TMDbPaginatedMovieResponse = try await cached("popular_movies_\(p)", url: url, as: TMDbPaginatedMovieResponse.self)
        return response.results
    }

    /// Fetch trending movies
    func trendingMovies(inTimeWindow: TrendingTimeWindowFilterType = .day) async throws -> [MovieListItem] {
        let window = inTimeWindow == .day ? "day" : "week"
        let url = tmdbURL(path: "/trending/movie/\(window)")
        let response: TMDbPaginatedMovieResponse = try await cached("trending_movies_\(window)", url: url, as: TMDbPaginatedMovieResponse.self)
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
        #if DEBUG
        let t0 = CFAbsoluteTimeGetCurrent()
        #endif
        if let cached = movieCache[movieId] {
            #if DEBUG
            let elapsed = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
            print("[TMDbService] movieDetails HIT id=\(movieId) in \(elapsed)ms")
            #endif
            return cached
        }
        let movie = try await client.movies.details(forMovie: movieId)
        movieCache[movieId] = movie
        #if DEBUG
        let elapsed = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
        print("[TMDbService] movieDetails MISS id=\(movieId) network=\(elapsed)ms")
        #endif
        return movie
    }

    /// Get TV series details (cached)
    func tvSeriesDetails(forSeriesId seriesId: Int) async throws -> TVSeries {
        #if DEBUG
        let t0 = CFAbsoluteTimeGetCurrent()
        #endif
        if let cached = tvSeriesCache[seriesId] {
            #if DEBUG
            let elapsed = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
            print("[TMDbService] tvSeriesDetails HIT id=\(seriesId) in \(elapsed)ms")
            #endif
            return cached
        }
        let series = try await client.tvSeries.details(forTVSeries: seriesId)
        tvSeriesCache[seriesId] = series
        #if DEBUG
        let elapsed = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
        print("[TMDbService] tvSeriesDetails MISS id=\(seriesId) network=\(elapsed)ms")
        #endif
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
        let url = tmdbURL(path: "/configuration")
        return try await cached("api_config", url: url, as: APIConfiguration.self)
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
        let p = page ?? 1
        let url = tmdbURL(path: "/movie/top_rated", queryItems: ["page": "\(p)"])
        let response: TMDbPaginatedMovieResponse = try await cached("top_rated_movies_\(p)", url: url, as: TMDbPaginatedMovieResponse.self)
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
        let window = inTimeWindow == .day ? "day" : "week"
        let url = tmdbURL(path: "/trending/tv/\(window)")
        let response: TMDbPaginatedTVResponse = try await cached("trending_tv_\(window)", url: url, as: TMDbPaginatedTVResponse.self)
        return response.results
    }

    /// Fetch popular TV series
    func popularTVSeries(page: Int? = nil) async throws -> [TVSeriesListItem] {
        let p = page ?? 1
        let url = tmdbURL(path: "/tv/popular", queryItems: ["page": "\(p)"])
        let response: TMDbPaginatedTVResponse = try await cached("popular_tv_\(p)", url: url, as: TMDbPaginatedTVResponse.self)
        return response.results
    }

    /// Fetch top rated TV series (via discover with vote average sort)
    func topRatedTVSeries(page: Int? = nil) async throws -> [TVSeriesListItem] {
        let p = page ?? 1
        let url = tmdbURL(path: "/discover/tv", queryItems: ["sort_by": "vote_average.desc", "page": "\(p)"])
        let response: TMDbPaginatedTVResponse = try await cached("top_rated_tv_\(p)", url: url, as: TMDbPaginatedTVResponse.self)
        return response.results
    }

    /// Fetch now playing movies (currently in theatres)
    func nowPlayingMovies(page: Int? = nil) async throws -> [MovieListItem] {
        let p = page ?? 1
        let url = tmdbURL(path: "/movie/now_playing", queryItems: ["page": "\(p)"])
        let response: TMDbPaginatedMovieResponse = try await cached("now_playing_movies_\(p)", url: url, as: TMDbPaginatedMovieResponse.self)
        return response.results
    }

    /// Fetch upcoming movies
    func upcomingMovies(page: Int? = nil) async throws -> [MovieListItem] {
        let p = page ?? 1
        let url = tmdbURL(path: "/movie/upcoming", queryItems: ["page": "\(p)"])
        let response: TMDbPaginatedMovieResponse = try await cached("upcoming_movies_\(p)", url: url, as: TMDbPaginatedMovieResponse.self)
        return response.results
    }

    /// Fetch documentary movies (TMDb genre ID 99)
    func documentaryMovies(page: Int? = nil) async throws -> [MovieListItem] {
        let p = page ?? 1
        let url = tmdbURL(path: "/discover/movie", queryItems: ["with_genres": "99", "sort_by": "popularity.desc", "page": "\(p)"])
        let response: TMDbPaginatedMovieResponse = try await cached("documentary_movies_\(p)", url: url, as: TMDbPaginatedMovieResponse.self)
        return response.results
    }

    /// Fetch documentary TV series (TMDb genre ID 99)
    func documentaryTVSeries(page: Int? = nil) async throws -> [TVSeriesListItem] {
        let p = page ?? 1
        let url = tmdbURL(path: "/discover/tv", queryItems: ["with_genres": "99", "sort_by": "popularity.desc", "page": "\(p)"])
        let response: TMDbPaginatedTVResponse = try await cached("documentary_tv_\(p)", url: url, as: TMDbPaginatedTVResponse.self)
        return response.results
    }

    /// Fetch movie recommendations (for "Because you watched X").
    func movieRecommendations(forMovieId movieId: Int, page: Int = 1) async throws -> [MovieListItem] {
        let url = tmdbURL(path: "/movie/\(movieId)/recommendations", queryItems: ["page": "\(page)"])
        let response: TMDbPaginatedMovieResponse = try await cached("movie_recommendations_\(movieId)_\(page)", url: url, as: TMDbPaginatedMovieResponse.self)
        return response.results
    }

    /// Fetch TV series recommendations (for "Because you watched X").
    func tvSeriesRecommendations(forSeriesId seriesId: Int, page: Int = 1) async throws -> [TVSeriesListItem] {
        let url = tmdbURL(path: "/tv/\(seriesId)/recommendations", queryItems: ["page": "\(page)"])
        let response: TMDbPaginatedTVResponse = try await cached("tv_recommendations_\(seriesId)_\(page)", url: url, as: TMDbPaginatedTVResponse.self)
        return response.results
    }

    /// Load movies for a category (used by See All). Returns (items, hasMore) for pagination.
    func moviesPaginated(for category: MovieCategory, page: Int) async throws -> (items: [MovieListItem], hasMore: Bool) {
        if let genreId = category.genreId {
            let cacheKey = "movies_genre_\(genreId)_\(page)"
            let url = tmdbURL(path: "/discover/movie", queryItems: ["with_genres": "\(genreId)", "sort_by": "popularity.desc", "page": "\(page)"])
            let response: TMDbPaginatedMovieResponse = try await cached(cacheKey, url: url, as: TMDbPaginatedMovieResponse.self)
            let totalPages = response.totalPages ?? page
            return (response.results, page < totalPages)
        }
        switch category {
        case .trendingToday:
            let items = try await trendingMovies()
            return (items, false)
        case .popular:
            let url = tmdbURL(path: "/discover/movie", queryItems: ["sort_by": "popularity.desc", "page": "\(page)"])
            let response: TMDbPaginatedMovieResponse = try await cached("popular_movies_\(page)", url: url, as: TMDbPaginatedMovieResponse.self)
            return (response.results, page < (response.totalPages ?? page))
        case .topRated:
            let url = tmdbURL(path: "/movie/top_rated", queryItems: ["page": "\(page)"])
            let response: TMDbPaginatedMovieResponse = try await cached("top_rated_movies_\(page)", url: url, as: TMDbPaginatedMovieResponse.self)
            return (response.results, page < (response.totalPages ?? page))
        case .nowPlaying:
            let url = tmdbURL(path: "/movie/now_playing", queryItems: ["page": "\(page)"])
            let response: TMDbPaginatedMovieResponse = try await cached("now_playing_movies_\(page)", url: url, as: TMDbPaginatedMovieResponse.self)
            return (response.results, page < (response.totalPages ?? page))
        case .upcoming:
            let url = tmdbURL(path: "/movie/upcoming", queryItems: ["page": "\(page)"])
            let response: TMDbPaginatedMovieResponse = try await cached("upcoming_movies_\(page)", url: url, as: TMDbPaginatedMovieResponse.self)
            return (response.results, page < (response.totalPages ?? page))
        case .documentaries, .action, .comedy, .drama, .horror, .romance, .sciFi, .thriller:
            fatalError("Genre categories handled above")
        }
    }

    /// Load TV series for a category (used by See All). Returns (items, hasMore) for pagination.
    func tvSeriesPaginated(for category: TVCategory, page: Int) async throws -> (items: [TVSeriesListItem], hasMore: Bool) {
        if let genreId = category.genreId {
            let cacheKey = "tv_genre_\(genreId)_\(page)"
            let url = tmdbURL(path: "/discover/tv", queryItems: ["with_genres": "\(genreId)", "sort_by": "popularity.desc", "page": "\(page)"])
            let response: TMDbPaginatedTVResponse = try await cached(cacheKey, url: url, as: TMDbPaginatedTVResponse.self)
            return (response.results, page < (response.totalPages ?? page))
        }
        switch category {
        case .trendingToday:
            let items = try await trendingTVSeries()
            return (items, false)
        case .popular:
            let url = tmdbURL(path: "/tv/popular", queryItems: ["page": "\(page)"])
            let response: TMDbPaginatedTVResponse = try await cached("popular_tv_\(page)", url: url, as: TMDbPaginatedTVResponse.self)
            return (response.results, page < (response.totalPages ?? page))
        case .topRated:
            let url = tmdbURL(path: "/discover/tv", queryItems: ["sort_by": "vote_average.desc", "page": "\(page)"])
            let response: TMDbPaginatedTVResponse = try await cached("top_rated_tv_\(page)", url: url, as: TMDbPaginatedTVResponse.self)
            return (response.results, page < (response.totalPages ?? page))
        case .documentaries, .actionAdventure, .comedy, .drama, .horror, .romance, .sciFiFantasy, .thriller:
            fatalError("Genre categories handled above")
        }
    }
}
