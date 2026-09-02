import SwiftUI

@main
struct SigmaStream_iOSApp: App {
    @State private var appState = AppState(apiKey: Secrets.tmdbApiKey)

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(appState)
                .preferredColorScheme(.dark)
        }
    }
}
