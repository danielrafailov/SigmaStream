//
//  StreamSource.swift
//  SigmaStream
//
//  OMSS-compliant streaming source models for CinePro Core.
//

import Foundation

/// Response from OMSS /v1/movies/{id} or /v1/tv/{id}/seasons/{s}/episodes/{e}
/// Fields are optional to tolerate CinePro and other backends that may omit some values.
struct OMSSSourceResponse: Decodable {
    let responseId: String?
    let expiresAt: String?
    let sources: [OMSSSource]
    let subtitles: [OMSSubtitle]?
    let diagnostics: [OMSSDiagnostic]?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        responseId = try c.decodeIfPresent(String.self, forKey: .responseId)
        expiresAt = try c.decodeIfPresent(String.self, forKey: .expiresAt)
        sources = try c.decodeIfPresent([OMSSSource].self, forKey: .sources) ?? []
        subtitles = try c.decodeIfPresent([OMSSubtitle].self, forKey: .subtitles)
        diagnostics = try c.decodeIfPresent([OMSSDiagnostic].self, forKey: .diagnostics)
    }

    private enum CodingKeys: String, CodingKey {
        case responseId, expiresAt, sources, subtitles, diagnostics
    }
}

/// A single streaming source (HLS, etc.)
/// id, quality, audioTracks, provider are optional—CinePro may omit them.
struct OMSSSource: Decodable {
    let id: String?
    let url: String
    let type: String
    let quality: String?
    let audioTracks: [OMSSAudioTrack]?
    let provider: OMSSProvider?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        url = try c.decode(String.self, forKey: .url)
        type = try c.decode(String.self, forKey: .type)
        quality = try c.decodeIfPresent(String.self, forKey: .quality)
        audioTracks = try c.decodeIfPresent([OMSSAudioTrack].self, forKey: .audioTracks)
        provider = try c.decodeIfPresent(OMSSProvider.self, forKey: .provider)
    }

    private enum CodingKeys: String, CodingKey {
        case id, url, type, quality, audioTracks, provider
    }
}

/// Subtitle track
struct OMSSubtitle: Decodable {
    let url: String
    let label: String?
    let format: String?
}

struct OMSSAudioTrack: Decodable {
    let language: String?
    let label: String?
}

struct OMSSProvider: Decodable {
    let id: String?
    let name: String?
}

struct OMSSDiagnostic: Decodable {
    let code: String?
    let message: String?
    let severity: String?
}

// MARK: - Quality sorting for source selection

extension OMSSSource {
    /// Absolute quality rank (higher = higher resolution). Used for display / picker ordering.
    var qualityRank: Int {
        switch (quality ?? "unknown").lowercased() {
        case "2160p", "4k": return 5
        case "1080p": return 4
        case "720p": return 3
        case "480p": return 2
        case "360p": return 1
        default: return 0
        }
    }

    /// Auto-play preference: favor stable 1080p/720p over 4K to reduce buffer underruns.
    var playbackPreferenceRank: Int {
        switch (quality ?? "unknown").lowercased() {
        case "1080p": return 6
        case "720p": return 5
        case "2160p", "4k": return 4
        case "480p": return 3
        case "360p": return 2
        default: return 1
        }
    }

    /// Prefer HLS for AVPlayer
    var isHLS: Bool {
        type.lowercased() == "hls"
    }

    /// Types OMSS/Stremio can emit; AVPlayer tries HLS/MP4; DASH MPD sometimes works depending on codecs.
    var isPlayable: Bool {
        let t = type.lowercased()
        if t == "hls" || t == "mp4" || t == "dash" { return true }
        let u = url.lowercased()
        return u.contains(".m3u8") || u.contains(".mp4") || u.contains(".mpd")
    }

    /// True if any audio track is English (prefer for playback)
    var hasEnglishAudio: Bool {
        guard let tracks = audioTracks, !tracks.isEmpty else { return false }
        let englishCodes = ["eng", "en", "english"]
        return tracks.contains { track in
            let lang = (track.language ?? "").lowercased()
            let label = (track.label ?? "").lowercased()
            return englishCodes.contains(lang) || label.contains("english")
        }
    }
}
