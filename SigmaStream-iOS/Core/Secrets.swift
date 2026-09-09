//
//  Secrets.swift
//  SigmaStream
//

import Foundation

enum Secrets {
    // Replace with your TMDb API key (https://www.themoviedb.org/settings/api)
    static let tmdbApiKey = "a6df3aeb4cabf76f74eada17351cf1a3"
    
    // Direct Local Wi-Fi Backend Server
    static let streamingServerBaseURL = "http://192.168.2.54:3000"
    
    // Google Gemini API Keys (Automatically cycles through keys when quotas expire)
    static let geminiApiKey1 = "AQ.Ab8RN6J6Es1Zrz2GJyn2lfp_UvDQQmigr9CjkdJ0p3c_cUHWaQ"
    static let geminiApiKey2 = "AQ.Ab8RN6IofXMyVeV0YpTto_z410BnugWsABFO5Nd_YMxQquTWqQ"
    static let geminiApiKey3 = "AQ.Ab8RN6JoX452WMROSm8Bq2v1x1CxOrYl9dcj6vF3gJLQ7R4yyw"
    
    static var geminiApiKeys: [String] {
        [geminiApiKey1, geminiApiKey2, geminiApiKey3]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.starts(with: "YOUR_") }
    }
    
    // ElevenLabs API Keys (Automatically cycles through keys when quotas expire)
    static let elevenLabsApiKey1 = "YOUR_ELEVENLABS_API_KEY_1"
    static let elevenLabsApiKey2 = "YOUR_ELEVENLABS_API_KEY_2"
    static let elevenLabsApiKey3 = "YOUR_ELEVENLABS_API_KEY_3"
    
    static var elevenLabsApiKeys: [String] {
        [elevenLabsApiKey1, elevenLabsApiKey2, elevenLabsApiKey3]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.starts(with: "YOUR_") }
    }

    // Voice.ai API Keys (Automatically cycles through keys when quotas expire)
    static let voiceAIApiKey1 = "vk_18ebe86c49283ec0704d6086cf8cef50801e462f71d55091323432b43c18400e"
    static let voiceAIApiKey2 = "vk_1ab552d401b0e26d9d589497fedb53e1a28111434cc36a0f0065e1da5299dfc1"
    static let voiceAIApiKey3 = "vk_6893ac22af6c521ec52fb866c5ec11f7d8a8f8737aa0d6264e66cfb2d4bad70a"
    
    static var voiceAIApiKeys: [String] {
        [voiceAIApiKey1, voiceAIApiKey2, voiceAIApiKey3]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.starts(with: "YOUR_") }
    }

    // Default Voice.ai Donald Trump Voice ID
    static let voiceAITrumpVoiceId = "40d320d7-558b-4207-b9e9-45772b0ce167"
    
    // Local AI Neural Voice Fallback (100% Free, runs on your Mac):
    // Options: "am_adam" (confident male), "af_heart" (warm female), "am_michael" (deep male)
    static let localTTSVoice = "am_adam"
}
