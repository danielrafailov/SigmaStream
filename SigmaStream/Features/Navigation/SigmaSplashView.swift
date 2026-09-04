//
//  SigmaSplashView.swift
//  SigmaStream
//
//  Created by Daniel Rafailov on 2026-09-02.
//

import SwiftUI
import AVKit

#if os(tvOS)
struct SigmaSplashView: View {
    let onFinished: () -> Void

    @State private var player: AVPlayer?
    @State private var hasFinished = false
    @State private var endObserver: NSObjectProtocol?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                SplashVideoPlayerRepresentable(player: player)
                    .ignoresSafeArea()
            }
        }
        .onTapGesture {
            finishSplash()
        }
        .onAppear {
            setupAndPlay()
        }
        .onDisappear {
            teardown()
        }
    }

    private func setupAndPlay() {
        guard let url = Bundle.main.url(forResource: "SigmaIntro", withExtension: "mp4") else {
            finishSplash()
            return
        }

        let item = AVPlayerItem(url: url)
        let avPlayer = AVPlayer(playerItem: item)
        avPlayer.actionAtItemEnd = .none
        avPlayer.preventsDisplaySleepDuringVideoPlayback = true
        self.player = avPlayer

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            finishSplash()
        }

        avPlayer.play()

        // Safety fallback timer dynamically based on video duration
        Task {
            var durationSec = 12.0
            if let d = try? await item.asset.load(.duration), d.seconds.isFinite, d.seconds > 0 {
                durationSec = d.seconds
            }
            try? await Task.sleep(nanoseconds: UInt64((durationSec + 2.5) * 1_000_000_000))
            if !hasFinished {
                await MainActor.run {
                    finishSplash()
                }
            }
        }
    }

    private func finishSplash() {
        guard !hasFinished else { return }
        hasFinished = true
        teardown()
        withAnimation(.easeInOut(duration: 0.4)) {
            onFinished()
        }
    }

    private func teardown() {
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
            endObserver = nil
        }
        player?.pause()
        player = nil
    }
}

private struct SplashVideoPlayerRepresentable: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> SplashPlayerUIView {
        let view = SplashPlayerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: SplashPlayerUIView, context: Context) {
        uiView.playerLayer.player = player
    }
}

private class SplashPlayerUIView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}
#endif
