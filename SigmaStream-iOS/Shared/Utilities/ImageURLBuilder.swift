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

    /// Build poster URL for a given path and configuration.
    /// Returns nil if config or path is nil.
    static func posterURL(
        for path: URL?,
        config: APIConfiguration?,
        idealWidth: Int = 500
    ) -> URL? {
        guard let config else { return nil }
        return config.images.posterURL(for: path, idealWidth: idealWidth)
    }

    /// Build backdrop URL for a given path and configuration.
    /// Returns nil if config or path is nil.
    static func backdropURL(
        for path: URL?,
        config: APIConfiguration?,
        idealWidth: Int = 1280
    ) -> URL? {
        guard let config else { return nil }
        return config.images.backdropURL(for: path, idealWidth: idealWidth)
    }

    /// Build still image URL for episode thumbnails. Uses same CDN as backdrops.
    static func stillURL(
        for path: URL?,
        config: APIConfiguration?,
        idealWidth: Int = 400
    ) -> URL? {
        guard let config else { return nil }
        return config.images.backdropURL(for: path, idealWidth: idealWidth)
    }

    /// Build profile URL for cast/crew photos.
    static func profileURL(
        for path: URL?,
        config: APIConfiguration?,
        idealWidth: Int = 185
    ) -> URL? {
        guard let config else { return nil }
        return config.images.posterURL(for: path, idealWidth: idealWidth)
    }
}
