//
//  VideoPlayerView.swift
//  SigmaStream
//
//  Native AVPlayer playback for HLS/MP4 streams from CinePro.
//

import AVKit
import SwiftUI

struct VideoPlayerView: View {
    let url: URL
    let title: String
    @Environment(\.dismiss) private var dismiss

    @State private var player: AVPlayer?
    @State private var loadError: String?
    @State private var retryTrigger = 0

    private let loadTimeout: TimeInterval = 25

    var body: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            }

            if let error = loadError {
                loadErrorOverlay(message: error)
            }
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .task(id: "\(url)-\(retryTrigger)") {
            await startPlaybackAndObserve()
        }
        .onDisappear { player?.pause() }
    }

    private func startPlaybackAndObserve() async {
        loadError = nil
        let newPlayer = AVPlayer(url: url)
        await MainActor.run { player = newPlayer }
        newPlayer.play()

        for _ in 0..<Int(loadTimeout) {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let item = newPlayer.currentItem else { continue }
            switch item.status {
            case .failed:
                let msg = item.error?.localizedDescription ?? "Stream failed to load"
                await MainActor.run { loadError = msg }
                return
            case .readyToPlay:
                return
            case .unknown:
                break
            @unknown default:
                break
            }
        }
        await MainActor.run {
            loadError = "Use your Mac's IP (e.g. http://192.168.1.5:3000) in Secrets. Required for tvOS Simulator and Apple TV."
        }
    }

    @ViewBuilder
    private func loadErrorOverlay(message: String) -> some View {
        Color.black.opacity(0.85)
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: 24) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.yellow)
                    Text("Failed to load stream")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                    HStack(spacing: 16) {
                        Button("Retry") {
                            retryTrigger += 1
                        }
                        Button("Done") {
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
    }
}

#Preview {
    NavigationStack {
        VideoPlayerView(
            url: URL(string: "https://example.com/sample.m3u8")!,
            title: "Sample"
        )
    }
}
