//
//  VideoPlayerView.swift
//  SigmaStream
//
//  Native AVPlayer playback for HLS/MP4 streams from CinePro.
//

import AVKit
import Foundation
import SwiftUI

struct CyclingThreeDotsView: View {
    @State private var activeIndex = 0
    @State private var timer: Timer?

    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(activeIndex == index ? 1.0 : 0.25))
                    .frame(width: 14, height: 14)
                    .scaleEffect(activeIndex == index ? 1.35 : 0.85)
                    .animation(.easeInOut(duration: 0.25), value: activeIndex)
            }
        }
        .onAppear {
            timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { _ in
                activeIndex = (activeIndex + 1) % 3
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
}

struct VideoPlayerView: View {
    let playableContent: PlayableContent
    var onPlaybackEnded: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var player: AVPlayer?
    @State private var loadError: String?
    @State private var currentURLIndex = 0
    @State private var resolvedURLs: [URL] = []
    @State private var isResolving = true
    @State private var endObserver: NSObjectProtocol?
    @State private var stallObserver: NSObjectProtocol?
    @State private var timeObserver: Any?
    @State private var didApplyStartTime = false

    private let loadTimeout: TimeInterval = 20
    private let pollInterval: TimeInterval = 0.2
    private let progressSaveInterval: TimeInterval = 15

    /// Larger forward buffer reduces intermittent freezes on high-bitrate streams.
    private let preferredForwardBufferDuration: TimeInterval = 25
    /// Cap adaptive bitrate (~6 Mbps) so Apple TV prefers stable 1080p-class variants.
    private let preferredPeakBitRate: Double = 6_000_000

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player, !isResolving {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else if let error = loadError {
                loadErrorOverlay(message: error)
            } else {
                // Fullscreen Searching for Streams Loading Screen with Dot Animation
                VStack(spacing: 24) {
                    Text("Searching for streams")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(.white)

                    CyclingThreeDotsView()
                        .padding(.vertical, 4)

                    Text(playableContent.title)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .navigationTitle(playableContent.title)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .task {
            await resolveAndStartPlayback()
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
            NotificationCenter.default.removeObserver(stallObserver)
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
        guard dur > 60, position > 5 else { return }

        if let movieId = playableContent.movieId {
            appState.watchProgressManager.updateMovieProgress(movieId: movieId, position: position, duration: dur)
        } else if let seriesId = playableContent.tvSeriesId,
                  let season = playableContent.season,
                  let episode = playableContent.episode {
            appState.watchProgressManager.updateEpisodeProgress(
                seriesId: seriesId,
                season: season,
                episode: episode,
                position: position,
                duration: dur
            )
        }
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

    private func installEndObserver(for item: AVPlayerItem) {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [self] _ in
            onPlaybackEnded?()
            dismiss()
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

    private func resolveAndStartPlayback() async {
        if resolvedURLs.isEmpty {
            if !playableContent.urls.isEmpty {
                resolvedURLs = playableContent.urls
            } else {
                do {
                    if let movieId = playableContent.movieId {
                        let (urls, _) = try await appState.streamingService.playableURLsAndQualityForMovie(tmdbId: movieId)
                        resolvedURLs = urls
                    } else if let seriesId = playableContent.tvSeriesId,
                              let season = playableContent.season,
                              let episode = playableContent.episode {
                        let (urls, _) = try await appState.streamingService.playableURLsAndQualityForEpisode(seriesId: seriesId, season: season, episode: episode)
                        resolvedURLs = urls
                    }
                } catch {
                    await MainActor.run {
                        loadError = "Unable to locate an active stream for this title."
                        isResolving = false
                    }
                    return
                }
            }
        }

        guard !resolvedURLs.isEmpty else {
            await MainActor.run {
                loadError = "No stream was found (none marked playable)."
                isResolving = false
            }
            return
        }

        await startPlaybackForCurrentIndex()
    }

    private func startPlaybackForCurrentIndex() async {
        guard currentURLIndex < resolvedURLs.count else {
            await MainActor.run {
                loadError = "No working stream was found."
                isResolving = false
            }
            return
        }

        let url = resolvedURLs[currentURLIndex]
        let newPlayer = makeConfiguredPlayer(url: url)
        installProgressObserver(on: newPlayer)

        let maxPolls = Int(loadTimeout / pollInterval)
        for _ in 0..<maxPolls {
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            guard let item = newPlayer.currentItem else { continue }
            switch item.status {
            case .failed:
                tearDownObservers()
                currentURLIndex += 1
                if currentURLIndex >= resolvedURLs.count {
                    await MainActor.run {
                        loadError = "Stream failed to load."
                        isResolving = false
                    }
                } else {
                    await startPlaybackForCurrentIndex()
                }
                return
            case .readyToPlay:
                selectEnglishAudioIfAvailable(for: item)
                if !didApplyStartTime, let start = playableContent.startTime, start > 0 {
                    let seekTime = CMTime(seconds: start, preferredTimescale: 600)
                    let tolerance = CMTime(seconds: 1, preferredTimescale: 600)
                    await newPlayer.seek(to: seekTime, toleranceBefore: tolerance, toleranceAfter: tolerance)
                    didApplyStartTime = true
                }
                installStallRecovery(for: item, player: newPlayer)
                installEndObserver(for: item)
                await MainActor.run {
                    self.player = newPlayer
                    self.isResolving = false
                }
                newPlayer.play()
                return
            default:
                break
            }
        }

        // Timed out on this stream
        currentURLIndex += 1
        if currentURLIndex >= resolvedURLs.count {
            await MainActor.run {
                loadError = "Timed out searching for stream."
                isResolving = false
            }
        } else {
            await startPlaybackForCurrentIndex()
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
                            isResolving = true
                            currentURLIndex = 0
                            didApplyStartTime = false
                            Task { await resolveAndStartPlayback() }
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
    init(content: PlayableContent, watchProgress: WatchProgressManager? = nil, onPlaybackEnded: (() -> Void)? = nil) {
        self.playableContent = content
        self.onPlaybackEnded = onPlaybackEnded
    }

    init(urls: [URL], title: String, startTime: TimeInterval? = nil, onProgress: ((TimeInterval, TimeInterval) -> Void)? = nil, onPlaybackEnded: (() -> Void)? = nil) {
        self.playableContent = PlayableContent(urls: urls, title: title, startTime: startTime)
        self.onPlaybackEnded = onPlaybackEnded
    }
}
