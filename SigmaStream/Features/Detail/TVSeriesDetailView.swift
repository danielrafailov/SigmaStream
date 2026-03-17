//
//  TVSeriesDetailView.swift
//  SigmaStream
//
//  Created by Daniel Rafailov on 2026-03-16.
//

import SwiftUI
import TMDb

struct TVSeriesDetailView: View {
    let seriesId: Int
    @Environment(AppState.self) private var appState
    @State private var series: TVSeries?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                ContentUnavailableView(
                    "Couldn't load TV series",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if let series {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(alignment: .top, spacing: 24) {
                            posterSection
                            VStack(alignment: .leading, spacing: 8) {
                                Text(series.name)
                                    .font(.largeTitle)
                                    .fontWeight(.bold)

                                if let date = series.firstAirDate {
                                    Text(formatYear(date))
                                        .font(.title3)
                                        .foregroundStyle(.secondary)
                                }

                                if let rating = series.voteAverage {
                                    Label(String(format: "%.1f/10", rating), systemImage: "star.fill")
                                        .font(.title3)
                                }
                            }
                            Spacer()
                        }
                        .padding()

                        if let overview = series.overview, !overview.isEmpty {
                            Text(overview)
                                .font(.body)
                                .padding(.horizontal)
                        }
                    }
                }
            }
        }
        .navigationTitle(series?.name ?? "TV Series")
        .task {
            await loadSeries()
        }
    }

    @ViewBuilder
    private var posterSection: some View {
        if let url = ImageURLBuilder.posterURL(for: series?.posterPath, config: appState.apiConfiguration, idealWidth: 500) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(2/3, contentMode: .fill)
                default:
                    posterPlaceholder
                }
            }
            .frame(width: 300, height: 450)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        } else {
            posterPlaceholder
        }
    }

    private var posterPlaceholder: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(.quaternary)
            .frame(width: 300, height: 450)
            .overlay {
                Image(systemName: "tv")
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)
            }
    }

    private func formatYear(_ date: Date) -> String {
        Calendar.current.component(.year, from: date).description
    }

    private func loadSeries() async {
        do {
            series = try await appState.tmdbService.tvSeriesDetails(forSeriesId: seriesId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

#Preview {
    NavigationStack {
        TVSeriesDetailView(seriesId: 1399)
            .environment(AppState(apiKey: "placeholder"))
    }
}
