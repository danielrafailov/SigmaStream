//
//  VoiceAssistantService.swift
//  SigmaStream
//
//  Streams studio-grade Neural Text-to-Speech from the local Mac backend server (100% Free, Unlimited).
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
    
    private var audioPlayer: AVAudioPlayer?
    private var activeTTSJob: Task<Void, Never>?
    private let session: URLSession
    private var currentElevenKeyIndex: Int = 0
    
    var serverBaseURL: String
    var voiceName: String
    
    init(serverBaseURL: String = Secrets.streamingServerBaseURL, voiceName: String = Secrets.localTTSVoice) {
        self.serverBaseURL = serverBaseURL
        self.voiceName = voiceName
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        self.session = URLSession(configuration: config)
        
        super.init()
    }
    
    // MARK: - Speech API
    
    @MainActor
    func speak(_ text: String) {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return }
        
        print("[VoiceAssistantService] 🎙️ speak() called with text: \"\(cleanText)\"")
        stopSpeaking()
        state = .speaking(text: cleanText)
        
        activeTTSJob = Task { [weak self] in
            guard let self else { return }
            do {
                let audioData: Data
                if !Secrets.elevenLabsApiKeys.isEmpty {
                    do {
                        audioData = try await self.fetchElevenLabsAudioWithKeyRotation(
                            text: cleanText,
                            voiceId: Secrets.elevenLabsTrumpVoiceId
                        )
                    } catch {
                        print("[VoiceAssistantService] ⚠️ All ElevenLabs keys failed/exhausted. Falling back to local Mac voice: \(error.localizedDescription)")
                        audioData = try await self.fetchLocalTTSAudio(text: cleanText)
                    }
                } else {
                    audioData = try await self.fetchLocalTTSAudio(text: cleanText)
                }
                
                guard !Task.isCancelled else {
                    print("[VoiceAssistantService] ⚠️ Task cancelled before playback.")
                    return
                }
                
                await MainActor.run {
                    self.playAudioData(audioData, text: cleanText)
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
    
    // MARK: - ElevenLabs Donald Trump TTS with Automatic Key Rotation
    
    private func fetchElevenLabsAudioWithKeyRotation(text: String, voiceId: String) async throws -> Data {
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
                let data = try await performElevenLabsRequest(text: text, apiKey: apiKey, voiceId: voiceId)
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
    
    private func performElevenLabsRequest(text: String, apiKey: String, voiceId: String) async throws -> Data {
        let endpoint = "https://api.elevenlabs.io/v1/text-to-speech/\(voiceId)?output_format=mp3_44100_128"
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
        
        // Candidate URLs: user configured IP, localhost fallback for simulator
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

