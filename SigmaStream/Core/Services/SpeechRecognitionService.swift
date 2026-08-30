//
//  SpeechRecognitionService.swift
//  SigmaStream
//
//  Handles live voice dictation via Apple TV Remote microphone,
//  automatically detecting when the user finishes speaking and returning the prompt.
//

import Foundation
import Speech
import AVFoundation

@Observable
final class SpeechRecognitionService: NSObject {
    
    var isRecording: Bool = false
    var liveTranscript: String = ""
    var errorMessage: String? = nil
    
    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    private var silenceTimer: Timer?
    private var onPromptFinished: ((String) -> Void)?
    
    override init() {
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) ?? SFSpeechRecognizer()
        super.init()
    }
    
    // MARK: - Permissions & Start Dictation
    
    @MainActor
    func toggleRecording(onFinished: @escaping (String) -> Void) {
        if isRecording {
            finishAndSubmit()
        } else {
            startRecording(onFinished: onFinished)
        }
    }
    
    @MainActor
    func startRecording(onFinished: @escaping (String) -> Void) {
        stopRecording()
        
        self.onPromptFinished = onFinished
        self.liveTranscript = ""
        self.errorMessage = nil
        
        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            Task { @MainActor in
                guard let self else { return }
                switch authStatus {
                case .authorized:
                    self.beginAudioEngineRecording()
                case .denied, .restricted, .notDetermined:
                    self.errorMessage = "Microphone access is not authorized for speech recognition."
                    self.isRecording = false
                @unknown default:
                    self.errorMessage = "Speech recognition error."
                    self.isRecording = false
                }
            }
        }
    }
    
    @MainActor
    private func beginAudioEngineRecording() {
        do {
            #if os(tvOS) || os(iOS)
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            #endif
            
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let recognitionRequest = recognitionRequest else {
                errorMessage = "Unable to initialize speech request."
                return
            }
            
            recognitionRequest.shouldReportPartialResults = true
            
            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
            }
            
            audioEngine.prepare()
            try audioEngine.start()
            
            isRecording = true
            
            recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    
                    if let result = result {
                        let text = result.bestTranscription.formattedString
                        self.liveTranscript = text
                        
                        // Reset silence timer on every new speech token
                        self.resetSilenceTimer()
                    }
                    
                    if error != nil || (result?.isFinal ?? false) {
                        if self.isRecording && !self.liveTranscript.isEmpty {
                            self.finishAndSubmit()
                        }
                    }
                }
            }
        } catch {
            print("[SpeechRecognitionService] ❌ Audio engine start error: \(error.localizedDescription)")
            errorMessage = "Failed to start microphone: \(error.localizedDescription)"
            stopRecording()
        }
    }
    
    // MARK: - Silence Detection & Auto-Submit
    
    @MainActor
    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        // If user pauses for 1.8 seconds after speaking, automatically send the prompt
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.8, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRecording else { return }
                if !self.liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    print("[SpeechRecognitionService] ⏱️ Silence detected. Auto-submitting prompt: \"\(self.liveTranscript)\"")
                    self.finishAndSubmit()
                }
            }
        }
    }
    
    @MainActor
    func finishAndSubmit() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        
        let finalText = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        stopRecording()
        
        if !finalText.isEmpty {
            onPromptFinished?(finalText)
        }
    }
    
    @MainActor
    func stopRecording() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        recognitionTask?.cancel()
        recognitionTask = nil
        
        isRecording = false
    }
}
