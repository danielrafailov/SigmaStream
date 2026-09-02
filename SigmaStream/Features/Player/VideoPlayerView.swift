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
    var startTime: TimeInterval? = nil
    var onProgress: ((TimeInterval, TimeInterval) -> Void)? = nil
    var onPlaybackEnded: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var player: AVPlayer?
    @State private var loadError: String?
    @State private var currentURLIndex = 0
    @State private var endObserver: NSObjectProtocol?
    @State private var stallObserver: NSObjectProtocol?
    @State private var timeObserver: Any?
    @State private var didApplyStartTime = false
    @State private var streamStatus: StreamStatus?

    private let loadTimeout: TimeInterval = 20
    private let failedMessageDuration: TimeInterval = 0.35
    private let pollInterval: TimeInterval = 0.2
    private let foundMessageDuration: TimeInterval = 0
    private let progressSaveInterval: TimeInterval = 15

    /// Larger forward buffer reduces intermittent freezes on high-bitrate streams.
    private let preferredForwardBufferDuration: TimeInterval = 25
    /// Cap adaptive bitrate (~6 Mbps) so Apple TV prefers stable 1080p-class variants.
    private let preferredPeakBitRate: Double = 6_000_000

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
            didApplyStartTime = false
            await startPlaybackAndObserve()
        }
        .onDisappear {
            flushProgress()
            tearDownObservers()
            player?.pause()
        }
    }

    private func tearDownObservers() {
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
            endObserver = nil
        }
        if let observer = stallObserver {
            NotificationCenter.default.removeObserver(observer)
            stallObserver = nil
        }
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }

    private func flushProgress() {
        guard let player, let item = player.currentItem else { return }
        let position = player.currentTime().seconds
        let duration = item.duration.seconds
        guard position.isFinite, position >= 0 else { return }
        let dur = duration.isFinite && duration > 0 ? duration : 0
        onProgress?(position, dur)
    }

    private func selectEnglishAudioIfAvailable(for item: AVPlayerItem) {
        Task {
            guard let group = try? await item.asset.loadMediaSelectionGroup(for: .audible) else { return }
            let englishOption = group.options.first { opt in
                if let lang = opt.locale?.language.languageCode?.identifier.lowercased(), lang == "en" { return true }
                if let tag = opt.extendedLanguageTag?.lowercased(), tag.hasPrefix("en") || tag == "eng" { return true }
                if opt.displayName.lowercased().contains("english") { return true }
                return false
            }
            if let option = englishOption {
                item.select(option, in: group)
            }
        }
    }

    private func configurePlaybackItem(_ item: AVPlayerItem) {
        item.preferredForwardBufferDuration = preferredForwardBufferDuration
        item.preferredPeakBitRate = preferredPeakBitRate
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = false
    }

    private func makeConfiguredPlayer(url: URL) -> AVPlayer {
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        configurePlaybackItem(item)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.automaticallyWaitsToMinimizeStalling = true
        
        let englishCriteria = AVPlayerMediaSelectionCriteria(
            preferredLanguages: ["en", "eng", "en-US", "en-GB"],
            preferredMediaCharacteristics: nil
        )
        newPlayer.setMediaSelectionCriteria(englishCriteria, forMediaCharacteristic: .audible)
        return newPlayer
    }

    private func installProgressObserver(on player: AVPlayer) {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        let interval = CMTime(seconds: progressSaveInterval, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { _ in
            flushProgress()
        }
    }

    private func installStallRecovery(for item: AVPlayerItem, player: AVPlayer) {
        if let stallObserver {
            NotificationCenter.default.removeObserver(stallObserver)
            self.stallObserver = nil
        }
        stallObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item,
            queue: .main
        ) { [weak player] _ in
            guard let player else { return }
            Task { @MainActor in
                for _ in 0..<50 {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    guard let current = player.currentItem, current === item else { return }
                    if current.isPlaybackLikelyToKeepUp || current.status == .readyToPlay {
                        if player.rate == 0 {
                            player.play()
                        }
                        return
                    }
                }
                if player.rate == 0 {
                    player.play()
                }
            }
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
        let newPlayer = makeConfiguredPlayer(url: url)
        await MainActor.run { player = newPlayer }

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
                    tearDownObservers()
                    currentURLIndex += 1
                    if currentURLIndex >= urls.count {
                        streamStatus = nil
                        loadError = message
                    }
                }
                return
            case .readyToPlay:
                selectEnglishAudioIfAvailable(for: item)
                if !didApplyStartTime, let start = startTime, start > 0 {
                    let seekTime = CMTime(seconds: start, preferredTimescale: 600)
                    let tolerance = CMTime(seconds: 1, preferredTimescale: 600)
                    await newPlayer.seek(to: seekTime, toleranceBefore: tolerance, toleranceAfter: tolerance)
                    didApplyStartTime = true
                }
                let token = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: item,
                    queue: .main
                ) { _ in
                    onPlaybackEnded?()
                    dismiss()
                }
                await MainActor.run {
                    endObserver = token
                    installStallRecovery(for: item, player: newPlayer)
                    installProgressObserver(on: newPlayer)
                }
                newPlayer.play()
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
            tearDownObservers()
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
        Color.black
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
                            didApplyStartTime = false
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

extension VideoPlayerView {
    init(content: PlayableContent, watchProgress: WatchProgressManager, onPlaybackEnded: (() -> Void)? = nil) {
        self.urls = content.urls
        self.title = content.title
        self.startTime = content.startTime
        self.onPlaybackEnded = onPlaybackEnded
        self.onProgress = { position, duration in
            if let movieId = content.movieId {
                watchProgress.updateMovieProgress(movieId: movieId, position: position, duration: duration)
            } else if let seriesId = content.tvSeriesId,
                      let season = content.season,
                      let episode = content.episode {
                watchProgress.updateEpisodeProgress(
                    seriesId: seriesId,
                    season: season,
                    episode: episode,
                    position: position,
                    duration: duration
                )
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
