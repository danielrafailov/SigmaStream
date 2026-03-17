# SigmaStream – Project Structure

A tvOS movie and TV show database app built with SwiftUI and TMDb.

## Folder Structure

```
SigmaStream/
├── App/                    # App entry point and configuration
├── Core/                   # Core application layer
│   ├── Services/           # API services (e.g., TMDbService)
│   ├── Extensions/         # Swift extensions
│   └── Utilities/          # Helper utilities
├── Features/               # Feature modules
│   ├── Movies/             # Movie browsing and detail
│   ├── TVShows/            # TV show browsing and detail
│   ├── Search/             # Search functionality
│   ├── Discovery/          # Discovery and recommendations
│   └── Detail/             # Shared detail views
├── Shared/                 # Shared across features
│   ├── Components/         # Reusable UI components
│   ├── Models/             # Data models
│   └── Views/              # Shared SwiftUI views
└── Resources/              # Assets, strings, etc.
    └── Assets.xcassets
```

## Dependencies

- **TMDb** – [adamayoung/TMDb](https://github.com/adamayoung/TMDb) – The Movie Database API client (v14.0.0+)

## Setup

1. Get a TMDb API key from https://www.themoviedb.org/documentation/api
2. Configure `TMDbService` with your API key when initializing the app
3. Build and run on tvOS Simulator or device

## TMDb Usage

The `TMDbService` in `Core/Services/TMDbService.swift` provides:

- `popularMovies()` – Popular movies
- `trendingMovies(inTimeWindow:)` – Trending movies
- `search(query:)` – Multi-type search (movies, TV, people)
- `movieDetails(forMovieId:)` – Movie details
- `tvSeriesDetails(forSeriesId:)` – TV series details
- `apiConfiguration()` – Image URL configuration
