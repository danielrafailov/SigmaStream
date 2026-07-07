//
//  TVEpisode+Released.swift
//  SigmaStream
//

import Foundation
import TMDb

enum TVEpisodeFilter {
    /// Episodes TMDb lists before release often use a placeholder title, no still, and no overview.
    static func isReleased(_ episode: TVEpisode, now: Date = Date()) -> Bool {
        if isFutureAirDate(episode.airDate, now: now) { return false }

        let hasPoster = episode.stillPath != nil
        let hasDescription = hasMeaningfulOverview(episode.overview)
        let genericName = isGenericEpisodeName(episode.name, episodeNumber: episode.episodeNumber)

        if genericName && !hasPoster && !hasDescription { return false }

        return true
    }

    static func releasedEpisodes(from episodes: [TVEpisode]?) -> [TVEpisode] {
        episodes?.filter { isReleased($0) } ?? []
    }

    private static func isFutureAirDate(_ airDate: Date?, now: Date) -> Bool {
        guard let airDate else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let today = calendar.startOfDay(for: now)
        return calendar.startOfDay(for: airDate) > today
    }

    private static func hasMeaningfulOverview(_ overview: String?) -> Bool {
        guard let overview else { return false }
        let trimmed = overview.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        let lower = trimmed.lowercased()
        if lower == "tba" || lower == "to be announced" { return false }
        return true
    }

    private static func isGenericEpisodeName(_ name: String, episodeNumber: Int) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }

        let lower = trimmed.lowercased()
        if lower == "tba" || lower == "to be announced" { return true }
        if trimmed == "Episode \(episodeNumber)" { return true }

        let pattern = "^Episode\\s+\\d+\\s*$"
        if trimmed.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }

        return false
    }
}

extension TVSeason {
    func filteringUnreleasedEpisodes() -> TVSeason {
        let filtered = TVEpisodeFilter.releasedEpisodes(from: episodes)
        guard let episodes, filtered.count != episodes.count else { return self }
        return TVSeason(
            id: id,
            name: name,
            seasonNumber: seasonNumber,
            overview: overview,
            airDate: airDate,
            posterPath: posterPath,
            episodes: filtered.isEmpty ? nil : filtered
        )
    }
}
