//
//  ConcurrentCatalogDiscoverFetch.swift
//  SigmaStream
//
//  Limits parallel discover/category requests so Home and tabs avoid 30+ simultaneous TMDb calls.
//

import Foundation
import os

enum ConcurrentCatalogDiscoverFetch {
    /// Runs `operation` for each item with at most `maxConcurrent` tasks in flight. Preserves input order in the result.
    static func mapLimited<T: Sendable, R: Sendable>(
        items: [T],
        maxConcurrent: Int = 5,
        log: OSLog = PerformanceSignposts.catalogDiscover,
        name: StaticString = "DiscoverBatch",
        operation: @Sendable @escaping (T) async -> R
    ) async -> [R] {
        guard !items.isEmpty else { return [] }
        let maxC = max(1, maxConcurrent)
        return await PerformanceSignposts.interval(log: log, name: name) {
            await mapLimitedUnlogged(items: items, maxConcurrent: maxC, operation: operation)
        }
    }

    private static func mapLimitedUnlogged<T: Sendable, R: Sendable>(
        items: [T],
        maxConcurrent: Int,
        operation: @Sendable @escaping (T) async -> R
    ) async -> [R] {
        await withTaskGroup(of: (Int, R).self) { group in
            var results: [(Int, R)] = []
            results.reserveCapacity(items.count)
            var nextIndex = 0
            while nextIndex < min(maxConcurrent, items.count) {
                let idx = nextIndex
                nextIndex += 1
                let item = items[idx]
                group.addTask {
                    (idx, await operation(item))
                }
            }
            while let (idx, value) = await group.next() {
                results.append((idx, value))
                if nextIndex < items.count {
                    let i = nextIndex
                    nextIndex += 1
                    let item = items[i]
                    group.addTask {
                        (i, await operation(item))
                    }
                }
            }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }
}
