//
//  SettingsView.swift
//  SigmaStream
//
//  Created by Daniel Rafailov on 2026-08-30.
//

import SwiftUI

struct CelebrityVoice: Identifiable, Hashable {
    let id: String // Voice.ai ID
    let slug: String // Local clone slug
    let name: String
    let icon: String
}

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedVoiceSlug: String = ""
    
    private let voices: [CelebrityVoice] = [
        CelebrityVoice(id: "2c61b0ed-c7e4-461d-a6d1-5a4f02fc8278", slug: "arnold_schwarzenegger", name: "Arnold Schwarzenegger", icon: "🏋️‍♂️"),
        CelebrityVoice(id: "barack_obama", slug: "barack_obama", name: "Barack Obama", icon: "🎤"),
        CelebrityVoice(id: "c1745484-ba67-4cba-b8f3-19f9bc538f61", slug: "daffy_duck", name: "Daffy Duck", icon: "🦆"),
        CelebrityVoice(id: "darth_vader", slug: "darth_vader", name: "Darth Vader", icon: "🌌"),
        CelebrityVoice(id: "40d320d7-558b-4207-b9e9-45772b0ce167", slug: "trump", name: "Donald Trump", icon: "🇺🇸"),
        CelebrityVoice(id: "c8909e12-a6d3-46d3-a4a2-c55b628acae0", slug: "eric_cartman", name: "Eric Cartman", icon: "🧢"),
        CelebrityVoice(id: "280e1b27-a62d-47a3-8840-b7ff288941aa", slug: "gordon_ramsay", name: "Gordon Ramsay", icon: "🍳"),
        CelebrityVoice(id: "joe_biden", slug: "joe_biden", name: "Joe Biden", icon: "🍦"),
        CelebrityVoice(id: "6a6d4859-fff1-4405-9f8a-a259768679be", slug: "joe_rogan", name: "Joe Rogan", icon: "🥊"),
        CelebrityVoice(id: "43ce1296-4969-4af6-bdc1-22ef5e347d08", slug: "mandalorian", name: "Mandalorian", icon: "🪐"),
        CelebrityVoice(id: "4aab5641-8f84-404a-be30-1d620d856dee", slug: "michael_jackson", name: "Michael Jackson", icon: "🕺"),
        CelebrityVoice(id: "a0cf2b27-25c9-45b8-a53d-21e7029c5bb1", slug: "morgan_freeman", name: "Morgan Freeman", icon: "🎬"),
        CelebrityVoice(id: "9a7860b8-70f8-461f-b0c7-d005d0b1504c", slug: "snoop_dogg", name: "Snoop Dogg", icon: "🕶️"),
        CelebrityVoice(id: "3caf42ba-3d92-4aed-8fda-1a70a4abd47c", slug: "tom_holland", name: "Tom Holland", icon: "🕷️")
    ]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text("AI Voice Assistant Settings")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("Sample and select your preferred celebrity AI voice personality for movie recommendations.")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 48)
                .padding(.top, 24)
                
                // Voices List
                LazyVStack(spacing: 16) {
                    ForEach(voices) { voice in
                        voiceRow(voice: voice)
                    }
                }
                .padding(.horizontal, 48)
            }
            .scrollTargetLayout()
            .padding(.vertical, 24)
        }
        .onAppear {
            selectedVoiceSlug = appState.voiceService.selectedVoiceSlug
        }
    }
    
    // MARK: - Single Voice Row
    private func voiceRow(voice: CelebrityVoice) -> some View {
        let isActive = (selectedVoiceSlug.isEmpty ? appState.voiceService.selectedVoiceSlug : selectedVoiceSlug) == voice.slug
        
        return HStack(spacing: 20) {
            Text(voice.icon)
                .font(.system(size: 38))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(voice.name)
                    .font(.title3)
                    .fontWeight(.bold)
                
                Text(isActive ? "Active Assistant Voice" : "Local AI Personality")
                    .font(.subheadline)
                    .foregroundStyle(isActive ? .blue : .secondary)
            }
            
            Spacer()
            
            HStack(spacing: 14) {
                // Play Sample Button
                Button {
                    let sampleText = sampleQuote(for: voice.slug, name: voice.name)
                    appState.voiceService.previewVoice(
                        voiceSlug: voice.slug,
                        voiceId: voice.id,
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
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedVoiceSlug = voice.slug
                        appState.voiceService.selectedVoiceSlug = voice.slug
                        appState.voiceService.selectedVoiceId = voice.id
                        appState.voiceService.selectedVoiceName = voice.name
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
        .padding(20)
        .background(isActive ? Color.blue.opacity(0.18) : Color.white.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(isActive ? Color.blue : Color.clear, lineWidth: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
    
    // MARK: - Character Signature Sample Quotes
    private func sampleQuote(for slug: String, name: String) -> String {
        switch slug {
        case "darth_vader":
            return "I find your lack of faith disturbing. Welcome to SigmaStream."
        case "barack_obama":
            return "Let me be clear, this is Barack Obama on SigmaStream."
        case "trump":
            return "Hello everybody, this is Donald Trump running on SigmaStream."
        case "arnold_schwarzenegger":
            return "I'll be back, with the greatest movie recommendations."
        case "gordon_ramsay":
            return "Listen to me, this movie recommendation is absolutely raw!"
        case "morgan_freeman":
            return "Hello, this is Morgan Freeman, narrating your movie journey."
        case "snoop_dogg":
            return "La da da da dah, it is the one and only D O double G on SigmaStream."
        case "joe_rogan":
            return "That is crazy man, have you ever tried watching movies on SigmaStream?"
        case "eric_cartman":
            return "Hey you guys, respect my authority on SigmaStream!"
        case "michael_jackson":
            return "Hee hee, shamone, Billie Jean is watching SigmaStream."
        case "mandalorian":
            return "This is the way. Let's find your next movie."
        case "daffy_duck":
            return "You are despicable, you know that? Welcome to SigmaStream."
        case "tom_holland":
            return "Hey everyone, Peter Parker here, ready for movie night on SigmaStream!"
        case "joe_biden":
            return "Here's the deal, folks, no joke, SigmaStream is the real deal."
        default:
            return "Hello, this is \(name) speaking on SigmaStream."
        }
    }
}
