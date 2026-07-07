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

private struct TMDbGenreListResponse: Decodable {
    let genres: [Genre]
}

/// Service layer for TMDb API. Configure with your API key before use.
/// Get a free API key at https://www.themoviedb.org/documentation/api
actor TMDbService {

    private let client: TMDbClient
    private let apiKey: String
    private var movieCache: [Int: Movie] = [:]
    private var tvSeriesCache: [Int: TVSeries] = [:]
    private var tvSeasonCache: [String: TVSeason] = [:]
    private var trailerYouTubeKeyCache: [String: String] = [:]
    private var movieCollectionDetailCache: [String: MovieCollectionDetail] = [:]
    private var searchMoviesTVCache: [String: (movies: [MovieListItem], tvSeries: [TVSeriesListItem])] = [:]
    private var movieGenresCache: [Genre]?
    private var tvGenresCache: [Genre]?
    private let diskCache = TMDbCache.shared

    private static let trailerCacheNoneSentinel = "__none__"

    private static let seasonDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static func tvSeasonCacheKey(seriesId: Int, seasonNumber: Int) -> String {
        "\(seriesId)-\(seasonNumber)"
    }

    private static func normalizedSearchCacheKey(query: String, page: Int) -> String {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(normalized)_\(page)"
    }

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

    /// TMDB CDN occasionally serves truncated gzip bodies; JSON decode then fails with opaque errors.
    private static func isGzipPayload(_ data: Data) -> Bool {
        data.count >= 2 && data[0] == 0x1f && data[1] == 0x8b
    }

    private static func urlByPassingCDNCache(_ url: URL) -> URL {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var items = comps.queryItems ?? []
        items.append(URLQueryItem(name: "_", value: "\(Int(Date().timeIntervalSince1970 * 1000))"))
        comps.queryItems = items
        return comps.url ?? url
    }

    private func fetchTMDbData(from url: URL, bypassCDNCache: Bool) async throws -> Data {
        var request = URLRequest(url: bypassCDNCache ? Self.urlByPassingCDNCache(url) : url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if bypassCDNCache {
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(TMDbErrorResponse.self, from: data))?.statusMessage ?? "Request failed"
            throw TMDbServiceError.apiError(message)
        }
        return data
    }

    private static func decodeTMDb<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        if isGzipPayload(data) {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Unexpected gzip payload from TMDB")
            )
        }
        return try tmdbDecoder.decode(T.self, from: data)
    }

    /// Fetch from cache or network, store raw Data, decode to T. Use for types that are Decodable but not Encodable.
    private func cached<T: Decodable>(_ key: String, url: URL, as type: T.Type) async throws -> T {
        if let data = diskCache.getData(key) {
            do {
                return try Self.decodeTMDb(T.self, from: data)
            } catch {
                diskCache.removeData(key)
            }
        }

        do {
            let data = try await fetchTMDbData(from: url, bypassCDNCache: false)
            let result = try Self.decodeTMDb(T.self, from: data)
            diskCache.setData(key, data: data)
            return result
        } catch {
            let data = try await fetchTMDbData(from: url, bypassCDNCache: true)
            let result = try Self.decodeTMDb(T.self, from: data)
            diskCache.setData(key, data: data)
            return result
        }
    }


    /// Calendar for comparing TMDb date-only `release_date` values (decoded as UTC midnight) to "today".
    private static var utcDateOnlyCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }

    /// TMDb `/movie/upcoming` can still return titles that have already released. Keep items whose release day is strictly after today (UTC).
    private static func filterMoviesReleasedInFuture(_ movies: [MovieListItem]) -> [MovieListItem] {
        let cal = utcDateOnlyCalendar
        let todayStart = cal.startOfDay(for: Date())
        return movies.filter { movie in
            guard let release = movie.releaseDate else { return false }
            return cal.startOfDay(for: release) > todayStart
        }
    }

    /// Dedupe and order upcoming rows by **popularity** (then vote count, then sooner release).
    private static func mergeUpcomingMovieLists(_ a: [MovieListItem], _ b: [MovieListItem]) -> [MovieListItem] {
        let cal = utcDateOnlyCalendar
        var seen = Set<Int>()
        var combined: [MovieListItem] = []
        for m in a + b {
            guard !seen.contains(m.id) else { continue }
            seen.insert(m.id)
            combined.append(m)
        }
        combined.sort { lhs, rhs in
            let pl = lhs.popularity ?? 0
            let pr = rhs.popularity ?? 0
            if pl != pr { return pl > pr }
            let vl = lhs.voteCount ?? 0
            let vr = rhs.voteCount ?? 0
            if vl != vr { return vl > vr }
            let dl = lhs.releaseDate.map { cal.startOfDay(for: $0) } ?? .distantFuture
            let dr = rhs.releaseDate.map { cal.startOfDay(for: $0) } ?? .distantFuture
            return dl < dr
        }
        return combined
    }

    // MARK: - English original-language catalog (shelves; search APIs stay unfiltered)

    private static let catalogOriginalLanguageEnglishCode = "en"

    /// TMDb discover movie: restrict to original language English (ISO 639-1).
    private static func discoverMovieQueryItems(_ base: [String: String]) -> [String: String] {
        var q = base
        q["with_original_language"] = catalogOriginalLanguageEnglishCode
        return q
    }

    /// TMDb discover TV: restrict to original language English (ISO 639-1).
    private static func discoverTVQueryItems(_ base: [String: String]) -> [String: String] {
        var q = base
        q["with_original_language"] = catalogOriginalLanguageEnglishCode
        return q
    }

    /// Trending / list endpoints without discover language params.
    private static func filterMovieListOriginalLanguageEnglish(_ movies: [MovieListItem]) -> [MovieListItem] {
        movies.filter { ($0.originalLanguage ?? "").lowercased() == catalogOriginalLanguageEnglishCode }
    }

    private static func filterTVListOriginalLanguageEnglish(_ series: [TVSeriesListItem]) -> [TVSeriesListItem] {
        series.filter { ($0.originalLanguage ?? "").lowercased() == catalogOriginalLanguageEnglishCode }
    }

    /// Category rows use the wide 16:9 backdrop when focused; drop items with no backdrop.
    private static func filterShelfMoviesRequireBackdrop(_ movies: [MovieListItem]) -> [MovieListItem] {
        movies.filter { $0.backdropPath != nil }
    }

    private static func filterShelfTVSeriesRequireBackdrop(_ series: [TVSeriesListItem]) -> [TVSeriesListItem] {
        series.filter { $0.backdropPath != nil }
    }

    // MARK: - Adult / explicit text filtering (list-based; no image analysis)

    /// Distinctive phrases in titles or overviews (lowercase; avoid bare "sex" here — use regex below).
    private static let adultContentPhraseSubstrings: [String] = [
        "nudity", " full nudity", " nude ", " nude,", "nude)", "nude.",
        "nudist", "naked", "topless", "bare-breasted", "bare breasted", "striptease", " strip club",
        "porn", "porno", "pornograph", "pornographic", "porn ", " porn", "adult film", "adult movie",
        "erotic", "erotica", "softcore", "hardcore", "xxx", " x-rated", "x-rated", "henati", "hentai",
        "stripper", "stripping for", "peep show", "live sex", "sex scene", "sexual encounter", "sexual relationship",
        "fetish", "bdsm", "bondage", "dominatrix", "orgy", "orgies", "gangbang", "bukkake", "blowjob",
        "blow job", "handjob", "hand job", "cumshot", "ejaculat", "masturbat", "dildo", "vibrator",
        "cunnilingus", "fellatio", "sodomy", "fuck scene", "intercourse", "penetration", "sensual massage",
        "nsfw", "adults only", "adult only", "sexual content", "sexually explicit", "depicts sex",
        "incest", "raped", " rape ", " rape.", " rape,", "shemale", "futanari", "loli", "shota", "yuri porn", "yaoi porn",
        "milf", "onlyfans", "escort", "brothel", "prostitut", "call girl", "happy ending (massage)",
        "unsimulated sex", "unsimulated"
    ]

    /// Whole-word match for common explicit terms (avoids "Sussex" / "Essex" for "sex").
    private static let adultContentRegex: NSRegularExpression? = {
        let pattern = #"(?i)\b(fuck|fucking|fucked|fucks|shag|shemale|whore|slut|whores|sluts|cocksucker|cock|dick|dicks|pussy|pussies|cunt|dildo|blowjob|handjob|gangbang|milf|bdsm|hentai|futanari|orgy|orgies|xxx|porn|porno|nude|nudes|naked|topless|erotic|stripper|escort|sex|sexes|raped|rapist|incest|nudity)\b"#
        return try? NSRegularExpression(pattern: pattern, options: [])
    }()

    private static func combinedText(_ parts: String?...) -> String {
        parts.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func textLikelyAdultOrSexual(_ text: String?) -> Bool {
        guard let raw = text?.lowercased(), !raw.isEmpty else { return false }
        for phrase in adultContentPhraseSubstrings {
            if raw.contains(phrase) { return true }
        }
        if let regex = adultContentRegex {
            let range = NSRange(raw.startIndex..., in: raw)
            if regex.firstMatch(in: raw, options: [], range: range) != nil { return true }
        }
        return false
    }

    private static func imagePathStringMightIndicateAdultFromMetadata(_ path: String?) -> Bool {
        guard let s = path?.lowercased(), s.count > 3 else { return false }
        // TMDb paths are usually hash-like; image pixels are not analyzed here.
        return ["porn", "xxx", "nude", "sex", "adult", "erotic", "nsfw", "18+", "18plus"].contains { s.contains($0) }
    }

    private static func imagePathMightIndicateAdultFromURL(_ url: URL?) -> Bool {
        imagePathStringMightIndicateAdultFromMetadata(url?.absoluteString)
    }

    private static func isFutureDate(_ date: Date?) -> Bool {
        guard let date else { return false }
        let cal = utcDateOnlyCalendar
        let todayStart = cal.startOfDay(for: Date())
        return cal.startOfDay(for: date) > todayStart
    }

    private static func isMovieAllowedForApp(_ movie: MovieListItem) -> Bool {
        if movie.isAdultOnly == true { return false }
        let text = combinedText(movie.title, movie.originalTitle, movie.overview)
        if textLikelyAdultOrSexual(text) { return false }
        if imagePathMightIndicateAdultFromURL(movie.posterPath) { return false }
        if imagePathMightIndicateAdultFromURL(movie.backdropPath) { return false }
        if isFutureDate(movie.releaseDate) { return false }
        return true
    }

    private static func isTVAllowedForApp(_ series: TVSeriesListItem) -> Bool {
        if series.isAdultOnly == true { return false }
        let text = combinedText(series.name, series.originalName, series.overview)
        if textLikelyAdultOrSexual(text) { return false }
        if imagePathMightIndicateAdultFromURL(series.posterPath) { return false }
        if imagePathMightIndicateAdultFromURL(series.backdropPath) { return false }
        if isFutureDate(series.firstAirDate) { return false }
        return true
    }

    private static func appSafeMovies(_ items: [MovieListItem]) -> [MovieListItem] {
        items.filter(isMovieAllowedForApp(_:))
    }

    /// Collection shelves only drop adult titles and not-yet-released movies (avoids false positives from overview/image heuristics).
    private static func isMovieAllowedInCollection(_ movie: MovieListItem) -> Bool {
        if movie.isAdultOnly == true { return false }
        if isFutureDate(movie.releaseDate) { return false }
        return true
    }

    private static func appSafeCollectionMovies(_ items: [MovieListItem]) -> [MovieListItem] {
        items.filter(isMovieAllowedInCollection(_:))
    }

    private static func appSafeTVSeries(_ items: [TVSeriesListItem]) -> [TVSeriesListItem] {
        items.filter(isTVAllowedForApp(_:))
    }

    /// Fetch movie videos (trailers). Returns first YouTube trailer or nil.
    func movieTrailerYouTubeKey(movieId: Int) async throws -> String? {
        let memKey = "movie_\(movieId)"
        if let cached = trailerYouTubeKeyCache[memKey] {
            return cached == Self.trailerCacheNoneSentinel ? nil : cached
        }
        let url = tmdbURL(path: "/movie/\(movieId)/videos")
        let response = try await cached("movie_videos_\(movieId)", url: url, as: TMDbVideosResponse.self)
        let key = (response.results ?? [])
            .first { $0.site.lowercased() == "youtube" && $0.type.lowercased() == "trailer" }?
            .key
        trailerYouTubeKeyCache[memKey] = key ?? Self.trailerCacheNoneSentinel
        return key
    }

    /// Fetch TV series videos (trailers). Returns first YouTube trailer or nil.
    func tvSeriesTrailerYouTubeKey(seriesId: Int) async throws -> String? {
        let memKey = "tv_\(seriesId)"
        if let cached = trailerYouTubeKeyCache[memKey] {
            return cached == Self.trailerCacheNoneSentinel ? nil : cached
        }
        let url = tmdbURL(path: "/tv/\(seriesId)/videos")
        let response = try await cached("tv_videos_\(seriesId)", url: url, as: TMDbVideosResponse.self)
        let key = (response.results ?? [])
            .first { $0.site.lowercased() == "youtube" && $0.type.lowercased() == "trailer" }?
            .key
        trailerYouTubeKeyCache[memKey] = key ?? Self.trailerCacheNoneSentinel
        return key
    }

    /// Fetch popular movies
    func popularMovies(page: Int? = nil) async throws -> [MovieListItem] {
        let p = page ?? 1
        let url = tmdbURL(
            path: "/discover/movie",
            queryItems: Self.discoverMovieQueryItems(["sort_by": "popularity.desc", "page": "\(p)"])
        )
        let response: TMDbPaginatedMovieResponse = try await cached("popular_movies_orig_en_\(p)", url: url, as: TMDbPaginatedMovieResponse.self)
        return Self.appSafeMovies(Self.filterShelfMoviesRequireBackdrop(response.results))
    }

    /// Fetch trending movies
    func trendingMovies(inTimeWindow: TrendingTimeWindowFilterType = .day) async throws -> [MovieListItem] {
        let window = inTimeWindow == .day ? "day" : "week"
        let url = tmdbURL(path: "/trending/movie/\(window)")
        let response: TMDbPaginatedMovieResponse = try await cached("trending_movies_orig_en_\(window)", url: url, as: TMDbPaginatedMovieResponse.self)
        return Self.appSafeMovies(Self.filterShelfMoviesRequireBackdrop(Self.filterMovieListOriginalLanguageEnglish(response.results)))
    }

    /// Search movies by query
    func searchMovies(query: String, page: Int? = nil) async throws -> [MovieListItem] {
        let p = page ?? 1
        let cacheKey = "search_movies_\(Self.normalizedSearchCacheKey(query: query, page: p))"
        let url = tmdbURL(
            path: "/search/movie",
            queryItems: ["query": query, "page": "\(p)", "include_adult": "false"]
        )
        let response: TMDbPaginatedMovieResponse = try await cached(cacheKey, url: url, as: TMDbPaginatedMovieResponse.self)
        return Self.appSafeMovies(response.results)
    }

    /// Search TV series by query
    func searchTVSeries(query: String, page: Int? = nil) async throws -> [TVSeriesListItem] {
        let p = page ?? 1
        let cacheKey = "search_tv_\(Self.normalizedSearchCacheKey(query: query, page: p))"
        let url = tmdbURL(
            path: "/search/tv",
            queryItems: ["query": query, "page": "\(p)", "include_adult": "false"]
        )
        let response: TMDbPaginatedTVResponse = try await cached(cacheKey, url: url, as: TMDbPaginatedTVResponse.self)
        return Self.appSafeTVSeries(response.results)
    }

    // MARK: - Movie collections (TMDb `/collection/{id}`)

    /// Fetches collection metadata and movies sorted by release date (oldest first).
    func movieCollectionDetails(
        collectionId: Int,
        additionalMovieIds: [Int] = [],
        curatedTitle: String = ""
    ) async throws -> MovieCollectionDetail {
        let cacheKey = "collection_\(collectionId)_\(additionalMovieIds.sorted())_\(curatedTitle)"
        if let cached = movieCollectionDetailCache[cacheKey] {
            return cached
        }

        let collection: Collection
        do {
            collection = try await client.collections.details(forCollection: collectionId, language: nil)
        } catch {
            throw TMDbServiceError.apiError("Collection not found.")
        }
        var movies = Self.sortMoviesByReleaseDate(Self.appSafeCollectionMovies(collection.parts))
        let existingIds = Set(movies.map(\.id))
        for movieId in additionalMovieIds where !existingIds.contains(movieId) {
            if let movie = try? await movieDetails(forMovieId: movieId) {
                movies.append(Self.movieListItem(from: movie))
            }
        }
        movies = Self.sortMoviesByReleaseDate(Self.appSafeCollectionMovies(movies))
        let displayName = MovieCollectionDisplay.title(apiName: collection.name, curatedTitle: curatedTitle)
        let detail = MovieCollectionDetail(
            id: collection.id,
            name: displayName,
            overview: collection.overview,
            posterPath: collection.posterPath,
            backdropPath: collection.backdropPath,
            movies: movies
        )
        movieCollectionDetailCache[cacheKey] = detail
        return detail
    }

    /// Loads poster/backdrop for curated collection cards (parallel, bounded). Omits invalid TMDb IDs.
    func movieCollectionSummaries(for collections: [CuratedMovieCollection]) async -> [MovieCollectionSummary] {
        await withTaskGroup(of: (Int, MovieCollectionSummary?).self) { group in
            for (index, item) in collections.enumerated() {
                group.addTask {
                    do {
                        let detail = try await self.movieCollectionDetails(
                            collectionId: item.id,
                            additionalMovieIds: item.additionalMovieIds,
                            curatedTitle: item.title
                        )
                        let summary = MovieCollectionSummary(
                            id: item.id,
                            title: detail.name,
                            posterPath: detail.posterPath,
                            backdropPath: detail.backdropPath,
                            overview: nil
                        )
                        return (index, summary)
                    } catch {
                        return (index, nil)
                    }
                }
            }
            var indexed: [(Int, MovieCollectionSummary)] = []
            for await (index, summary) in group {
                if let summary { indexed.append((index, summary)) }
            }
            return indexed.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private static func sortMoviesByReleaseDate(_ items: [MovieListItem]) -> [MovieListItem] {
        items.sorted { a, b in
            let da = a.releaseDate ?? .distantFuture
            let db = b.releaseDate ?? .distantFuture
            if da != db { return da < db }
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
    }

    /// Max rows returned per media type after merging title + person cast (keeps UI and payloads bounded).
    private static let searchMergedResultsCap = 80

    /// Title search for movies and TV, merged with **cast** credits for the top person match (e.g. actor name queries).
    /// Results are **deduped by id** and ordered by **popularity** (then vote count), not title-search order first.
    func searchMoviesTVIncludingPersonCast(query: String, page: Int? = nil) async throws -> (movies: [MovieListItem], tvSeries: [TVSeriesListItem]) {
        let p = page ?? 1
        let cacheKey = Self.normalizedSearchCacheKey(query: query, page: p)
        if let cached = searchMoviesTVCache[cacheKey] {
            return cached
        }

        async let titleMovies = searchMovies(query: query, page: page)
        async let titleTV = searchTVSeries(query: query, page: page)

        var fromPersonMovies: [MovieListItem] = []
        var fromPersonTV: [TVSeriesListItem] = []

        do {
            let peopleResponse = try await client.search.searchPeople(query: query, filter: nil, page: page, language: nil)
            guard let topPerson = peopleResponse.results.first else {
                let (m, t) = try await (titleMovies, titleTV)
                let result = (
                    movies: Self.sortMoviesByPopularity(Self.appSafeMovies(m)).prefix(Self.searchMergedResultsCap).map { $0 },
                    tvSeries: Self.sortTVByPopularity(Self.appSafeTVSeries(t)).prefix(Self.searchMergedResultsCap).map { $0 }
                )
                searchMoviesTVCache[cacheKey] = result
                return result
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

        let result = (
            movies: Self.sortMoviesByPopularity(Self.appSafeMovies(mergedMovies)).prefix(Self.searchMergedResultsCap).map { $0 },
            tvSeries: Self.sortTVByPopularity(Self.appSafeTVSeries(mergedTV)).prefix(Self.searchMergedResultsCap).map { $0 }
        )
        searchMoviesTVCache[cacheKey] = result
        return result
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

    private static func movieListItem(from movie: Movie) -> MovieListItem {
        MovieListItem(
            id: movie.id,
            title: movie.title,
            originalTitle: movie.originalTitle ?? movie.title,
            originalLanguage: movie.originalLanguage ?? "en",
            overview: movie.overview ?? "",
            genreIDs: (movie.genres ?? []).map(\.id),
            releaseDate: movie.releaseDate,
            posterPath: movie.posterPath,
            backdropPath: movie.backdropPath,
            popularity: movie.popularity,
            voteAverage: movie.voteAverage,
            voteCount: movie.voteCount,
            hasVideo: movie.hasVideo,
            isAdultOnly: movie.isAdultOnly
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

    /// Get movie details (cached in memory and on disk for 24h).
    func movieDetails(forMovieId movieId: Int) async throws -> Movie {
        if let cached = movieCache[movieId] {
            if Self.isMovieDetailAllowedForApp(cached) { return cached }
            movieCache.removeValue(forKey: movieId)
        }
        let url = tmdbURL(path: "/movie/\(movieId)", queryItems: ["language": "en-US"])
        if let movie = try? await cached("movie_detail_\(movieId)", url: url, as: Movie.self),
           Self.isMovieDetailAllowedForApp(movie) {
            movieCache[movieId] = movie
            return movie
        }
        let movie = try await client.movies.details(forMovie: movieId)
        guard Self.isMovieDetailAllowedForApp(movie) else {
            throw TMDbServiceError.apiError("This title isn’t available.")
        }
        movieCache[movieId] = movie
        return movie
    }

    /// Get TV series details (cached in memory and on disk for 24h).
    func tvSeriesDetails(forSeriesId seriesId: Int) async throws -> TVSeries {
        if let cached = tvSeriesCache[seriesId] {
            if Self.isTVSeriesDetailAllowedForApp(cached) { return Self.tvSeriesExcludingSeasonZero(cached) }
            tvSeriesCache.removeValue(forKey: seriesId)
        }
        let url = tmdbURL(path: "/tv/\(seriesId)", queryItems: ["language": "en-US"])
        if let series = try? await cached("tv_detail_\(seriesId)", url: url, as: TVSeries.self),
           Self.isTVSeriesDetailAllowedForApp(series) {
            let filtered = Self.tvSeriesExcludingSeasonZero(series)
            tvSeriesCache[seriesId] = filtered
            return filtered
        }
        let series = try await client.tvSeries.details(forTVSeries: seriesId)
        guard Self.isTVSeriesDetailAllowedForApp(series) else {
            throw TMDbServiceError.apiError("This title isn’t available.")
        }
        let filtered = Self.tvSeriesExcludingSeasonZero(series)
        tvSeriesCache[seriesId] = filtered
        return filtered
    }

    /// Whether season episode data is already in the in-memory cache (instant season switches).
    func isTVSeasonCached(seriesId: Int, seasonNumber: Int) -> Bool {
        tvSeasonCache[Self.tvSeasonCacheKey(seriesId: seriesId, seasonNumber: seasonNumber)] != nil
    }

    private static func tvSeriesExcludingSeasonZero(_ series: TVSeries) -> TVSeries {
        guard let seasons = series.seasons, seasons.contains(where: { $0.seasonNumber <= 0 }) else {
            return series
        }
        let filteredSeasons = seasons.filter { $0.seasonNumber > 0 }
        return TVSeries(
            id: series.id,
            name: series.name,
            tagline: series.tagline,
            originalName: series.originalName,
            originalLanguage: series.originalLanguage,
            overview: series.overview,
            episodeRunTime: series.episodeRunTime,
            numberOfSeasons: series.numberOfSeasons,
            numberOfEpisodes: series.numberOfEpisodes,
            seasons: filteredSeasons.isEmpty ? nil : filteredSeasons,
            createdBy: series.createdBy,
            genres: series.genres,
            firstAirDate: series.firstAirDate,
            originCountry: series.originCountry,
            posterPath: series.posterPath,
            backdropPath: series.backdropPath,
            homepageURL: series.homepageURL,
            isInProduction: series.isInProduction,
            languages: series.languages,
            lastAirDate: series.lastAirDate,
            lastEpisodeToAir: series.lastEpisodeToAir,
            nextEpisodeToAir: series.nextEpisodeToAir,
            networks: series.networks,
            productionCompanies: series.productionCompanies,
            status: series.status,
            type: series.type,
            popularity: series.popularity,
            voteAverage: series.voteAverage,
            voteCount: series.voteCount,
            isAdultOnly: series.isAdultOnly
        )
    }

    /// Text on full TMDb `Movie` (title, overview, tagline, etc.). Poster art is not analyzed.
    private static func isMovieDetailAllowedForApp(_ m: Movie) -> Bool {
        if m.isAdultOnly == true { return false }
        let text = combinedText(m.title, m.originalTitle, m.overview, m.tagline)
        if textLikelyAdultOrSexual(text) { return false }
        if imagePathMightIndicateAdultFromURL(m.posterPath) { return false }
        if imagePathMightIndicateAdultFromURL(m.backdropPath) { return false }
        return true
    }

    private static func isTVSeriesDetailAllowedForApp(_ s: TVSeries) -> Bool {
        if s.isAdultOnly == true { return false }
        let text = combinedText(s.name, s.originalName, s.overview, s.tagline)
        if textLikelyAdultOrSexual(text) { return false }
        if imagePathMightIndicateAdultFromURL(s.posterPath) { return false }
        if imagePathMightIndicateAdultFromURL(s.backdropPath) { return false }
        return true
    }

    /// Get full season details including episodes (cached in memory and on disk for 24h).
    func tvSeasonDetails(seriesId: Int, seasonNumber: Int) async throws -> TVSeason {
        let memKey = Self.tvSeasonCacheKey(seriesId: seriesId, seasonNumber: seasonNumber)
        if let cached = tvSeasonCache[memKey] {
            return cached
        }

        if let season = await fetchSeasonDirectly(seriesId: seriesId, seasonNumber: seasonNumber) {
            tvSeasonCache[memKey] = season
            return season
        }

        do {
            let season = try await client.tvSeasons.details(
                forSeason: seasonNumber,
                inTVSeries: seriesId,
                language: "en-US"
            )
            let filtered = season.filteringUnreleasedEpisodes()
            tvSeasonCache[memKey] = filtered
            return filtered
        } catch {
            throw error
        }
    }

    private static func tvSeason(from api: TMDbSeasonDetailAPI) -> TVSeason {
        let episodes: [TVEpisode]? = api.episodes?.compactMap { ep -> TVEpisode? in
            let name = ep.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? ep.name! : "Episode \(ep.epNum)"
            let airDate: Date? = ep.airDate.flatMap { seasonDateFormatter.date(from: $0) }
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

        let seasonAirDate: Date? = api.airDate.flatMap { seasonDateFormatter.date(from: $0) }
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
        ).filteringUnreleasedEpisodes()
    }

    /// Direct TMDb API fetch for season details (disk-cached; also used when package decoding fails).
    private func fetchSeasonDirectly(seriesId: Int, seasonNumber: Int) async -> TVSeason? {
        let url = tmdbURL(path: "/tv/\(seriesId)/season/\(seasonNumber)", queryItems: ["language": "en-US"])
        let diskKey = "tv_season_\(seriesId)_\(seasonNumber)"
        guard let api = try? await cached(diskKey, url: url, as: TMDbSeasonDetailAPI.self) else {
            return nil
        }
        return Self.tvSeason(from: api)
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

    /// TMDb `discover` date format (UTC calendar day).
    private static func tmdbDiscoverDate(daysFromToday: Int) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone.current
        let base = cal.startOfDay(for: Date())
        let d = cal.date(byAdding: .day, value: daysFromToday, to: base) ?? base
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.string(from: d)
    }

    /// Format a concrete date for discover date-range filters.
    private static func tmdbDiscoverDate(year: Int, month: Int, day: Int) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone.current
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        let date = cal.date(from: comps) ?? Date()
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.string(from: date)
    }

    /// Keyword "based on novel or book" on TMDb (common discover filter).
    /// Discover OR keywords — epic spectacle: antiquity & Rome (Gladiator), sword-and-sandal, video-game adaptations (Prince of Persia, Assassin's Creed), Mars / other worlds (John Carter). TMDB keyword IDs: ancient world, roman empire, sword and sandal, based on video game, planet mars.
    private static let epicSpectacleAdventureKeywordIds = "14704|1405|317728|41645|839"

    private static let basedOnBookKeywordId = "818"

    /// TMDb keyword "racing" (no dedicated genre); discover uses `with_keywords`.
    /// See https://www.themoviedb.org/keyword/10039-racing
    private static let racingKeywordId = "10039"

    /// Movies first released in roughly the last 45 days (popularity order).
    func recentReleaseMovies(page: Int? = nil) async throws -> [MovieListItem] {
        let p = page ?? 1
        let from = Self.tmdbDiscoverDate(daysFromToday: -45)
        let url = tmdbURL(
            path: "/discover/movie",
            queryItems: Self.discoverMovieQueryItems([
                "primary_release_date.gte": from,
                "sort_by": "popularity.desc",
                "page": "\(p)"
            ])
        )
        let response: TMDbPaginatedMovieResponse = try await cached("movies_new_orig_en_\(from)_\(p)", url: url, as: TMDbPaginatedMovieResponse.self)
        return Self.appSafeMovies(Self.filterShelfMoviesRequireBackdrop(response.results))
    }

    /// TV whose first air date is in roughly the last 45 days.
    func recentReleaseTVSeries(page: Int? = nil) async throws -> [TVSeriesListItem] {
        let p = page ?? 1
        let from = Self.tmdbDiscoverDate(daysFromToday: -45)
        let url = tmdbURL(
            path: "/discover/tv",
            queryItems: Self.discoverTVQueryItems([
                "first_air_date.gte": from,
                "sort_by": "popularity.desc",
                "page": "\(p)"
            ])
        )
        let response: TMDbPaginatedTVResponse = try await cached("tv_new_orig_en_\(from)_\(p)", url: url, as: TMDbPaginatedTVResponse.self)
        return Self.appSafeTVSeries(Self.filterShelfTVSeriesRequireBackdrop(response.results))
    }

    /// Strong ratings with enough votes to avoid one-off 10.0 titles.
    func criticallyAcclaimedMovies(page: Int? = nil) async throws -> [MovieListItem] {
        let p = page ?? 1
        let url = tmdbURL(
            path: "/discover/movie",
            queryItems: Self.discoverMovieQueryItems([
                "vote_average.gte": "7.5",
                "vote_count.gte": "250",
                "sort_by": "vote_average.desc",
                "page": "\(p)"
            ])
        )
        let response: TMDbPaginatedMovieResponse = try await cached("movies_acclaimed_orig_en_\(p)", url: url, as: TMDbPaginatedMovieResponse.self)
        return Self.appSafeMovies(Self.filterShelfMoviesRequireBackdrop(response.results))
    }

    func criticallyAcclaimedTVSeries(page: Int? = nil) async throws -> [TVSeriesListItem] {
        let p = page ?? 1
        let url = tmdbURL(
            path: "/discover/tv",
            queryItems: Self.discoverTVQueryItems([
                "vote_average.gte": "7.5",
                "vote_count.gte": "150",
                "sort_by": "vote_average.desc",
                "page": "\(p)"
            ])
        )
        let response: TMDbPaginatedTVResponse = try await cached("tv_acclaimed_orig_en_\(p)", url: url, as: TMDbPaginatedTVResponse.self)
        return Self.appSafeTVSeries(Self.filterShelfTVSeriesRequireBackdrop(response.results))
    }

    /// Fetch movie genres
    func movieGenres() async throws -> [Genre] {
        if let movieGenresCache { return movieGenresCache }
        let url = tmdbURL(path: "/genre/movie/list", queryItems: ["language": "en-US"])
        let response = try await cached("genre_movie_list", url: url, as: TMDbGenreListResponse.self)
        movieGenresCache = response.genres
        return response.genres
    }

    /// Fetch TV series genres
    func tvSeriesGenres() async throws -> [Genre] {
        if let tvGenresCache { return tvGenresCache }
        let url = tmdbURL(path: "/genre/tv/list", queryItems: ["language": "en-US"])
        let response = try await cached("genre_tv_list", url: url, as: TMDbGenreListResponse.self)
        tvGenresCache = response.genres
        return response.genres
    }

    /// Fetch trending TV series
    func trendingTVSeries(inTimeWindow: TrendingTimeWindowFilterType = .day) async throws -> [TVSeriesListItem] {
        let window = inTimeWindow == .day ? "day" : "week"
        let url = tmdbURL(path: "/trending/tv/\(window)")
        let response: TMDbPaginatedTVResponse = try await cached("trending_tv_orig_en_\(window)", url: url, as: TMDbPaginatedTVResponse.self)
        return Self.appSafeTVSeries(Self.filterShelfTVSeriesRequireBackdrop(Self.filterTVListOriginalLanguageEnglish(response.results)))
    }

    /// Fetch popular TV series (discover for `with_original_language` parity with movie shelves).
    func popularTVSeries(page: Int? = nil) async throws -> [TVSeriesListItem] {
        let p = page ?? 1
        let url = tmdbURL(
            path: "/discover/tv",
            queryItems: Self.discoverTVQueryItems(["sort_by": "popularity.desc", "page": "\(p)"])
        )
        let response: TMDbPaginatedTVResponse = try await cached("popular_tv_orig_en_\(p)", url: url, as: TMDbPaginatedTVResponse.self)
        return Self.appSafeTVSeries(Self.filterShelfTVSeriesRequireBackdrop(response.results))
    }

    /// Fetch now playing movies (currently in theatres)
    func nowPlayingMovies(page: Int? = nil) async throws -> [MovieListItem] {
        let p = page ?? 1
        let url = tmdbURL(path: "/movie/now_playing", queryItems: ["page": "\(p)"])
        let response: TMDbPaginatedMovieResponse = try await cached("now_playing_movies_orig_en_\(p)", url: url, as: TMDbPaginatedMovieResponse.self)
        return Self.appSafeMovies(Self.filterShelfMoviesRequireBackdrop(Self.filterMovieListOriginalLanguageEnglish(response.results)))
    }

    /// Discover movies with primary release strictly after today (UTC). No vote floor so future titles with few votes still appear.
    private func fetchDiscoverUpcomingPage(page: Int, fromDate: String) async throws -> TMDbPaginatedMovieResponse {
        let url = tmdbURL(
            path: "/discover/movie",
            queryItems: Self.discoverMovieQueryItems([
                "primary_release_date.gte": fromDate,
                "sort_by": "popularity.desc",
                "page": "\(page)"
            ])
        )
        return try await cached(
            "movies_discover_upcoming_v3_orig_en_\(fromDate)_\(page)",
            url: url,
            as: TMDbPaginatedMovieResponse.self
        )
    }

    /// Merges `/movie/upcoming` with discover. Page 1 pulls several discover pages so the row is not limited to one API page before filtering.
    private func upcomingMoviesMergedPage(page: Int) async throws -> (items: [MovieListItem], hasMore: Bool) {
        let officialURL = tmdbURL(path: "/movie/upcoming", queryItems: ["page": "\(page)"])
        let officialResponse: TMDbPaginatedMovieResponse = try await cached(
            "upcoming_movies_raw_orig_en_\(page)",
            url: officialURL,
            as: TMDbPaginatedMovieResponse.self
        )
        let from = Self.tmdbDiscoverDate(daysFromToday: 1)
        let officialFiltered = Self.filterMoviesReleasedInFuture(officialResponse.results)

        let discoverFlat: [MovieListItem]
        let discoverTotalPages: Int

        if page == 1 {
            let firstDiscover = try await fetchDiscoverUpcomingPage(page: 1, fromDate: from)
            discoverTotalPages = firstDiscover.totalPages ?? 1
            var collected = firstDiscover.results
            await withTaskGroup(of: [MovieListItem].self) { group in
                for p in 2...8 {
                    group.addTask {
                        (try? await self.fetchDiscoverUpcomingPage(page: p, fromDate: from).results) ?? []
                    }
                }
                for await chunk in group {
                    collected.append(contentsOf: chunk)
                }
            }
            discoverFlat = collected
        } else {
            let discoverResponse = try await fetchDiscoverUpcomingPage(page: page, fromDate: from)
            discoverFlat = discoverResponse.results
            discoverTotalPages = discoverResponse.totalPages ?? page
        }

        let discoverFiltered = Self.filterMoviesReleasedInFuture(discoverFlat)
        let merged = Self.mergeUpcomingMovieLists(officialFiltered, discoverFiltered)
        let englishOnly = Self.filterMovieListOriginalLanguageEnglish(merged)
        let shelfReady = Self.filterShelfMoviesRequireBackdrop(englishOnly)
        let tpOfficial = officialResponse.totalPages ?? page
        let hasMore: Bool
        if page == 1 {
            hasMore = tpOfficial > 1 || discoverTotalPages > 8
        } else {
            hasMore = page < max(tpOfficial, discoverTotalPages)
        }
        return (Self.appSafeMovies(shelfReady), hasMore)
    }

    /// Fetch upcoming movies (merged sources; capped for horizontal rows).
    func upcomingMovies(page: Int? = nil) async throws -> [MovieListItem] {
        let p = page ?? 1
        let (items, _) = try await upcomingMoviesMergedPage(page: p)
        return Array(items.prefix(20))
    }

    /// Fetch documentary movies (TMDb genre ID 99)
    func documentaryMovies(page: Int? = nil) async throws -> [MovieListItem] {
        let p = page ?? 1
        let url = tmdbURL(
            path: "/discover/movie",
            queryItems: Self.discoverMovieQueryItems(["with_genres": "99", "sort_by": "popularity.desc", "page": "\(p)"])
        )
        let response: TMDbPaginatedMovieResponse = try await cached("documentary_movies_orig_en_\(p)", url: url, as: TMDbPaginatedMovieResponse.self)
        return Self.appSafeMovies(Self.filterShelfMoviesRequireBackdrop(response.results))
    }

    /// Fetch documentary TV series (TMDb genre ID 99)
    func documentaryTVSeries(page: Int? = nil) async throws -> [TVSeriesListItem] {
        let p = page ?? 1
        let url = tmdbURL(
            path: "/discover/tv",
            queryItems: Self.discoverTVQueryItems(["with_genres": "99", "sort_by": "popularity.desc", "page": "\(p)"])
        )
        let response: TMDbPaginatedTVResponse = try await cached("documentary_tv_orig_en_\(p)", url: url, as: TMDbPaginatedTVResponse.self)
        return Self.appSafeTVSeries(Self.filterShelfTVSeriesRequireBackdrop(response.results))
    }

    /// Fetch movie recommendations (for "Because you watched X").
    func movieRecommendations(forMovieId movieId: Int, page: Int = 1) async throws -> [MovieListItem] {
        let url = tmdbURL(path: "/movie/\(movieId)/recommendations", queryItems: ["page": "\(page)"])
        let response: TMDbPaginatedMovieResponse = try await cached(
            "movie_recommendations_orig_en_\(movieId)_\(page)",
            url: url,
            as: TMDbPaginatedMovieResponse.self
        )
        return Self.appSafeMovies(Self.filterShelfMoviesRequireBackdrop(Self.filterMovieListOriginalLanguageEnglish(response.results)))
    }

    /// Fetch TV series recommendations (for "Because you watched X").
    func tvSeriesRecommendations(forSeriesId seriesId: Int, page: Int = 1) async throws -> [TVSeriesListItem] {
        let url = tmdbURL(path: "/tv/\(seriesId)/recommendations", queryItems: ["page": "\(page)"])
        let response: TMDbPaginatedTVResponse = try await cached(
            "tv_recommendations_orig_en_\(seriesId)_\(page)",
            url: url,
            as: TMDbPaginatedTVResponse.self
        )
        return Self.appSafeTVSeries(Self.filterShelfTVSeriesRequireBackdrop(Self.filterTVListOriginalLanguageEnglish(response.results)))
    }

    /// Load movies for a category (used by See All). Returns (items, hasMore) for pagination.
    func moviesPaginated(for category: MovieCategory, page: Int) async throws -> (items: [MovieListItem], hasMore: Bool) {
        switch category {
        case .trendingToday:
            let items = try await trendingMovies(inTimeWindow: .day)
            return (items, false)
        case .popular:
            let url = tmdbURL(
                path: "/discover/movie",
                queryItems: Self.discoverMovieQueryItems(["sort_by": "popularity.desc", "page": "\(page)"])
            )
            let response: TMDbPaginatedMovieResponse = try await cached("popular_movies_orig_en_\(page)", url: url, as: TMDbPaginatedMovieResponse.self)
            return (Self.appSafeMovies(Self.filterShelfMoviesRequireBackdrop(response.results)), page < (response.totalPages ?? page))
        case .criticallyAcclaimed:
            let url = tmdbURL(
                path: "/discover/movie",
                queryItems: Self.discoverMovieQueryItems([
                    "vote_average.gte": "7.5",
                    "vote_count.gte": "250",
                    "sort_by": "vote_average.desc",
                    "page": "\(page)"
                ])
            )
            let response: TMDbPaginatedMovieResponse = try await cached("movies_acclaimed_orig_en_\(page)", url: url, as: TMDbPaginatedMovieResponse.self)
            return (Self.appSafeMovies(Self.filterShelfMoviesRequireBackdrop(response.results)), page < (response.totalPages ?? page))
        case .newReleases:
            let from = Self.tmdbDiscoverDate(daysFromToday: -45)
            let url = tmdbURL(
                path: "/discover/movie",
                queryItems: Self.discoverMovieQueryItems([
                    "primary_release_date.gte": from,
                    "sort_by": "popularity.desc",
                    "page": "\(page)"
                ])
            )
            let response: TMDbPaginatedMovieResponse = try await cached("movies_new_orig_en_\(from)_\(page)", url: url, as: TMDbPaginatedMovieResponse.self)
            return (Self.appSafeMovies(Self.filterShelfMoviesRequireBackdrop(response.results)), page < (response.totalPages ?? page))
        case .millennialFavorites:
            let from = Self.tmdbDiscoverDate(year: 1990, month: 1, day: 1)
            let to = Self.tmdbDiscoverDate(year: 2010, month: 12, day: 31)
            let url = tmdbURL(
                path: "/discover/movie",
                queryItems: Self.discoverMovieQueryItems([
                    "primary_release_date.gte": from,
                    "primary_release_date.lte": to,
                    "sort_by": "popularity.desc",
                    "page": "\(page)"
                ])
            )
            let response: TMDbPaginatedMovieResponse = try await cached("movies_millennial_orig_en_\(page)", url: url, as: TMDbPaginatedMovieResponse.self)
            return (Self.appSafeMovies(Self.filterShelfMoviesRequireBackdrop(response.results)), page < (response.totalPages ?? page))
        case .genZPicks:
            let from = Self.tmdbDiscoverDate(year: 2016, month: 1, day: 1)
            let url = tmdbURL(
                path: "/discover/movie",
                queryItems: Self.discoverMovieQueryItems([
                    "primary_release_date.gte": from,
                    "primary_release_date.lte": Self.tmdbDiscoverDate(daysFromToday: 0),
                    "sort_by": "popularity.desc",
                    "page": "\(page)"
                ])
            )
            let response: TMDbPaginatedMovieResponse = try await cached("movies_genz_orig_en_\(page)", url: url, as: TMDbPaginatedMovieResponse.self)
            return (Self.appSafeMovies(Self.filterShelfMoviesRequireBackdrop(response.results)), page < (response.totalPages ?? page))
        case .genXClassics:
            let from = Self.tmdbDiscoverDate(year: 1975, month: 1, day: 1)
            let to = Self.tmdbDiscoverDate(year: 1994, month: 12, day: 31)
            let url = tmdbURL(
                path: "/discover/movie",
                queryItems: Self.discoverMovieQueryItems([
                    "primary_release_date.gte": from,
                    "primary_release_date.lte": to,
                    "sort_by": "popularity.desc",
                    "page": "\(page)"
                ])
            )
            let response: TMDbPaginatedMovieResponse = try await cached("movies_genx_orig_en_\(page)", url: url, as: TMDbPaginatedMovieResponse.self)
            return (Self.appSafeMovies(Self.filterShelfMoviesRequireBackdrop(response.results)), page < (response.totalPages ?? page))
        case .nowPlaying:
            let url = tmdbURL(path: "/movie/now_playing", queryItems: ["page": "\(page)"])
            let response: TMDbPaginatedMovieResponse = try await cached("now_playing_movies_orig_en_\(page)", url: url, as: TMDbPaginatedMovieResponse.self)
            let items = Self.filterShelfMoviesRequireBackdrop(Self.filterMovieListOriginalLanguageEnglish(response.results))
            return (Self.appSafeMovies(items), page < (response.totalPages ?? page))
        case .upcoming:
            return ([], false)
        case .basedOnBooks:
            let url = tmdbURL(
                path: "/discover/movie",
                queryItems: Self.discoverMovieQueryItems([
                    "with_keywords": Self.basedOnBookKeywordId,
                    "sort_by": "popularity.desc",
                    "page": "\(page)"
                ])
            )
            let response: TMDbPaginatedMovieResponse = try await cached("movies_book_orig_en_\(page)", url: url, as: TMDbPaginatedMovieResponse.self)
            return (Self.appSafeMovies(Self.filterShelfMoviesRequireBackdrop(response.results)), page < (response.totalPages ?? page))
        case .racing:
            let url = tmdbURL(
                path: "/discover/movie",
                queryItems: Self.discoverMovieQueryItems([
                    "with_keywords": Self.racingKeywordId,
                    "sort_by": "popularity.desc",
                    "page": "\(page)"
                ])
            )
            let response: TMDbPaginatedMovieResponse = try await cached(
                "movies_racing_kw_orig_en_\(page)",
                url: url,
                as: TMDbPaginatedMovieResponse.self
            )
            let totalPages = response.totalPages ?? page
            return (Self.appSafeMovies(Self.filterShelfMoviesRequireBackdrop(response.results)), page < totalPages)
        case .epicSpectacleAdventures:
            let url = tmdbURL(
                path: "/discover/movie",
                queryItems: Self.discoverMovieQueryItems([
                    "with_keywords": Self.epicSpectacleAdventureKeywordIds,
                    "sort_by": "popularity.desc",
                    "page": "\(page)"
                ])
            )
            let response: TMDbPaginatedMovieResponse = try await cached(
                "movies_epic_spectacle_kw_orig_en_\(page)",
                url: url,
                as: TMDbPaginatedMovieResponse.self
            )
            let totalPages = response.totalPages ?? page
            return (Self.appSafeMovies(Self.filterShelfMoviesRequireBackdrop(response.results)), page < totalPages)
        default:
            guard let genreId = category.genreId else {
                preconditionFailure("MovieCategory must map to discover: \(category)")
            }
            let cacheKey = "movies_genre_orig_en_\(genreId)_\(page)"
            let url = tmdbURL(
                path: "/discover/movie",
                queryItems: Self.discoverMovieQueryItems([
                    "with_genres": "\(genreId)",
                    "sort_by": "popularity.desc",
                    "page": "\(page)"
                ])
            )
            let response: TMDbPaginatedMovieResponse = try await cached(cacheKey, url: url, as: TMDbPaginatedMovieResponse.self)
            let totalPages = response.totalPages ?? page
            return (Self.appSafeMovies(Self.filterShelfMoviesRequireBackdrop(response.results)), page < totalPages)
        }
    }

    /// Load TV series for a category (used by See All). Returns (items, hasMore) for pagination.
    func tvSeriesPaginated(for category: TVCategory, page: Int) async throws -> (items: [TVSeriesListItem], hasMore: Bool) {
        switch category {
        case .trendingToday:
            let items = try await trendingTVSeries(inTimeWindow: .day)
            return (items, false)
        case .popular:
            let url = tmdbURL(
                path: "/discover/tv",
                queryItems: Self.discoverTVQueryItems(["sort_by": "popularity.desc", "page": "\(page)"])
            )
            let response: TMDbPaginatedTVResponse = try await cached("popular_tv_orig_en_\(page)", url: url, as: TMDbPaginatedTVResponse.self)
            return (Self.appSafeTVSeries(Self.filterShelfTVSeriesRequireBackdrop(response.results)), page < (response.totalPages ?? page))
        case .criticallyAcclaimed:
            let url = tmdbURL(
                path: "/discover/tv",
                queryItems: Self.discoverTVQueryItems([
                    "vote_average.gte": "7.5",
                    "vote_count.gte": "150",
                    "sort_by": "vote_average.desc",
                    "page": "\(page)"
                ])
            )
            let response: TMDbPaginatedTVResponse = try await cached("tv_acclaimed_orig_en_\(page)", url: url, as: TMDbPaginatedTVResponse.self)
            return (Self.appSafeTVSeries(Self.filterShelfTVSeriesRequireBackdrop(response.results)), page < (response.totalPages ?? page))
        case .newReleases:
            let from = Self.tmdbDiscoverDate(daysFromToday: -45)
            let url = tmdbURL(
                path: "/discover/tv",
                queryItems: Self.discoverTVQueryItems([
                    "first_air_date.gte": from,
                    "sort_by": "popularity.desc",
                    "page": "\(page)"
                ])
            )
            let response: TMDbPaginatedTVResponse = try await cached("tv_new_orig_en_\(from)_\(page)", url: url, as: TMDbPaginatedTVResponse.self)
            return (Self.appSafeTVSeries(Self.filterShelfTVSeriesRequireBackdrop(response.results)), page < (response.totalPages ?? page))
        case .millennialFavorites:
            let from = Self.tmdbDiscoverDate(year: 1990, month: 1, day: 1)
            let to = Self.tmdbDiscoverDate(year: 2010, month: 12, day: 31)
            let url = tmdbURL(
                path: "/discover/tv",
                queryItems: Self.discoverTVQueryItems([
                    "first_air_date.gte": from,
                    "first_air_date.lte": to,
                    "sort_by": "popularity.desc",
                    "page": "\(page)"
                ])
            )
            let response: TMDbPaginatedTVResponse = try await cached("tv_millennial_orig_en_\(page)", url: url, as: TMDbPaginatedTVResponse.self)
            return (Self.appSafeTVSeries(Self.filterShelfTVSeriesRequireBackdrop(response.results)), page < (response.totalPages ?? page))
        case .genZPicks:
            let from = Self.tmdbDiscoverDate(year: 2016, month: 1, day: 1)
            let url = tmdbURL(
                path: "/discover/tv",
                queryItems: Self.discoverTVQueryItems([
                    "first_air_date.gte": from,
                    "first_air_date.lte": Self.tmdbDiscoverDate(daysFromToday: 0),
                    "sort_by": "popularity.desc",
                    "page": "\(page)"
                ])
            )
            let response: TMDbPaginatedTVResponse = try await cached("tv_genz_orig_en_\(page)", url: url, as: TMDbPaginatedTVResponse.self)
            return (Self.appSafeTVSeries(Self.filterShelfTVSeriesRequireBackdrop(response.results)), page < (response.totalPages ?? page))
        case .genXClassics:
            let from = Self.tmdbDiscoverDate(year: 1975, month: 1, day: 1)
            let to = Self.tmdbDiscoverDate(year: 1994, month: 12, day: 31)
            let url = tmdbURL(
                path: "/discover/tv",
                queryItems: Self.discoverTVQueryItems([
                    "first_air_date.gte": from,
                    "first_air_date.lte": to,
                    "sort_by": "popularity.desc",
                    "page": "\(page)"
                ])
            )
            let response: TMDbPaginatedTVResponse = try await cached("tv_genx_orig_en_\(page)", url: url, as: TMDbPaginatedTVResponse.self)
            return (Self.appSafeTVSeries(Self.filterShelfTVSeriesRequireBackdrop(response.results)), page < (response.totalPages ?? page))
        case .basedOnBooks:
            let url = tmdbURL(
                path: "/discover/tv",
                queryItems: Self.discoverTVQueryItems([
                    "with_keywords": Self.basedOnBookKeywordId,
                    "sort_by": "popularity.desc",
                    "page": "\(page)"
                ])
            )
            let response: TMDbPaginatedTVResponse = try await cached("tv_book_orig_en_\(page)", url: url, as: TMDbPaginatedTVResponse.self)
            return (Self.appSafeTVSeries(Self.filterShelfTVSeriesRequireBackdrop(response.results)), page < (response.totalPages ?? page))
        case .racing:
            let url = tmdbURL(
                path: "/discover/tv",
                queryItems: Self.discoverTVQueryItems([
                    "with_keywords": Self.racingKeywordId,
                    "sort_by": "popularity.desc",
                    "page": "\(page)"
                ])
            )
            let response: TMDbPaginatedTVResponse = try await cached(
                "tv_racing_kw_orig_en_\(page)",
                url: url,
                as: TMDbPaginatedTVResponse.self
            )
            let totalPages = response.totalPages ?? page
            return (Self.appSafeTVSeries(Self.filterShelfTVSeriesRequireBackdrop(response.results)), page < totalPages)
        default:
            guard let genreId = category.genreId else {
                preconditionFailure("TVCategory must map to discover: \(category)")
            }
            let cacheKey = "tv_genre_orig_en_\(genreId)_\(page)"
            let url = tmdbURL(
                path: "/discover/tv",
                queryItems: Self.discoverTVQueryItems([
                    "with_genres": "\(genreId)",
                    "sort_by": "popularity.desc",
                    "page": "\(page)"
                ])
            )
            let response: TMDbPaginatedTVResponse = try await cached(cacheKey, url: url, as: TMDbPaginatedTVResponse.self)
            return (Self.appSafeTVSeries(Self.filterShelfTVSeriesRequireBackdrop(response.results)), page < (response.totalPages ?? page))
        }
    }
}
