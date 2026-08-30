//
//  AIAssistantView.swift
//  SigmaStream
//
//  Conversational AI Assistant featuring a centered Red/Green circular microphone button,
//  Siri Remote voice dictation, multi-turn conversation memory, spoken Neural AI, and media curation.
//

import SwiftUI
import TMDb

struct NoHighlightCircleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
    }
}

struct AIAssistantView: View {
    @Environment(AppState.self) private var appState
    
    @State private var voicePromptText: String = ""
    @State private var isDictating: Bool = false
    @State private var movies: [MovieListItem] = []
    @State private var tvSeries: [TVSeriesListItem] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var lastPrompt: String? = nil
    
    @State private var selectedMovie: MovieSelection?
    @State private var selectedSeries: TVSeriesSelection?
    
    @FocusState private var isMicButtonFocused: Bool
    @FocusState private var isDictationFieldFocused: Bool
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 44) {
                    if movies.isEmpty && tvSeries.isEmpty && !isLoading && !isDictating {
                        Spacer(minLength: 120)
                    }
                    
                    // MARK: - Centerpiece Circular Microphone Button
                    micButtonSection
                    
                    // MARK: - Discovered Media Rows
                    if !isLoading {
                        resultsSection
                    }
                    
                    if movies.isEmpty && tvSeries.isEmpty && !isLoading && !isDictating {
                        Spacer(minLength: 120)
                    }
                }
                .padding(.horizontal, 48)
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity, minHeight: 700)
            }
            .navigationTitle("")
            .navigationDestination(item: $selectedMovie) { selection in
                MovieDetailView(movieId: selection.id)
            }
            .navigationDestination(item: $selectedSeries) { selection in
                TVSeriesDetailView(seriesId: selection.id)
            }
            .onDisappear {
                appState.voiceService.stopSpeaking()
            }
        }
    }
    
    // MARK: - Circular Microphone Button Section
    
    private var micButtonSection: some View {
        VStack(spacing: 28) {
            Button {
                handleMicButtonPress()
            } label: {
                ZStack {
                    // Pulsating ring when dictation is active
                    if isDictating {
                        Circle()
                            .stroke(Color.red.opacity(0.35), lineWidth: 16)
                            .frame(width: 230, height: 230)
                            .scaleEffect(isDictating ? 1.15 : 1.0)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isDictating)
                    }
                    
                    // Main Circular Button Body (Red when idle, Green when prompt sent/loading)
                    Circle()
                        .fill(isLoading ? Color.green : Color.red)
                        .frame(width: 175, height: 175)
                        .shadow(
                            color: (isLoading ? Color.green : Color.red).opacity(isMicButtonFocused ? 0.85 : 0.4),
                            radius: isMicButtonFocused ? 36 : 16
                        )
                    
                    // White Microphone Silhouette
                    Image(systemName: "mic.fill")
                        .font(.system(size: 70, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .contentShape(Circle())
                .scaleEffect(isMicButtonFocused ? 1.14 : 1.0)
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isMicButtonFocused)
                .animation(.easeInOut(duration: 0.25), value: isLoading)
            }
            .buttonStyle(NoHighlightCircleButtonStyle())
            .focused($isMicButtonFocused)
            
            // Status Subtitle & Siri Remote Voice Dictation Field
            VStack(spacing: 14) {
                if isDictating {
                    HStack(spacing: 12) {
                        Image(systemName: "waveform")
                            .symbolEffect(.variableColor.iterative.reversing)
                            .foregroundStyle(.red)
                        
                        TextField("Speak into Siri Remote (or type)...", text: $voicePromptText)
                            .focused($isDictationFieldFocused)
                            .font(.title3)
                            .multilineTextAlignment(.center)
                            .onSubmit {
                                let prompt = voicePromptText
                                isDictating = false
                                voicePromptText = ""
                                submitPrompt(prompt)
                            }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Capsule())
                    .frame(maxWidth: 650)
                } else if isLoading {
                    Text("Curating recommendations...")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                } else if let prompt = lastPrompt {
                    HStack(spacing: 16) {
                        Text("\"\(prompt)\"")
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                        
                        Button {
                            resetConversation()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.counterclockwise")
                                Text("New Chat")
                            }
                            .font(.callout)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                } else if let error = errorMessage {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                } else {
                    Text("Click to speak into your Siri Remote")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .animation(.easeInOut, value: isDictating)
            .animation(.easeInOut, value: isLoading)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Discovered Results (Movies & TV Shows)
    
    @ViewBuilder
    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 36) {
            if !movies.isEmpty {
                MovieMediaRow(
                    title: "Movies",
                    movies: movies,
                    config: appState.apiConfiguration,
                    onSelect: { movie in
                        selectedMovie = MovieSelection(id: movie.id)
                    }
                )
            }
            
            if !tvSeries.isEmpty {
                TVSeriesMediaRow(
                    title: "TV Shows",
                    tvSeries: tvSeries,
                    config: appState.apiConfiguration,
                    onSelect: { series in
                        selectedSeries = TVSeriesSelection(id: series.id)
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Actions & Conversational Flow
    
    private func handleMicButtonPress() {
        if case .speaking = appState.voiceService.state {
            appState.voiceService.stopSpeaking()
        }
        
        voicePromptText = ""
        isDictating.toggle()
        if isDictating {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isDictationFieldFocused = true
            }
        }
    }
    
    private func resetConversation() {
        Task {
            await appState.aiService.clearConversation()
        }
        appState.voiceService.stopSpeaking()
        lastPrompt = nil
        movies = []
        tvSeries = []
        errorMessage = nil
    }
    
    private func submitPrompt(_ prompt: String) {
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPrompt.isEmpty else { return }
        
        lastPrompt = cleanPrompt
        isLoading = true
        errorMessage = nil
        appState.voiceService.stopSpeaking()
        
        Task {
            do {
                let result = try await appState.aiService.query(
                    prompt: cleanPrompt,
                    tmdbService: appState.tmdbService
                )
                
                await MainActor.run {
                    self.movies = result.movies
                    self.tvSeries = result.tvSeries
                    self.isLoading = false
                    
                    // Speak the response out loud via local Mac Neural TTS
                    self.appState.voiceService.speak(result.spokenResponse)
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to query AI: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
}

#Preview {
    AIAssistantView()
        .environment(AppState(apiKey: "placeholder"))
}
