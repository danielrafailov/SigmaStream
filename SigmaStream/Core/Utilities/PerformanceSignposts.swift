//
//  PerformanceSignposts.swift
//  SigmaStream
//
//  OS signposts for Instruments (Points of Interest + os_signpost interval).
//

import os

/// Use **Instruments → Time Profiler** (or **os_signpost**) with the subsystem filter `SigmaStream` / categories `HomeLoad`, `MoviesTabLoad`, `TVTabLoad`, `CatalogDiscover`.
enum PerformanceSignposts: Sendable {
    /// Matches app bundle id so Instruments can filter consistently without touching `Bundle` off the main actor.
    private nonisolated static let subsystem = "com.danielrafailov.SigmaStream"

    nonisolated static let homeLoad = OSLog(subsystem: subsystem, category: "HomeLoad")
    nonisolated static let moviesTabLoad = OSLog(subsystem: subsystem, category: "MoviesTabLoad")
    nonisolated static let tvTabLoad = OSLog(subsystem: subsystem, category: "TVTabLoad")
    nonisolated static let catalogDiscover = OSLog(subsystem: subsystem, category: "CatalogDiscover")

    /// Begin/end interval; visible in Instruments when profiling Points of Interest / signposts.
    nonisolated static func interval<T>(log: OSLog, name: StaticString, _ block: () throws -> T) rethrows -> T {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        defer { os_signpost(.end, log: log, name: name, signpostID: id) }
        return try block()
    }

    nonisolated static func interval<T>(log: OSLog, name: StaticString, _ block: () async throws -> T) async rethrows -> T {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        defer { os_signpost(.end, log: log, name: name, signpostID: id) }
        return try await block()
    }

    nonisolated static func interval<T>(log: OSLog, name: StaticString, _ block: () async -> T) async -> T {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        defer { os_signpost(.end, log: log, name: name, signpostID: id) }
        return await block()
    }
}
