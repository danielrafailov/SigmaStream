//
//  AIAssistantView.swift
//  SigmaStream
//
//  Dedicated AI Assistant tab featuring Conversational AI responses,
//  Audio speech playback out loud (Text-to-Speech), and matching Movie/TV show rows.
//

import SwiftUI
import TMDb

struct AIAssistantView: View {
    @Environment(AppState.self) private var appState
    
    @State private var inputPrompt: String = ""
    @State private var aiResponse: String? = nil
    @State private var movies: [MovieListItem] = []
    @State private var tvSeries: [TVSeriesListItem] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    
    @State private var selectedMovie: MovieSelection?
    @State private var selectedSeries: TVSeriesSelection?
    
    @FocusState private var isSearchFieldFocused: Bool
    @FocusState private var isAskButtonFocused: Bool
    
    private let suggestedPrompts = [
        "Mind-bending 90s sci-fi movies",
        "Dark comedy series with clever plot twists",
        "Feel-good animated adventure movies",
        "Space exploration thrillers"
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 40) {
                    // MARK: - Header & Prompt Hero
                    heroSection
                    
                    // MARK: - Suggested Prompts (when idle)
                    if aiResponse == nil && !isLoading && movies.isEmpty && tvSeries.isEmpty {
                        suggestedSection
                    }
                    
                    // MARK: - Loading Indicator
                    if isLoading {
                        loadingSection
                    }
                    
                    // MARK: - AI Spoken Response Card
                    if let response = aiResponse, !isLoading {
                        aiResponseCard(response: response)
                    }
                    
                    // MARK: - Discovered Movies & TV Shows
                    if !isLoading {
                        resultsSection
                    }
                }
                .padding(.horizontal, 48)
                .padding(.vertical, 24)
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
    
    // MARK: - Hero Voice & Prompt Input
    
    private var heroSection: some View {
        VStack(spacing: 24) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text("Ask Sigma AI")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
            }
            
            Text("Speak with Siri Remote dictation or type what kind of movies & shows you want to watch.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            // Search Input & Action Bar
            HStack(spacing: 20) {
                HStack {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.cyan)
                    
                    TextField("Ask anything... (e.g. '90s sci-fi thrillers')", text: $inputPrompt)
                        .focused($isSearchFieldFocused)
                        .onSubmit {
                            submitPrompt(inputPrompt)
                        }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(Color.white.opacity(0.12))
                .clipShape(Capsule())
                .frame(maxWidth: 700)
                
                Button {
                    submitPrompt(inputPrompt)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkle.magnifyingglass")
                            .font(.system(size: 22, weight: .semibold))
                        Text("Ask AI")
                            .font(.headline)
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 16)
                    .background(isAskButtonFocused ? Color.white : Color.blue.opacity(0.8))
                    .foregroundStyle(isAskButtonFocused ? Color.black : Color.white)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .focused($isAskButtonFocused)
            }
            .padding(.top, 8)
            
            if let error = errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.top, 4)
            }
        }
    }
    
    // MARK: - Suggested Prompts
    
    private var suggestedSection: some View {
        VStack(spacing: 18) {
            Text("Need Inspiration?")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 16) {
                ForEach(suggestedPrompts, id: \.self) { prompt in
                    Button {
                        inputPrompt = prompt
                        submitPrompt(prompt)
                    } label: {
                        Text(prompt)
                            .font(.callout)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.card)
                }
            }
        }
        .padding(.top, 16)
    }
    
    // MARK: - Loading View
    
    private var loadingSection: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.6)
            
            Text("Sigma is analyzing your request and curating titles...")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    // MARK: - AI Spoken Response Card
    
    private func aiResponseCard(response: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
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
                    title: "Movies Matching Your Criteria",
                    movies: movies,
                    config: appState.apiConfiguration,
                    onSelect: { movie in
                        selectedMovie = MovieSelection(id: movie.id)
                    }
                )
            }
            
            if !tvSeries.isEmpty {
                TVSeriesMediaRow(
                    title: "TV Shows Matching Your Criteria",
                    tvSeries: tvSeries,
                    config: appState.apiConfiguration,
                    onSelect: { series in
                        selectedSeries = TVSeriesSelection(id: series.id)
                    }
                )
            }
            
            if movies.isEmpty && tvSeries.isEmpty && aiResponse != nil {
                ContentUnavailableView(
                    "No Exact Media Matches",
                    systemImage: "film.stack",
                    description: Text("Try asking with different genres, actors, or themes.")
                )
                .padding(.vertical, 40)
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
    
    private func submitPrompt(_ prompt: String) {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        isLoading = true
        errorMessage = nil
        movies = []
        tvSeries = []
        aiResponse = nil
        appState.voiceService.stopSpeaking()
        
        Task {
            do {
                let result = try await appState.aiService.query(
                    prompt: prompt,
                    tmdbService: appState.tmdbService
                )
                
                await MainActor.run {
                    self.aiResponse = result.spokenResponse
                    self.movies = result.movies
                    self.tvSeries = result.tvSeries
                    self.isLoading = false
                    
                    // Speak the AI response out loud via Apple TV speakers
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
