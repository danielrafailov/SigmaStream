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
    @State private var hasError = false
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

            // Layer 2: Auto-playing Video Preview (Fades in over backdrop only when playing with no errors)
            if !hasError {
                TrailerWebViewRepresentable(
                    videoKey: videoKey,
                    isMuted: $isMuted,
                    isVideoReady: $isVideoReady,
                    hasError: $hasError,
                    webViewRef: $webView
                )
                .frame(maxWidth: .infinity, maxHeight: height)
                .opacity(isVideoReady ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.5), value: isVideoReady)
                .allowsHitTesting(false) // Allow touch pass-through for vertical scrolling
            }

            // Layer 3: Netflix Glass Audio Mute/Unmute Control Pill
            if isVideoReady && !hasError {
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
        let js = isMuted ?
            "if(window.player && player.mute){player.mute();}else{document.getElementById('ytplayer')?.contentWindow?.postMessage('{\"event\":\"command\",\"func\":\"mute\",\"args\":\"\"}', '*');}" :
            "if(window.player && player.unMute){player.unMute();player.setVolume(100);}else{document.getElementById('ytplayer')?.contentWindow?.postMessage('{\"event\":\"command\",\"func\":\"unMute\",\"args\":\"\"}', '*');document.getElementById('ytplayer')?.contentWindow?.postMessage('{\"event\":\"command\",\"func\":\"setVolume\",\"args\":[100]}', '*');}"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
}

private struct TrailerWebViewRepresentable: UIViewRepresentable {
    let videoKey: String
    @Binding var isMuted: Bool
    @Binding var isVideoReady: Bool
    @Binding var hasError: Bool
    @Binding var webViewRef: WKWebView?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        userContentController.add(context.coordinator, name: "sigmastream")
        config.userContentController = userContentController
        
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = false
        
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
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
                body, html { width: 100%; height: 100%; background: #000; overflow: hidden; }
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
                            'playlist': '\(videoKey)',
                            'origin': 'https://www.themoviedb.org'
                        },
                        events: {
                            'onReady': onPlayerReady,
                            'onStateChange': onPlayerStateChange,
                            'onError': onPlayerError
                        }
                    });
                }

                function onPlayerReady(event) {
                    try {
                        event.target.mute();
                        event.target.playVideo();
                    } catch(e) {}
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.sigmastream) {
                        window.webkit.messageHandlers.sigmastream.postMessage("ready");
                    }
                }

                function onPlayerStateChange(event) {
                    if (event.data == 1) { // YT.PlayerState.PLAYING
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.sigmastream) {
                            window.webkit.messageHandlers.sigmastream.postMessage("playing");
                        }
                    }
                }

                function onPlayerError(event) {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.sigmastream) {
                        window.webkit.messageHandlers.sigmastream.postMessage("error");
                    }
                }
            </script>
        </body>
        </html>
        """

        webView.loadHTMLString(htmlContent, baseURL: URL(string: "https://www.themoviedb.org"))
        
        DispatchQueue.main.async {
            self.webViewRef = webView
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKScriptMessageHandler {
        var parent: TrailerWebViewRepresentable

        init(_ parent: TrailerWebViewRepresentable) {
            self.parent = parent
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? String else { return }
            DispatchQueue.main.async {
                if body == "ready" || body == "playing" {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        self.parent.isVideoReady = true
                    }
                } else if body == "error" {
                    withAnimation {
                        self.parent.hasError = true
                        self.parent.isVideoReady = false
                    }
                }
            }
        }
    }
}
#endif


