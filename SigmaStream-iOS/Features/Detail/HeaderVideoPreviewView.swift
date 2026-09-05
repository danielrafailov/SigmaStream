//
//  HeaderVideoPreviewView.swift
//  SigmaStream-iOS
//
//  Created by Daniel Rafailov on 2026-09-02.
//

import SwiftUI
import WebKit
import AVFoundation

#if os(iOS)
struct HeaderVideoPreviewView: View {
    let videoKey: String
    let fallbackImageURL: URL?
    let height: CGFloat

    @State private var isMuted = true
    @State private var isVideoReady = false
    @State private var hasError = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Layer 1: Static Backdrop Fallback
            if let fallbackImageURL {
                AsyncImage(url: fallbackImageURL) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Color.black
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: height)
                .clipped()
            } else {
                Color.black
                    .frame(maxWidth: .infinity, maxHeight: height)
            }

            // Layer 2: Auto-playing Video Preview (Fades in over backdrop only when playing with no errors)
            if !hasError && !videoKey.isEmpty {
                TrailerWebViewRepresentable(
                    videoKey: videoKey,
                    isMuted: isMuted,
                    isVideoReady: $isVideoReady,
                    hasError: $hasError
                )
                .frame(maxWidth: .infinity, maxHeight: height)
                .opacity(isVideoReady ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.5), value: isVideoReady)
                .allowsHitTesting(false) // Allow touch pass-through for vertical scrolling
            }

            // Layer 3: Top-Right Liquid Glass Audio Mute/Unmute Control Pill
            if isVideoReady && !hasError {
                Button {
                    isMuted.toggle()
                    if !isMuted {
                        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
                        try? AVAudioSession.sharedInstance().setActive(true)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text(isMuted ? "Muted" : "Audio On")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 18)
                .padding(.top, 50)
                .transition(.opacity.combined(with: .scale))
            }
        }
        .frame(height: height)
        .onDisappear {
            isMuted = true
        }
    }
}

private struct TrailerWebViewRepresentable: UIViewRepresentable {
    let videoKey: String
    let isMuted: Bool
    @Binding var isVideoReady: Bool
    @Binding var hasError: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = false
        
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black

        if let embedURL = URL(string: "https://www.youtube-nocookie.com/embed/\(videoKey)?autoplay=1&mute=1&playsinline=1&controls=0&rel=0&modestbranding=1&loop=1&playlist=\(videoKey)&enablejsapi=1") {
            var request = URLRequest(url: embedURL)
            request.setValue("https://www.themoviedb.org", forHTTPHeaderField: "Referer")
            webView.load(request)
        } else {
            hasError = true
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if context.coordinator.lastMutedState != isMuted {
            context.coordinator.lastMutedState = isMuted
            let js: String
            if isMuted {
                js = """
                (function() {
                    var videos = document.querySelectorAll('video');
                    videos.forEach(function(v) { v.muted = true; });
                    if (window.player && typeof player.mute === 'function') { player.mute(); }
                    window.postMessage('{"event":"command","func":"mute","args":""}', '*');
                    var iframes = document.querySelectorAll('iframe');
                    iframes.forEach(function(f) {
                        try { f.contentWindow.postMessage('{"event":"command","func":"mute","args":""}', '*'); } catch(e){}
                    });
                })();
                """
            } else {
                js = """
                (function() {
                    var videos = document.querySelectorAll('video');
                    videos.forEach(function(v) { 
                        v.muted = false; 
                        v.volume = 1.0; 
                    });
                    if (window.player && typeof player.unMute === 'function') { 
                        player.unMute(); 
                        if (typeof player.setVolume === 'function') { player.setVolume(100); }
                    }
                    window.postMessage('{"event":"command","func":"unMute","args":""}', '*');
                    window.postMessage('{"event":"command","func":"setVolume","args":[100]}', '*');
                    var iframes = document.querySelectorAll('iframe');
                    iframes.forEach(function(f) {
                        try { 
                            f.contentWindow.postMessage('{"event":"command","func":"unMute","args":""}', '*'); 
                            f.contentWindow.postMessage('{"event":"command","func":"setVolume","args":[100]}', '*'); 
                        } catch(e){}
                    });
                })();
                """
            }
            uiView.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.stopLoading()
        uiView.navigationDelegate = nil
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: TrailerWebViewRepresentable
        var lastMutedState: Bool = true

        init(parent: TrailerWebViewRepresentable) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.easeInOut(duration: 0.5)) {
                    self.parent.isVideoReady = true
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.hasError = true
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.hasError = true
            }
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            DispatchQueue.main.async {
                self.parent.hasError = true
            }
        }
    }
}
#endif
