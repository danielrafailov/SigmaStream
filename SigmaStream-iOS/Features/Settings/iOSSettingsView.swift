//
//  iOSSettingsView.swift
//  SigmaStream-iOS
//
//  Created by Daniel Rafailov on 2026-09-01.
//

import SwiftUI

#if os(iOS)
struct CelebrityVoice: Identifiable, Hashable {
    let id: String // Voice.ai ID
    let slug: String // Local clone slug
    let name: String
    let icon: String
}

struct iOSSettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var serverStatus = "Checking..."
    @State private var isServerOnline = false
    @State private var showingClearHistoryAlert = false
    @State private var selectedVoiceSlug: String = ""

    private let voices: [CelebrityVoice] = [
        CelebrityVoice(id: "2c61b0ed-c7e4-461d-a6d1-5a4f02fc8278", slug: "arnold_schwarzenegger", name: "Arnold Schwarzenegger", icon: "🏋️‍♂️"),
        CelebrityVoice(id: "c1745484-ba67-4cba-b8f3-19f9bc538f61", slug: "daffy_duck", name: "Daffy Duck", icon: "🦆"),
        CelebrityVoice(id: "40d320d7-558b-4207-b9e9-45772b0ce167", slug: "trump", name: "Donald Trump", icon: "🇺🇸"),
        CelebrityVoice(id: "c8909e12-a6d3-46d3-a4a2-c55b628acae0", slug: "eric_cartman", name: "Eric Cartman", icon: "🧢"),
        CelebrityVoice(id: "280e1b27-a62d-47a3-8840-b7ff288941aa", slug: "gordon_ramsay", name: "Gordon Ramsay", icon: "🍳"),
        CelebrityVoice(id: "6a6d4859-fff1-4405-9f8a-a259768679be", slug: "joe_rogan", name: "Joe Rogan", icon: "🥊"),
        CelebrityVoice(id: "43ce1296-4969-4af6-bdc1-22ef5e347d08", slug: "mandalorian", name: "Mandalorian", icon: "🪐"),
        CelebrityVoice(id: "4aab5641-8f84-404a-be30-1d620d856dee", slug: "michael_jackson", name: "Michael Jackson", icon: "🕺"),
        CelebrityVoice(id: "a0cf2b27-25c9-45b8-a53d-21e7029c5bb1", slug: "morgan_freeman", name: "Morgan Freeman", icon: "🎬"),
        CelebrityVoice(id: "9a7860b8-70f8-461f-b0c7-d005d0b1504c", slug: "snoop_dogg", name: "Snoop Dogg", icon: "🕶️"),
        CelebrityVoice(id: "3caf42ba-3d92-4aed-8fda-1a70a4abd47c", slug: "tom_holland", name: "Tom Holland", icon: "🕷️")
    ]

    var body: some View {
        NavigationStack {
            Form {
                // Parental Controls / Kids Edition Section
                Section {
                    Toggle(isOn: Binding(
                        get: { appState.isKidsMode },
                        set: { appState.isKidsMode = $0 }
                    )) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text("Kids Edition")
                                    .font(.body.bold())
                                if appState.isKidsMode {
                                    Text("ACTIVE")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.black)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.yellow)
                                        .clipShape(Capsule())
                                }
                            }
                            Text("Restricts all movies, TV shows, categories, searches, and AI to G & PG rated family content only.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.orange)
                } header: {
                    Text("Parental Controls")
                } footer: {
                    Text("When active, Deadpool, R-rated, and mature content are completely filtered out.")
                }

                // AI Voice Assistant Section
                Section {
                    ForEach(voices) { voice in
                        let isActive = (selectedVoiceSlug.isEmpty ? appState.voiceService.selectedVoiceSlug : selectedVoiceSlug) == voice.slug

                        HStack(spacing: 14) {
                            Text(voice.icon)
                                .font(.system(size: 28))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(voice.name)
                                    .font(.body.weight(.semibold))
                                Text(isActive ? "Active Assistant Voice" : "Celebrity AI Voice")
                                    .font(.caption)
                                    .foregroundStyle(isActive ? .blue : .secondary)
                            }

                            Spacer()

                            // Sample Button
                            Button {
                                let sampleText = sampleQuote(for: voice.slug, name: voice.name)
                                appState.voiceService.previewVoice(
                                    voiceSlug: voice.slug,
                                    voiceId: voice.id,
                                    sampleText: sampleText
                                )
                            } label: {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.subheadline)
                                    .padding(8)
                                    .background(Color.blue.opacity(0.12))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)

                            // Select / Checkmark Button
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedVoiceSlug = voice.slug
                                    appState.voiceService.selectedVoiceSlug = voice.slug
                                    appState.voiceService.selectedVoiceId = voice.id
                                    appState.voiceService.selectedVoiceName = voice.name
                                }
                            } label: {
                                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(isActive ? .blue : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("AI Voice Assistant")
                } footer: {
                    Text("Select your preferred AI voice personality for movie and TV show recommendations.")
                }

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
                    Text("The CinePro backend aggregates streaming sources and manages high-speed video buffer.")
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
                selectedVoiceSlug = appState.voiceService.selectedVoiceSlug
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

    private func sampleQuote(for slug: String, name: String) -> String {
        switch slug {
        case "trump":
            return "Hello everybody, this is Donald Trump running on SigmaStream."
        case "arnold_schwarzenegger":
            return "I'll be back, with the greatest movie recommendations."
        case "gordon_ramsay":
            return "Listen to me, this movie selection is cooked to perfection."
        case "morgan_freeman":
            return "I can remember when cinema told a truly captivating story."
        case "snoop_dogg":
            return "Drop it like it's hot, ya dig? Welcome to SigmaStream."
        case "joe_rogan":
            return "Have you ever watched a mind-bending sci-fi documentary?"
        case "michael_jackson":
            return "Hee-hee! Just beat it and enjoy this movie tonight."
        case "mandalorian":
            return "This is the way."
        case "eric_cartman":
            return "Respect my authoritah, you guys!"
        case "daffy_duck":
            return "You're despicable! But this show is fantastic."
        case "tom_holland":
            return "Hey everyone, Peter Parker here, ready to pick a show."
        default:
            return "Hello, I am \(name), your AI assistant on SigmaStream."
        }
    }

    private func checkServer() async {
        let base = Secrets.streamingServerBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/") else { return }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
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
                serverStatus = "Offline (\(error.localizedDescription))"
            }
        }
    }
}
#endif
