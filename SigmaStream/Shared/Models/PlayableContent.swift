//
//  PlayableContent.swift
//  SigmaStream
//
//  Identifiable wrapper for presenting video player with URL and title.
//

import Foundation

struct PlayableContent: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
}
