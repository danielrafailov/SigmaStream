//
//  SettingsView.swift
//  SigmaStream
//
//  Created by Daniel Rafailov on 2026-08-30.
//

import SwiftUI

struct VoiceProfile: Identifiable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    let icon: String
    let voiceId: String
}

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    
    @State private var selectedEngine: VoiceEngine = .voiceAI
    @State private var searchText: String = ""
    @State private var customVoiceId: String = ""
    @State private var previewingVoiceId: String? = nil
    
    // Curated Popular Voice.ai Celebrity & Character Presets
    private let voiceAIPresets: [VoiceProfile] = [
        VoiceProfile(id: "trump", name: "Donald Trump", subtitle: "45th President • Signature Style", icon: "🇺🇸", voiceId: "28c76ce1-147d-439e-8d6d-4b15316101e6"),
        VoiceProfile(id: "morgan", name: "Morgan Freeman", subtitle: "Iconic Narrator & Actor", icon: "🎬", voiceId: "757dafae-b2d9-4ca7-b2e1-450f6120531c"),
        VoiceProfile(id: "rogan", name: "Joe Rogan", subtitle: "Podcast Host & Comedian", icon: "🎙️", voiceId: "7da89f2a-7bfd-4676-963d-4959db625f44"),
        VoiceProfile(id: "attenborough", name: "David Attenborough", subtitle: "Nature Documentary Legend", icon: "🌿", voiceId: "08e4be0b-b2aa-4d76-880a-9d95f87b8f9e"),
        VoiceProfile(id: "arnold", name: "Arnold Schwarzenegger", subtitle: "The Terminator & Bodybuilder", icon: "🦾", voiceId: "d599bfae-f63b-48ae-94a2-23253b26c710"),
        VoiceProfile(id: "musk", name: "Elon Musk", subtitle: "Tech Entrepreneur", icon: "🚀", voiceId: "9532822a-f887-43cf-aa0e-be40660a9f02"),
        VoiceProfile(id: "batman", name: "Batman", subtitle: "The Dark Knight", icon: "🦇", voiceId: "1a5905d4-4bb8-4d5a-8b83-a447936a7ea5"),
        VoiceProfile(id: "obama", name: "Barack Obama", subtitle: "44th President", icon: "👑", voiceId: "c0cfb638-7014-41e7-a9a3-5c7fe9b3a726"),
        VoiceProfile(id: "ramsay", name: "Gordon Ramsay", subtitle: "Celebrity Master Chef", icon: "🍳", voiceId: "0b6b23d9-6932-47a8-8b94-0cfb2e043681"),
        VoiceProfile(id: "gandalf", name: "Gandalf / Sir Ian McKellen", subtitle: "Legendary Wizard", icon: "🧙‍♂️", voiceId: "e135ceba-f6b2-4d2a-9e1c-5d15a995393a")
    ]
    
    // Curated Local Neural Voices (Kokoro-82M on Mac)
    private let localVoicePresets: [VoiceProfile] = [
        VoiceProfile(id: "am_adam", name: "Adam (Male)", subtitle: "Clear, confident American male", icon: "🎙️", voiceId: "am_adam"),
        VoiceProfile(id: "am_michael", name: "Michael (Male)", subtitle: "Deep, warm American male", icon: "🎙️", voiceId: "am_michael"),
        VoiceProfile(id: "af_heart", name: "Heart (Female)", subtitle: "Expressive, warm American female", icon: "🎙️", voiceId: "af_heart"),
        VoiceProfile(id: "af_bella", name: "Bella (Female)", subtitle: "Bright, articulate female", icon: "🎙️", voiceId: "af_bella"),
        VoiceProfile(id: "bf_emma", name: "Emma (British)", subtitle: "Classic British female narrator", icon: "🎙️", voiceId: "bf_emma")
    ]
    
    private var filteredVoiceAIPresets: [VoiceProfile] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return voiceAIPresets
        }
        return voiceAIPresets.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.subtitle.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    
                    // MARK: - Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Voice Assistant Settings")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text("Choose and preview the AI voice personality for Siri Search recommendations.")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 48)
                    .padding(.top, 24)
                    
                    // MARK: - Current Active Voice Card
                    activeVoiceCard
                        .padding(.horizontal, 48)
                    
                    // MARK: - Engine Selector
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Voice Synthesis Engine")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Picker("Voice Engine", selection: $selectedEngine) {
                            ForEach(VoiceEngine.allCases) { engine in
                                Text(engine.rawValue).tag(engine)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 700)
                    }
                    .padding(.horizontal, 48)
                    .onChange(of: selectedEngine) { _, newEngine in
                        appState.voiceService.selectedEngine = newEngine
                    }
                    
                    // MARK: - Engine Specific Voice List
                    if selectedEngine == .voiceAI {
                        voiceAISection
                            .padding(.horizontal, 48)
                    } else if selectedEngine == .localKokoro {
                        localVoicesSection
                            .padding(.horizontal, 48)
                    } else {
                        elevenLabsSection
                            .padding(.horizontal, 48)
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 32)
            }
            .navigationTitle("Settings")
            .onAppear {
                selectedEngine = appState.voiceService.selectedEngine
                customVoiceId = appState.voiceService.selectedVoiceAIVoiceId
            }
        }
    }
    
    // MARK: - Active Voice Card
    private var activeVoiceCard: some View {
        HStack(spacing: 24) {
            Image(systemName: "sparkles")
                .font(.system(size: 36))
                .foregroundStyle(.yellow)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Currently Active Voice")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                
                Text(appState.voiceService.selectedEngine == .voiceAI ? "\(appState.voiceService.selectedVoiceAIName) (Voice.ai)" : appState.voiceService.selectedEngine.rawValue)
                    .font(.title2)
                    .fontWeight(.bold)
            }
            
            Spacer()
            
            Button {
                let text = "Hello! I am your AI assistant on Apple TV, ready to find your next favorite movie."
                appState.voiceService.previewVoice(
                    voiceId: appState.voiceService.selectedVoiceAIVoiceId,
                    engine: appState.voiceService.selectedEngine,
                    sampleText: text
                )
            } label: {
                Label("Test Active Voice", systemImage: "play.fill")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
        }
        .padding(28)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
    
    // MARK: - Voice.ai Section
    private var voiceAISection: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Popular Celebrity & Character Voices (Voice.ai)")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Select any voice to set it as your active AI assistant. Click Preview to hear a live demo.")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter celebrity voices (e.g. Trump, Morgan, Rogan)...", text: $searchText)
            }
            .padding(18)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .frame(maxWidth: 700)
            
            // Grid of Voice Cards
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 24), GridItem(.flexible(), spacing: 24)], spacing: 24) {
                ForEach(filteredVoiceAIPresets) { profile in
                    voiceCard(profile: profile, engine: .voiceAI)
                }
            }
            
            // Custom Voice ID Input
            VStack(alignment: .leading, spacing: 12) {
                Text("Use Custom Voice ID from Voice.ai")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                HStack(spacing: 16) {
                    TextField("Enter Voice.ai Voice ID (e.g. 28c76ce1-...)", text: $customVoiceId)
                        .padding(18)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .frame(maxWidth: 550)
                    
                    Button("Save & Activate") {
                        let clean = customVoiceId.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !clean.isEmpty {
                            appState.voiceService.selectedVoiceAIVoiceId = clean
                            appState.voiceService.selectedVoiceAIName = "Custom Voice (\(clean.prefix(8))...)"
                            appState.voiceService.selectedEngine = .voiceAI
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
            }
            .padding(.top, 16)
        }
    }
    
    // MARK: - Local Mac Voices Section
    private var localVoicesSection: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Local Mac Neural Voices (Kokoro-82M)")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Runs 100% free and unlimited on your local Mac server with zero cloud latency.")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 24), GridItem(.flexible(), spacing: 24)], spacing: 24) {
                ForEach(localVoicePresets) { profile in
                    voiceCard(profile: profile, engine: .localKokoro)
                }
            }
        }
    }
    
    // MARK: - ElevenLabs Section
    private var elevenLabsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ElevenLabs Studio Engine")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Generates speech using the high-fidelity ElevenLabs Turbo v2.5 cloud model, automatically cycling through your 3 configured API keys.")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            Button {
                appState.voiceService.selectedEngine = .elevenLabs
                appState.voiceService.previewVoice(voiceId: "21m00Tcm4TlvDq8ikWAM", engine: .elevenLabs)
            } label: {
                Label("Test ElevenLabs Voice", systemImage: "play.fill")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .padding(.top, 12)
        }
    }
    
    // MARK: - Single Voice Card View
    private func voiceCard(profile: VoiceProfile, engine: VoiceEngine) -> some View {
        let isActive = (engine == .voiceAI && appState.voiceService.selectedVoiceAIVoiceId == profile.voiceId && appState.voiceService.selectedEngine == .voiceAI) ||
                       (engine == .localKokoro && appState.voiceService.voiceName == profile.voiceId && appState.voiceService.selectedEngine == .localKokoro)
        
        return HStack(spacing: 20) {
            Text(profile.icon)
                .font(.system(size: 40))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.name)
                    .font(.title3)
                    .fontWeight(.bold)
                Text(profile.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                // Preview Button
                Button {
                    previewingVoiceId = profile.id
                    let text = "Hello, this is \(profile.name) speaking on SigmaStream."
                    appState.voiceService.previewVoice(voiceId: profile.voiceId, engine: engine, sampleText: text)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.headline)
                }
                .buttonStyle(.bordered)
                
                // Select / Active Button
                Button {
                    if engine == .voiceAI {
                        appState.voiceService.selectedVoiceAIVoiceId = profile.voiceId
                        appState.voiceService.selectedVoiceAIName = profile.name
                        appState.voiceService.selectedEngine = .voiceAI
                    } else if engine == .localKokoro {
                        appState.voiceService.voiceName = profile.voiceId
                        appState.voiceService.selectedEngine = .localKokoro
                    }
                } label: {
                    if isActive {
                        Label("Active", systemImage: "checkmark")
                            .fontWeight(.bold)
                    } else {
                        Text("Select")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(isActive ? .green : .blue)
            }
        }
        .padding(22)
        .background(isActive ? Color.blue.opacity(0.18) : Color.white.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(isActive ? Color.blue : Color.clear, lineWidth: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}
