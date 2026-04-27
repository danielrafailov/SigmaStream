//
//  VideoPlayerView.swift
//  SigmaStream
//
//  Native AVPlayer playback for HLS/MP4 streams from CinePro.
//

import AVKit
import Foundation
import SwiftUI

private enum StreamStatus: Equatable {
    case trying(index: Int, total: Int)
    case failed(index: Int)
    case found
}

struct VideoPlayerView: View {
    let urls: [URL]
    let title: String
    var onPlaybackEnded: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var player: AVPlayer?
    @State private var loadError: String?
    @State private var currentURLIndex = 0
    @State private var endObserver: NSObjectProtocol?
    @State private var streamStatus: StreamStatus?

    private let loadTimeout: TimeInterval = 20
    private let failedMessageDuration: TimeInterval = 0.8
    private let pollInterval: TimeInterval = 0.2
    private let foundMessageDuration: TimeInterval = 0.15

    var body: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            }

            if let status = streamStatus {
                streamStatusOverlay(status: status)
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
        .task(id: currentURLIndex) {
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
        guard currentURLIndex < urls.count else {
            await MainActor.run { loadError = "No stream was found" }
            return
        }
        loadError = nil
        await MainActor.run {
            streamStatus = .trying(index: currentURLIndex + 1, total: urls.count)
        }
        let url = urls[currentURLIndex]
        let newPlayer = AVPlayer(url: url)
        await MainActor.run { player = newPlayer }
        newPlayer.play()

        let maxPolls = Int(loadTimeout / pollInterval)
        for _ in 0..<maxPolls {
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            guard let item = newPlayer.currentItem else { continue }
            switch item.status {
            case .failed:
                let message = playbackFailureMessage(for: item, url: url)
                await MainActor.run {
                    streamStatus = .failed(index: currentURLIndex + 1)
                }
                try? await Task.sleep(nanoseconds: UInt64(failedMessageDuration * 1_000_000_000))
                await MainActor.run {
                    player = nil
                    currentURLIndex += 1
                    if currentURLIndex >= urls.count {
                        streamStatus = nil
                        loadError = message
                    }
                }
                return
            case .readyToPlay:
                selectEnglishAudioIfAvailable(for: item)
                let token = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { _ in
                    onPlaybackEnded?()
                    dismiss()
                }
                await MainActor.run { endObserver = token }
                await MainActor.run {
                    streamStatus = .found
                }
                try? await Task.sleep(nanoseconds: UInt64(foundMessageDuration * 1_000_000_000))
                await MainActor.run {
                    streamStatus = nil
                }
                return
            case .unknown:
                break
            @unknown default:
                break
            }
        }
        await MainActor.run {
            streamStatus = .failed(index: currentURLIndex + 1)
        }
        try? await Task.sleep(nanoseconds: UInt64(failedMessageDuration * 1_000_000_000))
        await MainActor.run {
            player = nil
            currentURLIndex += 1
            if currentURLIndex >= urls.count {
                streamStatus = nil
                loadError = "No stream was found (timed out while loading)"
            }
        }
    }

    private func playbackFailureMessage(for item: AVPlayerItem, url: URL) -> String {
        if let err = item.error {
            return "Stream failed: \(err.localizedDescription)"
        }
        if let log = item.errorLog(),
           let event = log.events.last {
            if let statusCode = event.errorStatusCode as Int?,
               statusCode != 0 {
                return "Stream failed (HTTP \(statusCode))"
            }
            if let errorComment = event.errorComment,
               !errorComment.isEmpty {
                return "Stream failed: \(errorComment)"
            }
        }
        return "No stream was found for \(url.host ?? "this source")"
    }

    @ViewBuilder
    private func streamStatusOverlay(status: StreamStatus) -> some View {
        Color.black.opacity(0.85)
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: 24) {
                    switch status {
                    case .trying(let index, let total):
                        ProgressView()
                            .scaleEffect(1.2)
                            .tint(.white)
                        Text("Trying stream \(index) of \(total)")
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                    case .failed(let index):
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.red)
                        Text("Stream \(index) failed")
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundStyle(.red)
                    case .found:
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.green)
                        Text("Found stream!")
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundStyle(.green)
                    }
                    if case .trying = status {
                        Button("Cancel") {
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                        .padding(.top, 8)
                    }
                }
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
                    Text(message)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    HStack(spacing: 16) {
                        Button("Retry") {
                            loadError = nil
                            currentURLIndex = 0
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
            urls: [URL(string: "https://example.com/sample.m3u8")!],
            title: "Sample"
        )
    }
}
