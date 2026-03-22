# Season Loading Flow – Invincible (and all TV series)

This document traces how seasons and episodes are loaded when viewing a TV series in SigmaStream.

---

## 1. Entry Points

| Entry point | View | When |
|-------------|------|------|
| User navigates to TV series detail | `TVSeriesDetailView` | Tap Invincible from browse/search/etc |
| User taps "More Episodes" | `TVSeriesMoreEpisodesView` | From TVSeriesDetailView |

Both views load data **independently**. `TVSeriesMoreEpisodesView` only receives `seriesId` and `seriesName`; it fetches `series` itself via TMDb.

---

## 2. Data Sources

| Data | Source | Used for |
|------|--------|----------|
| **Season list** (0, 1, 2, 3, 4, 5) | `series.seasons` from `tvSeriesDetails` | Season picker buttons |
| **Episodes per season** | `loadedSeason.episodes` from `tvSeasonDetails` | Episode list |
| **Fallback** | `series.numberOfSeasons` | If `seasons` is empty → `Array(1...n)` |

---

## 3. Full Flow (TVSeriesMoreEpisodesView – where seasons are shown)

```
.task {
  ├─ if series == nil:
  │   ├─ series = tmdbService.tvSeriesDetails(seriesId)
  │   │   └─ TMDbService.tvSeriesDetails
  │   │       └─ client.tvSeries.details(forTVSeries:)  [TMDb Swift package]
  │   │       └─ (or cache hit: tvSeriesCache[seriesId])
  │   │
  │   ├─ seasons = (series?.seasons ?? []).map(\.seasonNumber).sorted()
  │   │   └─ e.g. [0, 1, 2, 3, 4, 5]
  │   │
  │   └─ selectedSeason = seasons.first  ← First season (0 for Invincible)
  │
  └─ await loadSeason(selectedSeason)
}

.onChange(of: selectedSeason) { _, newValue in
  └─ Task { await loadSeason(newValue) }   ← When user taps different season
}

loadSeason(seasonNumber):
  ├─ isLoadingSeason = true
  ├─ streamError = nil
  ├─ loadedSeason = tmdbService.tvSeasonDetails(seriesId, seasonNumber)
  │   └─ TMDbService.tvSeasonDetails
  │       └─ client.tvSeasons.details(forSeason:inTVSeries:language:)
  │           └─ TMDb API: GET /tv/{id}/season/{n}
  │           └─ Decodes to TVSeason (episodes array)
  ├─ on success: loadedSeason set
  └─ on error: loadedSeason = nil, streamError = error.localizedDescription

UI:
  seasonNumbers = series.seasons.map(\.seasonNumber).sorted()
  ForEach(seasonNumbers) { num in
    Button { selectedSeason = num }   ← Triggers onChange → loadSeason
  }
  episodesSection: loadedSeason?.episodes ?? "No episodes available"
```

---

## 4. Key Code Locations

| Step | File | Lines |
|------|------|-------|
| Initial load | `TVSeriesMoreEpisodesView.swift` | .task, 380–387 |
| Season change | `TVSeriesMoreEpisodesView.swift` | .onChange(selectedSeason), 388–390 |
| loadSeason | `TVSeriesMoreEpisodesView.swift` | 398–430 |
| seasonNumbers | `TVSeriesMoreEpisodesView.swift` | 30–39 |
| tvSeriesDetails | `TMDbService.swift` | 162–170 |
| tvSeasonDetails | `TMDbService.swift` | 172–200 |

---

## 5. TMDbService Caching

- **tvSeriesCache**: In-memory cache for `TVSeries` by `seriesId`. First request hits TMDb; subsequent requests use cache.
- **tvSeasonDetails**: No app-level cache; each call goes to TMDb Swift package → TMDb API.

---

## 6. Failure Modes (where “Unknown” comes from)

1. **tvSeriesDetails** fails → `series` stays nil → `seasonNumbers` = `[1]` (fallback)
2. **tvSeasonDetails** fails → `loadedSeason` = nil, `streamError` = "Unknown"
   - TMDb Swift package throws; `TMDbError` maps decoding/other errors to `.unknown` → `localizedDescription` = "Unknown"

---

## 7. Invincible-Specific (from list-invincible-tmdb.mjs)

TMDb returns:

- Seasons: 0 (Specials), 1, 2, 3, 4, 5 (6 entries)
- Season 4: 8 episodes, including S4E1 "Making the World a Better Place"

So Season 4 appears in TMDb’s series and season endpoints. If it’s missing in the app:

- Season list comes from `series.seasons` → check whether the TMDb Swift package or parsing omits some seasons.
- Episodes come from `tvSeasonDetails(4)` → check whether that call succeeds for season 4.
