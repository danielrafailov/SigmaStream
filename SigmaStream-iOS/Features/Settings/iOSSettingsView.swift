//
//  iOSSettingsView.swift
//  SigmaStream-iOS
//
//  Created by Daniel Rafailov on 2026-09-01.
//

import SwiftUI

#if os(iOS)
struct iOSSettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var serverStatus = "Checking..."
    @State private var isServerOnline = false
    @State private var showingClearHistoryAlert = false

    var body: some View {
        NavigationStack {
            Form {
                // Streaming Backend Section
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("CinePro Backend")
                                .font(.body.bold())
                            Text(Secrets.streamingServerBaseURL)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        HStack(spacing: 6) {
                            Circle()
                                .fill(isServerOnline ? Color.green : Color.red)
                                .frame(width: 10, height: 10)
                            Text(isServerOnline ? "Online" : "Offline")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button("Check Backend Status") {
                        Task { await checkServer() }
                    }
                } header: {
                    Text("Streaming Server")
                } footer: {
                    Text("The local CinePro backend aggregates 14 streaming sources and manages the high-speed RAM mega-buffer.")
                }

                // Storage & Playback Section
                Section("Playback & Data") {
                    Button(role: .destructive) {
                        showingClearHistoryAlert = true
                    } label: {
                        Text("Clear Watch History")
                    }
                }

                // About Section
                Section("About") {
                    HStack {
                        Text("App Version")
                        Spacer()
                        Text("1.0.0 (iOS)")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Platform")
                        Spacer()
                        Text(UIDevice.current.userInterfaceIdiom == .pad ? "iPadOS" : "iOS")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .task {
                await checkServer()
            }
            .alert("Clear Watch History?", isPresented: $showingClearHistoryAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) {
                    appState.watchProgressManager.clearAllHistory()
                }
            } message: {
                Text("This will remove resume playback progress for all movies and TV shows.")
            }
        }
    }

    private func checkServer() async {
        guard let url = URL(string: "\(Secrets.streamingServerBaseURL)/v1/health") else { return }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 3
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                await MainActor.run {
                    isServerOnline = true
                    serverStatus = "Online"
                }
            } else {
                await MainActor.run {
                    isServerOnline = false
                    serverStatus = "Offline"
                }
            }
        } catch {
            await MainActor.run {
                isServerOnline = false
                serverStatus = "Offline"
            }
        }
    }
}
#endif
