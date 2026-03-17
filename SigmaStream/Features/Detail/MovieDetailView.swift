//
//  MovieDetailView.swift
//  SigmaStream
//
//  Created by Daniel Rafailov on 2026-03-16.
//

import SwiftUI
import TMDb

struct MovieDetailView: View {
    let movieId: Int
    @Environment(AppState.self) private var appState
    @State private var movie: Movie?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                ContentUnavailableView(
                    "Couldn't load movie",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if let movie {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(alignment: .top, spacing: 24) {
                            posterSection
                            VStack(alignment: .leading, spacing: 8) {
                                Text(movie.title)
                                    .font(.largeTitle)
                                    .fontWeight(.bold)

                                if let date = movie.releaseDate {
                                    Text(Calendar.current.component(.year, from: date).description)
                                        .font(.title3)
                                        .foregroundStyle(.secondary)
                                }

                                if let rating = movie.voteAverage {
                                    Label(String(format: "%.1f/10", rating), systemImage: "star.fill")
                                        .font(.title3)
                                }
                            }
                            Spacer()
                        }
                        .padding()

                        if let overview = movie.overview, !overview.isEmpty {
                            Text(overview)
                                .font(.body)
                                .padding(.horizontal)
                        }
                    }
                }
            }
        }
        .navigationTitle(movie?.title ?? "Movie")
        .task {
            await loadMovie()
        }
    }

    @ViewBuilder
    private var posterSection: some View {
        if let url = ImageURLBuilder.posterURL(for: movie?.posterPath, config: appState.apiConfiguration, idealWidth: 500) {
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
                Image(systemName: "film")
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)
            }
    }

    private func loadMovie() async {
        do {
            movie = try await appState.tmdbService.movieDetails(forMovieId: movieId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

#Preview {
    NavigationStack {
        MovieDetailView(movieId: 550)
            .environment(AppState(apiKey: "placeholder"))
    }
}
