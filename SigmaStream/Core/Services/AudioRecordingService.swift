//
//  AudioRecordingService.swift
//  SigmaStream
//
//  Records audio directly from the Siri Remote / Apple TV microphone via AVAudioRecorder,
//  automatically detects when speaking ends, and transcribes it via the local Mac Whisper AI service.
//

import Foundation
import AVFoundation

@Observable
final class AudioRecordingService: NSObject, AVAudioRecorderDelegate {
    
    var isRecording: Bool = false
    var isTranscribing: Bool = false
    var errorMessage: String? = nil
    
    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var meteringTimer: Timer?
    private var silenceDuration: TimeInterval = 0
    private var hasSpoken: Bool = false
    private var onTranscriptionComplete: ((String) -> Void)?
    private let session: URLSession
    
    var serverBaseURL: String
    
    init(serverBaseURL: String = Secrets.streamingServerBaseURL) {
        self.serverBaseURL = serverBaseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 25
        self.session = URLSession(configuration: config)
        super.init()
    }
    
    // MARK: - Start / Stop Recording
    
    @MainActor
    func startRecording(onFinished: @escaping (String) -> Void) {
        stopRecording()
        
        self.onTranscriptionComplete = onFinished
        self.errorMessage = nil
        self.silenceDuration = 0
        self.hasSpoken = false
        
        #if os(tvOS)
        if #available(tvOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    if granted {
                        self.beginRecordingSession()
                    } else {
                        self.errorMessage = "Microphone access is not authorized."
                        self.isRecording = false
                    }
                }
            }
        } else {
            beginRecordingSession()
        }
        #elseif os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        audioSession.requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                if granted {
                    self.beginRecordingSession()
                } else {
                    self.errorMessage = "Microphone access is not authorized."
                    self.isRecording = false
                }
            }
        }
        #else
        beginRecordingSession()
        #endif
    }
    
    @MainActor
    private func beginRecordingSession() {
        do {
            #if os(tvOS)
            let audioSession = AVAudioSession.sharedInstance()
            try? audioSession.setCategory(.record, mode: .default)
            try? audioSession.setActive(true)
            #elseif os(iOS)
            let audioSession = AVAudioSession.sharedInstance()
            try? audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try? audioSession.setActive(true)
            #endif
            
            let tempDir = FileManager.default.temporaryDirectory
            let fileURL = tempDir.appendingPathComponent("sigmastream_mic_input.wav")
            self.recordingURL = fileURL
            
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: 16000.0,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false
            ]
            
            let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            
            if recorder.record() {
                self.audioRecorder = recorder
                self.isRecording = true
                print("[AudioRecordingService] 🎙️ Recording started from Siri Remote microphone...")
                startMetering()
            } else {
                errorMessage = "Failed to initiate audio recording."
            }
        } catch {
            print("[AudioRecordingService] ❌ Failed to start recorder: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            stopRecording()
        }
    }
    
    @MainActor
    private func startMetering() {
        meteringTimer?.invalidate()
        meteringTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let recorder = self.audioRecorder, recorder.isRecording else { return }
                
                recorder.updateMeters()
                let avgPower = recorder.averagePower(forChannel: 0) // dB (-160 to 0)
                
                if avgPower > -38.0 {
                    self.hasSpoken = true
                    self.silenceDuration = 0
                } else if self.hasSpoken {
                    self.silenceDuration += 0.1
                    // 1.5 seconds of silence after speech -> auto-finish
                    if self.silenceDuration >= 1.5 {
                        print("[AudioRecordingService] ⏱️ Silence detected. Auto-submitting audio...")
                        self.finishRecording()
                    }
                }
            }
        }
    }
    
    @MainActor
    func finishRecording() {
        meteringTimer?.invalidate()
        meteringTimer = nil
        
        guard isRecording, let recorder = audioRecorder else { return }
        recorder.stop()
        self.audioRecorder = nil
        self.isRecording = false
        
        guard let fileURL = recordingURL, FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }
        
        // Transcribe audio via local Mac Whisper STT
        isTranscribing = true
        Task {
            do {
                let audioData = try Data(contentsOf: fileURL)
                guard audioData.count > 1000 else {
                    await MainActor.run { self.isTranscribing = false }
                    return
                }
                
                let transcript = try await self.transcribeAudio(audioData)
                await MainActor.run {
                    self.isTranscribing = false
                    if !transcript.isEmpty {
                        self.onTranscriptionComplete?(transcript)
                    }
                }
            } catch {
                print("[AudioRecordingService] ❌ Transcription error: \(error.localizedDescription)")
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isTranscribing = false
                }
            }
        }
    }
    
    @MainActor
    func stopRecording() {
        meteringTimer?.invalidate()
        meteringTimer = nil
        
        if let recorder = audioRecorder, recorder.isRecording {
            recorder.stop()
        }
        audioRecorder = nil
        isRecording = false
        isTranscribing = false
        
        #if os(tvOS) || os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
    
    // MARK: - HTTP Transcription Request
    
    private func transcribeAudio(_ wavData: Data) async throws -> String {
        let base = serverBaseURL.hasSuffix("/") ? String(serverBaseURL.dropLast()) : serverBaseURL
        
        var candidateURLs: [URL] = []
        if let primary = URL(string: "\(base)/api/transcribe") {
            candidateURLs.append(primary)
        }
        if let localhost = URL(string: "http://127.0.0.1:3000/api/transcribe"), !candidateURLs.contains(localhost) {
            candidateURLs.append(localhost)
        }
        
        struct TranscriptionResponse: Decodable {
            let text: String?
        }
        
        var lastError: Error?
        for candidateURL in candidateURLs {
            print("[AudioRecordingService] 🌐 Sending audio to transcription endpoint: \(candidateURL.absoluteString)...")
            var request = URLRequest(url: candidateURL)
            request.httpMethod = "POST"
            request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
            request.httpBody = wavData
            
            do {
                let (data, response) = try await session.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                    let decoded = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
                    let text = (decoded.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    print("[AudioRecordingService] ✅ Transcribed text: \"\(text)\"")
                    return text
                }
            } catch {
                print("[AudioRecordingService] ⚠️ Connection failed to \(candidateURL.absoluteString): \(error.localizedDescription)")
                lastError = error
            }
        }
        
        throw lastError ?? URLError(.badServerResponse)
    }
}
