//
//  StreamPickerView.swift
//  SigmaStream
//
//  Presents available streams with provider, quality, and type for user selection.
//

import SwiftUI

struct StreamPickerView: View {
    let title: String
    let sources: [OMSSSource]
    let onSelect: (OMSSSource) -> Void
    let onDismiss: () -> Void
    @Environment(AppState.self) private var appState
    @FocusState private var focusedIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("Choose Stream")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Cancel") {
                    onDismiss()
                }
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            Text("Select a stream to play. Quality and source are shown above.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(sources.enumerated()), id: \.element.url) { index, source in
                        streamRow(source: source, index: index)
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 24)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .defaultFocus($focusedIndex, 0)
    }

    private func streamRow(source: OMSSSource, index: Int) -> some View {
        let isFocused = focusedIndex == index
        let providerName = source.provider?.name ?? "Unknown"
        let quality = source.quality ?? "Unknown"
        let typeLabel = source.type.uppercased()

        return Button {
            onSelect(source)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(providerName)
                        .font(.headline)
                    Spacer()
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 16) {
                    Label(quality, systemImage: "film")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Label(typeLabel, systemImage: "antenna.radiowaves.left.and.right")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(isFocused ? Color.white.opacity(0.25) : Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .buttonBorderShape(.roundedRectangle(radius: 12))
        .focused($focusedIndex, equals: index)
    }
}
