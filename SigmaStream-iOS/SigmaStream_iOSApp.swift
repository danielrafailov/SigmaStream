//
//  SigmaStream_iOSApp.swift
//  SigmaStream-iOS
//
//  Created by Daniel Rafailov on 2026-09-01.
//

import SwiftUI
import SwiftData

@main
struct SigmaStream_iOSApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
