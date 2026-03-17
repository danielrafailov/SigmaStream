# Storage & Streaming Guide

## Storage: My List & Continue Watching

### Current Approach (UserDefaults)
- **MyListManager** and **WatchProgressManager** use UserDefaults with JSON-encoded data.
- Keys: `mylist.movieIds`, `mylist.seriesIds`, `watchprogress.movies`, `watchprogress.episodes`.

### When to Upgrade

| Factor | UserDefaults | SwiftData / Core Data |
|--------|--------------|------------------------|
| List size | Fine up to ~100–200 IDs | Better for 500+ items |
| Querying/sorting | Limited | Full SQL/predicates |
| Sync (iCloud) | Manual/custom | Built-in with CloudKit |
| Watch progress (timestamp) | Can store in UserDefaults | Better for complex metadata |
| Migration | Simple | Requires schema versioning |

### Recommendation
**Keep UserDefaults for now.** Your current My List and Continue Watching use cases are small:
- IDs and simple metadata
- No complex queries
- Single device, no sync

**Consider SwiftData when:**
- You add resume-at-timestamp (need `progressSeconds` per item)
- Users have 100+ items and want sorting (e.g., by date added)
- You want iCloud sync across devices
- You add custom lists (“Watch Later”, “Documentaries”, etc.)

Migration path: read current UserDefaults on first launch, write into SwiftData, then switch managers to SwiftData.

---

## Streaming: Expanding Coverage

### How Your App Works Today
- **CinePro** (OMSS) is your streaming backend. It resolves TMDb IDs to playable URLs.
- Your app calls: `GET /v1/movies/{tmdbId}` and `GET /v1/tv/{seriesId}/seasons/{s}/episodes/{e}`.
- CinePro aggregates sources from third-party sites and returns HLS/MP4 links.

### Why Many Titles Have No Stream
CinePro (and similar aggregators) only return links for content that exists on the sources they scrape. Common gaps:
- New releases (not yet mirrored)
- Obscure or regional titles
- Geo-restricted or takedown-heavy content

### Options to Expand Coverage

**1. Add More Aggregator APIs to CinePro**

If you control or can modify CinePro, add backends such as:
- **VidSrc** (vidsrc.online) – TMDb/IMDb ID support, HD/4K
- **Streamsrc** (streamsrc.cc) – Free API, TMDb-based
- **VidPop** (vidpop.xyz) – TMDb IDs, watch progress
- **MoviesSource** – Aggregates multiple sites, auto-refreshes dead links

These expose embeds/APIs that CinePro could call when its main sources fail.

**2. Client-Side Fallbacks**

If you can’t change CinePro:
- Add a second backend (e.g., VidSrc) in your app.
- Try CinePro first; if it returns 404 or no sources, call the fallback.
- Combine sources before presenting to the user (e.g., pick best quality).

**3. “Request Source” Flow**

- Let users report “No stream” for a title.
- Store these in a simple list (e.g., UserDefaults or a small backend).
- Use this data to prioritize which sources to add or which titles to fix.

**4. Legal/Ethical Notes**

- Aggregators often pull from piracy sites; legality varies by jurisdiction.
- Hosting or proxying copyrighted streams yourself can create liability.
- Using third-party APIs/embeds (e.g., VidSrc) shifts some risk to the provider but does not remove it.
- Consider geo-restrictions, terms of service, and local laws before adding new sources.

### Practical Next Step
The simplest improvement: add a **single fallback API** (e.g., VidSrc) to your streaming layer. If CinePro returns no sources, request the same TMDb ID from the fallback and use that URL if available.
