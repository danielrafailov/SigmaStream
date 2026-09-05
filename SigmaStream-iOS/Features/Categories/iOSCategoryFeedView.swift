//
//  iOSCategoryFeedView.swift
//  SigmaStream-iOS
//
//  Created by Daniel Rafailov on 2026-09-02.
//

import SwiftUI
import TMDb

#if os(iOS)
struct CuratedCategoryShelf: Identifiable {
    let id = UUID()
    let title: String
    let items: [iOSMediaRowItem]
}

struct iOSCategoryFeedView: View {
    let categoryName: String
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var heroItems: [MediaListItem] = []
    @State private var curatedShelves: [CuratedCategoryShelf] = []
    @State private var allItems: [iOSMediaRowItem] = []
    @State private var currentPage = 1
    @State private var hasMore = true
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var selectedHeroIndex = 0

    @State private var selectedMovieId: Int?
    @State private var selectedTVSeriesId: Int?

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Top Bar with Back Button and Category Title Label
            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }

                Text(categoryName)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)

            if isLoading {
                ProgressView("Loading \(categoryName)...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if curatedShelves.isEmpty && allItems.isEmpty {
                ContentUnavailableView(
                    "No Titles Found",
                    systemImage: "film.stack",
                    description: Text("No items available in \(categoryName).")
                )
            } else {
                ScrollView {
                    VStack(spacing: 24) {
                        // Category Hero Carousel (Netflix-style 3D Depth Carousel)
                        if !heroItems.isEmpty {
                            categoryHeroCarousel
                        }

                        // Curated Category Shelves (Netflix-style tailored lists)
                        ForEach(curatedShelves) { shelf in
                            iOSMediaRow(
                                title: shelf.title,
                                items: shelf.items
                            ) { item in
                                if item.isTVSeries {
                                    selectedTVSeriesId = item.id
                                } else {
                                    selectedMovieId = item.id
                                }
                            }
                        }

                        // More in Category Section Header
                        if !allItems.isEmpty {
                            HStack {
                                Text("More in \(categoryName)")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(.white)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 4)

                            // 3-Column Media Grid with Pagination
                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(Array(allItems.enumerated()), id: \.element.id) { index, item in
                                    Button {
                                        if item.isTVSeries {
                                            selectedTVSeriesId = item.id
                                        } else {
                                            selectedMovieId = item.id
                                        }
                                    } label: {
                                        iOSMediaCard(
                                            id: item.id,
                                            title: item.title,
                                            posterPath: item.posterURL,
                                            rating: item.rating,
                                            releaseYear: item.releaseYear,
                                            isTVSeries: item.isTVSeries,
                                            progress: nil
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .onAppear {
                                        if index >= allItems.count - 4 && hasMore && !isLoadingMore {
                                            Task { await loadMore() }
                                        }
                                    }
                                }

                                if isLoadingMore {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 20)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: Binding(
            get: { selectedMovieId != nil },
            set: { if !$0 { selectedMovieId = nil } }
        )) {
            if let movieId = selectedMovieId {
                iOSMovieDetailView(movieId: movieId)
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { selectedTVSeriesId != nil },
            set: { if !$0 { selectedTVSeriesId = nil } }
        )) {
            if let tvId = selectedTVSeriesId {
                iOSTVSeriesDetailView(seriesId: tvId)
            }
        }
        .task {
            if allItems.isEmpty {
                await loadCategoryContent()
            }
        }
    }

    // MARK: - Netflix Style 3D Hero Carousel
    @ViewBuilder
    private var categoryHeroCarousel: some View {
        let count = heroItems.count
        let virtualCount = count * 200
        let baseOffset = (virtualCount / 2) - ((virtualCount / 2) % max(1, count))

        TabView(selection: $selectedHeroIndex) {
            ForEach(0..<virtualCount, id: \.self) { vIndex in
                let item = heroItems[vIndex % count]
                let isTV = item.isTVSeries

                GeometryReader { geo in
                    let minX = geo.frame(in: .global).minX
                    let screenWidth = UIScreen.main.bounds.width
                    let rotation = Double((minX - (screenWidth - 290) / 2) / 18)
                    let scale = max(0.88, 1.0 - abs(minX - (screenWidth - 290) / 2) / 1200)

                    ZStack(alignment: .bottom) {
                        // Poster image
                        if let posterURL = item.posterURL {
                            AsyncImage(url: posterURL) { phase in
                                if let img = phase.image {
                                    img
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: geo.size.width, height: geo.size.height)
                                        .clipped()
                                } else {
                                    Color.white.opacity(0.08)
                                }
                            }
                        }

                        // Bottom Gradient Scrim
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color.black.opacity(0.2),
                                Color.black.opacity(0.7),
                                Color.black.opacity(0.96)
                            ],
                            startPoint: .center,
                            endPoint: .bottom
                        )

                        // Info & Buttons
                        VStack(spacing: 10) {
                            Text(item.title)
                                .font(.system(size: 24, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .shadow(color: .black.opacity(0.8), radius: 6, y: 2)
                                .padding(.horizontal, 16)

                            Text(isTV ? "Watch All Episodes Now" : "Watch Now")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.9))
                                .shadow(color: .black.opacity(0.7), radius: 4)

                            HStack(spacing: 12) {
                                Button {
                                    if isTV {
                                        selectedTVSeriesId = item.id
                                    } else {
                                        selectedMovieId = item.id
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 16, weight: .bold))
                                        Text(isTV ? "Play Show" : "Play Movie")
                                            .font(.system(size: 15, weight: .bold))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.white)
                                    .foregroundStyle(.black)
                                    .clipShape(Capsule())
                                }

                                let inList = isTV ? appState.myListManager.isSeriesInList(item.id) : appState.myListManager.isMovieInList(item.id)
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        if isTV {
                                            appState.myListManager.toggleSeries(item.id)
                                        } else {
                                            appState.myListManager.toggleMovie(item.id)
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: inList ? "checkmark" : "plus")
                                            .font(.system(size: 16, weight: .bold))
                                        Text(inList ? "In List" : "My List")
                                            .font(.system(size: 15, weight: .bold))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(.ultraThinMaterial)
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 20)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.16), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.6), radius: 14, y: 8)
                    .scaleEffect(scale)
                    .rotation3DEffect(.degrees(rotation), axis: (x: 0, y: 1, z: 0))
                }
                .frame(width: 290, height: 420)
                .tag(vIndex)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 440)
        .onAppear {
            if selectedHeroIndex == 0 && count > 0 {
                selectedHeroIndex = baseOffset
            }
        }
        .task {
            // Auto-rotate hero carousel every 5.5 seconds
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_500_000_000)
                guard !Task.isCancelled else { break }
                if count > 1 {
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.7)) {
                            selectedHeroIndex += 1
                        }
                    }
                }
            }
        }
    }

    private func loadCategoryContent() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let shelvesFetch = appState.tmdbService.fetchCategoryCuratedShelves(category: categoryName)
            async let baseItemsFetch = appState.tmdbService.fetchCategoryFeedItems(category: categoryName, page: 1)

            let shelves = await shelvesFetch
            let baseItems = (try? await baseItemsFetch) ?? (movies: [], tv: [])

            // Map Curated Shelves
            var mappedShelves: [CuratedCategoryShelf] = []
            for shelf in shelves {
                var shelfItems: [iOSMediaRowItem] = []
                for m in shelf.movies {
                    let posterURL = ImageURLBuilder.posterURL(for: m.posterPath, config: appState.apiConfiguration, idealWidth: 342)
                    let year = m.releaseDate.map { String(Calendar.current.component(.year, from: $0)) }
                    shelfItems.append(iOSMediaRowItem(
                        id: m.id,
                        title: m.title,
                        posterURL: posterURL,
                        rating: m.voteAverage,
                        releaseYear: year,
                        isTVSeries: false,
                        progress: nil
                    ))
                }
                for t in shelf.tvSeries {
                    let posterURL = ImageURLBuilder.posterURL(for: t.posterPath, config: appState.apiConfiguration, idealWidth: 342)
                    let year = t.firstAirDate.map { String(Calendar.current.component(.year, from: $0)) }
                    shelfItems.append(iOSMediaRowItem(
                        id: t.id,
                        title: t.name,
                        posterURL: posterURL,
                        rating: t.voteAverage,
                        releaseYear: year,
                        isTVSeries: true,
                        progress: nil
                    ))
                }
                if !shelfItems.isEmpty {
                    mappedShelves.append(CuratedCategoryShelf(title: shelf.title, items: shelfItems))
                }
            }

            // Map Hero and Grid Items
            var heroes: [MediaListItem] = []
            var allGrid: [iOSMediaRowItem] = []

            for m in baseItems.movies {
                let posterURL = ImageURLBuilder.posterURL(for: m.posterPath, config: appState.apiConfiguration, idealWidth: 780) ?? ImageURLBuilder.backdropURL(for: m.backdropPath, config: appState.apiConfiguration, idealWidth: 780)
                let year = m.releaseDate.map { String(Calendar.current.component(.year, from: $0)) }
                heroes.append(MediaListItem(
                    id: m.id,
                    title: m.title,
                    posterURL: posterURL,
                    rating: m.voteAverage,
                    releaseYear: year,
                    isTVSeries: false,
                    releaseDate: m.releaseDate
                ))
                allGrid.append(iOSMediaRowItem(
                    id: m.id,
                    title: m.title,
                    posterURL: posterURL,
                    rating: m.voteAverage,
                    releaseYear: year,
                    isTVSeries: false,
                    progress: nil
                ))
            }

            for t in baseItems.tv {
                let posterURL = ImageURLBuilder.posterURL(for: t.posterPath, config: appState.apiConfiguration, idealWidth: 780) ?? ImageURLBuilder.backdropURL(for: t.backdropPath, config: appState.apiConfiguration, idealWidth: 780)
                let year = t.firstAirDate.map { String(Calendar.current.component(.year, from: $0)) }
                heroes.append(MediaListItem(
                    id: t.id,
                    title: t.name,
                    posterURL: posterURL,
                    rating: t.voteAverage,
                    releaseYear: year,
                    isTVSeries: true,
                    releaseDate: t.firstAirDate
                ))
                allGrid.append(iOSMediaRowItem(
                    id: t.id,
                    title: t.name,
                    posterURL: posterURL,
                    rating: t.voteAverage,
                    releaseYear: year,
                    isTVSeries: true,
                    progress: nil
                ))
            }

            // If heroItems from base is empty, take from first shelf
            if heroes.isEmpty, let firstShelf = mappedShelves.first {
                for item in firstShelf.items.prefix(6) {
                    heroes.append(MediaListItem(
                        id: item.id,
                        title: item.title,
                        posterURL: item.posterURL,
                        rating: item.rating,
                        releaseYear: item.releaseYear,
                        isTVSeries: item.isTVSeries
                    ))
                }
            }

            self.curatedShelves = mappedShelves
            self.heroItems = Array(heroes.prefix(6))
            self.allItems = allGrid
            self.hasMore = allGrid.count >= 12
        } catch {}
    }

    private func loadMore() async {
        guard !isLoadingMore && hasMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let next = currentPage + 1
        do {
            let result = try await appState.tmdbService.fetchCategoryFeedItems(category: categoryName, page: next)
            var newItems: [iOSMediaRowItem] = []
            for m in result.movies {
                let posterURL = ImageURLBuilder.posterURL(for: m.posterPath, config: appState.apiConfiguration, idealWidth: 500)
                let year = m.releaseDate.map { String(Calendar.current.component(.year, from: $0)) }
                newItems.append(iOSMediaRowItem(
                    id: m.id,
                    title: m.title,
                    posterURL: posterURL,
                    rating: m.voteAverage,
                    releaseYear: year,
                    isTVSeries: false,
                    progress: nil
                ))
            }
            for t in result.tv {
                let posterURL = ImageURLBuilder.posterURL(for: t.posterPath, config: appState.apiConfiguration, idealWidth: 500)
                let year = t.firstAirDate.map { String(Calendar.current.component(.year, from: $0)) }
                newItems.append(iOSMediaRowItem(
                    id: t.id,
                    title: t.name,
                    posterURL: posterURL,
                    rating: t.voteAverage,
                    releaseYear: year,
                    isTVSeries: true,
                    progress: nil
                ))
            }
            if newItems.isEmpty {
                hasMore = false
            } else {
                allItems.append(contentsOf: newItems)
                currentPage = next
            }
        } catch {
            hasMore = false
        }
    }
}
#endif
