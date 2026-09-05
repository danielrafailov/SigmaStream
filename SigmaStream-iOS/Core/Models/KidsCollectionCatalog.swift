//
//  KidsCollectionCatalog.swift
//  SigmaStream
//
//  Curated TMDb movie collection IDs strictly tailored for Sigma Kids.
//  Contains only G and PG rated animated and family franchises.
//

import Foundation
import TMDb

/// Browse categories for Sigma Kids franchises & animated worlds.
enum KidsCollectionCategory: String, CaseIterable, Identifiable {
    case pixarDisney = "Pixar & Disney Magic"
    case dreamworksIllumination = "DreamWorks & Illumination"
    case animatedSuperheroes = "Animated Superheroes"
    case magicalAdventures = "Magical Adventures"
    case funAndLaughs = "Fun & Laughs"
    case familyClassics = "Family Movie Night"

    var id: String { rawValue }

    var collections: [CuratedMovieCollection] {
        switch self {
        case .pixarDisney:
            return [
                CuratedMovieCollection(id: 10194, title: "Toy Story"),
                CuratedMovieCollection(id: 93452, title: "Inside Out"),
                CuratedMovieCollection(id: 386382, title: "Frozen"),
                CuratedMovieCollection(id: 8354, title: "Cars"),
                CuratedMovieCollection(id: 87118, title: "Finding Nemo & Dory"),
                CuratedMovieCollection(id: 468552, title: "The Incredibles"),
                CuratedMovieCollection(id: 8097, title: "Monsters, Inc."),
                CuratedMovieCollection(id: 8352, title: "The Lion King"),
                CuratedMovieCollection(id: 10681, title: "WALL-E"),
                CuratedMovieCollection(id: 269149, title: "Zootopia"),
                CuratedMovieCollection(id: 1241982, title: "Moana")
            ]
        case .dreamworksIllumination:
            return [
                CuratedMovieCollection(id: 86504, title: "Despicable Me & Minions"),
                CuratedMovieCollection(id: 77816, title: "Kung Fu Panda"),
                CuratedMovieCollection(id: 215, title: "Shrek"),
                CuratedMovieCollection(id: 86512, title: "How to Train Your Dragon"),
                CuratedMovieCollection(id: 135427, title: "Madagascar"),
                CuratedMovieCollection(id: 96878, title: "Hotel Transylvania"),
                CuratedMovieCollection(id: 9485, title: "The Secret Life of Pets"),
                CuratedMovieCollection(id: 391851, title: "Sing"),
                CuratedMovieCollection(id: 334346, title: "The Boss Baby"),
                CuratedMovieCollection(id: 396011, title: "Trolls"),
                CuratedMovieCollection(id: 1565, title: "Ice Age")
            ]
        case .animatedSuperheroes:
            return [
                CuratedMovieCollection(id: 573436, title: "Spider-Man: Spider-Verse"),
                CuratedMovieCollection(id: 37312, title: "The Lego Movie & Lego Batman"),
                CuratedMovieCollection(id: 468552, title: "The Incredibles"),
                CuratedMovieCollection(id: 1058342, title: "Teenage Mutant Ninja Turtles"),
                CuratedMovieCollection(id: 427776, title: "Megamind"),
                CuratedMovieCollection(id: 390161, title: "Big Hero 6")
            ]
        case .magicalAdventures:
            return [
                CuratedMovieCollection(id: 1241, title: "Harry Potter"),
                CuratedMovieCollection(id: 121938, title: "The Chronicles of Narnia"),
                CuratedMovieCollection(id: 338908, title: "Paddington"),
                CuratedMovieCollection(id: 722956, title: "Sonic the Hedgehog"),
                CuratedMovieCollection(id: 495037, title: "The Super Mario Bros. Movie"),
                CuratedMovieCollection(id: 10543, title: "Spy Kids"),
                CuratedMovieCollection(id: 1184918, title: "The Wild Robot")
            ]
        case .funAndLaughs:
            return [
                CuratedMovieCollection(id: 2163, title: "SpongeBob SquarePants"),
                CuratedMovieCollection(id: 9888, title: "Home Alone"),
                CuratedMovieCollection(id: 85943, title: "Night at the Museum"),
                CuratedMovieCollection(id: 10761, title: "Alvin and the Chipmunks"),
                CuratedMovieCollection(id: 79148, title: "The Muppets"),
                CuratedMovieCollection(id: 44342, title: "Scooby-Doo"),
                CuratedMovieCollection(id: 111166, title: "Garfield"),
                CuratedMovieCollection(id: 938, title: "Stuart Little"),
                CuratedMovieCollection(id: 2884, title: "Diary of a Wimpy Kid")
            ]
        case .familyClassics:
            return [
                CuratedMovieCollection(id: 10228, title: "Mary Poppins"),
                CuratedMovieCollection(id: 9530, title: "Willy Wonka & Charlie and the Chocolate Factory"),
                CuratedMovieCollection(id: 135431, title: "The Karate Kid"),
                CuratedMovieCollection(id: 9686, title: "Space Jam"),
                CuratedMovieCollection(id: 10286, title: "Dr. Seuss Movies"),
                CuratedMovieCollection(id: 10452, title: "Honey, I Shrunk the Kids"),
                CuratedMovieCollection(id: 10651, title: "The Parent Trap")
            ]
        }
    }
}

