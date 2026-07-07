//
//  TVSeries+PlayableSeasons.swift
//  SigmaStream
//

import TMDb

extension TVSeries {
    /// Season numbers for playback UI (excludes season 0 specials).
    var playableSeasonNumbers: [Int] {
        if let seasons, !seasons.isEmpty {
            return seasons.map(\.seasonNumber).filter { $0 > 0 }.sorted()
        }
        if let numberOfSeasons, numberOfSeasons > 0 {
            return Array(1...numberOfSeasons)
        }
        return [1]
    }

    var defaultPlayableSeason: Int {
        playableSeasonNumbers.first ?? 1
    }
}
