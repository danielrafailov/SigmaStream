# SigmaStream 🎬

A native tvOS streaming application for Apple TV. SigmaStream browses rich TMDb metadata and streams movies and TV shows via an OMSS-compliant local backend scraper.

---

## 🏗️ Architecture Overview

SigmaStream is composed of two components:

1. **SigmaStream (Apple TV App)**: A Swift / SwiftUI app built for tvOS. It interfaces with TMDb for metadata (posters, synopses, season/episode catalogs, search) and sends playback requests to the local backend.
2. **Backend (CinePro Core / OMSS)**: A Node.js / TypeScript server that aggregates and scrapes multiple streaming providers concurrently, resolving direct HLS video streams and proxying them securely to your Apple TV.

---

## 📋 Prerequisites

Before starting, ensure you have:

1. **Mac** running macOS Sonoma or newer.
2. **Xcode 15+** (available from the Mac App Store).
3. **Node.js 20+** & **npm** (verify with `node -v` in Terminal; install via [nodejs.org](https://nodejs.org) or `brew install node`).
4. **TMDb API Key** (Free):
   - Sign up / log in at [The Movie Database (TMDb)](https://www.themoviedb.org/).
   - Go to **Settings > API** and generate a Developer API key (v3 auth).
5. **Power Adapter**: Keep your Mac laptop plugged into power when serving streams to an Apple TV.

---

## 🚀 Step-by-Step Setup Guide

Follow these steps in order to set up and run SigmaStream for the first time.

### Step 1: Install Backend Dependencies

Open Terminal and navigate to the `backend` folder:

```bash
cd backend
npm install
```

---

### Step 2: Configure Backend Environment (`backend/.env`)

1. In the `backend` folder, create your `.env` file from the provided example:

```env
PORT=3000
HOST=0.0.0.0            
NODE_ENV=development
TMDB_API_KEY=your_actual_tmdb_api_key_here
TMDB_CACHE_TTL=86400
CACHE_TYPE=memory
```

---

### Step 3: Configure App Secrets (`SigmaStream/Core/Secrets.swift`)

The frontend application requires a `Secrets.swift` configuration file. For security reasons, this file is gitignored and must be created manually.

1. Create a file at `SigmaStream/Core/Secrets.swift`.
2. Add the following content:

```swift
import Foundation

enum Secrets {
    static let tmdbApiKey = "your_actual_tmdb_api_key_here"
    static let streamingServerBaseURL = "http://localhost:3000"
}
```
---

### Step 4: Start the Backend Server

To ensure smooth, uninterrupted playback during movies or shows, keep your laptop plugged in and start the server with sleep-prevention enabled:

```bash
cd "backend"
npm run dev:awake
```

* `npm run dev:awake` uses macOS `caffeinate` to prevent your Mac from sleeping while the backend process is running.
* Alternatively, run `npm run dev` for standard execution.

When the server starts successfully, you will see:
```
🚀 Server listening at http://localhost:3000
```

---

### Step 5: Open & Run the App in Xcode

1. Open `SigmaStream.xcodeproj` in Xcode.
2. In the top toolbar, select the **SigmaStream** scheme and your target destination:
   - **Apple TV Simulator** (e.g., *Apple TV 4K (3rd generation) (1080p)*), or
   - Your connected **Physical Apple TV**.
3. Press **Run** (`Cmd + R`) or click the **Play** button in Xcode.
4. Browse movies and TV shows, select a title, and press play!

---

## 🔍 Understanding Backend Logs & Provider Behavior

When you play a title, you will see logs similar to this in the backend terminal:

```
[SourceService] Cache MISS for movie:1368337
[SourceService] Fetching from 14 provider(s) (3 filtered out)
[SourceService] Provider 'CineSu' returned 0 source(s) in 102ms
[SourceService] Provider 'VixSrc' returned 1 source(s) in 1353ms
[SourceService] Provider 'Videasy' failed: Error: Videasy: timed out after 25000ms
GET /v1/movies/1368337 200 - 25034ms
GET /v1/proxy?data=... 200
```

### Why do some providers return 0 sources or time out?
- **Aggregator Design**: The backend queries 14+ independent streaming scrapers concurrently. Not every provider hosts every movie or TV episode.
- **Provider Timeouts & Errors**: Free third-party streaming sources frequently change domains, experience rate limits, or suffer downtime.
- **Resilience**: The backend isolates provider failures. As long as **at least one provider** (e.g., `VixSrc`) returns working streams, the request succeeds with a `200` status and the video plays seamlessly on your Apple TV.

---

## 📁 Project Structure

```
SigmaStream/
├── SigmaStream/                  # tvOS Application (Swift / SwiftUI)
│   ├── Core/                     # AppState, TMDb / Streaming Services, Secrets.swift
│   ├── Features/                 # Views (Home, Movies, TV, Search, Detail, Player, Collections)
│   └── Shared/                   # Reusable components, theme, utilities
├── backend/                      # CinePro Core / OMSS Backend (Node.js / TypeScript)
│   ├── src/
│   │   ├── server.ts             # Fastify server entrypoint
│   │   └── providers/            # Third-party scraper implementations
│   ├── .env                      # Backend environment variables
│   └── package.json
└── README.md
```

---

## 🛡️ License & Legal Disclaimer

* The backend utilizes the PolyForm Noncommercial License 1.0.0 (see [`backend/LICENSE`](file:///Users/danielrafailov/Desktop/XCode%20Apps/SigmaStream/backend/LICENSE)).
* **Disclaimer**: SigmaStream is intended for home and educational use. This software does not host, store, or distribute any copyrighted media. All metadata is provided by TMDb, and streams are scraped on-demand from third-party publicly accessible web services.
