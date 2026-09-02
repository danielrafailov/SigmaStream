//
//  MovieCollectionCatalog.swift
//  SigmaStream
//
//  Curated TMDb movie collection IDs grouped for the Collections tab.
//  IDs verified via TMDb `/collection/{id}` (invalid entries omitted from the app).
//

import Foundation
import TMDb

/// Loaded metadata for a collection card (poster + title).
struct MovieCollectionSummary: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let posterPath: URL?
    let backdropPath: URL?
    let overview: String?

    init(id: Int, title: String, posterPath: URL?, backdropPath: URL?, overview: String? = nil) {
        self.id = id
        self.title = title
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.overview = overview
    }
}

/// Full collection with movies in release order.
struct MovieCollectionDetail: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let overview: String
    let posterPath: URL?
    let backdropPath: URL?
    let movies: [MovieListItem]
}

/// A franchise / series on TMDb (`/collection/{id}`).
struct CuratedMovieCollection: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    /// TMDb movie IDs to include when missing from the API collection payload.
    let additionalMovieIds: [Int]

    init(id: Int, title: String, additionalMovieIds: [Int] = []) {
        self.id = id
        self.title = title
        self.additionalMovieIds = additionalMovieIds
    }
}

/// Strips TMDb suffixes like " Collection" for on-screen titles.
enum MovieCollectionDisplay {
    static func title(apiName: String, curatedTitle: String) -> String {
        if !curatedTitle.isEmpty { return curatedTitle }
        return stripCollectionSuffixes(from: apiName)
    }

    static func stripCollectionSuffixes(from name: String) -> String {
        var result = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffixes = [
            " Moviefilms Collection",
            " Collection",
            " Universe",
            " Saga",
            " Trilogy"
        ]
        var changed = true
        while changed {
            changed = false
            for suffix in suffixes {
                if result.hasSuffix(suffix) {
                    result = String(result.dropLast(suffix.count))
                    changed = true
                    break
                }
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Browse buckets for movie franchises (curated; not from a TMDb API).
enum MovieCollectionCategory: String, CaseIterable, Identifiable {
    case action = "Action Franchises"
    case horror = "Horror Franchises"
    case comedy = "Comedy Franchises"
    case sciFi = "Sci-Fi Franchises"
    case superhero = "Superhero"
    case animationFamily = "Animation & Family"
    case fantasy = "Fantasy & Epic"
    case adventure = "Adventure"
    case crimeThriller = "Crime & Thriller"

    var id: String { rawValue }

    var collections: [CuratedMovieCollection] {
        switch self {
        case .action:
            return [
                CuratedMovieCollection(id: 645, title: "James Bond"),
                CuratedMovieCollection(id: 87359, title: "Mission: Impossible"),
                CuratedMovieCollection(id: 9485, title: "Fast & Furious"),
                CuratedMovieCollection(id: 404609, title: "John Wick"),
                CuratedMovieCollection(id: 31562, title: "Bourne"),
                CuratedMovieCollection(id: 84, title: "Indiana Jones"),
                CuratedMovieCollection(id: 1570, title: "Die Hard"),
                CuratedMovieCollection(id: 5039, title: "Rambo"),
                CuratedMovieCollection(id: 528, title: "Terminator"),
                CuratedMovieCollection(id: 8945, title: "Mad Max"),
                CuratedMovieCollection(id: 295, title: "Pirates of the Caribbean"),
                CuratedMovieCollection(id: 1069584, title: "Gladiator"),
                CuratedMovieCollection(id: 945, title: "Lethal Weapon"),
                CuratedMovieCollection(id: 8650, title: "Transformers"),
                CuratedMovieCollection(id: 1733, title: "The Mummy"),
                CuratedMovieCollection(id: 86055, title: "Men in Black"),
                CuratedMovieCollection(id: 304, title: "Ocean's"),
                CuratedMovieCollection(id: 126125, title: "The Expendables"),
                CuratedMovieCollection(id: 9518, title: "The Transporter"),
                CuratedMovieCollection(id: 523855, title: "The Equalizer"),
                CuratedMovieCollection(id: 391860, title: "Kingsman"),
                CuratedMovieCollection(id: 14890, title: "Bad Boys"),
                CuratedMovieCollection(id: 85861, title: "Beverly Hills Cop"),
                CuratedMovieCollection(id: 90863, title: "Rush Hour"),
                CuratedMovieCollection(id: 2883, title: "Kill Bill"),
                CuratedMovieCollection(id: 531330, title: "Top Gun"),
                CuratedMovieCollection(id: 535313, title: "Godzilla"),
                CuratedMovieCollection(id: 363369, title: "Pacific Rim"),
                CuratedMovieCollection(id: 125570, title: "300"),
                CuratedMovieCollection(id: 1575, title: "Rocky"),
                CuratedMovieCollection(id: 553717, title: "Creed"),
                CuratedMovieCollection(id: 9338, title: "Police Academy"),
                CuratedMovieCollection(id: 135483, title: "Taken"),
                CuratedMovieCollection(id: 2794, title: "Riddick"),
                CuratedMovieCollection(id: 399, title: "Predator"),
                CuratedMovieCollection(id: 115762, title: "Alien vs. Predator"),
                CuratedMovieCollection(id: 10522, title: "Starship Troopers"),
                CuratedMovieCollection(id: 5547, title: "RoboCop")
            ]
        case .horror:
            return [
                CuratedMovieCollection(id: 2602, title: "Scream"),
                CuratedMovieCollection(id: 91361, title: "Halloween"),
                CuratedMovieCollection(id: 313086, title: "The Conjuring"),
                CuratedMovieCollection(id: 228446, title: "Insidious"),
                CuratedMovieCollection(id: 8091, title: "Alien"),
                CuratedMovieCollection(id: 1960, title: "Evil Dead"),
                CuratedMovieCollection(id: 10455, title: "Child's Play"),
                CuratedMovieCollection(id: 8581, title: "A Nightmare on Elm Street"),
                CuratedMovieCollection(id: 656, title: "Saw"),
                CuratedMovieCollection(id: 33514, title: "Twilight"),
                CuratedMovieCollection(id: 9735, title: "Friday the 13th"),
                CuratedMovieCollection(id: 8864, title: "Final Destination"),
                CuratedMovieCollection(id: 41437, title: "Paranormal Activity"),
                CuratedMovieCollection(id: 8917, title: "Hellraiser"),
                CuratedMovieCollection(id: 12263, title: "The Exorcist"),
                CuratedMovieCollection(id: 10789, title: "Pet Sematary"),
                CuratedMovieCollection(id: 402074, title: "Annabelle"),
                CuratedMovieCollection(id: 357173, title: "Sinister"),
                CuratedMovieCollection(id: 3601, title: "I Know What You Did Last Summer"),
                CuratedMovieCollection(id: 14563, title: "The Ring"),
                CuratedMovieCollection(id: 1974, title: "The Grudge"),
                CuratedMovieCollection(id: 94899, title: "Jeepers Creepers"),
                CuratedMovieCollection(id: 52985, title: "Wrong Turn"),
                CuratedMovieCollection(id: 86578, title: "Hostel"),
                CuratedMovieCollection(id: 10919, title: "The Omen"),
                CuratedMovieCollection(id: 10453, title: "Poltergeist"),
                CuratedMovieCollection(id: 17255, title: "Resident Evil"),
                CuratedMovieCollection(id: 2326, title: "Underworld"),
                CuratedMovieCollection(id: 735, title: "Blade"),
                CuratedMovieCollection(id: 17235, title: "Hellboy"),
                CuratedMovieCollection(id: 64750, title: "Blair Witch"),
                CuratedMovieCollection(id: 64748, title: "Silent Hill")
            ]
        case .comedy:
            return [
                CuratedMovieCollection(id: 86119, title: "The Hangover"),
                CuratedMovieCollection(id: 2806, title: "American Pie"),
                CuratedMovieCollection(id: 93791, title: "Anchorman"),
                CuratedMovieCollection(id: 212562, title: "Jump Street"),
                CuratedMovieCollection(id: 1006, title: "Austin Powers"),
                CuratedMovieCollection(id: 4246, title: "Scary Movie"),
                CuratedMovieCollection(id: 306031, title: "Pitch Perfect"),
                CuratedMovieCollection(id: 37139, title: "Naked Gun"),
                CuratedMovieCollection(id: 747168, title: "Borat"),
                CuratedMovieCollection(id: 8936, title: "Bridget Jones"),
                CuratedMovieCollection(id: 51509, title: "Meet the Parents"),
                CuratedMovieCollection(id: 937, title: "The Pink Panther"),
                CuratedMovieCollection(id: 86117, title: "Johnny English"),
                CuratedMovieCollection(id: 2980, title: "Ghostbusters"),
                CuratedMovieCollection(id: 945475, title: "Beetlejuice"),
                CuratedMovieCollection(id: 9888, title: "Home Alone"),
                CuratedMovieCollection(id: 85943, title: "Night at the Museum")
            ]
        case .sciFi:
            return [
                CuratedMovieCollection(id: 10, title: "Star Wars"),
                CuratedMovieCollection(id: 173710, title: "Planet of the Apes"),
                CuratedMovieCollection(id: 1709, title: "Planet of the Apes (Original)"),
                CuratedMovieCollection(id: 726871, title: "Dune"),
                CuratedMovieCollection(id: 2344, title: "The Matrix"),
                CuratedMovieCollection(id: 115575, title: "Star Trek"),
                CuratedMovieCollection(id: 264, title: "Back to the Future"),
                CuratedMovieCollection(id: 8091, title: "Alien"),
                CuratedMovieCollection(id: 87096, title: "Avatar"),
                CuratedMovieCollection(id: 131635, title: "The Hunger Games"),
                CuratedMovieCollection(id: 295130, title: "The Maze Runner"),
                CuratedMovieCollection(id: 283579, title: "Divergent"),
                CuratedMovieCollection(id: 135416, title: "Prometheus")
            ]
        case .superhero:
            return [
                CuratedMovieCollection(id: 86311, title: "Marvel Cinematic Universe"),
                CuratedMovieCollection(id: 263, title: "The Dark Knight"),
                CuratedMovieCollection(id: 556, title: "Spider-Man"),
                CuratedMovieCollection(id: 531241, title: "Spider-Man (MCU)"),
                CuratedMovieCollection(id: 748, title: "X-Men"),
                CuratedMovieCollection(id: 448150, title: "Deadpool"),
                CuratedMovieCollection(id: 724848, title: "Shazam!"),
                CuratedMovieCollection(id: 131292, title: "Iron Man"),
                CuratedMovieCollection(id: 131295, title: "Captain America"),
                CuratedMovieCollection(id: 131296, title: "Thor"),
                CuratedMovieCollection(id: 284433, title: "Guardians of the Galaxy"),
                CuratedMovieCollection(id: 529892, title: "Black Panther"),
                CuratedMovieCollection(id: 422834, title: "Ant-Man"),
                CuratedMovieCollection(id: 618529, title: "Doctor Strange"),
                CuratedMovieCollection(id: 558216, title: "Venom"),
                CuratedMovieCollection(id: 8537, title: "Superman"),
                CuratedMovieCollection(id: 573693, title: "Aquaman"),
                CuratedMovieCollection(id: 209131, title: "Man of Steel"),
                CuratedMovieCollection(id: 531242, title: "Suicide Squad"),
                CuratedMovieCollection(id: 9744, title: "Fantastic Four"),
                CuratedMovieCollection(id: 735, title: "Blade")
            ]
        case .animationFamily:
            return [
                CuratedMovieCollection(id: 10194, title: "Toy Story"),
                CuratedMovieCollection(id: 386382, title: "Frozen"),
                CuratedMovieCollection(id: 94032, title: "The Lion King"),
                CuratedMovieCollection(id: 1241984, title: "Moana"),
                CuratedMovieCollection(id: 2150, title: "Shrek", additionalMovieIds: [810]),
                CuratedMovieCollection(id: 86066, title: "Despicable Me"),
                CuratedMovieCollection(id: 544669, title: "Minions"),
                CuratedMovieCollection(id: 544670, title: "Sing"),
                CuratedMovieCollection(id: 89137, title: "How to Train Your Dragon"),
                CuratedMovieCollection(id: 77816, title: "Kung Fu Panda"),
                CuratedMovieCollection(id: 137696, title: "Monsters, Inc."),
                CuratedMovieCollection(id: 137697, title: "Finding Nemo"),
                CuratedMovieCollection(id: 468222, title: "The Incredibles"),
                CuratedMovieCollection(id: 404825, title: "Wreck-It Ralph"),
                CuratedMovieCollection(id: 87118, title: "Cars"),
                CuratedMovieCollection(id: 8354, title: "Ice Age"),
                CuratedMovieCollection(id: 14740, title: "Madagascar"),
                CuratedMovieCollection(id: 229932, title: "Rio"),
                CuratedMovieCollection(id: 519457, title: "The Boss Baby"),
                CuratedMovieCollection(id: 86486, title: "Spy Kids"),
                CuratedMovieCollection(id: 86860, title: "Scooby-Doo"),
                CuratedMovieCollection(id: 11716, title: "Addams Family"),
                CuratedMovieCollection(id: 8819, title: "Casper")
            ]
        case .fantasy:
            return [
                CuratedMovieCollection(id: 119, title: "The Lord of the Rings"),
                CuratedMovieCollection(id: 121938, title: "The Hobbit"),
                CuratedMovieCollection(id: 1241, title: "Harry Potter"),
                CuratedMovieCollection(id: 420, title: "The Chronicles of Narnia"),
                CuratedMovieCollection(id: 726871, title: "Dune"),
                CuratedMovieCollection(id: 328, title: "Jurassic Park"),
                CuratedMovieCollection(id: 2467, title: "Tomb Raider"),
                CuratedMovieCollection(id: 751156, title: "Hocus Pocus")
            ]
        case .adventure:
            return [
                CuratedMovieCollection(id: 84, title: "Indiana Jones"),
                CuratedMovieCollection(id: 295, title: "Pirates of the Caribbean"),
                CuratedMovieCollection(id: 495527, title: "Jumanji"),
                CuratedMovieCollection(id: 328, title: "Jurassic Park"),
                CuratedMovieCollection(id: 89151, title: "Gremlins"),
                CuratedMovieCollection(id: 230, title: "The Godfather")
            ]
        case .crimeThriller:
            return [
                CuratedMovieCollection(id: 230, title: "The Godfather"),
                CuratedMovieCollection(id: 9743, title: "Hannibal Lecter"),
                CuratedMovieCollection(id: 2883, title: "Kill Bill"),
                CuratedMovieCollection(id: 135483, title: "Taken"),
                CuratedMovieCollection(id: 523855, title: "The Equalizer"),
                CuratedMovieCollection(id: 304, title: "Ocean's"),
                CuratedMovieCollection(id: 344830, title: "Fifty Shades")
            ]
        }
    }
}
