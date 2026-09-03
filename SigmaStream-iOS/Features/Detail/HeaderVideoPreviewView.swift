//
//  HeaderVideoPreviewView.swift
//  SigmaStream-iOS
//
//  Created by Daniel Rafailov on 2026-09-02.
//

import SwiftUI
import WebKit

#if os(iOS)
struct HeaderVideoPreviewView: View {
    let videoKey: String
    let fallbackImageURL: URL?
    let height: CGFloat

    @State private var isMuted = true
    @State private var isVideoReady = false
    @State private var webView: WKWebView?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
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

            // Layer 2: Auto-playing Video Preview (Fades in over backdrop)
            TrailerWebViewRepresentable(
                videoKey: videoKey,
                isMuted: $isMuted,
                isVideoReady: $isVideoReady,
                webViewRef: $webView
            )
            .frame(maxWidth: .infinity, maxHeight: height)
            .opacity(isVideoReady ? 1.0 : 0.0)
            .animation(.easeInOut(duration: 0.6), value: isVideoReady)
            .allowsHitTesting(false) // Let user scroll naturally over the video

            // Layer 3: Netflix Glass Audio Mute/Unmute Control Pill
            if isVideoReady {
                Button {
                    isMuted.toggle()
                    toggleMuteState()
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
                .padding(.trailing, 16)
                .padding(.bottom, 22)
                .transition(.opacity.combined(with: .scale))
            }
        }
        .frame(height: height)
    }

    private func toggleMuteState() {
        guard let webView else { return }
        let js = isMuted ? "if(window.player){player.mute();}" : "if(window.player){player.unMute();player.setVolume(100);}"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
}

private struct TrailerWebViewRepresentable: UIViewRepresentable {
    let videoKey: String
    @Binding var isMuted: Bool
    @Binding var isVideoReady: Bool
    @Binding var webViewRef: WKWebView?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        
        let htmlContent = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                body, html { width: 100%; height: 100%; background: #000; overflow: hidden; pointer-events: none; }
                #player { width: 100%; height: 100%; position: absolute; top: 0; left: 0; }
            </style>
        </head>
        <body>
            <div id="player"></div>
            <script>
                var tag = document.createElement('script');
                tag.src = "https://www.youtube.com/iframe_api";
                var firstScriptTag = document.getElementsByTagName('script')[0];
                firstScriptTag.parentNode.insertBefore(tag, firstScriptTag);

                var player;
                function onYouTubeIframeAPIReady() {
                    player = new YT.Player('player', {
                        videoId: '\(videoKey)',
                        playerVars: {
                            'autoplay': 1,
                            'mute': 1,
                            'playsinline': 1,
                            'controls': 0,
                            'disablekb': 1,
                            'fs': 0,
                            'rel': 0,
                            'modestbranding': 1,
                            'showinfo': 0,
                            'iv_load_policy': 3,
                            'loop': 1,
                            'playlist': '\(videoKey)'
                        },
                        events: {
                            'onReady': onPlayerReady,
                            'onStateChange': onPlayerStateChange
                        }
                    });
                }

                function onPlayerReady(event) {
                    event.target.mute();
                    event.target.playVideo();
                    window.location.href = "sigmastream://ready";
                }

                function onPlayerStateChange(event) {
                    if (event.data == YT.PlayerState.PLAYING) {
                        window.location.href = "sigmastream://playing";
                    }
                }
            </script>
        </body>
        </html>
        """

        webView.loadHTMLString(htmlContent, baseURL: URL(string: "https://www.youtube.com"))
        
        DispatchQueue.main.async {
            self.webViewRef = webView
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: TrailerWebViewRepresentable

        init(_ parent: TrailerWebViewRepresentable) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url, url.scheme == "sigmastream" {
                if url.host == "playing" || url.host == "ready" {
                    DispatchQueue.main.async {
                        withAnimation {
                            self.parent.isVideoReady = true
                        }
                    }
                }
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
#endif
