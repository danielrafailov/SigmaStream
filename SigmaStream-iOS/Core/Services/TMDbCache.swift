//
//  TMDbCache.swift
//  SigmaStream
//
//  Disk cache for TMDb API responses with 24-hour TTL.
//  Stores raw JSON Data to avoid TMDb types not conforming to Encodable.
//

import Foundation

/// Disk-backed cache for TMDb API responses. Entries expire after `ttlInterval`.
final class TMDbCache {

    static let shared = TMDbCache()
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let ttlInterval: TimeInterval = 24 * 60 * 60 // 24 hours

    private var cacheDirectory: URL {
        let dir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("TMDbCache", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateString) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(dateString)")
        }
    }

    private func fileURL(for key: String) -> URL {
        let safeKey = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
        return cacheDirectory.appendingPathComponent("\(safeKey).json")
    }

    /// Fetch raw cached Data if not expired. Returns nil if miss or expired.
    func getData(_ key: String) -> Data? {
        let url = fileURL(for: key)
        guard let fileData = try? Data(contentsOf: url) else { return nil }
        guard let entry = try? decoder.decode(DataCacheEntry.self, from: fileData) else { return nil }
        if entry.expiresAt < Date() { return nil }
        return entry.payload
    }

    /// Store raw Data with TTL from now.
    func setData(_ key: String, data: Data) {
        let entry = DataCacheEntry(payload: data, expiresAt: Date().addingTimeInterval(ttlInterval))
        let url = fileURL(for: key)
        try? encoder.encode(entry).write(to: url)
    }

    /// Remove cached Data (e.g. when decode fails).
    func removeData(_ key: String) {
        try? fileManager.removeItem(at: fileURL(for: key))
    }

    /// Clear all cached entries
    func clearAll() {
        try? fileManager.removeItem(at: cacheDirectory)
    }
}

private struct DataCacheEntry: Codable {
    let payloadBase64: String
    let expiresAt: Date

    var payload: Data {
        Data(base64Encoded: payloadBase64) ?? Data()
    }

    init(payload: Data, expiresAt: Date) {
        self.payloadBase64 = payload.base64EncodedString()
        self.expiresAt = expiresAt
    }

    enum CodingKeys: String, CodingKey {
        case payloadBase64 = "payload"
        case expiresAt
    }
}
