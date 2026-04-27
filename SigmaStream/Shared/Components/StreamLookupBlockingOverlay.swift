//
//  StreamLookupBlockingOverlay.swift
//  SigmaStream
//
//  Full-screen overlay while resolving streams; blocks interaction until Cancel.
//

import SwiftUI

struct StreamLookupBlockingOverlay: View {
    let headline: String
    let message: String
    let onCancel: () -> Void

    @FocusState private var cancelFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.94)
                .ignoresSafeArea()
                .allowsHitTesting(true)

            VStack(spacing: 28) {
                ProgressView()
                    .scaleEffect(1.35)

                Text(headline)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 620)

                Button("Cancel", role: .cancel, action: onCancel)
                    .buttonStyle(.borderedProminent)
                    .focused($cancelFocused)
            }
            .padding(56)
        }
        .focusSection()
        .onAppear {
            cancelFocused = true
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(headline). \(message)")
    }
}
