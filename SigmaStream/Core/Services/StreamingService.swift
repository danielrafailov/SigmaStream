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

    /// Fetch all playable URLs for a movie, sorted by quality. Empty if none.
    func playableURLsForMovie(tmdbId: Int) async throws -> [URL] {
        let urlString = "\(baseURL)/v1/movies/\(tmdbId)"
        guard let url = URL(string: urlString) else {
            throw StreamingError.invalidURL(urlString)
        }
        let response = try await fetchSourceResponse(from: url)
        return sortedPlayableURLs(from: response)
    }

    /// Fetch all playable URLs for a TV episode, sorted by quality. Empty if none.
    func playableURLsForEpisode(seriesId: Int, season: Int, episode: Int) async throws -> [URL] {
        let urlString = "\(baseURL)/v1/tv/\(seriesId)/seasons/\(season)/episodes/\(episode)"
        guard let url = URL(string: urlString) else {
            throw StreamingError.invalidURL(urlString)
        }
        let response = try await fetchSourceResponse(from: url)
        return sortedPlayableURLs(from: response)
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
        #if DEBUG
        print("[StreamingService] Requesting: \(url.absoluteString)")
        #endif

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            #if DEBUG
            print("[StreamingService] Network error for \(url.absoluteString): \(error)")
            #endif
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw StreamingError.invalidResponse
        }

        if httpResponse.statusCode == 404 {
            let errorBody = try? JSONDecoder().decode(OMSSErrorResponse.self, from: data)
            let msg = errorBody?.error?.message ?? "No sources found"
            #if DEBUG
            print("[StreamingService] 404: \(msg)")
            #endif
            throw StreamingError.noSourcesAvailable(msg)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            #if DEBUG
            print("[StreamingService] HTTP \(httpResponse.statusCode) from \(url.absoluteString)")
            #endif
            throw StreamingError.serverError(statusCode: httpResponse.statusCode)
        }

        do {
            return try JSONDecoder().decode(OMSSSourceResponse.self, from: data)
        } catch {
            #if DEBUG
            print("[StreamingService] Decode failed: \(error)")
            #endif
            throw StreamingError.decodeFailed(error)
        }
    }

    /// Returns all playable URLs sorted by quality (best first). Empty if none.
    private func sortedPlayableURLs(from response: OMSSSourceResponse) -> [URL] {
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
        #if DEBUG
        print("[StreamingService] Returning \(result.count) playable URL(s): \(result.map(\.absoluteString))")
        #endif
        return result
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
        let rewritten = comps?.url ?? url
        #if DEBUG
        print("[StreamingService] Rewrote localhost URL to \(rewritten.absoluteString)")
        #endif
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
