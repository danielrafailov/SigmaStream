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
    let streamURLs: [URL]
    let fallbackImageURL: URL?

    @State private var player: AVPlayer?
    @State private var isVideoReady = false
    @State private var currentURLIndex = 0
    @State private var statusObserver: NSKeyValueObservation?
    @State private var itemObserver: NSObjectProtocol?

    var body: some View {
        ZStack {
            // Layer 1: Fallback Backdrop Image (Full Screen Edge-to-Edge)
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

            // Layer 2: Native AVPlayer Full Screen Video Layer (Zero UI clutter / channel names)
            if let player {
                TVPlayerLayerRepresentable(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                    .opacity(isVideoReady ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.8), value: isVideoReady)
            }
        }
        .onAppear {
            currentURLIndex = 0
            setupPlayer()
        }
        .onDisappear {
            teardownPlayer()
        }
        .onChange(of: streamURLs) { _, newURLs in
            if !newURLs.isEmpty && player == nil {
                currentURLIndex = 0
                setupPlayer()
            }
        }
    }

    private func setupPlayer() {
        guard currentURLIndex < streamURLs.count else { return }
        teardownPlayer()

        let targetURL = streamURLs[currentURLIndex]
        let asset = AVURLAsset(url: targetURL)
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 1.0
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = false

        let p = AVPlayer(playerItem: item)
        p.isMuted = true
        p.automaticallyWaitsToMinimizeStalling = false
        p.actionAtItemEnd = .none

        // Seamless loop
        itemObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            p.seek(to: .zero)
            p.play()
        }

        // KVO on player status to detect successful render or failure
        statusObserver = item.observe(\.status, options: [.new]) { [self] observedItem, _ in
            DispatchQueue.main.async {
                if observedItem.status == .readyToPlay {
                    withAnimation(.easeInOut(duration: 0.8)) {
                        self.isVideoReady = true
                    }
                } else if observedItem.status == .failed {
                    self.currentURLIndex += 1
                    self.setupPlayer()
                }
            }
        }

        p.play()
        self.player = p
    }

    private func teardownPlayer() {
        if let itemObserver {
            NotificationCenter.default.removeObserver(itemObserver)
            self.itemObserver = nil
        }
        statusObserver?.invalidate()
        statusObserver = nil
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
        view.playerLayer.needsDisplayOnBoundsChange = true
        return view
    }

    func updateUIView(_ uiView: TVPlayerUIView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
        uiView.playerLayer.frame = uiView.bounds
    }
}

private class TVPlayerUIView: UIView {
    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}
#endif
