# SigmaStream 🎬

A native **iOS & Apple TV (tvOS)** streaming application built with Swift and SwiftUI. SigmaStream browses rich TMDb metadata and streams movies and TV shows via a high-performance, multi-provider scraping backend with integrated AI voice search and celebrity voice cloning.

---

## 🏗️ Architecture Overview

SigmaStream is structured into three main components:

1. **SigmaStream (iOS App)**: A modern iOS 17+ iPhone application featuring a Netflix-inspired liquid glass UI, auto-rotating 3D hero carousels, responsive media grids, gesture-controlled player, and AI voice search with realistic celebrity voice cloning.
2. **SigmaStream (Apple TV App)**: A native tvOS application tailored for the 10-foot TV experience with Apple TV remote focus engine support, Top Shelf integration, and full AVPlayer playback.
3. **Backend Server (CinePro / OMSS + Python Voice Clone)**:
   - **Node.js / TypeScript (OMSS)**: Aggregates and scrapes 15+ independent streaming providers concurrently, resolving direct HLS video streams with lookahead segment buffering and proxying.
   - **Python RVC Engine**: Real-time Retrieval-based Voice Conversion (RVC) and neural TTS powering celebrity AI voice generation.

---

## ✨ Features Breakdown

### 🎬 Netflix-Style User Experience & Visuals
- **Pseudo-Splash Video Intro**: Custom hardware-accelerated video splash screen (`SigmaIntro.mp4`) that autoplays smoothly on launch and fades seamlessly into the app on both iOS and Apple TV.
- **Liquid Glass Navigation**: Horizontally scrollable frosted glass navigation pills for quick switching between *Shows*, *Movies*, and curated *Categories*.
- **Curated Category Feeds**: Liquid glass dropdown featuring 11 tailored genres (*Action*, *Anime*, *Astrology*, *Book Adaptations*, *Canadian*, *Comedies*, *Critically Acclaimed*, *Culture Edit*, *Documentaries*, *Dramas*, *Emmys*) with category-specific sub-shelves (e.g. *Relentless Crime Dramas*, *Action Anime Dubbed in English*, *Get in on the Action*).
- **Auto-Rotating 3D Depth Carousels**: Featured hero carousel that smoothly cycles through spotlighted movies and TV series with 3D scaling and depth perspective.
- **Dynamic Continue Watching**: Persistent playback progress bars with instant 1-tap resumption at the exact second you left off.
- **Responsive Media Layouts**: Pixel-perfect, non-overlapping 3-column poster rows and smooth horizontal swipeable shelves with badges and ratings.

### 🔍 Search, Discovery & TMDb Filters
- **Authentic TMDb Discovery Engine**: Search and filter entertainment across all genres, release decades (80s, 90s, 2000s, 2010s, modern), minimum star ratings, and sorting modes (*Popularity*, *Top Rated*, *Release Date*, *Title*).
- **Search Result Limits & Infinite Scroll**: Configurable result limit filters (*5*, *10*, *20*, *50*, or *Infinite* on-scroll pagination).
- **Rich Media Detail Pages**: Cast profiles, trailers, age ratings, season/episode pickers, recommendations, and related content.

### 🤖 AI Voice Search & Celebrity Voice Cloner
- **Interactive AI Assistant**: Voice-activated natural language movie search powered by on-device Speech-to-Text (STT) and backend LLM intent parsing.
- **Celebrity RVC Voice Engine**: Conversational audio spoken in realistic cloned celebrity voices (e.g., *Morgan Freeman*, *Donald Trump*, *Gordon Ramsay*, *Walter White*, *Snoop Dogg*, *Arnold Schwarzenegger*, *Joe Rogan*, *David Attenborough*, etc.).
- **Voice Sample Previews**: In-app sample playback to audition celebrity voices before selecting your AI assistant's voice.

### ▶️ High-Performance Player
- **Immediate Playback**: Connects to multiple providers simultaneously and immediately starts playing the first stream that returns a successful status.
- **Custom Touch & Remote Controls**: Double-tap forward/backward 10-second seek with haptic feedback, custom scrubber, audio track selector, and subtitle selector.
- **AirPlay 2 Support**: Full video and audio routing to HomePods, Apple TVs, and AirPlay-compatible smart TVs.
- **Robust Error Recovery**: Automatic fallback to secondary stream sources if a primary stream disconnects or fails.

---

## 📋 Prerequisites

Before starting, ensure you have:

1. **Mac** running macOS Sonoma or newer.
2. **Xcode 15+** or **Xcode 16+** (available via the Mac App Store).
3. **Node.js 20+** & **npm** (install via [nodejs.org](https://nodejs.org) or `brew install node`).
4. **Python 3.10+** (required for AI voice cloning backend).
5. **TMDb API Key** (Free):
   - Sign up / log in at [The Movie Database (TMDb)](https://www.themoviedb.org/).
   - Go to **Settings > API** and generate a Developer API key (v3 auth).

---

## 🚀 Step-by-Step Setup Guide

### Step 1: Install Backend Dependencies

Open Terminal and navigate to the `backend` folder:

```bash
cd backend
npm install
npm run build
```

---

### Step 2: Configure Backend Environment (`backend/.env`)

In the `backend` directory, create a `.env` file:

```env
PORT=3000
HOST=0.0.0.0            
NODE_ENV=development
TMDB_API_KEY=your_actual_tmdb_api_key_here
TMDB_CACHE_TTL=86400
CACHE_TYPE=memory
```

---

### Step 3: Configure App Secrets (`SigmaStream/Core/Secrets.swift` & `SigmaStream-iOS/Core/Secrets.swift`)

Create your `Secrets.swift` file:

```swift
import Foundation

enum Secrets {
    static let tmdbApiKey = "your_actual_tmdb_api_key_here"
    static let streamingServerBaseURL = "http://localhost:3000"
}
```

---

### Step 4: Start the Backend Server

Start the Node.js scraper server (with macOS `caffeinate` to prevent sleep during streaming):

```bash
cd backend
npm run dev:awake
```

*(Optional)* Start the Python Voice Clone service for AI celebrity voice search:

```bash
cd backend/voice_clone
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python3 server.py
```

---

### Step 5: Open & Run the App in Xcode

1. Open `SigmaStream.xcodeproj` in Xcode.
2. Select your desired scheme from the top toolbar:
   - **`SigmaStream-iOS`**: Run on iPhone Simulator or physical iPhone.
   - **`SigmaStream`**: Run on Apple TV Simulator or physical Apple TV 4K.
3. Press **Run** (`Cmd + R`) to launch the app!

---

## 📁 Project Structure

```
SigmaStream/
├── SigmaStream-iOS/                  # iOS 17+ Application (Swift / SwiftUI)
│   ├── Core/                         # AppState, TMDbService, StreamingService, Models
│   ├── Features/
│   │   ├── Home/                     # Liquid glass navigation, 3D Hero Carousel, Continue Watching
│   │   ├── Categories/               # Curated category feeds & tailored shelves
│   │   ├── Search/                   # Discovery filters, voice search & celebrity voice cloner
│   │   ├── Detail/                   # Movie & TV detail sheets, trailers, episodes
│   │   ├── Player/                   # Gesture-based touch player with AirPlay & track selector
│   │   └── Navigation/               # SigmaSplashView (video splash screen) & TabView
│   └── SigmaIntro.mp4                # Launch intro video asset
│
├── SigmaStream/                      # tvOS Application (Apple TV)
│   ├── Core/                         # Services, AppState, Focus Engine adapters
│   ├── Features/
│   │   ├── Home/                     # Apple TV hero banner, shelves, navigation
│   │   ├── Player/                   # tvOS AVPlayer view with stream resolution
│   │   └── Navigation/               # tvOS SigmaSplashView
│   └── SigmaIntro.mp4                # Launch intro video asset
│
├── backend/                          # Multi-Provider Scraper Backend (TypeScript)
│   ├── src/
│   │   ├── server.ts                 # OMSS aggregation server
│   │   ├── providers/                # 15+ streaming scrapers (VixSrc, VidSrc, VidAPI, StreamMafia, etc.)
│   │   ├── services/                 # Stream buffer service & cache
│   │   └── tts.ts / stt.ts           # Speech synthesis & transcription
│   └── voice_clone/                  # Python RVC voice conversion server & model weights
│
└── README.md
```

---

## 🛡️ License & Legal Disclaimer

* The backend utilizes the PolyForm Noncommercial License 1.0.0 (see [`backend/LICENSE`](file:///Users/danielrafailov/Desktop/XCode%20Apps/SigmaStream/backend/LICENSE)).
* **Disclaimer**: SigmaStream is intended strictly for home and educational use. This software does not host, store, or distribute any copyrighted media. All metadata is provided by TMDb, and streams are scraped on-demand from third-party publicly accessible web services.

