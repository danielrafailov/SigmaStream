//
//  FilterSheet.swift
//  SigmaStream
//
//  Created by Daniel Rafailov on 2026-03-16.
//

import SwiftUI
import TMDb

/// Identifiable wrapper for navigation destination.
struct MovieSelection: Identifiable, Hashable {
    let id: Int
}

/// Identifiable wrapper for TV series navigation.
struct TVSeriesSelection: Identifiable, Hashable {
    let id: Int
}

/// Filter sheet for movies (genre, sort, year).
struct MovieFilterSheet: View {
    @Binding var filter: MediaFilter
    let genres: [Genre]
    let onApply: () -> Void
    let onClear: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Genre") {
                    ForEach(Array(genres.enumerated()), id: \.element.id) { _, genre in
                        Button {
                            toggleGenre(genre.id)
                        } label: {
                            HStack {
                                Text(genre.name)
                                Spacer()
                                if (filter.genreIDs ?? []).contains(genre.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }

                Section("Sort By") {
                    ForEach(MediaFilter.SortOption.allCases, id: \.rawValue) { option in
                        Button {
                            filter.sortOption = option
                        } label: {
                            HStack {
                                Text(option.rawValue)
                                Spacer()
                                if filter.sortOption == option {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }

                Section("Release Year") {
                    Picker("Year", selection: $filter.primaryReleaseYear) {
                        Text("Any").tag(nil as Int?)
                        ForEach((Calendar.current.component(.year, from: Date()) - 100)...(Calendar.current.component(.year, from: Date())), id: \.self) { year in
                            Text(String(year)).tag(year as Int?)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .navigationTitle("Filter Movies")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") {
                        onClear()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func toggleGenre(_ genreId: Genre.ID) {
        var ids = filter.genreIDs ?? []
        if ids.contains(genreId) {
            ids.removeAll { $0 == genreId }
        } else {
            ids.append(genreId)
        }
        filter.genreIDs = ids.isEmpty ? nil : ids
    }
}

/// Filter sheet for TV series (genre, sort only).
struct TVSeriesFilterSheet: View {
    @Binding var filter: MediaFilter
    let genres: [Genre]
    let onApply: () -> Void
    let onClear: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Genre") {
                    ForEach(Array(genres.enumerated()), id: \.element.id) { _, genre in
                        Button {
                            toggleGenre(genre.id)
                        } label: {
                            HStack {
                                Text(genre.name)
                                Spacer()
                                if (filter.genreIDs ?? []).contains(genre.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }

                Section("Sort By") {
                    ForEach(MediaFilter.SortOption.allCases, id: \.rawValue) { option in
                        Button {
                            filter.sortOption = option
                        } label: {
                            HStack {
                                Text(option.rawValue)
                                Spacer()
                                if filter.sortOption == option {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Filter TV Shows")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") {
                        onClear()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func toggleGenre(_ genreId: Genre.ID) {
        var ids = filter.genreIDs ?? []
        if ids.contains(genreId) {
            ids.removeAll { $0 == genreId }
        } else {
            ids.append(genreId)
        }
        filter.genreIDs = ids.isEmpty ? nil : ids
    }
}
