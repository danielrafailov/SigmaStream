//
//  StreamingService.swift
//  SigmaStream
//
//  Resolves streaming sources from CinePro Core (OMSS) and returns playable HLS URLs.
//

import Foundation

/// Resolves streaming sources from CinePro Core for AVPlayer playback.
actor StreamingService {

    private let baseURL: String
    private let session: URLSession
    private var sourceResponseCache: [String: CachedOMSSResponse] = [:]
    /// Stream manifests can shift; cache long enough to speed replay without going stale.
    private let sourceResponseCacheTTL: TimeInterval = 30 * 60

    private struct CachedOMSSResponse {
        let response: OMSSSourceResponse
        let expiresAt: Date
    }

    init(baseURL: String) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        // OMSS waits for slow providers before writing any bytes; idle gap exceeds URLSession.shared’s default (~60s).
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 600
        cfg.timeoutIntervalForResource = 600
        cfg.waitsForConnectivity = true
        self.session = URLSession(configuration: cfg)
    }

    /// Fetch all playable URLs for a movie, sorted by quality. Empty if none.
    func playableURLsForMovie(tmdbId: Int) async throws -> [URL] {
        let (urls, _) = try await playableURLsAndQualityForMovie(tmdbId: tmdbId)
        return urls
    }

    /// Fetch playable URLs and best quality for a movie.
    func playableURLsAndQualityForMovie(tmdbId: Int) async throws -> (urls: [URL], quality: String?) {
        let urlString = "\(baseURL)/v1/movies/\(tmdbId)"
        guard let url = URL(string: urlString) else {
            throw StreamingError.invalidURL(urlString)
        }
        let response = try await fetchSourceResponse(from: url)
        return sortedPlayableURLsAndQuality(from: response)
    }

    /// Fetch all playable URLs for a TV episode, sorted by quality. Empty if none.
    func playableURLsForEpisode(seriesId: Int, season: Int, episode: Int) async throws -> [URL] {
        let (urls, _) = try await playableURLsAndQualityForEpisode(seriesId: seriesId, season: season, episode: episode)
        return urls
    }

    /// Fetch playable URLs and best quality for a TV episode.
    func playableURLsAndQualityForEpisode(seriesId: Int, season: Int, episode: Int) async throws -> (urls: [URL], quality: String?) {
        let urlString = "\(baseURL)/v1/tv/\(seriesId)/seasons/\(season)/episodes/\(episode)"
        guard let url = URL(string: urlString) else {
            throw StreamingError.invalidURL(urlString)
        }
        let response = try await fetchSourceResponse(from: url)
        return sortedPlayableURLsAndQuality(from: response)
    }

    /// Returns all sources for optional source picker UI (quality, provider).
    func sourcesForMovie(tmdbId: Int) async throws -> [OMSSSource] {
        let urlString = "\(baseURL)/v1/movies/\(tmdbId)"
        guard let url = URL(string: urlString) else {
            throw StreamingError.invalidURL(urlString)
        }
        let response = try await fetchSourceResponse(from: url)
        return response.sources
    }

    func sourcesForEpisode(seriesId: Int, season: Int, episode: Int) async throws -> [OMSSSource] {
        let urlString = "\(baseURL)/v1/tv/\(seriesId)/seasons/\(season)/episodes/\(episode)"
        guard let url = URL(string: urlString) else {
            throw StreamingError.invalidURL(urlString)
        }
        let response = try await fetchSourceResponse(from: url)
        return response.sources
    }

    private func fetchSourceResponse(from url: URL) async throws -> OMSSSourceResponse {
        let cacheKey = url.absoluteString
        if let entry = sourceResponseCache[cacheKey], entry.expiresAt > Date() {
            return entry.response
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw StreamingError.invalidResponse
        }

        if httpResponse.statusCode == 404 {
            let errorBody = try? JSONDecoder().decode(OMSSErrorResponse.self, from: data)
            let msg = errorBody?.error?.message ?? "No sources found"
            throw StreamingError.noSourcesAvailable(msg)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw StreamingError.serverError(statusCode: httpResponse.statusCode)
        }

        do {
            let decoded = try JSONDecoder().decode(OMSSSourceResponse.self, from: data)
            sourceResponseCache[cacheKey] = CachedOMSSResponse(
                response: decoded,
                expiresAt: Date().addingTimeInterval(sourceResponseCacheTTL)
            )
            return decoded
        } catch {
            throw StreamingError.decodeFailed(error)
        }
    }

    /// Returns playable URLs (stable quality first: prefer 1080p over 4K) and the top source's quality string.
    private func sortedPlayableURLsAndQuality(from response: OMSSSourceResponse) -> ([URL], String?) {
        let playable = response.sources.filter { $0.isPlayable }
        let sorted = playable.sorted { a, b in
            if a.playbackPreferenceRank != b.playbackPreferenceRank {
                return a.playbackPreferenceRank > b.playbackPreferenceRank
            }
            if a.isHLS != b.isHLS {
                return a.isHLS
            }
            return a.hasEnglishAudio && !b.hasEnglishAudio
        }
        let bestQuality = sorted.first?.quality
        let result = sorted.compactMap { source -> URL? in
            let proxyPath = source.url
            let urlString: String
            if proxyPath.hasPrefix("http") {
                urlString = proxyPath
            } else {
                urlString = proxyPath.hasPrefix("/") ? "\(baseURL)\(proxyPath)" : "\(baseURL)/\(proxyPath)"
            }
            guard let url = URL(string: urlString) else { return nil }
            return rewriteLocalhostToBaseHost(url)
        }
        return (result, bestQuality)
    }

    /// Builds a playable URL for a single source (for stream picker selection).
    func playableURL(for source: OMSSSource) -> URL? {
        let proxyPath = source.url
        let urlString: String
        if proxyPath.hasPrefix("http") {
            urlString = proxyPath
        } else {
            urlString = proxyPath.hasPrefix("/") ? "\(baseURL)\(proxyPath)" : "\(baseURL)/\(proxyPath)"
        }
        guard let url = URL(string: urlString) else { return nil }
        return rewriteLocalhostToBaseHost(url)
    }

    /// Rewrites localhost/127.0.0.1 in proxy URLs so clients reach the same host as `baseURL` (Mac, LAN IP, or HTTPS deploy).
    private func rewriteLocalhostToBaseHost(_ url: URL) -> URL {
        guard url.host == "localhost" || url.host == "127.0.0.1",
              let base = URL(string: baseURL), let baseHost = base.host else {
            return url
        }
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        comps?.host = baseHost
        comps?.scheme = base.scheme ?? "http"
        // Only use an explicit port when `baseURL` has one (e.g. http://192.168.x.x:3000).
        // For https://host (implicit 443), `base.port` is nil — do not default to 3000 or AVPlayer uses the wrong port.
        comps?.port = base.port
        let rewritten = comps?.url ?? url
        return rewritten
    }
}

// MARK: - Errors

enum StreamingError: LocalizedError {
    case invalidURL(String)
    case invalidResponse
    case noSourcesAvailable(String)
    case serverError(statusCode: Int)
    case decodeFailed(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url): return "Invalid URL: \(url)"
        case .invalidResponse: return "Invalid response from streaming server"
        case .noSourcesAvailable(let msg): return msg
        case .serverError(let code): return "Streaming server error (\(code))"
        case .decodeFailed(let e): return "Failed to parse response: \(e.localizedDescription)"
        }
    }
}

/// OMSS error response structure
private struct OMSSErrorResponse: Decodable {
    let error: OMSSErrorObject?
}

private struct OMSSErrorObject: Decodable {
    let message: String?
}

/// Messages for SwiftUI when OMSS playback resolution fails (network, decode, no sources).
func userFacingStreamingErrorMessage(for error: Error) -> String {
    if error is CancellationError { return "" }
    if let urlError = error as? URLError, urlError.code == .cancelled { return "" }
    let nsError = error as NSError
    if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return "" }
    if nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError { return "" }
    let desc = error.localizedDescription.lowercased()
    if desc.contains("cancelled") || desc.contains("canceled") { return "" }

    if let streaming = error as? StreamingError {
        return streaming.errorDescription ?? "Could not load streams"
    }
    return error.localizedDescription
}
