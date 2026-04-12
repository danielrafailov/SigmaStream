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

    /// Fire-and-forget GETs so responses populate `URLCache` (used by `AsyncImage`).
    static func prefetch(urls: [URL]) {
        for url in urls {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            session.dataTask(with: request) { _, _, _ in }.resume()
        }
    }
}
