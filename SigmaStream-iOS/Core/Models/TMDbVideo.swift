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

    /// YouTube embed URL for playback
    var youtubeEmbedURL: URL? {
        guard site.lowercased() == "youtube" else { return nil }
        return URL(string: "https://www.youtube.com/embed/\(key)?playsinline=1&autoplay=1")
    }
}
