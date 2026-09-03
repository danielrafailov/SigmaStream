//
//  TVBackdropVideoPlayerView.swift
//  SigmaStream
//
//  Created by Daniel Rafailov on 2026-09-03.
//

import SwiftUI
import AVKit

#if os(tvOS)
struct TVBackdropVideoPlayerView: View {
    let streamURL: URL?
    let fallbackImageURL: URL?

    @State private var player: AVPlayer?
    @State private var isVideoReady = false
    @State private var isMuted = true

    var body: some View {
        ZStack {
            // Layer 1: Fallback Backdrop Image
            if let fallbackImageURL {
                AsyncImage(url: fallbackImageURL) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Color.black
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
            } else {
                Color.black
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
            }

            // Layer 2: AVPlayer Video Layer (Crossfades smoothly over the poster)
            if let player {
                TVPlayerLayerRepresentable(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                    .opacity(isVideoReady ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.8), value: isVideoReady)
            }
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            teardownPlayer()
        }
        .onChange(of: streamURL) { _, _ in
            setupPlayer()
        }
    }

    private func setupPlayer() {
        guard let streamURL else { return }
        teardownPlayer()

        let item = AVPlayerItem(url: streamURL)
        item.preferredForwardBufferDuration = 1.0
        let p = AVPlayer(playerItem: item)
        p.isMuted = isMuted
        p.automaticallyWaitsToMinimizeStalling = false
        p.actionAtItemEnd = .none

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            p.seek(to: .zero)
            p.play()
        }

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemNewAccessLogEntry,
            object: item,
            queue: .main
        ) { _ in
            withAnimation(.easeInOut(duration: 0.8)) {
                self.isVideoReady = true
            }
        }

        p.play()
        self.player = p

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.8)) {
                self.isVideoReady = true
            }
        }
    }

    private func teardownPlayer() {
        player?.pause()
        player = nil
        isVideoReady = false
    }
}

private struct TVPlayerLayerRepresentable: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> TVPlayerUIView {
        let view = TVPlayerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: TVPlayerUIView, context: Context) {
        uiView.playerLayer.player = player
    }
}

private class TVPlayerUIView: UIView {
    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}
#endif
