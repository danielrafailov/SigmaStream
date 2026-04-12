//
//  ImagePrefetcher.swift
//  SigmaStream
//
//  Warms URLCache for poster/backdrop URLs so focus transitions hit disk/memory first.
//

import Foundation

enum ImagePrefetcher {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache.shared
        config.httpMaximumConnectionsPerHost = 6
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

    /// Fire-and-forget GETs so responses populate `URLCache` (used by shelf remote image views / system image loads).
    static func prefetch(urls: [URL]) {
        var seen = Set<URL>()
        for url in urls {
            guard seen.insert(url).inserted else { continue }
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            session.dataTask(with: request) { _, _, _ in }.resume()
        }
    }
}
