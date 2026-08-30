//
//  AIAssistantView.swift
//  SigmaStream
//
//  Minimalist Voice-First AI Assistant featuring a circular Red/Green Remote Microphone button,
//  automatic silence detection dictation, and spoken Neural AI movie curation.
//

import SwiftUI
import TMDb

struct AIAssistantView: View {
    @Environment(AppState.self) private var appState
    @State private var speechService = SpeechRecognitionService()
    
    @State private var aiResponse: String? = nil
    @State private var movies: [MovieListItem] = []
    @State private var tvSeries: [TVSeriesListItem] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    
    @State private var selectedMovie: MovieSelection?
    @State private var selectedSeries: TVSeriesSelection?
    
    @FocusState private var isMicButtonFocused: Bool
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 48) {
                    Spacer(minLength: 20)
                    
                    // MARK: - Central Circular Voice Button
                    micButtonSection
                    
                    // MARK: - Spoken Response Card
                    if let response = aiResponse, !isLoading {
                        aiResponseCard(response: response)
                    }
                    
                    // MARK: - Discovered Movies & TV Shows
                    if !isLoading {
                        resultsSection
                    }
                }
                .padding(.horizontal, 48)
                .padding(.vertical, 32)
            }
            .navigationTitle("")
            .navigationDestination(item: $selectedMovie) { selection in
                MovieDetailView(movieId: selection.id)
            }
            .navigationDestination(item: $selectedSeries) { selection in
                TVSeriesDetailView(seriesId: selection.id)
            }
            .onDisappear {
                speechService.stopRecording()
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
                    // Pulsating ring when actively listening
                    if speechService.isRecording {
                        Circle()
                            .stroke(Color.red.opacity(0.4), lineWidth: 16)
                            .frame(width: 220, height: 220)
                            .scaleEffect(speechService.isRecording ? 1.15 : 1.0)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: speechService.isRecording)
                    }
                    
                    // Main Circular Button Body (Red when idle/recording, Green when sent/loading)
                    Circle()
                        .fill(isLoading ? Color.green : Color.red)
                        .frame(width: 170, height: 170)
                        .shadow(color: (isLoading ? Color.green : Color.red).opacity(0.6), radius: isMicButtonFocused ? 35 : 18)
                    
                    // White Microphone Silhouette
                    Image(systemName: "mic.fill")
                        .font(.system(size: 68, weight: .medium))
                        .foregroundStyle(.white)
                }
                .scaleEffect(isMicButtonFocused ? 1.12 : 1.0)
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isMicButtonFocused)
                .animation(.easeInOut(duration: 0.25), value: isLoading)
            }
            .buttonStyle(.plain)
            .focused($isMicButtonFocused)
            
            // Status Subtitle
            VStack(spacing: 8) {
                if speechService.isRecording {
                    Text(speechService.liveTranscript.isEmpty ? "Listening to your remote..." : "\"\(speechService.liveTranscript)\"")
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                } else if isLoading {
                    Text("Finding recommendations...")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                } else if let error = speechService.errorMessage ?? errorMessage {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                } else if aiResponse == nil {
                    Text("Press to speak into your Siri Remote")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 700)
            .animation(.easeInOut, value: speechService.isRecording)
            .animation(.easeInOut, value: isLoading)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }
    
    // MARK: - AI Spoken Response Card
    
    private func aiResponseCard(response: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.cyan)
                    Text("Sigma")
                        .font(.headline)
                        .fontWeight(.bold)
                }
                
                Spacer()
                
                // Replay Speech / Stop Audio Controls
                Button {
                    if isSpeakingCurrently {
                        appState.voiceService.stopSpeaking()
                    } else {
                        appState.voiceService.speak(response)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isSpeakingCurrently ? "speaker.wave.3.fill" : "speaker.wave.2.fill")
                            .symbolEffect(.pulse, isActive: isSpeakingCurrently)
                        Text(isSpeakingCurrently ? "Stop Speaking" : "Replay Voice")
                            .font(.subheadline)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            
            Text(response)
                .font(.title3)
                .fontWeight(.medium)
                .lineSpacing(6)
                .foregroundStyle(.primary)
        }
        .padding(26)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            LinearGradient(
                                colors: [.purple.opacity(0.6), .blue.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
        )
        .padding(.vertical, 8)
    }
    
    // MARK: - Discovered Results (Movies & TV Shows)
    
    @ViewBuilder
    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 36) {
            if !movies.isEmpty {
                MovieMediaRow(
                    title: "Movies Matching Your Request",
                    movies: movies,
                    config: appState.apiConfiguration,
                    onSelect: { movie in
                        selectedMovie = MovieSelection(id: movie.id)
                    }
                )
            }
            
            if !tvSeries.isEmpty {
                TVSeriesMediaRow(
                    title: "TV Shows Matching Your Request",
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
    
    // MARK: - Actions
    
    private var isSpeakingCurrently: Bool {
        if case .speaking = appState.voiceService.state {
            return true
        }
        return false
    }
    
    private func handleMicButtonPress() {
        if isSpeakingCurrently {
            appState.voiceService.stopSpeaking()
        }
        
        if speechService.isRecording {
            speechService.finishAndSubmit()
        } else {
            speechService.startRecording { capturedPrompt in
                submitPrompt(capturedPrompt)
            }
        }
    }
    
    private func submitPrompt(_ prompt: String) {
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPrompt.isEmpty else { return }
        
        isLoading = true
        errorMessage = nil
        movies = []
        tvSeries = []
        aiResponse = nil
        appState.voiceService.stopSpeaking()
        
        Task {
            do {
                let result = try await appState.aiService.query(
                    prompt: cleanPrompt,
                    tmdbService: appState.tmdbService
                )
                
                await MainActor.run {
                    self.aiResponse = result.spokenResponse
                    self.movies = result.movies
                    self.tvSeries = result.tvSeries
                    self.isLoading = false
                    
                    // Speak the AI response out loud via local Mac Neural TTS
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

