//
//  KidsConfig.swift
//  SigmaStream
//
//  Defines age-appropriate safety boundaries, certification allowlists,
//  and genre mappings for Sigma Kids.
//

import Foundation
import TMDb

enum KidsConfig {
    #if SIGMA_KIDS
    static var isKidsEdition: Bool {
        get { true }
        set { }
    }
    #else
    private static var _isKidsOverride: Bool? = nil

    static var isKidsEdition: Bool {
        get {
            if let override = _isKidsOverride {
                return override
            }
            if ProcessInfo.processInfo.arguments.contains("-KidsMode") || ProcessInfo.processInfo.environment["SIGMA_KIDS"] == "1" {
                return true
            }
            return UserDefaults.standard.bool(forKey: "isKidsEdition")
        }
        set {
            _isKidsOverride = newValue
            UserDefaults.standard.set(newValue, forKey: "isKidsEdition")
        }
    }

    static func setKidsEdition(_ enabled: Bool) {
        isKidsEdition = enabled
    }
    #endif

    /// Allowed movie certifications (US Rating System)
    static let allowedMovieCertifications: Set<String> = [
        "G",
        "PG"
    ]

    /// Allowed TV content ratings (US Rating System)
    static let allowedTVCertifications: Set<String> = [
        "TV-Y",
        "TV-Y7",
        "TV-G",
        "TV-PG"
    ]

    /// Explicitly blocked movie certifications
    static let blockedMovieCertifications: Set<String> = [
        "PG-13",
        "R",
        "NC-17",
        "NR",
        "UR"
    ]

    /// Explicitly blocked TV ratings
    static let blockedTVCertifications: Set<String> = [
        "TV-14",
        "TV-MA"
    ]

    /// Kid-friendly TMDb Genre IDs
    enum GenreID {
        static let animation = 16
        static let family = 10751
        static let kidsTV = 10762
        static let adventure = 12
        static let comedy = 35
        static let fantasy = 14
        static let sciFi = 878
    }

    /// Blocked mature TMDb Genre IDs (Horror, Crime, Thriller, War)
    static let blockedGenreIDs: Set<Int> = [
        27,    // Horror
        80,    // Crime
        53,    // Thriller
        10752, // War
        10768  // War & Politics
    ]

    /// Required genre IDs for movies in Kids mode (Must be Animation or Family)
    static let requiredMovieGenreIDs: Set<Int> = [
        GenreID.animation, // 16
        GenreID.family     // 10751
    ]

    /// Required genre IDs for TV shows in Kids mode (Must be Animation, Family, or Kids TV)
    static let requiredTVGenreIDs: Set<Int> = [
        GenreID.animation, // 16
        GenreID.family,    // 10751
        GenreID.kidsTV     // 10762
    ]

    /// Curated list of high-profile, universally loved Kids movie TMDB IDs for the Hero Carousel
    static let heroCarouselKidsMovieIDs: [Int] = [
        1241982, // Moana 2
        519182,  // Despicable Me 4
        1022789, // Inside Out 2
        1011985, // Kung Fu Panda 4
        502356,  // The Super Mario Bros. Movie
        569094,  // Spider-Man: Across the Spider-Verse
        1184918, // The Wild Robot
        438148,  // Minions: The Rise of Gru
        585083,  // Hotel Transylvania: Transformania
        12,      // Finding Nemo
        862,     // Toy Story
        10681,   // WALL-E
        269149,  // Zootopia
        109445   // Frozen
    ]

    /// Checks if a movie's genre list contains any blocked mature genres or lacks required kid genres
    static func isMovieGenreAllowed(genreIds: [Int]?) -> Bool {
        guard let genreIds, !genreIds.isEmpty else { return false }
        if genreIds.contains(where: { blockedGenreIDs.contains($0) }) {
            return false
        }
        return genreIds.contains(where: { requiredMovieGenreIDs.contains($0) })
    }

    /// Checks if a TV series genre list contains any blocked mature genres or lacks required kid genres
    static func isTVGenreAllowed(genreIds: [Int]?) -> Bool {
        guard let genreIds, !genreIds.isEmpty else { return false }
        if genreIds.contains(where: { blockedGenreIDs.contains($0) }) {
            return false
        }
        return genreIds.contains(where: { requiredTVGenreIDs.contains($0) })
    }

    /// Checks if a title or overview contains adult keywords, mature franchises, or inappropriate content
    static func containsInappropriateKeywords(text: String?) -> Bool {
        guard let rawText = text?.lowercased(), !rawText.isEmpty else { return false }
        let text = " " + rawText + " "
        let matureKeywords = [
            "erotic", "sex", "nude", "nudity", "porn", "gore", "slasher",
            "horror", "murderer", "psychopath", "massacre", "bloody", "cartel",
            "drug cartel", "terrorist", "prostitution", "explicit", "deadpool",
            "jackass", "saw", "scream", "chucky", "halloween", "evil dead",
            "terrifier", "alien", "predator", "john wick", "rambo", "terminator",
            "die hard", "bad boys", "the boys", "game of thrones", "house of the dragon",
            "breaking bad", "dexter", "walking dead", "fargo", "sopranos", "godfather",
            "fifty shades", "ted", "borat", "sausage party", "south park", "rick and morty",
            "family guy", "big mouth", "invincible", "harley quinn", "spawn", "blade",
            "punisher", "kill bill", "sin city", "hellraiser", "exorcist", "conjuring",
            "annabelle", "insidious", "purge", "hostel", "friday the 13th", "nightmare on elm street",
            "odyssey", "gladiator", "mad max", "the equalizer", "kingsman", "taken",
            "robocop", "starship troopers", "beverly hills cop", "the hangover", "american pie"
        ]
        return matureKeywords.contains { kw in
            rawText.contains(kw)
        }
    }
}
