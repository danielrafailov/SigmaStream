//
//  SearchView.swift
//  SigmaStream
//
//  Created by Daniel Rafailov on 2026-03-16.
//

import SwiftUI
import TMDb

enum SearchMode: String, CaseIterable, Identifiable {
    case standard = "Basic"
    case ai = "AI Mode ✨"
    
    var id: String { rawValue }
}

struct SearchView: View {
    @Environment(AppState.self) private var appState
    
    @State private var searchText = ""
    @State private var searchMode: SearchMode = .standard
    @State private var movies: [MovieListItem] = []
    @State private var tvSeries: [TVSeriesListItem] = []
    @State private var aiSpokenResponse: String?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var selectedMovie: MovieSelection?
    @State private var selectedSeries: TVSeriesSelection?
    
    @FocusState private var isPickerFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    // MARK: - Search Mode Switcher (Standard vs AI)
                    HStack {
                        Picker("Search Mode", selection: $searchMode) {
                            ForEach(SearchMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 500)
                        .focused($isPickerFocused)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 48)
                    .padding(.top, 16)
                    
                    if let error = errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 48)
                    }

                    if isLoading {
                        HStack {
                            Spacer()
                            VStack(spacing: 16) {
                                ProgressView()
                                    .scaleEffect(1.4)
                                Text(searchMode == .ai ? "Sigma AI is analyzing..." : "Searching titles...")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, minHeight: 350)
                        .padding(.vertical, 40)
                    } else {
                        // AI Spoken Response Card (Conversational Answer)
                        if searchMode == .ai, let response = aiSpokenResponse, !response.isEmpty {
                            HStack(alignment: .top, spacing: 18) {
                                Image(systemName: "waveform.circle.fill")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.cyan)
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("Sigma AI")
                                            .font(.headline)
                                            .foregroundStyle(.cyan)
                                        
                                        Spacer()
                                        
                                        Button {
                                            appState.voiceService.speak(response)
                                        } label: {
                                            HStack(spacing: 6) {
                                                Image(systemName: "speaker.wave.2.fill")
                                                Text("Replay")
                                            }
                                            .font(.caption.bold())
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                    
                                    Text(response)
                                        .font(.title3)
                                        .foregroundStyle(.white)
                                        .lineSpacing(4)
                                }
                            }
                            .padding(24)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .padding(.horizontal, 48)
                        }

                        // Media Results Rows
                        if !movies.isEmpty || !tvSeries.isEmpty {
                            VStack(alignment: .leading, spacing: 32) {
                                if !movies.isEmpty {
                                    MovieMediaRow(
                                        title: searchMode == .ai ? "AI Movie Recommendations" : "Movies",
                                        movies: movies,
                                        config: appState.apiConfiguration,
                                        onSelect: { movie in selectedMovie = MovieSelection(id: movie.id) }
                                    )
                                }

                                if !tvSeries.isEmpty {
                                    TVSeriesMediaRow(
                                        title: searchMode == .ai ? "AI TV Recommendations" : "TV Shows",
                                        tvSeries: tvSeries,
                                        config: appState.apiConfiguration,
                                        onSelect: { series in selectedSeries = TVSeriesSelection(id: series.id) }
                                    )
                                }
                            }
                        } else if searchMode == .ai && aiSpokenResponse == nil && !searchText.isEmpty && !isLoading {
                            HStack {
                                Spacer()
                                VStack(spacing: 12) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 48))
                                        .foregroundStyle(.cyan)
                                    Text("Press Enter / Return on your remote to ask Sigma AI")
                                        .font(.title3)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, minHeight: 250)
                            .padding(.vertical, 40)
                        } else if searchMode == .standard && !searchText.isEmpty && movies.isEmpty && tvSeries.isEmpty && !isLoading {
                            HStack {
                                Spacer()
                                ContentUnavailableView(
                                    "No results found",
                                    systemImage: "magnifyingglass",
                                    description: Text("Try a different search term")
                                )
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, minHeight: 350)
                            .padding(.vertical, 40)
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical)
            }
            .navigationTitle("")
            .searchable(
                text: $searchText,
                prompt: searchMode == .ai ? "Ask AI Anything" : "Search titles, actors, genres..."
            )
            .onSubmit(of: .search) {
                // Trigger search only when the user explicitly presses Enter / Return / Done
                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !query.isEmpty else { return }
                searchTask?.cancel()
                let currentMode = searchMode
                searchTask = Task {
                    await performSearch(query: query, mode: currentMode)
                }
            }
            .onChange(of: searchText) { _, newValue in
                searchTask?.cancel()
                appState.voiceService.stopSpeaking()
                
                if newValue.isEmpty {
                    movies = []
                    tvSeries = []
                    aiSpokenResponse = nil
                    errorMessage = nil
                }
            }
            .onChange(of: searchMode) { _, newMode in
                searchTask?.cancel()
                appState.voiceService.stopSpeaking()
                movies = []
                tvSeries = []
                aiSpokenResponse = nil
                errorMessage = nil
                
                // If there is existing search text and mode is switched, run on submit or re-trigger
                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !query.isEmpty {
                    searchTask = Task {
                        await performSearch(query: query, mode: newMode)
                    }
                }
            }
            .onAppear {
                // Ensure Basic mode is always the default when opening the search tab
                searchMode = .standard
            }
            .navigationDestination(item: $selectedMovie) { selection in
                MovieDetailView(movieId: selection.id)
            }
            .navigationDestination(item: $selectedSeries) { selection in
                TVSeriesDetailView(seriesId: selection.id)
            }
            .task {
                await appState.loadConfiguration()
            }
            .onDisappear {
                appState.voiceService.stopSpeaking()
            }
        }
    }

    private func performSearch(query: String, mode: SearchMode) async {
        guard !query.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        aiSpokenResponse = nil

        do {
            if mode == .ai {
                let result = try await appState.aiService.query(prompt: query, tmdbService: appState.tmdbService)
                guard !Task.isCancelled else { return }
                movies = result.movies
                tvSeries = result.tvSeries
                aiSpokenResponse = result.spokenResponse
                
                // Speak the AI response out loud via celebrity voice engine
                appState.voiceService.speak(result.spokenResponse)
            } else {
                let result = try await appState.tmdbService.searchMoviesTVIncludingPersonCast(query: query)
                guard !Task.isCancelled else { return }
                movies = result.movies
                tvSeries = result.tvSeries
            }
        } catch {
            if !Task.isCancelled {
                errorMessage = error.localizedDescription
            }
        }

        isLoading = false
    }
}

#Preview {
    SearchView()
        .environment(AppState(apiKey: "placeholder"))
}

