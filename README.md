# SigmaStream

A tvOS app for streaming movies and TV shows. Browse TMDb metadata, discover content, and play streams through an OMSS-compliant backend.

## Overview

SigmaStream consists of two parts:

| Component | Description |
|-----------|-------------|
| **SigmaStream** (tvOS app) | Swift/SwiftUI app for Apple TV. Uses TMDb for metadata (posters, descriptions, seasons, episodes). |
| **Backend** (CinePro Core) | Node.js streaming API that scrapes multiple providers and returns playable HLS streams. |

The app fetches metadata from TMDb and streams from your backend. Both must be configured and running.

## Prerequisites

- **Xcode** 15+ (for the tvOS app)
- **Node.js** 20+ (for the backend)
- **TMDb API key** — [Get one free](https://www.themoviedb.org/settings/api)

## Quick Start

### 1. Backend

```bash
cd backend
npm install
cp .env.example .env
```

Edit `.env` and set:

```
TMDB_API_KEY=your_tmdb_api_key
HOST=0.0.0.0
```

Start the server:

```bash
npm run dev
```

The backend runs at `http://localhost:3000` (or `http://<your-mac-ip>:3000` on your network).

### 2. App configuration

1. Create `SigmaStream/Core/Secrets.swift` (it's gitignored):

```swift
import Foundation

enum Secrets {
    static let tmdbApiKey = "your_tmdb_api_key"
    static let streamingServerBaseURL = "http://YOUR_MAC_IP:3000"
}
```

2. Replace `YOUR_MAC_IP` with your Mac's local IP (e.g. `192.168.1.5`) so the Apple TV can reach the backend on the same network.

### 3. Run the app

Open `SigmaStream.xcodeproj` in Xcode, select the tvOS Simulator or a connected Apple TV, and run.

## Project Structure

```
SigmaStream/
├── SigmaStream/           # tvOS app (Swift/SwiftUI)
│   ├── Core/              # AppState, services, Secrets
│   ├── Features/         # Views (Movies, TV, Search, Detail, Player)
│   └── Shared/            # Components, utilities
├── backend/               # CinePro Core (Node.js/TypeScript)
│   ├── src/
│   │   ├── server.ts
│   │   └── providers/     # Streaming scrapers
│   └── .env
├── docs/                  # Additional documentation
└── README.md
```

## Updating the backend

`backend/` is a [git submodule](https://github.com/cinepro-org/core) pointing at [cinepro-org/core](https://github.com/cinepro-org/core.git). To pull the latest upstream:

```bash
cd backend
git pull origin main
cd ..
git add backend
git commit -m "chore(backend): bump submodule to latest core"
```

Your `backend/.env` is local-only and is not overwritten by pulls.

## Backend Details

The backend uses the [OMSS framework](https://www.npmjs.com/package/@omss/framework) and multiple streaming providers. See `backend/README.md` for:

- Full configuration (Redis, Docker)
- API reference
- Provider development

## Standalone / Remote Deployment

For use outside your home network, deploy the backend to a VPS or hosting service. Update `Secrets.streamingServerBaseURL` in the app to the deployed backend URL (e.g. `https://your-server.com`).

> **Note:** Designed for personal use. Ensure compliance with applicable laws and streaming source terms of service.

## License

The backend uses the PolyForm Noncommercial License 1.0.0 — see `backend/LICENSE`. This software does not host, store, or distribute any copyrighted content.
