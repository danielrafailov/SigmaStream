//
//  AIAssistantView.swift
//  SigmaStream
//
//  Conversational AI Assistant featuring multi-turn natural language exploration,
//  long-press remote audio dictation, spoken Neural AI responses, and dynamic media curation.
//

import SwiftUI
import TMDb

struct AIAssistantView: View {
    @Environment(AppState.self) private var appState
    @State private var recordingService = AudioRecordingService()
    
    @State private var movies: [MovieListItem] = []
    @State private var tvSeries: [TVSeriesListItem] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var lastPrompt: String? = nil
    
    @State private var selectedMovie: MovieSelection?
    @State private var selectedSeries: TVSeriesSelection?
    
    @FocusState private var isPromptCardFocused: Bool
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 40) {
                    if movies.isEmpty && tvSeries.isEmpty && !isLoading && !recordingService.isTranscribing {
                        Spacer(minLength: 100)
                    }
                    
                    // MARK: - Conversational Voice Prompt Banner
                    conversationalBanner
                    
                    // MARK: - Discovered Media Rows
                    if !isLoading {
                        resultsSection
                    }
                    
                    if movies.isEmpty && tvSeries.isEmpty && !isLoading && !recordingService.isTranscribing {
                        Spacer(minLength: 100)
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
            .onPlayPauseCommand {
                triggerVoiceInput()
            }
            .onDisappear {
                recordingService.stopRecording()
                appState.voiceService.stopSpeaking()
            }
        }
    }
    
    // MARK: - Conversational Banner (Long-press & Speak)
    
    private var isWorking: Bool {
        isLoading || recordingService.isTranscribing
    }
    
    private var conversationalBanner: some View {
        VStack(spacing: 20) {
            Button {
                triggerVoiceInput()
            } label: {
                HStack(spacing: 20) {
                    // Animated Status Icon
                    ZStack {
                        Circle()
                            .fill(statusGlowColor.opacity(0.2))
                            .frame(width: 64, height: 64)
                            .scaleEffect(recordingService.isRecording ? 1.25 : 1.0)
                            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: recordingService.isRecording)
                        
                        Image(systemName: statusIconName)
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(statusGlowColor)
                            .symbolEffect(.variableColor.iterative.reversing, isActive: recordingService.isRecording)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(statusTitle)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                        
                        Text(statusSubtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    // Reset / Clear Chat History Button (if conversation active)
                    if lastPrompt != nil || !movies.isEmpty || !tvSeries.isEmpty {
                        Button {
                            resetConversation()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.counterclockwise")
                                Text("New Chat")
                            }
                            .font(.callout)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 22)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color.white.opacity(isPromptCardFocused ? 0.15 : 0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(statusGlowColor.opacity(isPromptCardFocused ? 0.8 : 0.3), lineWidth: isPromptCardFocused ? 2 : 1)
                        )
                )
                .scaleEffect(isPromptCardFocused ? 1.02 : 1.0)
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isPromptCardFocused)
            }
            .buttonStyle(.plain)
            .focused($isPromptCardFocused)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.4)
                    .onEnded { _ in
                        triggerVoiceInput()
                    }
            )
            
            if let error = recordingService.errorMessage ?? errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: 900)
    }
    
    private var statusTitle: String {
        if recordingService.isRecording {
            return "Listening to your remote..."
        } else if recordingService.isTranscribing {
            return "Understanding speech..."
        } else if isLoading {
            return "Curating recommendations..."
        } else if let prompt = lastPrompt {
            return "Refine: \"\(prompt)\""
        } else {
            return "Hold Remote Button or Click to Speak"
        }
    }
    
    private var statusSubtitle: String {
        if recordingService.isRecording {
            return "Speak naturally... silence will automatically send your request"
        } else if isWorking {
            return "Hold on while Sigma analyzes and searches titles..."
        } else if lastPrompt != nil {
            return "Hold or click to continue the conversation (e.g. 'Now only show sci-fi', 'Change to comedy')"
        } else {
            return "Ask for any genre, actor, mood, or year (e.g. 'Movies with Leonardo DiCaprio')"
        }
    }
    
    private var statusIconName: String {
        if recordingService.isRecording {
            return "waveform"
        } else if isWorking {
            return "sparkles"
        } else if lastPrompt != nil {
            return "bubble.left.and.bubble.right.fill"
        } else {
            return "mic.fill"
        }
    }
    
    private var statusGlowColor: Color {
        if recordingService.isRecording {
            return .red
        } else if isWorking {
            return .green
        } else if lastPrompt != nil {
            return .cyan
        } else {
            return .blue
        }
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
    
    // MARK: - Actions & Conversation Management
    
    private func triggerVoiceInput() {
        if case .speaking = appState.voiceService.state {
            appState.voiceService.stopSpeaking()
        }
        
        if recordingService.isRecording {
            recordingService.finishRecording()
        } else {
            recordingService.startRecording { transcribedPrompt in
                self.lastPrompt = transcribedPrompt
                self.submitPrompt(transcribedPrompt)
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
