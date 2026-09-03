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
            .animation(.easeInOut(duration: 0.5), value: isVideoReady)
            .allowsHitTesting(false) // Allow touch pass-through for vertical scrolling

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
        .onAppear {
            // Smoothly reveal trailer preview after brief backdrop view
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation {
                    self.isVideoReady = true
                }
            }
        }
    }

    private func toggleMuteState() {
        guard let webView else { return }
        let js = isMuted ?
            "document.getElementById('ytplayer').contentWindow.postMessage('{\"event\":\"command\",\"func\":\"mute\",\"args\":\"\"}', '*');" :
            "document.getElementById('ytplayer').contentWindow.postMessage('{\"event\":\"command\",\"func\":\"unMute\",\"args\":\"\"}', '*'); document.getElementById('ytplayer').contentWindow.postMessage('{\"event\":\"command\",\"func\":\"setVolume\",\"args\":[100]}', '*');"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
}

private struct TrailerWebViewRepresentable: UIViewRepresentable {
    let videoKey: String
    @Binding var isMuted: Bool
    @Binding var isVideoReady: Bool
    @Binding var webViewRef: WKWebView?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = false
        
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        let webView = WKWebView(frame: .zero, configuration: config)
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
                iframe { width: 100%; height: 100%; border: none; position: absolute; top: 0; left: 0; }
            </style>
        </head>
        <body>
            <iframe id="ytplayer" type="text/html" width="100%" height="100%"
                src="https://www.youtube-nocookie.com/embed/\(videoKey)?autoplay=1&mute=1&playsinline=1&controls=0&disablekb=1&fs=0&rel=0&modestbranding=1&showinfo=0&iv_load_policy=3&loop=1&playlist=\(videoKey)&enablejsapi=1&origin=https://www.youtube.com"
                frameborder="0"
                allow="autoplay; encrypted-media; picture-in-picture"
                allowfullscreen>
            </iframe>
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
}
#endif


