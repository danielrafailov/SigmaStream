//
//  SettingsView.swift
//  SigmaStream
//
//  Created by Daniel Rafailov on 2026-08-30.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    
    @State private var searchText: String = ""
    @State private var availableVoices: [VoiceAIDeviceVoice] = []
    @State private var isLoadingVoices: Bool = false
    
    private var filteredVoices: [VoiceAIDeviceVoice] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return availableVoices
        }
        return availableVoices.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    
                    // MARK: - Currently Active AI Voice Row
                    HStack(spacing: 20) {
                        Text("Currently Active AI Voice:")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        
                        Text(appState.voiceService.selectedVoiceAIName)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                        
                        Button {
                            let text = "Hello! I am your AI assistant on Apple TV, ready to find your next favorite movie."
                            appState.voiceService.previewVoice(
                                voiceId: appState.voiceService.selectedVoiceAIVoiceId,
                                engine: .voiceAI,
                                sampleText: text
                            )
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "play.fill")
                                Text("Play Sample")
                            }
                            .fontWeight(.semibold)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 48)
                    .padding(.top, 28)
                    
                    // MARK: - Search Bar by Name
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search AI voices by name (e.g. Trump, Matt, Ellie, Emma, Lauren)...", text: $searchText)
                    }
                    .padding(18)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 48)
                    
                    // MARK: - Voices List
                    if isLoadingVoices && availableVoices.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView("Loading available voices...")
                                .font(.headline)
                            Spacer()
                        }
                        .padding(.vertical, 40)
                    } else {
                        VStack(spacing: 16) {
                            ForEach(filteredVoices) { voice in
                                voiceRow(voice: voice)
                            }
                        }
                        .padding(.horizontal, 48)
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 24)
            }
            .navigationTitle("")
            .task {
                isLoadingVoices = true
                availableVoices = await appState.voiceService.fetchAvailableVoiceAIVoices()
                isLoadingVoices = false
            }
        }
    }
    
    // MARK: - Single Voice Row
    private func voiceRow(voice: VoiceAIDeviceVoice) -> some View {
        let isActive = appState.voiceService.selectedVoiceAIVoiceId == voice.voiceId
        
        return HStack(spacing: 20) {
            Image(systemName: "person.wave.2.fill")
                .font(.title2)
                .foregroundStyle(isActive ? .blue : .secondary)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(voice.name)
                    .font(.title3)
                    .fontWeight(.bold)
                
                Text(voice.voiceId == Secrets.voiceAITrumpVoiceId ? "Featured Celebrity Voice" : "Voice.ai Studio Voice")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 14) {
                // Play Sample Button
                Button {
                    let sampleText = "Hello, this is \(voice.name) speaking on SigmaStream."
                    appState.voiceService.previewVoice(
                        voiceId: voice.voiceId,
                        engine: .voiceAI,
                        sampleText: sampleText
                    )
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "speaker.wave.2.fill")
                        Text("Sample")
                    }
                }
                .buttonStyle(.bordered)
                
                // Select / Active Button
                Button {
                    appState.voiceService.selectedVoiceAIVoiceId = voice.voiceId
                    appState.voiceService.selectedVoiceAIName = voice.name
                    appState.voiceService.selectedEngine = .voiceAI
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
        .padding(20)
        .background(isActive ? Color.blue.opacity(0.18) : Color.white.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(isActive ? Color.blue : Color.clear, lineWidth: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}
