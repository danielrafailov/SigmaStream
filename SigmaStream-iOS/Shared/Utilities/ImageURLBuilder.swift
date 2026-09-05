//
//  ImageURLBuilder.swift
//  SigmaStream
//
//  Created by Daniel Rafailov on 2026-03-16.
//

import Foundation
import TMDb

/// Helper for building TMDb image URLs from API configuration.
enum ImageURLBuilder {

    /// Shelves rarely need assets wider than TMDb’s `w780` profile; caps decode size and bandwidth.
    static let shelfBackdropIdealWidthCap = 780
    /// Focused poster bump without requesting oversized stills.
    static let shelfPosterFocusedIdealWidth = 400

    static func clampedIdealWidth(_ requested: Int, cap: Int) -> Int {
        min(max(1, requested), cap)
    }

    private static let fallbackBaseURL = "https://image.tmdb.org/t/p/"

    /// Build poster URL for a given path and configuration.
    /// Falls back to TMDb's standard image CDN if config is nil.
    static func posterURL(
        for path: URL?,
        config: APIConfiguration?,
        idealWidth: Int = 500
    ) -> URL? {
        guard let path else { return nil }
        if let config, let url = config.images.posterURL(for: path, idealWidth: idealWidth) {
            return url
        }
        let size = idealWidth <= 185 ? "w185" : (idealWidth <= 342 ? "w342" : (idealWidth <= 500 ? "w500" : "w780"))
        let cleanPath = path.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "\(fallbackBaseURL)\(size)/\(cleanPath)")
    }

    /// Build backdrop URL for a given path and configuration.
    /// Falls back to TMDb's standard image CDN if config is nil.
    static func backdropURL(
        for path: URL?,
        config: APIConfiguration?,
        idealWidth: Int = 1280
    ) -> URL? {
        guard let path else { return nil }
        if let config, let url = config.images.backdropURL(for: path, idealWidth: idealWidth) {
            return url
        }
        let size = idealWidth <= 300 ? "w300" : (idealWidth <= 780 ? "w780" : "w1280")
        let cleanPath = path.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "\(fallbackBaseURL)\(size)/\(cleanPath)")
    }

    /// Build still image URL for episode thumbnails. Uses same CDN as backdrops.
    static func stillURL(
        for path: URL?,
        config: APIConfiguration?,
        idealWidth: Int = 400
    ) -> URL? {
        guard let path else { return nil }
        if let config, let url = config.images.backdropURL(for: path, idealWidth: idealWidth) {
            return url
        }
        let size = idealWidth <= 300 ? "w300" : "original"
        let cleanPath = path.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "\(fallbackBaseURL)\(size)/\(cleanPath)")
    }

    /// Build profile URL for cast/crew photos.
    static func profileURL(
        for path: URL?,
        config: APIConfiguration?,
        idealWidth: Int = 185
    ) -> URL? {
        guard let path else { return nil }
        if let config, let url = config.images.posterURL(for: path, idealWidth: idealWidth) {
            return url
        }
        let size = idealWidth <= 185 ? "w185" : "h632"
        let cleanPath = path.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "\(fallbackBaseURL)\(size)/\(cleanPath)")
    }
}
