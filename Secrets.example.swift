//
//  Secrets.example.swift
//  Copy this file to SigmaStream/Core/Secrets.swift and add your API key.
//  Get a free TMDb API key at https://www.themoviedb.org/documentation/api
//

import Foundation

enum Secrets {
    static let tmdbApiKey = "YOUR_TMDB_API_KEY"

    /// CinePro Core base URL. Use your Mac's LAN IP (e.g. http://192.168.1.5:3000), not localhost.
    /// Required for both tvOS Simulator and physical Apple TV. Find IP: ipconfig getifaddr en0
    static let streamingServerBaseURL = "http://YOUR_MAC_IP:3000"
}
