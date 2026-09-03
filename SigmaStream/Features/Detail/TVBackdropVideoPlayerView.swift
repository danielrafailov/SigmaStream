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

            // Layer 2: Native AVKit VideoPlayer (Full Screen Hardware Accelerated, 0 UI chrome)
            if let player {
                VideoPlayer(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                    .disabled(true)
                    .allowsHitTesting(false)
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

        // Seamless loop when video reaches end
        itemObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            p.seek(to: .zero)
            p.play()
        }

        // Observe player readiness
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
#endif
