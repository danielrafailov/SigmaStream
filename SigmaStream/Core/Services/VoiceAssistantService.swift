//
//  VoiceAssistantService.swift
//  SigmaStream
//
//  Created by Daniel Rafailov on 2026-08-30.
//

import Foundation
import AVFoundation
import SwiftUI
import Observation

enum VoiceAssistantState: Equatable {
    case idle
    case listening
    case processing
    case speaking(text: String)
    case error(String)
}

@Observable
final class VoiceAssistantService: NSObject, AVAudioPlayerDelegate {
    
    var state: VoiceAssistantState = .idle
    var isMicrophoneAvailable: Bool = true
    
    // User Settings (Stored persistently in UserDefaults with @Observable tracking)
    var selectedVoiceSlug: String = UserDefaults.standard.string(forKey: "selected_voice_slug") ?? "trump" {
        didSet {
            UserDefaults.standard.set(selectedVoiceSlug, forKey: "selected_voice_slug")
        }
    }
    
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
        config.timeoutIntervalForResource = 25
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
                
                // 1. Try Local Zero-Shot Voice Clone Server (100% Free, GPU-accelerated on Mac)
                let voiceSlug = self.selectedVoiceSlug
                do {
                    audioData = try await self.fetchLocalVoiceCloneAudio(text: cleanText, voice: voiceSlug)
                    print("[VoiceAssistantService] 🚀 Synthesized speech via local Mac voice cloning engine (Voice: \(voiceSlug))")
                } catch {
                    print("[VoiceAssistantService] ⚠️ Local clone engine unavailable: \(error.localizedDescription). Trying Voice.ai fallback...")
                }
                
                // 2. Try Voice.ai with currently active voice ID and key rotation
                if audioData == nil && !Secrets.voiceAIApiKeys.isEmpty {
                    do {
                        audioData = try await self.fetchVoiceAIAudioWithKeyRotation(
                            text: cleanText,
                            voiceId: self.selectedVoiceId
                        )
                    } catch {
                        print("[VoiceAssistantService] ⚠️ Voice.ai failed: \(error.localizedDescription). Falling back to ElevenLabs...")
                    }
                }
                
                // 3. Try ElevenLabs fallback with key rotation
                if audioData == nil && !Secrets.elevenLabsApiKeys.isEmpty {
                    do {
                        audioData = try await self.fetchElevenLabsAudioWithKeyRotation(text: cleanText)
                    } catch {
                        print("[VoiceAssistantService] ⚠️ ElevenLabs failed: \(error.localizedDescription). Falling back to local Mac voice...")
                    }
                }
                
                // 4. Fallback to Local Kokoro-82M
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
    
    private func sampleCacheURL(for voiceSlug: String) -> URL? {
        let cleanSlug = voiceSlug.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        guard !cleanSlug.isEmpty else { return nil }
        guard let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = cachesDir.appendingPathComponent("VoiceSamples", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sample_rvc_\(cleanSlug).wav")
    }
    
    @MainActor
    func previewVoice(voiceSlug: String, voiceId: String, sampleText: String) {
        stopSpeaking()
        state = .speaking(text: sampleText)
        
        let cacheURL = sampleCacheURL(for: voiceSlug)
        
        // 1. Check if cached locally on disk
        if let cacheURL = cacheURL, FileManager.default.fileExists(atPath: cacheURL.path),
           let cachedData = try? Data(contentsOf: cacheURL) {
            print("[VoiceAssistantService] 💾 Playing cached sample audio for voice: \(voiceSlug)")
            self.playAudioData(cachedData, text: sampleText)
            return
        }
        
        // 2. Otherwise fetch from local clone engine or Voice.ai and cache to disk
        activeTTSJob = Task { [weak self] in
            guard let self else { return }
            do {
                var audioData: Data? = nil
                
                // Try local clone engine first
                do {
                    audioData = try await self.fetchLocalVoiceCloneAudio(text: sampleText, voice: voiceSlug)
                } catch {
                    // Fallback to Voice.ai
                    audioData = try await self.fetchVoiceAIAudioWithKeyRotation(text: sampleText, voiceId: voiceId)
                }
                
                guard let finalAudio = audioData else { return }
                
                if let cacheURL = cacheURL {
                    try? finalAudio.write(to: cacheURL, options: .atomic)
                    print("[VoiceAssistantService] 💾 Saved sample audio to local cache: \(cacheURL.lastPathComponent)")
                }
                
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.playAudioData(finalAudio, text: sampleText)
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
    
    // MARK: - Local Mac Zero-Shot Voice Clone Server
    
    private func fetchLocalVoiceCloneAudio(text: String, voice: String) async throws -> Data {
        let endpoint = "\(serverBaseURL)/api/tts"
        guard let url = URL(string: endpoint) else { throw URLError(.badURL) }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 25
        
        let payload: [String: String] = [
            "text": text,
            "voice": voice
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        return data
    }
    
    // MARK: - Voice.ai TTS with Automatic Key Rotation (Fallback)
    
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
        request.timeoutInterval = 15
        
        let body: [String: Any] = [
            "text": text,
            "model": "voiceai-tts-v1-latest",
            "voice_id": voiceId,
            "language": "en"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        if (200...299).contains(httpResponse.statusCode) {
            return data
        } else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            print("[VoiceAssistantService] ❌ Voice.ai returned status \(httpResponse.statusCode): \(errorMsg)")
            throw URLError(.init(rawValue: httpResponse.statusCode))
        }
    }
    
    // MARK: - ElevenLabs TTS with Key Rotation (Fallback)
    
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
                self.currentElevenKeyIndex = keyIndex
                return data
            } catch {
                print("[VoiceAssistantService] ⚠️ ElevenLabs Key #\(keyIndex + 1) quota exceeded/failed: \(error.localizedDescription)")
                lastError = error
                self.currentElevenKeyIndex = (keyIndex + 1) % keys.count
            }
        }
        
        throw lastError ?? URLError(.badServerResponse)
    }
    
    private func performElevenLabsRequest(text: String, apiKey: String) async throws -> Data {
        let voiceId = "21m00Tcm4TlvDq8ikWAM"
        let endpoint = "https://api.elevenlabs.io/v1/text-to-speech/\(voiceId)?output_format=mp3_44100_128"
        guard let url = URL(string: endpoint) else { throw URLError(.badURL) }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 12
        
        let body: [String: Any] = [
            "text": text,
            "model_id": "eleven_multilingual_v2",
            "voice_settings": [
                "stability": 0.5,
                "similarity_boost": 0.75
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        if (200...299).contains(httpResponse.statusCode) {
            return data
        } else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            print("[VoiceAssistantService] ❌ ElevenLabs returned status \(httpResponse.statusCode): \(errorMsg)")
            throw URLError(.init(rawValue: httpResponse.statusCode))
        }
    }
    
    // MARK: - Local Mac Server TTS (Kokoro-82M Fallback)
    
    private func fetchLocalTTSAudio(text: String) async throws -> Data {
        guard let url = URL(string: "\(serverBaseURL)/api/tts") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: String] = [
            "text": text,
            "voice": voiceName
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        return data
    }
    
    // MARK: - Audio Playback
    
    private func playAudioData(_ data: Data, text: String) {
        do {
            #if os(iOS) || os(tvOS)
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try audioSession.setActive(true)
            #endif
            
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            
            self.state = .speaking(text: text)
        } catch {
            print("[VoiceAssistantService] ❌ Audio playback error: \(error.localizedDescription)")
            self.state = .idle
        }
    }
    
    // MARK: - AVAudioPlayerDelegate
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            if case .speaking = self.state {
                self.state = .idle
            }
        }
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            if let error = error {
                print("[VoiceAssistantService] ❌ Audio decode error: \(error.localizedDescription)")
            }
            if case .speaking = self.state {
                self.state = .idle
            }
        }
    }
}
