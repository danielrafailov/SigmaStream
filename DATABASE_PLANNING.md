# Database Planning: Favourites & Settings

This document outlines options for persisting user favourites and settings if you decide to move beyond UserDefaults.

## Current Approach (UserDefaults)

- **My List**: `MyListManager` stores movie IDs and TV series IDs in UserDefaults. Simple and works for moderate lists.
- **Settings**: Currently read from `Secrets.swift` (compile-time). No user-editable settings stored.

## When a Database Makes Sense

Consider a database when:

- Favourites grow large (100+ items) and you want querying/sorting
- You want custom lists (e.g. "Watch Later", "Documentaries")
- You need sync across devices (iCloud)
- You want richer metadata (notes, watched status, progress)
- Settings become complex and user-editable

## Option 1: SwiftData (iOS 17+, tvOS 17+)

**Pros**: Native, modern, declarative. Works well with SwiftUI `@Query`.

**Models**:
```
FavouriteMovie: id, tmdbId, addedAt, title?, posterPath?
FavouriteSeries: id, tmdbId, addedAt, name?, posterPath?
UserSettings: key, value (or typed fields)
```

**Use case**: Good fit for tvOS if you target iOS 17+. Single-device, no sync.

---

## Option 2: Core Data

**Pros**: Mature, supports older OS versions, flexible.

**Cons**: More boilerplate than SwiftData.

**Use case**: If you need iOS 16 or earlier support.

---

## Option 3: SQLite (via GRDB.swift or similar)

**Pros**: Lightweight, full control, no framework lock-in.

**Cons**: More manual work; no built-in SwiftUI integration.

**Use case**: Minimal dependencies or cross-platform needs.

---

## Option 4: Keep UserDefaults + Enhance

**Pros**: No new dependencies. Add JSON files for larger data if needed.

**Enhancements**:
- Store `[FavouriteEntry]` with `tmdbId`, `type` (movie/tv), `addedAt`, optional `title` for offline display
- Use `UserDefaults` for settings keys (e.g. `preferredAudioLanguage`, `streamingServerOverride`)

**Use case**: Keeps things simple; favs and settings stay manageable.

---

## Recommendation

- **Short term**: Stay with UserDefaults. It’s enough for favourites and a few settings.
- **Medium term**: If you add watch progress, multiple lists, or richer metadata, plan for **SwiftData** (if you can require tvOS 17+).
- **Sync**: If you want iCloud sync later, use **CloudKit** with SwiftData or Core Data.

---

## Future Schema Sketch (SwiftData)

```swift
@Model
final class FavouriteMovie {
    var tmdbId: Int
    var addedAt: Date
    var title: String?
    var posterPath: String?
}

@Model
final class FavouriteSeries {
    var tmdbId: Int
    var addedAt: Date
    var name: String?
    var posterPath: String?
}

@Model
final class UserSettings {
    var streamingServerOverride: String?
    var preferredAudioLanguage: String?  // "en", etc.
}
```

---

*Do not implement database changes yet. This is for planning only.*
