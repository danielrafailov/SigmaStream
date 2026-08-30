//
//  AIService.swift
//  SigmaStream
//
//  Understands natural language movie & TV requests, generates tailored spoken responses,
//  and performs parallel batch searches to populate exact matching media.
//

import Foundation
import TMDb

struct AIResponseResult {
    let spokenResponse: String
    let movies: [MovieListItem]
    let tvSeries: [TVSeriesListItem]
}

private struct GeminiRequest: Encodable {
    struct Content: Encodable {
        struct Part: Encodable {
            let text: String
        }
        let role: String
        let parts: [Part]
    }
    struct GenerationConfig: Encodable {
        let responseMimeType: String
        let temperature: Double
    }
    
    let contents: [Content]
    let generationConfig: GenerationConfig
}

private struct GeminiResponse: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            struct Part: Decodable {
                let text: String?
            }
            let parts: [Part]?
        }
        let content: Content?
    }
    let candidates: [Candidate]?
}

private struct AIStructuredOutput: Decodable {
    let spokenResponse: String
    let movieQueries: [String]?
    let tvQueries: [String]?
}

actor AIService {
    private let apiKey: String
    private let session: URLSession
    private var conversationHistory: [GeminiRequest.Content] = []
    
    init(apiKey: String = Secrets.geminiApiKey) {
        self.apiKey = apiKey
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 35
        self.session = URLSession(configuration: config)
    }
    
    /// Reset the conversational context
    func clearConversation() {
        conversationHistory.removeAll()
    }
    
    /// Process a natural language prompt and return a spoken response + resolved TMDb movies and TV shows.
    func query(prompt: String, tmdbService: TMDbService) async throws -> AIResponseResult {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            return AIResponseResult(
                spokenResponse: "I didn't catch that. Please hold the remote button and try speaking again.",
                movies: [],
                tvSeries: []
            )
        }
        
        // If Gemini API key is valid, use Gemini LLM + Batch Parallel TMDb queries
        if !apiKey.isEmpty && apiKey != "YOUR_GEMINI_API_KEY" {
            do {
                let structuredData = try await requestGemini(prompt: trimmedPrompt)
                
                // Execute parallel batch searches for each suggested title
                async let moviesTask = resolveBatchMovieQueries(structuredData.movieQueries ?? [], tmdbService: tmdbService)
                async let tvTask = resolveBatchTVQueries(structuredData.tvQueries ?? [], tmdbService: tmdbService)
                
                let (movies, tvSeries) = await (moviesTask, tvTask)
                
                if !movies.isEmpty || !tvSeries.isEmpty {
                    return AIResponseResult(
                        spokenResponse: structuredData.spokenResponse,
                        movies: movies,
                        tvSeries: tvSeries
                    )
                }
            } catch {
                print("[AIService] ⚠️ Gemini request failed, falling back to local resolver: \(error.localizedDescription)")
            }
        }
        
        // Intelligent On-Device Natural Language Criteria Resolver
        return try await performIntelligentCriteriaDiscovery(prompt: trimmedPrompt, tmdbService: tmdbService)
    }
    
    // MARK: - Gemini API Call with Multi-Turn Memory
    
    private func requestGemini(prompt: String) async throws -> AIStructuredOutput {
        let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=\(apiKey)"
        guard let url = URL(string: endpoint) else {
            throw URLError(.badURL)
        }
        
        let systemInstructions = """
        You are Sigma, an intelligent conversational movie and TV curator for Apple TV.
        You support ongoing, multi-turn conversational exploration (e.g. user asks for movies with an actor, then refines to sci-fi only, or changes genre, or narrows results).
        
        Respond with JSON matching this schema:
        {
          "spokenResponse": "A natural, conversational 1-2 sentence spoken response tailored specifically to the user's ongoing request and refinements, mentioning 2-3 highlight titles found.",
          "movieQueries": ["Title 1", "Title 2", "Title 3", ...],
          "tvQueries": ["Show 1", "Show 2", ...]
        }

        Instructions:
        - Maintain conversation context from previous turns to refine or change results accordingly.
        - If the user specifies a quantity (e.g. '10 movies', '5 shows'), return that exact number of distinct title recommendations.
        - Return precise standalone titles for accurate TMDb search resolution.
        """
        
        // Append user turn to conversation history
        let userContent = GeminiRequest.Content(
            role: "user",
            parts: [.init(text: conversationHistory.isEmpty ? "\(systemInstructions)\n\nUser request: \(prompt)" : prompt)]
        )
        conversationHistory.append(userContent)
        
        // Keep last 10 turns to avoid exceeding context
        if conversationHistory.count > 10 {
            conversationHistory.removeFirst(conversationHistory.count - 10)
        }
        
        let geminiReq = GeminiRequest(
            contents: conversationHistory,
            generationConfig: .init(responseMimeType: "application/json", temperature: 0.8)
        )
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(geminiReq)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Gemini API Error"
            throw NSError(domain: "AIService", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: errorText])
        }
        
        let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
        guard let rawJson = decoded.candidates?.first?.content?.parts?.first?.text else {
            throw NSError(domain: "AIService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Empty response from Gemini"])
        }
        
        // Append model response to conversation history for future turns
        conversationHistory.append(GeminiRequest.Content(role: "model", parts: [.init(text: rawJson)]))
        
        let outputData = Data(rawJson.utf8)
        return try JSONDecoder().decode(AIStructuredOutput.self, from: outputData)
    }
    
    // MARK: - Batch Parallel Title Resolution
    
    private func resolveBatchMovieQueries(_ queries: [String], tmdbService: TMDbService) async -> [MovieListItem] {
        await withTaskGroup(of: (Int, MovieListItem?).self) { group in
            for (index, query) in queries.enumerated() {
                group.addTask {
                    do {
                        let search = try await tmdbService.searchMoviesTVIncludingPersonCast(query: query)
                        return (index, search.movies.first)
                    } catch {
                        return (index, nil)
                    }
                }
            }
            
            var indexedResults: [(Int, MovieListItem)] = []
            for await (index, item) in group {
                if let item = item {
                    indexedResults.append((index, item))
                }
            }
            
            // Preserve ranking order
            indexedResults.sort { $0.0 < $1.0 }
            
            var seenIds = Set<Int>()
            var uniqueResults: [MovieListItem] = []
            for (_, item) in indexedResults {
                if !seenIds.contains(item.id) {
                    seenIds.insert(item.id)
                    uniqueResults.append(item)
                }
            }
            return uniqueResults
        }
    }
    
    private func resolveBatchTVQueries(_ queries: [String], tmdbService: TMDbService) async -> [TVSeriesListItem] {
        await withTaskGroup(of: (Int, TVSeriesListItem?).self) { group in
            for (index, query) in queries.enumerated() {
                group.addTask {
                    do {
                        let search = try await tmdbService.searchMoviesTVIncludingPersonCast(query: query)
                        return (index, search.tvSeries.first)
                    } catch {
                        return (index, nil)
                    }
                }
            }
            
            var indexedResults: [(Int, TVSeriesListItem)] = []
            for await (index, item) in group {
                if let item = item {
                    indexedResults.append((index, item))
                }
            }
            
            indexedResults.sort { $0.0 < $1.0 }
            
            var seenIds = Set<Int>()
            var uniqueResults: [TVSeriesListItem] = []
            for (_, item) in indexedResults {
                if !seenIds.contains(item.id) {
                    seenIds.insert(item.id)
                    uniqueResults.append(item)
                }
            }
            return uniqueResults
        }
    }
    
    // MARK: - Intelligent Criteria Discovery (Local Parser)
    
    private func performIntelligentCriteriaDiscovery(prompt: String, tmdbService: TMDbService) async throws -> AIResponseResult {
        let lower = prompt.lowercased()
        
        // 1. Extract requested count (e.g. "10 random action movies" -> 10)
        var count = 10
        let numbers = ["1": 1, "2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7, "8": 8, "9": 9, "10": 10, "15": 15, "20": 20, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "ten": 10]
        for (word, val) in numbers {
            if lower.contains("\(word) ") || lower.hasPrefix("\(word) ") {
                count = val
                break
            }
        }
        
        // 2. Determine target media types
        let isTVExclusive = lower.contains("tv show") || lower.contains("tv series") || lower.contains("shows") || lower.contains("series") || lower.contains("episodes")
        let isMovieExclusive = lower.contains("movie") || lower.contains("movies") || lower.contains("film") || lower.contains("films")
        
        let wantMovies = isMovieExclusive || !isTVExclusive
        let wantTV = isTVExclusive || !isMovieExclusive
        
        // 3. Map Genres
        let genreMap: [String: Int] = [
            "action": 28,
            "adventure": 12,
            "animation": 16, "animated": 16, "anime": 16,
            "comedy": 35, "funny": 35, "humor": 35,
            "crime": 80, "gangster": 80, "heist": 80,
            "documentary": 99, "doc": 99,
            "drama": 18, "dramatic": 18,
            "family": 10751, "kids": 10751, "children": 10751,
            "fantasy": 14, "magical": 14,
            "history": 36, "historical": 36,
            "horror": 27, "scary": 27, "spooky": 27,
            "music": 10402, "musical": 10402,
            "mystery": 9648, "detective": 9648,
            "romance": 10749, "romantic": 10749, "love": 10749,
            "sci-fi": 878, "science fiction": 878, "space": 878, "alien": 878,
            "thriller": 53, "suspense": 53,
            "war": 10752, "military": 10752,
            "western": 37, "cowboy": 37
        ]
        
        var matchedGenreIds: [Int] = []
        var detectedGenreName: String? = nil
        
        for (keyword, id) in genreMap {
            if lower.contains(keyword) {
                matchedGenreIds.append(id)
                if detectedGenreName == nil {
                    detectedGenreName = keyword.capitalized
                }
            }
        }
        
        // 4. Determine page & sorting (e.g. "random" picks a random page)
        let isRandom = lower.contains("random") || lower.contains("surprise") || lower.contains("any")
        let page = isRandom ? Int.random(in: 1...6) : 1
        
        var movies: [MovieListItem] = []
        var tvSeries: [TVSeriesListItem] = []
        
        if wantMovies {
            let filter = matchedGenreIds.isEmpty ? nil : DiscoverMovieFilter(genres: matchedGenreIds)
            let sort: MovieSort = isRandom ? .popularity(descending: true) : .voteAverage(descending: true)
            do {
                let disc = try await tmdbService.discoverMovies(filter: filter, sortedBy: sort, page: page)
                movies = Array(disc.prefix(count))
            } catch {}
        }
        
        if wantTV {
            let filter = matchedGenreIds.isEmpty ? nil : DiscoverTVSeriesFilter(genres: matchedGenreIds)
            let sort: TVSeriesSort = isRandom ? .popularity(descending: true) : .voteAverage(descending: true)
            do {
                let disc = try await tmdbService.discoverTVSeries(filter: filter, sortedBy: sort, page: page)
                tvSeries = Array(disc.prefix(count))
            } catch {}
        }
        
        // Fallback to direct search if discover returned empty
        if movies.isEmpty && tvSeries.isEmpty {
            let cleanQuery = prompt
                .replacingOccurrences(of: "show me", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "find me", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "random", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            let direct = try await tmdbService.searchMoviesTVIncludingPersonCast(query: cleanQuery.isEmpty ? prompt : cleanQuery)
            movies = Array(direct.movies.prefix(count))
            tvSeries = Array(direct.tvSeries.prefix(count))
        }
        
        // 5. Craft intelligent spoken response tailored to criteria
        let spoken: String
        let genreLabel = detectedGenreName ?? "matching"
        
        if !movies.isEmpty || !tvSeries.isEmpty {
            let highlights = (movies.prefix(2).map(\.title) + tvSeries.prefix(2).map(\.name)).joined(separator: ", ")
            
            if !movies.isEmpty && !tvSeries.isEmpty {
                spoken = "Here are \(movies.count) \(genreLabel.lowercased()) movies and \(tvSeries.count) shows matching your criteria, including \(highlights)."
            } else if !movies.isEmpty {
                spoken = "Here are \(movies.count) \(genreLabel.lowercased()) movies for you, including \(highlights)."
            } else {
                spoken = "Here are \(tvSeries.count) \(genreLabel.lowercased()) shows for you, including \(highlights)."
            }
        } else {
            spoken = "I couldn't find any titles matching your exact criteria. Try asking with different genres, themes, or actors."
        }
        
        return AIResponseResult(
            spokenResponse: spoken,
            movies: movies,
            tvSeries: tvSeries
        )
    }
}
