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
    var onPlaybackEnded: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var player: AVPlayer?
    @State private var loadError: String?
    @State private var retryTrigger = 0
    @State private var endObserver: NSObjectProtocol?

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
        .onDisappear {
            if let observer = endObserver {
                NotificationCenter.default.removeObserver(observer)
                endObserver = nil
            }
            player?.pause()
        }
    }

    private func selectEnglishAudioIfAvailable(for item: AVPlayerItem) {
        guard let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .audible) else { return }
        let englishOption = group.options.first { opt in
            let tag = (opt.extendedLanguageTag ?? "").lowercased()
            return tag.hasPrefix("en") || tag == "eng"
        }
        if let option = englishOption {
            item.select(option, in: group)
        }
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
                await MainActor.run { loadError = "No stream was found" }
                return
            case .readyToPlay:
                selectEnglishAudioIfAvailable(for: item)
                let token = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { _ in
                    onPlaybackEnded?()
                    dismiss()
                }
                await MainActor.run { endObserver = token }
                return
            case .unknown:
                break
            @unknown default:
                break
            }
        }
        await MainActor.run {
            loadError = "No stream was found"
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
                    Text("No stream was found")
                        .font(.title2)
                        .fontWeight(.semibold)
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
