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
        CelebrityVoice(id: "alan_rickman", slug: "alan_rickman", name: "Alan Rickman (Snape)", icon: "🪄"),
        CelebrityVoice(id: "2c61b0ed-c7e4-461d-a6d1-5a4f02fc8278", slug: "arnold_schwarzenegger", name: "Arnold Schwarzenegger", icon: "🏋️‍♂️"),
        CelebrityVoice(id: "arthur_morgan", slug: "arthur_morgan", name: "Arthur Morgan (RDR2)", icon: "🤠"),
        CelebrityVoice(id: "barack_obama", slug: "barack_obama", name: "Barack Obama", icon: "🎤"),
        CelebrityVoice(id: "batman", slug: "batman", name: "Batman", icon: "🦇"),
        CelebrityVoice(id: "bill_burr", slug: "bill_burr", name: "Bill Burr", icon: "🎙️"),
        CelebrityVoice(id: "british_butler", slug: "british_butler", name: "British Butler (Jarvis)", icon: "🎩"),
        CelebrityVoice(id: "bugs_bunny", slug: "bugs_bunny", name: "Bugs Bunny", icon: "🥕"),
        CelebrityVoice(id: "cyberpunk_ai", slug: "cyberpunk_ai", name: "Cyberpunk AI", icon: "⚡"),
        CelebrityVoice(id: "c1745484-ba67-4cba-b8f3-19f9bc538f61", slug: "daffy_duck", name: "Daffy Duck", icon: "🦆"),
        CelebrityVoice(id: "darth_vader", slug: "darth_vader", name: "Darth Vader", icon: "🌌"),
        CelebrityVoice(id: "56e0b000-b8fb-4fd3-832a-03bde62f8dbc", slug: "david_attenborough", name: "David Attenborough", icon: "🌍"),
        CelebrityVoice(id: "40d320d7-558b-4207-b9e9-45772b0ce167", slug: "trump", name: "Donald Trump", icon: "🇺🇸"),
        CelebrityVoice(id: "dr_phil", slug: "dr_phil", name: "Dr. Phil", icon: "👨‍🦲"),
        CelebrityVoice(id: "elon_musk", slug: "elon_musk", name: "Elon Musk", icon: "🚀"),
        CelebrityVoice(id: "c8909e12-a6d3-46d3-a4a2-c55b628acae0", slug: "eric_cartman", name: "Eric Cartman", icon: "🧢"),
        CelebrityVoice(id: "gandalf", slug: "gandalf", name: "Gandalf", icon: "🧙‍♂️"),
        CelebrityVoice(id: "gollum", slug: "gollum", name: "Gollum", icon: "💍"),
        CelebrityVoice(id: "280e1b27-a62d-47a3-8840-b7ff288941aa", slug: "gordon_ramsay", name: "Gordon Ramsay", icon: "🍳"),
        CelebrityVoice(id: "homer_simpson", slug: "homer_simpson", name: "Homer Simpson", icon: "🍩"),
        CelebrityVoice(id: "iron_man", slug: "iron_man", name: "Iron Man (Tony Stark)", icon: "🤖"),
        CelebrityVoice(id: "jack_sparrow", slug: "jack_sparrow", name: "Jack Sparrow", icon: "🏴‍☠️"),
        CelebrityVoice(id: "joe_biden", slug: "joe_biden", name: "Joe Biden", icon: "🍦"),
        CelebrityVoice(id: "6a6d4859-fff1-4405-9f8a-a259768679be", slug: "joe_rogan", name: "Joe Rogan", icon: "🥊"),
        CelebrityVoice(id: "joker", slug: "joker", name: "Joker", icon: "🃏"),
        CelebrityVoice(id: "keanu_reeves", slug: "keanu_reeves", name: "Keanu Reeves", icon: "🕶️"),
        CelebrityVoice(id: "kermit", slug: "kermit", name: "Kermit the Frog", icon: "🐸"),
        CelebrityVoice(id: "kratos", slug: "kratos", name: "Kratos (God of War)", icon: "🪓"),
        CelebrityVoice(id: "489b1783-5724-45e8-84dc-ace995595845", slug: "lebron_james", name: "LeBron James", icon: "👑"),
        CelebrityVoice(id: "43ce1296-4969-4af6-bdc1-22ef5e347d08", slug: "mandalorian", name: "Mandalorian", icon: "🪐"),
        CelebrityVoice(id: "mario", slug: "mario", name: "Mario", icon: "🍄"),
        CelebrityVoice(id: "master_chief", slug: "master_chief", name: "Master Chief", icon: "🛡️"),
        CelebrityVoice(id: "matthew_mcconaughey", slug: "matthew_mcconaughey", name: "Matthew McConaughey", icon: "🛞"),
        CelebrityVoice(id: "4aab5641-8f84-404a-be30-1d620d856dee", slug: "michael_jackson", name: "Michael Jackson", icon: "🕺"),
        CelebrityVoice(id: "mickey_mouse", slug: "mickey_mouse", name: "Mickey Mouse", icon: "🐭"),
        CelebrityVoice(id: "a0cf2b27-25c9-45b8-a53d-21e7029c5bb1", slug: "morgan_freeman", name: "Morgan Freeman", icon: "🎬"),
        CelebrityVoice(id: "movie_trailer", slug: "movie_trailer", name: "Movie Trailer Guy", icon: "🍿"),
        CelebrityVoice(id: "patrick_star", slug: "patrick_star", name: "Patrick Star", icon: "⭐️"),
        CelebrityVoice(id: "peter_griffin", slug: "peter_griffin", name: "Peter Griffin", icon: "🍺"),
        CelebrityVoice(id: "rick_sanchez", slug: "rick_sanchez", name: "Rick Sanchez", icon: "🧪"),
        CelebrityVoice(id: "samuel_l_jackson", slug: "samuel_l_jackson", name: "Samuel L. Jackson", icon: "💥"),
        CelebrityVoice(id: "06baf53c-9f1e-43ba-adf0-0385dd022991", slug: "saul_goodman", name: "Saul Goodman", icon: "⚖️"),
        CelebrityVoice(id: "shrek", slug: "shrek", name: "Shrek", icon: "🧅"),
        CelebrityVoice(id: "smooth_dj", slug: "smooth_dj", name: "Smooth Late Night DJ", icon: "📻"),
        CelebrityVoice(id: "9a7860b8-70f8-461f-b0c7-d005d0b1504c", slug: "snoop_dogg", name: "Snoop Dogg", icon: "🕶️"),
        CelebrityVoice(id: "spongebob", slug: "spongebob", name: "SpongeBob SquarePants", icon: "🍍"),
        CelebrityVoice(id: "taylor_swift", slug: "taylor_swift", name: "Taylor Swift", icon: "🎸"),
        CelebrityVoice(id: "3caf42ba-3d92-4aed-8fda-1a70a4abd47c", slug: "tom_holland", name: "Tom Holland", icon: "🕷️"),
        CelebrityVoice(id: "40e41528-8f28-4f6d-94ac-7670f9fec4a9", slug: "walter_white", name: "Walter White", icon: "🧪"),
        CelebrityVoice(id: "yoda", slug: "yoda", name: "Master Yoda", icon: "🌌")
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
        case "walter_white":
            return "I am the one who knocks. Welcome to SigmaStream."
        case "saul_goodman":
            return "Better call Saul! I've got the best movie deals in town."
        case "batman":
            return "I am vengeance. I am the night. I am Batman."
        case "joker":
            return "Why so serious? Let's put a smile on that face."
        case "spongebob":
            return "I'm ready! I'm ready for the best movies on SigmaStream!"
        case "peter_griffin":
            return "Holy crap, this is Peter Griffin on SigmaStream, hehehehe."
        case "homer_simpson":
            return "Mmm... movie night on SigmaStream. D'oh!"
        case "rick_sanchez":
            return "Wubba lubba dub dub! Check out these movies."
        case "shrek":
            return "What are you doing in my swamp? Let's watch a movie."
        case "gandalf":
            return "You shall not pass, without checking these recommendations."
        case "gollum":
            return "My precious! We wants to watch the best movies, yes precious!"
        case "movie_trailer":
            return "In a world, where streaming has no limits... Welcome to SigmaStream."
        case "british_butler":
            return "At your service, sir. May I suggest an exceptional film for this evening?"
        case "smooth_dj":
            return "You're tuned in to the smoothest stream in the city. Sit back and enjoy."
        case "yoda":
            return "Great movies, find you will. The Force is strong with SigmaStream."
        case "jack_sparrow":
            return "Why is the rum always gone? Ah, but you have movies on SigmaStream."
        case "kratos":
            return "Boy! Prepare yourself for the greatest stories ever told."
        case "master_chief":
            return "Master Chief, mind telling me what you're doing? Sir, finishing this movie."
        case "matthew_mcconaughey":
            return "Alright, alright, alright. Let's find a great film tonight."
        case "samuel_l_jackson":
            return "Hold on to your seats, we're watching the best movies on SigmaStream."
        case "keanu_reeves":
            return "Whoa. That is a breathtaking movie selection."
        case "elon_musk":
            return "To the moon and beyond, with the future of streaming."
        case "joe_biden":
            return "Here's the deal, folks, no joke, SigmaStream is the real deal."
        case "mario":
            return "It's-a me, Mario! Let's-a go watch a movie!"
        case "kermit":
            return "Hi-ho, Kermit the Frog here! Welcome to SigmaStream, yay!"
        default:
            return "Hello, this is \(name) speaking on SigmaStream."
        }
    }
}
