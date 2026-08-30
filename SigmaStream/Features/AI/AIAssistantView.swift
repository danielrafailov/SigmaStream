//
//  AIAssistantView.swift
//  SigmaStream
//
//  Minimalist Voice-First AI Assistant featuring a centered circular Red/Green Remote Microphone button,
//  hands-free Siri Remote audio recording with automatic silence detection, and Neural AI curation.
//

import SwiftUI
import TMDb

struct AIAssistantView: View {
    @Environment(AppState.self) private var appState
    @State private var recordingService = AudioRecordingService()
    
    @State private var aiResponse: String? = nil
    @State private var movies: [MovieListItem] = []
    @State private var tvSeries: [TVSeriesListItem] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var capturedPrompt: String? = nil
    
    @State private var selectedMovie: MovieSelection?
    @State private var selectedSeries: TVSeriesSelection?
    
    @FocusState private var isMicButtonFocused: Bool
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 44) {
                    if aiResponse == nil && !isLoading && !recordingService.isTranscribing {
                        Spacer(minLength: 120)
                    }
                    
                    // MARK: - Centered Circular Microphone Button
                    micButtonSection
                    
                    // MARK: - Spoken Response Card
                    if let response = aiResponse, !isLoading {
                        aiResponseCard(response: response)
                    }
                    
                    // MARK: - Discovered Movies & TV Shows
                    if !isLoading {
                        resultsSection
                    }
                    
                    if aiResponse == nil && !isLoading && !recordingService.isTranscribing {
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
                recordingService.stopRecording()
                appState.voiceService.stopSpeaking()
            }
        }
    }
    
    // MARK: - Circular Microphone Button Section
    
    private var isSentOrLoading: Bool {
        isLoading || recordingService.isTranscribing
    }
    
    private var micButtonSection: some View {
        VStack(spacing: 28) {
            Button {
                handleMicButtonPress()
            } label: {
                ZStack {
                    // Pulsating ring when actively listening to Siri Remote
                    if recordingService.isRecording {
                        Circle()
                            .stroke(Color.red.opacity(0.35), lineWidth: 16)
                            .frame(width: 230, height: 230)
                            .scaleEffect(recordingService.isRecording ? 1.15 : 1.0)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: recordingService.isRecording)
                    }
                    
                    // Main Circular Button Body (Red when idle/recording, Green when prompt sent/loading)
                    Circle()
                        .fill(isSentOrLoading ? Color.green : Color.red)
                        .frame(width: 175, height: 175)
                        .shadow(
                            color: (isSentOrLoading ? Color.green : Color.red).opacity(isMicButtonFocused ? 0.75 : 0.4),
                            radius: isMicButtonFocused ? 32 : 16
                        )
                    
                    // White Microphone Silhouette
                    Image(systemName: "mic.fill")
                        .font(.system(size: 68, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .contentShape(Circle())
                .scaleEffect(isMicButtonFocused ? 1.12 : 1.0)
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isMicButtonFocused)
                .animation(.easeInOut(duration: 0.25), value: isSentOrLoading)
            }
            .buttonStyle(.plain)
            .buttonBorderShape(.circle)
            .focused($isMicButtonFocused)
            
            // Status Subtitle
            VStack(spacing: 10) {
                if recordingService.isRecording {
                    HStack(spacing: 10) {
                        Image(systemName: "waveform")
                            .symbolEffect(.variableColor.iterative.reversing)
                            .foregroundStyle(.red)
                        Text("Listening... speak into your remote")
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                    }
                } else if recordingService.isTranscribing {
                    Text("Understanding your speech...")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                } else if isLoading {
                    Text("Curating recommendations...")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                } else if let prompt = capturedPrompt, aiResponse != nil {
                    Text("\"\(prompt)\"")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                } else if let error = recordingService.errorMessage ?? errorMessage {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                } else if aiResponse == nil {
                    Text("Press to speak into your Siri Remote")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .animation(.easeInOut, value: recordingService.isRecording)
            .animation(.easeInOut, value: isSentOrLoading)
        }
        .frame(maxWidth: .infinity)
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
        
        if recordingService.isRecording {
            recordingService.finishRecording()
        } else {
            recordingService.startRecording { transcribedPrompt in
                self.capturedPrompt = transcribedPrompt
                self.submitPrompt(transcribedPrompt)
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
