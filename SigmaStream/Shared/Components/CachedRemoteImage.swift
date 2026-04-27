//
//  CachedRemoteImage.swift
//  SigmaStream
//
//  Non-generic shelf image views (avoids heavy Swift generic metadata + ProgressView/ActivityIndicator churn
//  seen in Time Profiler during hangs). Shared decode/cache path.
//

import ImageIO
import SwiftUI
import UIKit

private enum RemoteImageDecoder: Sendable {
    nonisolated static func uiImage(data: Data, maxPixelSize: Int) -> UIImage? {
        guard maxPixelSize > 0 else { return UIImage(data: data) }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cg)
    }
}

private final class PosterMemoryCache {
    static let shared = PosterMemoryCache()
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 200
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url.absoluteString as NSString)
    }

    func insert(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url.absoluteString as NSString)
    }
}

private func posterMemoryCachedImage(for url: URL) -> UIImage? {
    PosterMemoryCache.shared.image(for: url)
}

private func loadShelfRemoteImage(url: URL, maxPixelSize: Int) async -> UIImage? {
    if let cached = PosterMemoryCache.shared.image(for: url) {
        return cached
    }
    do {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), !data.isEmpty else {
            return nil
        }
        let decoded = await Task.detached(priority: .userInitiated) {
            RemoteImageDecoder.uiImage(data: data, maxPixelSize: maxPixelSize)
        }.value
        guard let decoded else { return nil }
        PosterMemoryCache.shared.insert(decoded, for: url)
        return decoded
    } catch {
        return nil
    }
}

// MARK: - Fixed-shape poster (no ProgressView — avoids UIActivityIndicator churn on main thread)

/// Shelf poster with a static placeholder only (no `ProgressView`).
struct ShelfPosterRemoteImage: View {
    let url: URL
    var maxPixelSize: Int
    var aspectRatio: CGFloat
    var contentMode: ContentMode

    @State private var uiImage: UIImage?

    var body: some View {
        Group {
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(aspectRatio, contentMode: contentMode)
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .aspectRatio(aspectRatio, contentMode: contentMode)
                    .overlay {
                        Image(systemName: "film")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        // Reset image state per URL so LazyVGrid cannot show the wrong title’s pixels when cells recycle.
        .id(url)
        .task(id: url) {
            if let mem = posterMemoryCachedImage(for: url) {
                await MainActor.run { uiImage = mem }
                return
            }
            let img = await loadShelfRemoteImage(url: url, maxPixelSize: maxPixelSize)
            await MainActor.run {
                if let img { uiImage = img }
            }
        }
    }
}

// MARK: - Backdrop (clear empty state; optional fade callback)

/// Focused backdrop: no progress spinner; `onImageReady` runs on main actor when pixels are ready.
struct ShelfBackdropRemoteImage: View {
    let url: URL
    var maxPixelSize: Int
    var onImageReady: (() -> Void)?

    @State private var uiImage: UIImage?

    var body: some View {
        Group {
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(16 / 9, contentMode: .fill)
            } else {
                Color.clear
            }
        }
        .task(id: url.absoluteString) {
            await MainActor.run { uiImage = nil }
            guard let img = await loadShelfRemoteImage(url: url, maxPixelSize: maxPixelSize) else { return }
            await MainActor.run {
                uiImage = img
                onImageReady?()
            }
        }
    }
}
