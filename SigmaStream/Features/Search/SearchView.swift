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
    @State private var searchMode: SearchMode = .ai
    @State private var movies: [MovieListItem] = []
    @State private var tvSeries: [TVSeriesListItem] = []
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

                    if isLoading && searchText.count >= 2 {
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.4)
                            Text(searchMode == .ai ? "Sigma AI is analyzing and curating recommendations..." : "Searching titles...")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    } else if searchText.count >= 2 {
                        if movies.isEmpty && tvSeries.isEmpty && !isLoading {
                            ContentUnavailableView(
                                "No results found",
                                systemImage: searchMode == .ai ? "sparkles" : "magnifyingglass",
                                description: Text(searchMode == .ai ? "Try asking with different themes, actors, or genres." : "Try a different search term")
                            )
                            .padding(.vertical, 60)
                        } else {
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
                        }
                    } else if !searchText.isEmpty {
                        Text("Enter at least 2 characters to search")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 48)
                            .padding(.vertical, 40)
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical)
            }
            .navigationTitle("")
            .searchable(
                text: $searchText,
                prompt: searchMode == .ai ? "Ask AI with Siri Remote (e.g. '90s sci-fi movies')..." : "Search titles, actors, genres..."
            )
            .onChange(of: searchText) { _, newValue in
                searchTask?.cancel()
                movies = []
                tvSeries = []
                errorMessage = nil
                appState.voiceService.stopSpeaking()

                guard newValue.count >= 2 else { return }

                let query = newValue
                let currentMode = searchMode
                searchTask = Task {
                    // Slight debounce for keyboard input; dictation submits immediately
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled else { return }
                    await performSearch(query: query, mode: currentMode)
                }
            }
            .onChange(of: searchMode) { _, newMode in
                if searchText.count >= 2 {
                    let query = searchText
                    searchTask?.cancel()
                    searchTask = Task {
                        await performSearch(query: query, mode: newMode)
                    }
                }
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

        do {
            if mode == .ai {
                let result = try await appState.aiService.query(prompt: query, tmdbService: appState.tmdbService)
                guard !Task.isCancelled else { return }
                movies = result.movies
                tvSeries = result.tvSeries
                
                // Speak the AI response out loud via local Mac Neural TTS
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

