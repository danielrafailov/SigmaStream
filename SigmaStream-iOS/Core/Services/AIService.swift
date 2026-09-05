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
    let personName: String?
    let targetCount: Int?
    let sortBy: String?
}

actor AIService {
    private let session: URLSession
    private var currentKeyIndex: Int = 0
    private var conversationHistory: [GeminiRequest.Content] = []
    
    init() {
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
        
        // If Gemini API keys are configured, use Gemini LLM + Batch Parallel TMDb queries
        if !Secrets.geminiApiKeys.isEmpty {
            do {
                let structuredData = try await requestGemini(prompt: trimmedPrompt)
                let limit = structuredData.targetCount ?? extractTargetCount(from: trimmedPrompt) ?? 20
                let sortPreference = structuredData.sortBy?.lowercased() ?? extractSortPreference(from: trimmedPrompt)
                
                // 1. Resolve direct title queries
                async let moviesTask = resolveBatchMovieQueries(structuredData.movieQueries ?? [], tmdbService: tmdbService)
                async let tvTask = resolveBatchTVQueries(structuredData.tvQueries ?? [], tmdbService: tmdbService)
                
                // 2. Resolve person cast if identified (e.g. "Alan Ritchson")
                var personMovies: [MovieListItem] = []
                var personTV: [TVSeriesListItem] = []
                if let person = structuredData.personName, !person.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    do {
                        let personResult = try await tmdbService.searchMoviesTVIncludingPersonCast(query: person)
                        personMovies = personResult.movies
                        personTV = personResult.tvSeries
                    } catch {}
                }
                
                var (resolvedMovies, resolvedTV) = await (moviesTask, tvTask)
                
                // Merge title results with person cast results
                var allMovies = mergeAndDeduplicateMovies(primary: resolvedMovies, secondary: personMovies)
                var allTV = mergeAndDeduplicateTV(primary: resolvedTV, secondary: personTV)
                
                // Apply sorting
                allMovies = applySorting(allMovies, sortBy: sortPreference)
                allTV = applySorting(allTV, sortBy: sortPreference)
                
                // Apply requested count limit
                let finalMovies = Array(allMovies.prefix(limit))
                let finalTV = Array(allTV.prefix(limit))
                
                if !finalMovies.isEmpty || !finalTV.isEmpty {
                    return AIResponseResult(
                        spokenResponse: structuredData.spokenResponse,
                        movies: finalMovies,
                        tvSeries: finalTV
                    )
                }
            } catch {
                print("[AIService] ⚠️ Gemini request failed on all keys, falling back to local resolver: \(error.localizedDescription)")
            }
        }
        
        // Intelligent On-Device Natural Language Criteria Resolver
        return try await performIntelligentCriteriaDiscovery(prompt: trimmedPrompt, tmdbService: tmdbService)
    }
    
    // MARK: - Gemini API Call with Multi-Turn Memory & Key Rotation
    
    private func requestGemini(prompt: String) async throws -> AIStructuredOutput {
        let keys = Secrets.geminiApiKeys
        guard !keys.isEmpty else {
            throw URLError(.userAuthenticationRequired)
        }
        
        let kidsSafetyDirective = KidsConfig.isKidsEdition ? """
        CRITICAL KIDS SAFETY REQUIREMENT: You are Sigma Kids AI. You must ONLY recommend G and PG-rated movies and TV-Y/TV-G/TV-PG animated and family shows (such as Disney, Pixar, DreamWorks, Illumination, animated superheroes, cartoons, family adventures). NEVER recommend, search for, or mention any R-rated, PG-13, TV-MA, horror, crime, violent, or mature titles. All results must be 100% suitable for children and family viewing.
        """ : ""

        let systemInstructions = """
        You are Sigma, an expert movie and TV AI curator for Apple TV.
        \(kidsSafetyDirective)
        Analyze user queries for criteria, actor/director names, release date sorting, quantity limits, studios (e.g. Disney, Marvel, Pixar), and genres.
        
        Respond with JSON matching this schema:
        {
          "spokenResponse": "A natural, conversational 1-2 sentence spoken response tailored specifically to the user's ongoing request and filters, mentioning 2-3 highlight titles found.",
          "movieQueries": ["Title 1", "Title 2", "Title 3", ...],
          "tvQueries": ["Show 1", "Show 2", ...],
          "personName": "Name of actor/director if specified (e.g. 'Tom Hanks')",
          "targetCount": 35,
          "sortBy": "newest | oldest | rating | popularity"
        }

        Instructions:
        - If the user asks for a specific count (e.g. 'Show 35 movies with Tom Hanks', 'top 10 newest disney movies'), set 'targetCount' to that number and return up to that many distinct title queries.
        - If the user asks for 'newest', 'latest', or 'recent', set 'sortBy' to 'newest' and list the newest released titles.
        - If the user specifies an actor or person, set 'personName' to the correct actor name.
        - If the user specifies a studio/franchise (e.g. 'Disney', 'Pixar', 'DreamWorks'), ensure all movieQueries belong to that studio.
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
            generationConfig: .init(responseMimeType: "application/json", temperature: 0.7)
        )
        let bodyData = try JSONEncoder().encode(geminiReq)
        
        var lastError: Error?
        for attempt in 0..<keys.count {
            let keyIndex = (currentKeyIndex + attempt) % keys.count
            let apiKey = keys[keyIndex]
            
            let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent?key=\(apiKey)"
            guard let url = URL(string: endpoint) else { continue }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = bodyData
            
            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 500
                    let errorText = String(data: data, encoding: .utf8) ?? "Gemini API Error"
                    print("[AIService] ⚠️ Gemini Key #\(keyIndex + 1) returned HTTP \(code): \(errorText)")
                    lastError = NSError(domain: "AIService", code: code, userInfo: [NSLocalizedDescriptionKey: errorText])
                    self.currentKeyIndex = (keyIndex + 1) % keys.count
                    continue
                }
                
                let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
                guard let rawJson = decoded.candidates?.first?.content?.parts?.first?.text else {
                    throw NSError(domain: "AIService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Empty response from Gemini"])
                }
                
                // Append model response to conversation history for future turns
                conversationHistory.append(GeminiRequest.Content(role: "model", parts: [.init(text: rawJson)]))
                
                self.currentKeyIndex = keyIndex // Keep working key
                let outputData = Data(rawJson.utf8)
                return try JSONDecoder().decode(AIStructuredOutput.self, from: outputData)
            } catch {
                print("[AIService] ⚠️ Gemini request failed on Key #\(keyIndex + 1): \(error.localizedDescription)")
                lastError = error
                self.currentKeyIndex = (keyIndex + 1) % keys.count
            }
        }
        
        throw lastError ?? URLError(.badServerResponse)
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
    
    // MARK: - Helpers: Deduplication & Sorting
    
    private func mergeAndDeduplicateMovies(primary: [MovieListItem], secondary: [MovieListItem]) -> [MovieListItem] {
        var seenIds = Set<Int>()
        var result: [MovieListItem] = []
        for movie in (primary + secondary) {
            if !seenIds.contains(movie.id) {
                seenIds.insert(movie.id)
                result.append(movie)
            }
        }
        return result
    }
    
    private func mergeAndDeduplicateTV(primary: [TVSeriesListItem], secondary: [TVSeriesListItem]) -> [TVSeriesListItem] {
        var seenIds = Set<Int>()
        var result: [TVSeriesListItem] = []
        for show in (primary + secondary) {
            if !seenIds.contains(show.id) {
                seenIds.insert(show.id)
                result.append(show)
            }
        }
        return result
    }
    
    private func applySorting(_ movies: [MovieListItem], sortBy: String?) -> [MovieListItem] {
        guard let sortBy = sortBy else { return movies }
        switch sortBy {
        case "newest", "recent", "latest":
            return movies.sorted { ($0.releaseDate ?? .distantPast) > ($1.releaseDate ?? .distantPast) }
        case "oldest", "classic":
            return movies.sorted { ($0.releaseDate ?? .distantFuture) < ($1.releaseDate ?? .distantFuture) }
        case "rating", "top":
            return movies.sorted { ($0.voteAverage ?? 0) > ($1.voteAverage ?? 0) }
        default:
            return movies
        }
    }
    
    private func applySorting(_ tv: [TVSeriesListItem], sortBy: String?) -> [TVSeriesListItem] {
        guard let sortBy = sortBy else { return tv }
        switch sortBy {
        case "newest", "recent", "latest":
            return tv.sorted { ($0.firstAirDate ?? .distantPast) > ($1.firstAirDate ?? .distantPast) }
        case "oldest", "classic":
            return tv.sorted { ($0.firstAirDate ?? .distantFuture) < ($1.firstAirDate ?? .distantFuture) }
        case "rating", "top":
            return tv.sorted { ($0.voteAverage ?? 0) > ($1.voteAverage ?? 0) }
        default:
            return tv
        }
    }
    
    private func extractTargetCount(from prompt: String) -> Int? {
        let pattern = #"\b(\d+)\b"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: prompt, range: NSRange(prompt.startIndex..., in: prompt)),
           let range = Range(match.range(at: 1), in: prompt),
           let count = Int(prompt[range]), count > 0 {
            return count
        }
        return nil
    }
    
    private func extractSortPreference(from prompt: String) -> String? {
        let lower = prompt.lowercased()
        if lower.contains("newest") || lower.contains("latest") || lower.contains("recent") {
            return "newest"
        }
        if lower.contains("oldest") || lower.contains("classic") {
            return "oldest"
        }
        if lower.contains("top") || lower.contains("best") || lower.contains("highest rated") {
            return "rating"
        }
        return nil
    }
    
    // MARK: - Intelligent Criteria Discovery (Local Parser)
    
    private func performIntelligentCriteriaDiscovery(prompt: String, tmdbService: TMDbService) async throws -> AIResponseResult {
        let lower = prompt.lowercased()
        let count = extractTargetCount(from: prompt) ?? 20
        let sortPreference = extractSortPreference(from: prompt)
        
        let isTVExclusive = lower.contains("tv show") || lower.contains("tv series") || lower.contains("shows") || lower.contains("series") || lower.contains("episodes")
        let isMovieExclusive = lower.contains("movie") || lower.contains("movies") || lower.contains("film") || lower.contains("films")
        
        let wantMovies = isMovieExclusive || !isTVExclusive
        let wantTV = isTVExclusive || !isMovieExclusive
        
        // Extract Actor / Query
        var cleanQuery = prompt
            .replacingOccurrences(of: "show me", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "show", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "find me", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "top", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "newest", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "movies with", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "movie with", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "shows with", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "with actor", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "with", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "starring", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "movies", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "movie", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "shows", with: "", options: .caseInsensitive)
        
        // Remove numbers from search string
        if let regex = try? NSRegularExpression(pattern: #"\b\d+\b"#) {
            cleanQuery = regex.stringByReplacingMatches(in: cleanQuery, range: NSRange(cleanQuery.startIndex..., in: cleanQuery), withTemplate: "")
        }
        cleanQuery = cleanQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let direct = try await tmdbService.searchMoviesTVIncludingPersonCast(query: cleanQuery.isEmpty ? prompt : cleanQuery)
        
        var movies = wantMovies ? direct.movies : []
        var tvSeries = wantTV ? direct.tvSeries : []
        
        movies = applySorting(movies, sortBy: sortPreference)
        tvSeries = applySorting(tvSeries, sortBy: sortPreference)
        
        let finalMovies = Array(movies.prefix(count))
        let finalTV = Array(tvSeries.prefix(count))
        
        let spoken: String
        if !finalMovies.isEmpty || !finalTV.isEmpty {
            let highlights = (finalMovies.prefix(2).map(\.title) + finalTV.prefix(2).map(\.name)).joined(separator: ", ")
            if !finalMovies.isEmpty && !finalTV.isEmpty {
                spoken = "Here are \(finalMovies.count) movies and \(finalTV.count) shows matching your request, including \(highlights)."
            } else if !finalMovies.isEmpty {
                spoken = "Here are \(finalMovies.count) movies matching your request, including \(highlights)."
            } else {
                spoken = "Here are \(finalTV.count) shows matching your request, including \(highlights)."
            }
        } else {
            spoken = "I couldn't find any titles matching your exact criteria. Try asking with different genres, themes, or actors."
        }
        
        return AIResponseResult(
            spokenResponse: spoken,
            movies: finalMovies,
            tvSeries: finalTV
        )
    }
}
