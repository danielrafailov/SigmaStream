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

/// Lenient API structs for direct TMDb season fetch (fallback when TMDb package decoding fails)
private struct TMDbSeasonDetailAPI: Decodable {
    let id: Int
    let name: String?
    let seasonNumber: Int?
    let overview: String?
    let airDate: String?
    let posterPath: String?
    let episodes: [TMDbEpisodeAPI]?

    var seasonNum: Int { seasonNumber ?? 0 }
}

private struct TMDbEpisodeAPI: Decodable {
    let id: Int
    let name: String?
    let episodeNumber: Int?
    let seasonNumber: Int?
    let overview: String?
    let airDate: String?
    let productionCode: String?
    let stillPath: String?
    let voteAverage: Double?
    let voteCount: Int?

    var epNum: Int { episodeNumber ?? 0 }
    var seasonNum: Int { seasonNumber ?? 0 }
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
        if let data = diskCache.getData(key) {
            do {
                let result = try Self.tmdbDecoder.decode(T.self, from: data)
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

    /// Max rows returned per media type after merging title + person cast (keeps UI and payloads bounded).
    private static let searchMergedResultsCap = 80

    /// Title search for movies and TV, merged with **cast** credits for the top person match (e.g. actor name queries).
    /// Results are **deduped by id** and ordered by **popularity** (then vote count), not title-search order first.
    func searchMoviesTVIncludingPersonCast(query: String, page: Int? = nil) async throws -> (movies: [MovieListItem], tvSeries: [TVSeriesListItem]) {
        async let titleMovies = searchMovies(query: query, page: page)
        async let titleTV = searchTVSeries(query: query, page: page)

        var fromPersonMovies: [MovieListItem] = []
        var fromPersonTV: [TVSeriesListItem] = []

        do {
            let peopleResponse = try await client.search.searchPeople(query: query, filter: nil, page: page, language: nil)
            guard let topPerson = peopleResponse.results.first else {
                let (m, t) = try await (titleMovies, titleTV)
                return (
                    movies: Self.sortMoviesByPopularity(m).prefix(Self.searchMergedResultsCap).map { $0 },
                    tvSeries: Self.sortTVByPopularity(t).prefix(Self.searchMergedResultsCap).map { $0 }
                )
            }
            let credits = try await client.people.combinedCredits(forPerson: topPerson.id)
            for credit in credits.cast {
                switch credit {
                case .movie(let c):
                    fromPersonMovies.append(Self.movieListItem(from: c))
                case .tvSeries(let c):
                    fromPersonTV.append(Self.tvSeriesListItem(from: c))
                }
            }
        } catch {
            // Person search or credits are optional; title results still matter.
        }

        let (titleMovieList, titleTVList) = try await (titleMovies, titleTV)
        let mergedMovies = Self.mergeMoviesPreferringRicherMetadata(title: titleMovieList, personCast: fromPersonMovies)
        let mergedTV = Self.mergeTVPreferringRicherMetadata(title: titleTVList, personCast: fromPersonTV)

        return (
            movies: Self.sortMoviesByPopularity(mergedMovies).prefix(Self.searchMergedResultsCap).map { $0 },
            tvSeries: Self.sortTVByPopularity(mergedTV).prefix(Self.searchMergedResultsCap).map { $0 }
        )
    }

    private static func moviePopularitySortKey(_ m: MovieListItem) -> (Double, Int) {
        (m.popularity ?? 0, m.voteCount ?? 0)
    }

    private static func tvPopularitySortKey(_ s: TVSeriesListItem) -> (Double, Int) {
        (s.popularity ?? 0, s.voteCount ?? 0)
    }

    private static func sortMoviesByPopularity(_ items: [MovieListItem]) -> [MovieListItem] {
        items.sorted {
            let a = moviePopularitySortKey($0)
            let b = moviePopularitySortKey($1)
            if a.0 != b.0 { return a.0 > b.0 }
            return a.1 > b.1
        }
    }

    private static func sortTVByPopularity(_ items: [TVSeriesListItem]) -> [TVSeriesListItem] {
        items.sorted {
            let a = tvPopularitySortKey($0)
            let b = tvPopularitySortKey($1)
            if a.0 != b.0 { return a.0 > b.0 }
            return a.1 > b.1
        }
    }

    /// One row per id; when title and cast both return the same title, keep the version with higher popularity (then votes).
    private static func mergeMoviesPreferringRicherMetadata(title: [MovieListItem], personCast: [MovieListItem]) -> [MovieListItem] {
        var bestById: [Int: MovieListItem] = [:]
        for m in title + personCast {
            guard let existing = bestById[m.id] else {
                bestById[m.id] = m
                continue
            }
            let newKey = moviePopularitySortKey(m)
            let oldKey = moviePopularitySortKey(existing)
            if newKey > oldKey { bestById[m.id] = m }
        }
        return Array(bestById.values)
    }

    private static func mergeTVPreferringRicherMetadata(title: [TVSeriesListItem], personCast: [TVSeriesListItem]) -> [TVSeriesListItem] {
        var bestById: [Int: TVSeriesListItem] = [:]
        for s in title + personCast {
            guard let existing = bestById[s.id] else {
                bestById[s.id] = s
                continue
            }
            let newKey = tvPopularitySortKey(s)
            let oldKey = tvPopularitySortKey(existing)
            if newKey > oldKey { bestById[s.id] = s }
        }
        return Array(bestById.values)
    }

    private static func movieListItem(from credit: MovieCastCredit) -> MovieListItem {
        MovieListItem(
            id: credit.id,
            title: credit.title,
            originalTitle: credit.originalTitle,
            originalLanguage: credit.originalLanguage,
            overview: credit.overview,
            genreIDs: credit.genreIDs,
            releaseDate: credit.releaseDate,
            posterPath: credit.posterPath,
            backdropPath: credit.backdropPath,
            popularity: credit.popularity,
            voteAverage: credit.voteAverage,
            voteCount: credit.voteCount,
            hasVideo: credit.hasVideo,
            isAdultOnly: credit.isAdultOnly
        )
    }

    private static func tvSeriesListItem(from credit: TVSeriesCastCredit) -> TVSeriesListItem {
        TVSeriesListItem(
            id: credit.id,
            name: credit.name,
            originalName: credit.originalName,
            originalLanguage: credit.originalLanguage,
            overview: credit.overview,
            genreIDs: credit.genreIDs,
            firstAirDate: credit.firstAirDate,
            originCountries: credit.originCountries,
            posterPath: credit.posterPath,
            backdropPath: credit.backdropPath,
            popularity: credit.popularity,
            voteAverage: credit.voteAverage,
            voteCount: credit.voteCount,
            isAdultOnly: credit.isAdultOnly
        )
    }

    /// Get movie details (cached)
    func movieDetails(forMovieId movieId: Int) async throws -> Movie {
        if let cached = movieCache[movieId] {
            return cached
        }
        let movie = try await client.movies.details(forMovie: movieId)
        movieCache[movieId] = movie
        return movie
    }

    /// Get TV series details (cached)
    func tvSeriesDetails(forSeriesId seriesId: Int) async throws -> TVSeries {
        if let cached = tvSeriesCache[seriesId] {
            return cached
        }
        let series = try await client.tvSeries.details(forTVSeries: seriesId)
        tvSeriesCache[seriesId] = series
        return series
    }

    /// Get full season details including episodes
    func tvSeasonDetails(seriesId: Int, seasonNumber: Int) async throws -> TVSeason {
        do {
            return try await client.tvSeasons.details(
                forSeason: seasonNumber,
                inTVSeries: seriesId,
                language: "en-US"
            )
        } catch {
            if let fallback = await fetchSeasonDirectly(seriesId: seriesId, seasonNumber: seasonNumber) {
                return fallback
            }
            throw error
        }
    }

    /// Direct TMDb API fetch for season details (fallback when TMDb package decoding fails)
    private func fetchSeasonDirectly(seriesId: Int, seasonNumber: Int) async -> TVSeason? {
        let url = tmdbURL(path: "/tv/\(seriesId)/season/\(seasonNumber)", queryItems: ["language": "en-US"])
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return nil
        }
        guard let api = try? Self.tmdbDecoder.decode(TMDbSeasonDetailAPI.self, from: data) else {
            return nil
        }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)

        let episodes: [TVEpisode]? = api.episodes?.compactMap { ep -> TVEpisode? in
            let name = ep.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? ep.name! : "Episode \(ep.epNum)"
            let airDate: Date? = ep.airDate.flatMap { dateFormatter.date(from: $0) }
            let stillPath: URL? = ep.stillPath.map { path in
                let s = path.hasPrefix("/") ? path : "/" + path
                return URL(string: s)
            }.flatMap { $0 }
            return TVEpisode(
                id: ep.id,
                name: name,
                episodeNumber: ep.epNum,
                seasonNumber: ep.seasonNum,
                overview: ep.overview,
                airDate: airDate,
                productionCode: ep.productionCode,
                stillPath: stillPath,
                crew: nil,
                guestStars: nil,
                voteAverage: ep.voteAverage,
                voteCount: ep.voteCount
            )
        }

        let seasonAirDate: Date? = api.airDate.flatMap { dateFormatter.date(from: $0) }
        let posterPath: URL? = api.posterPath.map { path in
            let s = path.hasPrefix("/") ? path : "/" + path
            return URL(string: s)
        }.flatMap { $0 }
        let seasonName = api.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? api.name! : "Season \(api.seasonNum)"

        return TVSeason(
            id: api.id,
            name: seasonName,
            seasonNumber: api.seasonNum,
            overview: api.overview,
            airDate: seasonAirDate,
            posterPath: posterPath,
            episodes: episodes
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
