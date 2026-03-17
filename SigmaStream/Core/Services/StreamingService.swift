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

    init(baseURL: String) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.session = URLSession.shared
    }

    /// Fetch streaming sources for a movie. Returns the best HLS URL or nil if none.
    func playableURLForMovie(tmdbId: Int) async throws -> URL? {
        let urlString = "\(baseURL)/v1/movies/\(tmdbId)"
        guard let url = URL(string: urlString) else {
            throw StreamingError.invalidURL(urlString)
        }
        let response = try await fetchSourceResponse(from: url)
        return buildPlayableURL(from: response)
    }

    /// Fetch streaming sources for a TV episode.
    func playableURLForEpisode(seriesId: Int, season: Int, episode: Int) async throws -> URL? {
        let urlString = "\(baseURL)/v1/tv/\(seriesId)/seasons/\(season)/episodes/\(episode)"
        guard let url = URL(string: urlString) else {
            throw StreamingError.invalidURL(urlString)
        }
        let response = try await fetchSourceResponse(from: url)
        return buildPlayableURL(from: response)
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
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw StreamingError.invalidResponse
        }

        if httpResponse.statusCode == 404 {
            let errorBody = try? JSONDecoder().decode(OMSSErrorResponse.self, from: data)
            throw StreamingError.noSourcesAvailable(errorBody?.error?.message ?? "No sources found")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw StreamingError.serverError(statusCode: httpResponse.statusCode)
        }

        do {
            return try JSONDecoder().decode(OMSSSourceResponse.self, from: data)
        } catch {
            throw StreamingError.decodeFailed(error)
        }
    }

    private func buildPlayableURL(from response: OMSSSourceResponse) -> URL? {
        // Include both HLS and MP4 (AVPlayer supports both)
        let playable = response.sources.filter { $0.isPlayable }
        let sorted = playable.sorted { a, b in
            if a.qualityRank != b.qualityRank {
                return a.qualityRank > b.qualityRank
            }
            if a.isHLS != b.isHLS {
                return a.isHLS
            }
            return a.hasEnglishAudio && !b.hasEnglishAudio
        }
        guard let best = sorted.first else { return nil }

        let proxyPath = best.url
        var urlString: String
        if proxyPath.hasPrefix("http") {
            urlString = proxyPath
        } else {
            urlString = proxyPath.hasPrefix("/") ? "\(baseURL)\(proxyPath)" : "\(baseURL)/\(proxyPath)"
        }
        guard let url = URL(string: urlString) else { return nil }
        // On physical Apple TV, CinePro returns localhost in URLs; rewrite to Mac's IP from Secrets
        return rewriteLocalhostToBaseHost(url)
    }

    /// Rewrites localhost/127.0.0.1 in proxy URLs so Apple TV can reach the Mac running CinePro.
    private func rewriteLocalhostToBaseHost(_ url: URL) -> URL {
        guard url.host == "localhost" || url.host == "127.0.0.1",
              let base = URL(string: baseURL), let baseHost = base.host else {
            return url
        }
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        comps?.host = baseHost
        comps?.port = base.port ?? 3000
        comps?.scheme = base.scheme ?? "http"
        return comps?.url ?? url
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
