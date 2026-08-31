//
//  VoiceAssistantService.swift
//  SigmaStream
//
//  Streams studio-grade Neural Text-to-Speech from Voice.ai, ElevenLabs, or local Mac Kokoro.
//

import Foundation
import AVFoundation

enum VoiceAssistantState: Equatable {
    case idle
    case processing
    case speaking(text: String)
    case error(String)
}

@Observable
final class VoiceAssistantService: NSObject, AVAudioPlayerDelegate {
    
    var state: VoiceAssistantState = .idle
    var isMicrophoneAvailable: Bool = true
    
    // User Settings (Stored persistently in UserDefaults with @Observable tracking)
    var selectedVoiceId: String = UserDefaults.standard.string(forKey: "selected_voice_id") ?? "40d320d7-558b-4207-b9e9-45772b0ce167" {
        didSet {
            UserDefaults.standard.set(selectedVoiceId, forKey: "selected_voice_id")
        }
    }
    
    var selectedVoiceName: String = UserDefaults.standard.string(forKey: "selected_voice_name") ?? "Trump" {
        didSet {
            UserDefaults.standard.set(selectedVoiceName, forKey: "selected_voice_name")
        }
    }
    
    private var audioPlayer: AVAudioPlayer?
    private var activeTTSJob: Task<Void, Never>?
    private let session: URLSession
    private var currentVoiceAIKeyIndex: Int = 0
    private var currentElevenKeyIndex: Int = 0
    
    var serverBaseURL: String
    var voiceName: String
    
    init(serverBaseURL: String = Secrets.streamingServerBaseURL, voiceName: String = Secrets.localTTSVoice) {
        self.serverBaseURL = serverBaseURL
        self.voiceName = voiceName
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 18
        self.session = URLSession(configuration: config)
        
        super.init()
    }
    
    // MARK: - Speech API
    
    @MainActor
    func speak(_ text: String) {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return }
        
        print("[VoiceAssistantService] 🎙️ speak() called with text: \"\(cleanText)\" (Voice: \(selectedVoiceName))")
        stopSpeaking()
        state = .speaking(text: cleanText)
        
        activeTTSJob = Task { [weak self] in
            guard let self else { return }
            do {
                var audioData: Data? = nil
                
                // 1. Try Voice.ai with currently active voice ID and key rotation
                if !Secrets.voiceAIApiKeys.isEmpty {
                    do {
                        audioData = try await self.fetchVoiceAIAudioWithKeyRotation(
                            text: cleanText,
                            voiceId: self.selectedVoiceId
                        )
                    } catch {
                        print("[VoiceAssistantService] ⚠️ Voice.ai failed: \(error.localizedDescription). Falling back to ElevenLabs...")
                    }
                }
                
                // 2. Try ElevenLabs fallback with key rotation
                if audioData == nil && !Secrets.elevenLabsApiKeys.isEmpty {
                    do {
                        audioData = try await self.fetchElevenLabsAudioWithKeyRotation(text: cleanText)
                    } catch {
                        print("[VoiceAssistantService] ⚠️ ElevenLabs failed: \(error.localizedDescription). Falling back to local Mac voice...")
                    }
                }
                
                // 3. Fallback to Local Mac Neural TTS (Kokoro-82M)
                if audioData == nil {
                    audioData = try await self.fetchLocalTTSAudio(text: cleanText)
                }
                
                guard let finalAudio = audioData, !Task.isCancelled else {
                    print("[VoiceAssistantService] ⚠️ Task cancelled before playback.")
                    return
                }
                
                await MainActor.run {
                    self.playAudioData(finalAudio, text: cleanText)
                }
            } catch {
                guard !Task.isCancelled else { return }
                print("[VoiceAssistantService] ❌ Speech synthesis error: \(error.localizedDescription)")
                await MainActor.run {
                    if case .speaking = self.state {
                        self.state = .idle
                    }
                }
            }
        }
    }
    
    private func sampleCacheURL(for voiceId: String) -> URL? {
        let cleanId = voiceId.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        guard !cleanId.isEmpty else { return nil }
        guard let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = cachesDir.appendingPathComponent("VoiceSamples", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sample_\(cleanId).mp3")
    }
    
    @MainActor
    func previewVoice(voiceId: String, sampleText: String) {
        stopSpeaking()
        state = .speaking(text: sampleText)
        
        let cacheURL = sampleCacheURL(for: voiceId)
        
        // 1. Check if cached locally on disk
        if let cacheURL = cacheURL, FileManager.default.fileExists(atPath: cacheURL.path),
           let cachedData = try? Data(contentsOf: cacheURL) {
            print("[VoiceAssistantService] 💾 Playing cached sample audio for voice: \(voiceId)")
            self.playAudioData(cachedData, text: sampleText)
            return
        }
        
        // 2. Otherwise fetch from API and cache to disk
        activeTTSJob = Task { [weak self] in
            guard let self else { return }
            do {
                let audioData = try await self.fetchVoiceAIAudioWithKeyRotation(text: sampleText, voiceId: voiceId)
                
                if let cacheURL = cacheURL {
                    try? audioData.write(to: cacheURL, options: .atomic)
                    print("[VoiceAssistantService] 💾 Saved sample audio to local cache: \(cacheURL.lastPathComponent)")
                }
                
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.playAudioData(audioData, text: sampleText)
                }
            } catch {
                guard !Task.isCancelled else { return }
                print("[VoiceAssistantService] ❌ Preview error: \(error.localizedDescription)")
                await MainActor.run {
                    if case .speaking = self.state {
                        self.state = .idle
                    }
                }
            }
        }
    }
    
    @MainActor
    func stopSpeaking() {
        activeTTSJob?.cancel()
        activeTTSJob = nil
        
        if let player = audioPlayer, player.isPlaying {
            player.stop()
        }
        audioPlayer = nil
        
        if case .speaking = state {
            state = .idle
        }
    }
    
    // MARK: - Voice.ai TTS with Automatic Key Rotation
    
    private func fetchVoiceAIAudioWithKeyRotation(text: String, voiceId: String) async throws -> Data {
        let keys = Secrets.voiceAIApiKeys
        guard !keys.isEmpty else {
            throw URLError(.userAuthenticationRequired)
        }
        
        var lastError: Error?
        for attempt in 0..<keys.count {
            let keyIndex = (currentVoiceAIKeyIndex + attempt) % keys.count
            let apiKey = keys[keyIndex]
            
            print("[VoiceAssistantService] 🎙️ Trying Voice.ai Key #\(keyIndex + 1)...")
            do {
                let data = try await performVoiceAIRequest(text: text, apiKey: apiKey, voiceId: voiceId)
                self.currentVoiceAIKeyIndex = keyIndex // Preserve working key
                return data
            } catch {
                print("[VoiceAssistantService] ⚠️ Voice.ai Key #\(keyIndex + 1) failed/expired: \(error.localizedDescription)")
                lastError = error
                self.currentVoiceAIKeyIndex = (keyIndex + 1) % keys.count
            }
        }
        
        throw lastError ?? URLError(.badServerResponse)
    }
    
    private func performVoiceAIRequest(text: String, apiKey: String, voiceId: String) async throws -> Data {
        let endpoint = "https://dev.voice.ai/api/v1/tts/speech"
        guard let url = URL(string: endpoint) else { throw URLError(.badURL) }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var bodyPayload: [String: Any] = [
            "text": text,
            "model": "voiceai-tts-v1-latest",
            "language": "en"
        ]
        let cleanVoiceId = voiceId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanVoiceId.isEmpty {
            bodyPayload["voice_id"] = cleanVoiceId
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: bodyPayload)
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Voice.ai HTTP error"
            print("[VoiceAssistantService] ❌ Voice.ai Error: \(errorText)")
            throw NSError(domain: "VoiceAssistantService", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: errorText])
        }
        
        print("[VoiceAssistantService] ✅ Successfully fetched \(data.count) bytes of audio from Voice.ai!")
        return data
    }
    
    // MARK: - ElevenLabs TTS with Automatic Key Rotation
    
    private func fetchElevenLabsAudioWithKeyRotation(text: String) async throws -> Data {
        let keys = Secrets.elevenLabsApiKeys
        guard !keys.isEmpty else {
            throw URLError(.userAuthenticationRequired)
        }
        
        var lastError: Error?
        for attempt in 0..<keys.count {
            let keyIndex = (currentElevenKeyIndex + attempt) % keys.count
            let apiKey = keys[keyIndex]
            
            print("[VoiceAssistantService] 🎙️ Trying ElevenLabs Key #\(keyIndex + 1)...")
            do {
                let data = try await performElevenLabsRequest(text: text, apiKey: apiKey)
                self.currentElevenKeyIndex = keyIndex // Preserve working key
                return data
            } catch {
                print("[VoiceAssistantService] ⚠️ ElevenLabs Key #\(keyIndex + 1) failed/expired: \(error.localizedDescription)")
                lastError = error
                self.currentElevenKeyIndex = (keyIndex + 1) % keys.count
            }
        }
        
        throw lastError ?? URLError(.badServerResponse)
    }
    
    private func performElevenLabsRequest(text: String, apiKey: String) async throws -> Data {
        let defaultVoice = "21m00Tcm4TlvDq8ikWAM"
        let endpoint = "https://api.elevenlabs.io/v1/text-to-speech/\(defaultVoice)?output_format=mp3_44100_128"
        guard let url = URL(string: endpoint) else { throw URLError(.badURL) }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let bodyPayload: [String: Any] = [
            "text": text,
            "model_id": "eleven_turbo_v2_5",
            "voice_settings": [
                "stability": 0.5,
                "similarity_boost": 0.85
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: bodyPayload)
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "ElevenLabs HTTP error"
            print("[VoiceAssistantService] ❌ ElevenLabs Error: \(errorText)")
            throw NSError(domain: "VoiceAssistantService", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: errorText])
        }
        
        print("[VoiceAssistantService] ✅ Successfully fetched \(data.count) bytes of MP3 audio from ElevenLabs!")
        return data
    }
    
    // MARK: - Local Mac Neural TTS Request
    
    private func fetchLocalTTSAudio(text: String) async throws -> Data {
        let base = serverBaseURL.hasSuffix("/") ? String(serverBaseURL.dropLast()) : serverBaseURL
        
        var candidateURLs: [URL] = []
        if let primary = URL(string: "\(base)/api/tts") {
            candidateURLs.append(primary)
        }
        if let localhost = URL(string: "http://127.0.0.1:3000/api/tts"), !candidateURLs.contains(localhost) {
            candidateURLs.append(localhost)
        }
        
        let bodyPayload: [String: String] = [
            "text": text,
            "voice": voiceName
        ]
        let postData = try JSONSerialization.data(withJSONObject: bodyPayload)
        
        var lastError: Error?
        for candidateURL in candidateURLs {
            print("[VoiceAssistantService] 🌐 Connecting to TTS endpoint: \(candidateURL.absoluteString)...")
            var request = URLRequest(url: candidateURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = postData
            
            do {
                let (data, response) = try await session.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                    print("[VoiceAssistantService] ✅ Successfully fetched \(data.count) bytes of WAV audio from \(candidateURL.absoluteString)!")
                    return data
                } else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 500
                    let errorMsg = String(data: data, encoding: .utf8) ?? "HTTP \(code)"
                    print("[VoiceAssistantService] ⚠️ Server \(candidateURL.absoluteString) returned status \(code): \(errorMsg)")
                }
            } catch {
                print("[VoiceAssistantService] ⚠️ Connection to \(candidateURL.absoluteString) failed: \(error.localizedDescription)")
                lastError = error
            }
        }
        
        throw lastError ?? URLError(.badServerResponse)
    }
    
    @MainActor
    private func playAudioData(_ data: Data, text: String) {
        do {
            #if os(tvOS) || os(iOS)
            let audioSession = AVAudioSession.sharedInstance()
            try? audioSession.setCategory(.playback, mode: .default)
            try? audioSession.setActive(true)
            #endif
            
            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            player.volume = 1.0
            self.audioPlayer = player
            self.state = .speaking(text: text)
            
            player.prepareToPlay()
            let started = player.play()
            print("[VoiceAssistantService] 🔊 AVAudioPlayer started playing! Success: \(started), Duration: \(String(format: "%.2f", player.duration))s, Volume: \(player.volume)")
        } catch {
            print("[VoiceAssistantService] ❌ AVAudioPlayer error: \(error.localizedDescription)")
            if case .speaking = self.state {
                self.state = .idle
            }
        }
    }
    
    // MARK: - AVAudioPlayerDelegate
    
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        print("[VoiceAssistantService] 🏁 Audio playback finished successfully: \(flag)")
        Task { @MainActor in
            if case .speaking = self.state {
                self.state = .idle
            }
        }
    }
    
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        print("[VoiceAssistantService] ❌ Audio decode error: \(error?.localizedDescription ?? "unknown")")
        Task { @MainActor in
            if case .speaking = self.state {
                self.state = .idle
            }
        }
    }
}
