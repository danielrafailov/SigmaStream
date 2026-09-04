//
//  iOSTouchPlayerView.swift
//  SigmaStream-iOS
//
//  Created by Daniel Rafailov on 2026-09-01.
//

import SwiftUI
import AVKit
import MediaPlayer

#if os(iOS)
struct CyclingThreeDotsView: View {
    @State private var activeIndex = 0
    @State private var timer: Timer?

    var body: some View {
        HStack(spacing: 9) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(activeIndex == index ? 1.0 : 0.25))
                    .frame(width: 11, height: 11)
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

struct iOSTouchPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let playableContent: PlayableContent

    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var showControls = true
    @State private var controlsTimer: Task<Void, Never>?
    @State private var isDraggingSlider = false
    @State private var dragTime: Double = 0
    @State private var selectedQuality: String?
    @State private var timeObserverToken: Any?

    @State private var isResolvingStream = true
    @State private var isBuffering = true
    @State private var streamResolveError: String?
    @State private var currentUrls: [URL] = []
    @State private var currentUrlIndex = 0
    @State private var didApplyStartTime = false
    @State private var didAttemptFreshResolve = false
    @State private var statusObservation: NSKeyValueObservation?
    @State private var timeControlStatusObservation: NSKeyValueObservation?

    // Audio & Subtitle Selection
    @State private var audibleGroup: AVMediaSelectionGroup?
    @State private var availableAudioOptions: [AVMediaSelectionOption] = []
    @State private var selectedAudioOption: AVMediaSelectionOption?

    @State private var legibleGroup: AVMediaSelectionGroup?
    @State private var availableSubtitleOptions: [AVMediaSelectionOption] = []
    @State private var selectedSubtitleOption: AVMediaSelectionOption?

    // Double-tap skip ripples
    @State private var leftRipple = false
    @State private var rightRipple = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Video Player Layer
            if let player {
                CustomVideoPlayerRepresentable(player: player)
                    .ignoresSafeArea()
                    .onTapGesture(count: 2) { location in
                        // Double-tap to seek
                        let screenWidth = UIScreen.main.bounds.width
                        if location.x < screenWidth / 2 {
                            seekRelative(-10)
                            triggerLeftRipple()
                        } else {
                            seekRelative(10)
                            triggerRightRipple()
                        }
                    }
                    .onTapGesture(count: 1) {
                        toggleControls()
                    }
            }

            // Searching for Streams / Loading Overlay
            // Shown when resolving streams OR while buffering initial video playback OR on error
            if streamResolveError != nil || isResolvingStream || (isBuffering && currentTime < 0.5) {
                ZStack {
                    Color.black.ignoresSafeArea()

                    // Top dismiss button during loading or error
                    VStack {
                        HStack {
                            Button {
                                cleanupAndDismiss()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(10)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 24)

                        Spacer()
                    }

                    if let error = streamResolveError {
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.red)

                            Text("No stream found")
                                .font(.title3.bold())
                                .foregroundStyle(.red)

                            Text(error.contains("No stream") ? "We were unable to locate an active video stream for this title." : error)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 36)

                            Button {
                                cleanupAndDismiss()
                            } label: {
                                Text("Close")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 28)
                                    .padding(.vertical, 10)
                                    .background(Color.white.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                            .padding(.top, 8)
                        }
                        .padding(24)
                    } else {
                        VStack(spacing: 16) {
                            Text(isResolvingStream ? "Searching for streams" : "Loading stream")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.white)

                            CyclingThreeDotsView()
                                .padding(.vertical, 2)

                            Text(playableContent.title)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .padding(.horizontal, 32)
                        }
                    }
                }
            } else if isBuffering && currentTime >= 0.5 {
                // Mid-playback buffering indicator
                ProgressView()
                    .scaleEffect(1.4)
                    .tint(.white)
                    .padding(20)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }

            // Left / Right Double-Tap Indicator Overlays
            if player != nil {
                HStack {
                    if leftRipple {
                        VStack {
                            Image(systemName: "gobackward.10")
                                .font(.system(size: 40, weight: .bold))
                                .foregroundStyle(.white)
                            Text("10s")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                        }
                        .padding(30)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .transition(.opacity.combined(with: .scale))
                    }
                    Spacer()
                    if rightRipple {
                        VStack {
                            Image(systemName: "goforward.10")
                                .font(.system(size: 40, weight: .bold))
                                .foregroundStyle(.white)
                            Text("10s")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                        }
                        .padding(30)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .transition(.opacity.combined(with: .scale))
                    }
                }
                .padding(.horizontal, 60)
                .allowsHitTesting(false)
            }

            // Touch HUD Controls Overlay (Only active when video player is loaded)
            if showControls && player != nil {
                ZStack {
                    // Dark gradient scrim
                    LinearGradient(
                        colors: [Color.black.opacity(0.8), Color.clear, Color.black.opacity(0.85)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                    VStack(spacing: 0) {
                        // Top Bar
                        HStack(alignment: .center, spacing: 16) {
                            Button {
                                cleanupAndDismiss()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(10)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(playableContent.title)
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .lineLimit(1)

                                if let q = selectedQuality ?? playableContent.quality {
                                    Text(q.uppercased())
                                        .font(.caption2.bold())
                                        .foregroundStyle(.cyan)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.cyan.opacity(0.2))
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                            }

                            Spacer()

                            // Audio Track Selector Menu
                            Menu {
                                if availableAudioOptions.isEmpty {
                                    Text("No alternate audio tracks")
                                } else {
                                    ForEach(availableAudioOptions, id: \.self) { option in
                                        Button {
                                            selectAudioOption(option)
                                        } label: {
                                            HStack {
                                                Text(option.displayName)
                                                if isSelectedAudio(option) {
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                }
                            } label: {
                                Image(systemName: "waveform.badge.magnifyingglass")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 36, height: 36)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }

                            // Subtitles & Captions Menu
                            Menu {
                                Button {
                                    selectSubtitleOption(nil)
                                } label: {
                                    HStack {
                                        Text("Off")
                                        if selectedSubtitleOption == nil {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }

                                if !availableSubtitleOptions.isEmpty {
                                    Divider()
                                    ForEach(availableSubtitleOptions, id: \.self) { option in
                                        Button {
                                            selectSubtitleOption(option)
                                        } label: {
                                            HStack {
                                                Text(option.displayName)
                                                if isSelectedSubtitle(option) {
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                }
                            } label: {
                                Image(systemName: selectedSubtitleOption != nil ? "captions.bubble.fill" : "captions.bubble")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(selectedSubtitleOption != nil ? .cyan : .white)
                                    .frame(width: 36, height: 36)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }

                            // AirPlay Route Picker
                            AirPlayView()
                                .frame(width: 36, height: 36)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                        Spacer()

                        // Center Playback Controls
                        HStack(spacing: 48) {
                            Button {
                                seekRelative(-10)
                                scheduleControlsHide()
                            } label: {
                                Image(systemName: "gobackward.10")
                                    .font(.system(size: 32, weight: .semibold))
                                    .foregroundStyle(.white)
                            }

                            Button {
                                togglePlayPause()
                                scheduleControlsHide()
                            } label: {
                                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 48, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 72, height: 72)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }

                            Button {
                                seekRelative(10)
                                scheduleControlsHide()
                            } label: {
                                Image(systemName: "goforward.10")
                                    .font(.system(size: 32, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                        }

                        Spacer()

                        // Bottom Scrubber Bar & Timestamps
                        VStack(spacing: 8) {
                            // Slider
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    // Track Background
                                    Capsule()
                                        .fill(Color.white.opacity(0.3))
                                        .frame(height: isDraggingSlider ? 8 : 5)

                                    // Progress Track
                                    Capsule()
                                        .fill(Color.red)
                                        .frame(
                                            width: max(0, min(geo.size.width, geo.size.width * CGFloat(progressFraction))),
                                            height: isDraggingSlider ? 8 : 5
                                        )

                                    // Scrubber Thumb
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: isDraggingSlider ? 18 : 12, height: isDraggingSlider ? 18 : 12)
                                        .shadow(color: .black.opacity(0.5), radius: 3)
                                        .offset(x: max(0, min(geo.size.width - 12, geo.size.width * CGFloat(progressFraction) - 6)))
                                }
                                .frame(height: 24)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            isDraggingSlider = true
                                            let fraction = max(0, min(1, value.location.x / geo.size.width))
                                            dragTime = duration * Double(fraction)
                                            resetControlsTimer()
                                        }
                                        .onEnded { value in
                                            let fraction = max(0, min(1, value.location.x / geo.size.width))
                                            let targetTime = duration * Double(fraction)
                                            seek(to: targetTime)
                                            isDraggingSlider = false
                                            scheduleControlsHide()
                                        }
                                )
                            }
                            .frame(height: 24)

                            // Time Labels
                            HStack {
                                Text(formatTime(isDraggingSlider ? dragTime : currentTime))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.white)

                                Spacer()

                                Text("-" + formatTime(max(0, duration - (isDraggingSlider ? dragTime : currentTime))))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                    }
                }
                .transition(.opacity.animation(.easeInOut(duration: 0.25)))
            }
        }
        .statusBarHidden(!showControls && player != nil && !isBuffering)
        .onAppear {
            lockLandscapeOrientation()
            currentUrls = playableContent.urls
            selectedQuality = playableContent.quality
            currentUrlIndex = 0
            didApplyStartTime = false
            didAttemptFreshResolve = false
            if currentUrls.isEmpty {
                resolveAndStartPlayback()
            } else if let first = currentUrls.first {
                isResolvingStream = false
                isBuffering = true
                initializePlayer(with: first)
            }
        }
        .onDisappear {
            restoreDefaultOrientation()
            teardownPlayer()
        }
    }

    private func lockLandscapeOrientation() {
        AppDelegate.orientationLock = .landscape
        if let windowScene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
            let geometryPreferences = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: .landscapeRight)
            windowScene.requestGeometryUpdate(geometryPreferences) { _ in }
        }
        UIViewController.attemptRotationToDeviceOrientation()
    }

    private func restoreDefaultOrientation() {
        AppDelegate.orientationLock = .allButUpsideDown
        if let windowScene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
            let geometryPreferences = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: .portrait)
            windowScene.requestGeometryUpdate(geometryPreferences) { _ in }
        }
        UIViewController.attemptRotationToDeviceOrientation()
    }

    private var progressFraction: Double {
        guard duration > 0 else { return 0 }
        let time = isDraggingSlider ? dragTime : currentTime
        return max(0, min(1, time / duration))
    }

    private func resolveAndStartPlayback() {
        isResolvingStream = true
        isBuffering = true
        streamResolveError = nil

        Task {
            do {
                let resolved: (urls: [URL], quality: String?)
                if let movieId = playableContent.movieId {
                    resolved = try await appState.streamingService.playableURLsAndQualityForMovie(tmdbId: movieId)
                } else if let seriesId = playableContent.tvSeriesId,
                          let season = playableContent.season,
                          let episode = playableContent.episode {
                    resolved = try await appState.streamingService.playableURLsAndQualityForEpisode(
                        seriesId: seriesId,
                        season: season,
                        episode: episode
                    )
                } else {
                    throw StreamingError.noSourcesAvailable("No stream found")
                }

                guard !resolved.urls.isEmpty else {
                    throw StreamingError.noSourcesAvailable("No stream found")
                }

                await MainActor.run {
                    self.currentUrls = resolved.urls
                    self.currentUrlIndex = 0
                    self.selectedQuality = resolved.quality
                    self.isResolvingStream = false
                    if let first = resolved.urls.first {
                        self.initializePlayer(with: first)
                    }
                }
            } catch {
                await MainActor.run {
                    self.isResolvingStream = false
                    self.isBuffering = false
                    let msg = userFacingStreamingErrorMessage(for: error)
                    self.streamResolveError = msg.isEmpty ? "No stream found" : msg
                }
            }
        }
    }

    private func initializePlayer(with url: URL) {
        isBuffering = true
        // Configure AVAudioSession for AirPlay video & audio routing
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("AudioSession setup error: \(error)")
        }

        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 1
        item.preferredPeakBitRate = 0

        let avPlayer = AVPlayer(playerItem: item)
        avPlayer.allowsExternalPlayback = true
        avPlayer.usesExternalPlaybackWhileExternalScreenIsActive = true
        avPlayer.preventsDisplaySleepDuringVideoPlayback = true
        avPlayer.automaticallyWaitsToMinimizeStalling = true
        
        let englishCriteria = AVPlayerMediaSelectionCriteria(
            preferredLanguages: ["en", "eng", "en-US", "en-GB"],
            preferredMediaCharacteristics: nil
        )
        avPlayer.setMediaSelectionCriteria(englishCriteria, forMediaCharacteristic: .audible)
        
        // Clean up previous observations
        statusObservation?.invalidate()
        timeControlStatusObservation?.invalidate()

        // Observe player item status
        statusObservation = item.observe(\.status, options: [.new, .initial]) { [weak avPlayer] currentItem, _ in
            DispatchQueue.main.async {
                switch currentItem.status {
                case .readyToPlay:
                    self.isResolvingStream = false
                    self.isBuffering = false
                    if !self.didApplyStartTime {
                        if let startTime = self.playableContent.startTime, startTime > 5 {
                            let cmTime = CMTime(seconds: startTime, preferredTimescale: 600)
                            avPlayer?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
                        }
                        self.didApplyStartTime = true
                    }
                    avPlayer?.play()
                    self.isPlaying = true
                case .failed:
                    print("Stream failed for URL: \(url). Error: \(String(describing: currentItem.error))")
                    self.tryNextURLOrFallback()
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
        }

        // Observe player timeControlStatus
        timeControlStatusObservation = avPlayer.observe(\.timeControlStatus, options: [.new]) { player, _ in
            DispatchQueue.main.async {
                switch player.timeControlStatus {
                case .waitingToPlayAtSpecifiedRate:
                    if self.isPlaying {
                        self.isBuffering = true
                    }
                case .playing:
                    self.isBuffering = false
                    self.isResolvingStream = false
                case .paused:
                    self.isBuffering = false
                @unknown default:
                    break
                }
            }
        }

        Task {
            if let group = try? await item.asset.loadMediaSelectionGroup(for: .audible) {
                let englishOption = group.options.first { opt in
                    if let lang = opt.locale?.language.languageCode?.identifier.lowercased(), lang == "en" { return true }
                    if let tag = opt.extendedLanguageTag?.lowercased(), tag.hasPrefix("en") || tag == "eng" { return true }
                    if opt.displayName.lowercased().contains("english") { return true }
                    return false
                }
                if let englishOption {
                    item.select(englishOption, in: group)
                }
            }
            await loadMediaSelectionOptions(for: item)
        }
        
        self.player = avPlayer

        // Observe periodic playback time
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            if !isDraggingSlider {
                self.currentTime = time.seconds
                if let currentItem = avPlayer.currentItem, currentItem.duration.isNumeric {
                    self.duration = currentItem.duration.seconds
                }
                saveProgress()
            }
        }

        avPlayer.play()
        isPlaying = true
        scheduleControlsHide()
    }

    private func tryNextURLOrFallback() {
        teardownPlayer()
        currentUrlIndex += 1
        if currentUrlIndex < currentUrls.count {
            let nextURL = currentUrls[currentUrlIndex]
            initializePlayer(with: nextURL)
        } else {
            if !didAttemptFreshResolve {
                didAttemptFreshResolve = true
                currentUrlIndex = 0
                currentUrls = []
                resolveAndStartPlayback()
            } else {
                isResolvingStream = false
                isBuffering = false
                streamResolveError = "No playable stream found for this title. Please try another source or try again later."
            }
        }
    }

    private func teardownPlayer() {
        statusObservation?.invalidate()
        statusObservation = nil
        timeControlStatusObservation?.invalidate()
        timeControlStatusObservation = nil
        if let token = timeObserverToken, let player {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
        saveProgress()
        player?.pause()
        player = nil
    }

    private func cleanupAndDismiss() {
        restoreDefaultOrientation()
        teardownPlayer()
        dismiss()
    }

    private func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    private func seek(to targetSeconds: Double) {
        guard let player else { return }
        let cmTime = CMTime(seconds: targetSeconds, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        self.currentTime = targetSeconds
        saveProgress()
    }

    private func seekRelative(_ deltaSeconds: Double) {
        let newTime = max(0, min(duration, currentTime + deltaSeconds))
        seek(to: newTime)
    }

    private func saveProgress() {
        guard duration > 60, currentTime > 5 else { return }
        if let movieId = playableContent.movieId {
            appState.watchProgressManager.updateMovieProgress(
                movieId: movieId,
                position: currentTime,
                duration: duration
            )
        } else if let tvId = playableContent.tvSeriesId,
                  let season = playableContent.season,
                  let episode = playableContent.episode {
            appState.watchProgressManager.updateEpisodeProgress(
                seriesId: tvId,
                season: season,
                episode: episode,
                position: currentTime,
                duration: duration
            )
        }
    }

    private func toggleControls() {
        withAnimation {
            showControls.toggle()
        }
        if showControls {
            scheduleControlsHide()
        }
    }

    private func resetControlsTimer() {
        controlsTimer?.cancel()
        controlsTimer = nil
    }

    private func scheduleControlsHide() {
        resetControlsTimer()
        controlsTimer = Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation {
                    if isPlaying && !isDraggingSlider {
                        showControls = false
                    }
                }
            }
        }
    }

    private func triggerLeftRipple() {
        withAnimation(.easeIn(duration: 0.15)) { leftRipple = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.easeOut(duration: 0.25)) { leftRipple = false }
        }
    }

    private func triggerRightRipple() {
        withAnimation(.easeIn(duration: 0.15)) { rightRipple = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.easeOut(duration: 0.25)) { rightRipple = false }
        }
    }

    private func loadMediaSelectionOptions(for item: AVPlayerItem) async {
        do {
            if let aGroup = try await item.asset.loadMediaSelectionGroup(for: .audible) {
                self.audibleGroup = aGroup
                self.availableAudioOptions = aGroup.options
                self.selectedAudioOption = item.currentMediaSelection.selectedMediaOption(in: aGroup)
            }
            if let lGroup = try await item.asset.loadMediaSelectionGroup(for: .legible) {
                self.legibleGroup = lGroup
                self.availableSubtitleOptions = lGroup.options
                self.selectedSubtitleOption = item.currentMediaSelection.selectedMediaOption(in: lGroup)
            }
        } catch {
            print("Failed to load media selection groups: \(error)")
        }
    }

    private func selectAudioOption(_ option: AVMediaSelectionOption) {
        guard let player, let item = player.currentItem, let audibleGroup else { return }
        item.select(option, in: audibleGroup)
        selectedAudioOption = option
    }

    private func selectSubtitleOption(_ option: AVMediaSelectionOption?) {
        guard let player, let item = player.currentItem, let legibleGroup else { return }
        item.select(option, in: legibleGroup)
        selectedSubtitleOption = option
    }

    private func isSelectedAudio(_ option: AVMediaSelectionOption) -> Bool {
        if let selectedAudioOption {
            return selectedAudioOption == option || selectedAudioOption.displayName == option.displayName
        }
        return false
    }

    private func isSelectedSubtitle(_ option: AVMediaSelectionOption) -> Bool {
        if let selectedSubtitleOption {
            return selectedSubtitleOption == option || selectedSubtitleOption.displayName == option.displayName
        }
        return false
    }

    private func formatTime(_ totalSeconds: Double) -> String {
        guard !totalSeconds.isNaN && !totalSeconds.isInfinite else { return "0:00" }
        let total = Int(totalSeconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

// UIKit AVPlayerLayer Representable for smooth rendering
struct CustomVideoPlayerRepresentable: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> CustomPlayerUIView {
        let view = CustomPlayerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: CustomPlayerUIView, context: Context) {
        uiView.playerLayer.player = player
    }
}

class CustomPlayerUIView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}

// Native AirPlay Route Picker Button
struct AirPlayView: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let routePicker = AVRoutePickerView()
        routePicker.tintColor = .white
        routePicker.activeTintColor = .cyan
        routePicker.prioritizesVideoDevices = true
        return routePicker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#endif
