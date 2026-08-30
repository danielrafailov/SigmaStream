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
                VStack(alignment: .leading, spacing: 28) {
                    if isLoadingVoices && availableVoices.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView("Loading voices...")
                                .font(.headline)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, minHeight: 350)
                        .padding(.vertical, 40)
                    } else if !searchText.isEmpty && filteredVoices.isEmpty {
                        HStack {
                            Spacer()
                            ContentUnavailableView(
                                "No voices found",
                                systemImage: "person.wave.2",
                                description: Text("Try searching for Trump, Matt, Ellie, Emma, Lauren, Alicia, or Dalton")
                            )
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, minHeight: 350)
                        .padding(.vertical, 40)
                    } else {
                        VStack(spacing: 16) {
                            ForEach(filteredVoices) { voice in
                                voiceRow(voice: voice)
                            }
                        }
                        .padding(.horizontal, 48)
                        .padding(.top, 16)
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 24)
            }
            .navigationTitle("")
            .searchable(
                text: $searchText,
                prompt: "Search AI voices (e.g. Trump, Matt, Ellie, Emma, Lauren)..."
            )
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
                
                Text(voice.voiceId == Secrets.voiceAITrumpVoiceId ? "Featured Voice • AI Model" : "Studio Neural Voice")
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
