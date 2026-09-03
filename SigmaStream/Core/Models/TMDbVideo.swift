//
//  TMDbVideo.swift
//  SigmaStream
//
//  TMDb API video/trailer response models.
//

import Foundation

/// Response from TMDb /movie/{id}/videos or /tv/{id}/videos
struct TMDbVideosResponse: Decodable {
    let id: Int?
    let results: [TMDbVideo]?
}

/// A single video (trailer, teaser, etc.)
struct TMDbVideo: Decodable {
    let id: String
    let key: String
    let name: String
    let site: String
    let type: String
    let official: Bool?

    /// YouTube embed URL for playback
    var youtubeEmbedURL: URL? {
        guard site.lowercased() == "youtube" else { return nil }
        return URL(string: "https://www.youtube.com/embed/\(key)?playsinline=1&autoplay=1")
    }

    /// Standard YouTube web URL
    var youtubeWatchURL: URL? {
        guard site.lowercased() == "youtube" else { return nil }
        return URL(string: "https://www.youtube.com/watch?v=\(key)")
    }

    /// Direct deep link to YouTube app
    var youtubeAppURL: URL? {
        guard site.lowercased() == "youtube" else { return nil }
        return URL(string: "youtube://watch?v=\(key)")
    }

    /// YouTube thumbnail URL
    var youtubeThumbnailURL: URL? {
        guard site.lowercased() == "youtube" else { return nil }
        return URL(string: "https://img.youtube.com/vi/\(key)/hqdefault.jpg")
    }
}
