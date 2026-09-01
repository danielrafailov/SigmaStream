/**
 * ============================================================================
 * STREAM BUFFER SERVICE (Continuous Lookahead & Rapid-Scrubbing Ring Buffer)
 * ============================================================================
 *
 * Implements intelligent edge-side prefetching and memory caching for HLS video segments.
 *
 * Features:
 * - Continuous Lookahead: Pre-fetches up to 24 future segments (~2.5 minutes) ahead of cursor.
 * - Rapid Scrubbing Optimization: Detects non-linear jumps (skips), clears stale prefetch
 *   queues, and bursts immediate parallel downloads for the new landing position.
 * - Trailing Ring Window: Retains up to 20 past segments for instant 0ms rewinds.
 * - Concurrency: Up to 6 simultaneous parallel download workers.
 * - Deduplication: Merges in-flight requests to eliminate redundant CDN queries.
 * - Memory Cap: Keeps up to 200 segments in LRU memory cache with 15-min TTL.
 */

export interface CachedSegment {
    data: Buffer;
    contentType: string;
    headers: Record<string, string>;
    statusCode: number;
    cachedAt: number;
}

interface PlaylistContext {
    id: string;
    segments: string[];
    headers?: Record<string, string>;
    lastActivity: number;
    lastRequestedIndex: number;
}

export class StreamBufferService {
    private static instance: StreamBufferService;

    // Cache of downloaded video segments: URL -> CachedSegment
    private segmentCache: Map<string, CachedSegment> = new Map();

    // In-flight download promises for deduplication: URL -> Promise<CachedSegment | null>
    private inFlightRequests: Map<string, Promise<CachedSegment | null>> =
        new Map();

    // In-flight AbortControllers to cancel obsolete prefetch requests on rapid seeks
    private inFlightControllers: Map<string, AbortController> = new Map();

    // Registered playlists: PlaylistId -> PlaylistContext
    private playlists: Map<string, PlaylistContext> = new Map();

    // Segment URL to Playlist lookup: SegmentURL -> { playlistId, index }
    private segmentIndexMap: Map<
        string,
        { playlistId: string; index: number }
    > = new Map();

    // Max segments to keep in memory across all streams (holds ~60+ mins of 1080p video, ~1.2GB RAM)
    private readonly MAX_TOTAL_SEGMENTS = 500;
    // Segment expiration TTL (20 minutes)
    private readonly SEGMENT_TTL_MS = 20 * 60 * 1000;
    // Lookahead forward prefetch depth (up to 60 segments ~ 8 to 10 minutes ahead)
    private readonly FORWARD_PREFETCH_COUNT = 60;
    // Trailing backward retain depth (up to 30 segments ~ 4 to 5 minutes behind for instant rewind)
    private readonly BACKWARD_PREFETCH_COUNT = 30;
    // Maximum concurrent background downloads (4 steady workers to prevent CDN rate limiting)
    private readonly MAX_CONCURRENT_PREFETCH = 4;

    private activePrefetchWorkers = 0;
    private prefetchQueue: Array<{
        url: string;
        headers?: Record<string, string>;
        priority: number;
        task: () => Promise<void>;
    }> = [];

    private constructor() {
        // Periodic cleanup timer every 2 minutes
        setInterval(() => this.cleanupStaleEntries(), 2 * 60 * 1000);
    }

    public static getInstance(): StreamBufferService {
        if (!StreamBufferService.instance) {
            StreamBufferService.instance = new StreamBufferService();
        }
        return StreamBufferService.instance;
    }

    /**
     * Register a parsed M3U8 manifest and its sequential segments.
     */
    public registerManifest(
        manifestUrl: string,
        content: string,
        requestHeaders?: Record<string, string>
    ): void {
        try {
            const playlistId = manifestUrl; // Preserve query parameters for distinct audio/video sub-playlists
            const lines = content.split('\n');
            const segments: string[] = [];

            for (let i = 0; i < lines.length; i++) {
                const line = lines[i].trim();
                if (!line || line.startsWith('#')) continue;

                let segmentUrl = line;

                // Unwrap proxied segment URLs (/v1/proxy?data=...) to extract the real CDN URL
                if (line.includes('proxy?data=')) {
                    try {
                        const dataMatch = line.match(/[?&]data=([^&\s]+)/);
                        if (dataMatch) {
                            const decoded = decodeURIComponent(dataMatch[1]);
                            const parsed = JSON.parse(decoded);
                            if (parsed.url) {
                                segmentUrl = parsed.url;
                            }
                        }
                    } catch {
                        // Fall back to line
                    }
                } else if (
                    !line.startsWith('http://') &&
                    !line.startsWith('https://')
                ) {
                    try {
                        segmentUrl = new URL(line, manifestUrl).toString();
                    } catch {
                        continue;
                    }
                }

                segments.push(segmentUrl);
            }

            if (segments.length === 0) return;

            // Save playlist context
            this.playlists.set(playlistId, {
                id: playlistId,
                segments,
                headers: requestHeaders,
                lastActivity: Date.now(),
                lastRequestedIndex: 0
            });

            // Map each segment to its playlist index
            for (let idx = 0; idx < segments.length; idx++) {
                this.segmentIndexMap.set(this.normalizeUrl(segments[idx]), {
                    playlistId,
                    index: idx
                });
            }

            const pName =
                manifestUrl.split('?')[0].split('/').pop() || 'playlist';
            console.log(
                `[StreamBuffer] 📋 Registered ${segments.length} segments for: ${pName}`
            );

            // Trigger immediate burst pre-roll prefetch for the first 6 segments on startup
            for (let k = 0; k < Math.min(6, segments.length); k++) {
                this.queuePrefetch(segments[k], requestHeaders, 100 - k);
            }
        } catch (err) {
            console.warn('[StreamBuffer] Failed to register manifest:', err);
        }
    }

    /**
     * Get a segment from cache or fetch with deduplication.
     */
    public async getOrFetchSegment(
        segmentUrl: string,
        fetchFn: (url: string) => Promise<{
            data: Buffer;
            contentType: string;
            headers: Record<string, string>;
            statusCode: number;
        }>,
        customHeaders?: Record<string, string>
    ): Promise<CachedSegment | null> {
        const normUrl = this.normalizeUrl(segmentUrl);
        const segShort = segmentUrl.split('?')[0].split('/').pop() || 'segment';

        // 1. Check RAM Cache (HIT)
        const cached = this.segmentCache.get(normUrl);
        if (cached) {
            cached.cachedAt = Date.now();
            console.log(
                `[StreamBuffer] ⚡ Cache HIT: ${segShort} (0ms from RAM, ${(cached.data.length / 1024 / 1024).toFixed(2)} MB)`
            );
            this.triggerLookahead(normUrl, customHeaders);
            return cached;
        }

        // 2. Check if already in-flight (Deduplication)
        const inFlight = this.inFlightRequests.get(normUrl);
        if (inFlight) {
            const result = await inFlight;
            if (result) {
                console.log(
                    `[StreamBuffer] ⚡ In-Flight HIT: ${segShort} (awaited prefetch, ${(result.data.length / 1024 / 1024).toFixed(2)} MB)`
                );
                this.triggerLookahead(normUrl, customHeaders);
                return result;
            }
        }

        // 3. Fetch from upstream (MISS)
        const fetchPromise = (async () => {
            try {
                const res = await fetchFn(segmentUrl);
                const segment: CachedSegment = {
                    data: res.data,
                    contentType: res.contentType,
                    headers: res.headers,
                    statusCode: res.statusCode,
                    cachedAt: Date.now()
                };

                this.putSegment(normUrl, segment);
                console.log(
                    `[StreamBuffer] 🌐 Fetched from CDN: ${segShort} (${(res.data.length / 1024 / 1024).toFixed(2)} MB)`
                );
                return segment;
            } catch (err) {
                console.error(
                    `[StreamBuffer] ❌ Error fetching segment ${segmentUrl.slice(-30)}:`,
                    err
                );
                return null;
            } finally {
                this.inFlightRequests.delete(normUrl);
            }
        })();

        this.inFlightRequests.set(normUrl, fetchPromise);
        const result = await fetchPromise;

        // Trigger lookahead prefetch for subsequent segments
        if (result) {
            this.triggerLookahead(normUrl, customHeaders);
        }

        return result;
    }

    /**
     * Store segment in LRU memory cache.
     */
    private putSegment(normUrl: string, segment: CachedSegment): void {
        // Enforce max capacity
        if (this.segmentCache.size >= this.MAX_TOTAL_SEGMENTS) {
            let oldestKey: string | null = null;
            let oldestTime = Infinity;

            for (const [key, val] of this.segmentCache.entries()) {
                if (val.cachedAt < oldestTime) {
                    oldestTime = val.cachedAt;
                    oldestKey = key;
                }
            }

            if (oldestKey) {
                this.segmentCache.delete(oldestKey);
            }
        }

        this.segmentCache.set(normUrl, segment);
    }

    /**
     * Trigger continuous lookahead & rapid-scrub prefetching around the current playback cursor.
     */
    private triggerLookahead(
        currentNormUrl: string,
        headers?: Record<string, string>
    ): void {
        const lookup = this.segmentIndexMap.get(currentNormUrl);
        if (!lookup) return;

        const playlist = this.playlists.get(lookup.playlistId);
        if (!playlist) return;

        playlist.lastActivity = Date.now();
        const currentIndex = lookup.index;
        const previousIndex = playlist.lastRequestedIndex;
        playlist.lastRequestedIndex = currentIndex;
        const total = playlist.segments.length;

        // Detect Rapid Skipping / Scrubbing jump (jumped more than 1 segment forward or backward)
        const isSeekJump = Math.abs(currentIndex - previousIndex) > 1;

        if (isSeekJump) {
            console.log(
                `[StreamBuffer] ⏩ Rapid Scrub/Seek detected (jump from #${previousIndex} -> #${currentIndex}). Re-prioritizing buffer...`
            );
            // Clear low-priority stale background downloads from previous position
            this.prefetchQueue = this.prefetchQueue.filter((item) => {
                const itemLookup = this.segmentIndexMap.get(
                    this.normalizeUrl(item.url)
                );
                if (!itemLookup) return false;
                // Keep only items near the new cursor
                return (
                    Math.abs(itemLookup.index - currentIndex) <=
                    this.FORWARD_PREFETCH_COUNT
                );
            });
        }

        // 1. Forward Lookahead: Pre-fetch next 24 segments ahead
        const forwardLimit = Math.min(
            total,
            currentIndex + 1 + this.FORWARD_PREFETCH_COUNT
        );
        for (
            let nextIdx = currentIndex + 1;
            nextIdx < forwardLimit;
            nextIdx++
        ) {
            const nextUrl = playlist.segments[nextIdx];
            const nextNormUrl = this.normalizeUrl(nextUrl);

            if (
                !this.segmentCache.has(nextNormUrl) &&
                !this.inFlightRequests.has(nextNormUrl)
            ) {
                // Higher priority for immediate upcoming segments (N+1, N+2, N+3)
                const dist = nextIdx - currentIndex;
                const priority = Math.max(1, 100 - dist * 3);
                this.queuePrefetch(
                    nextUrl,
                    headers || playlist.headers,
                    priority
                );
            }
        }

        // 2. Backward Retain/Prefetch: Ensure 4-6 segments behind cursor are in RAM for instant rewind
        const backwardLimit = Math.max(
            0,
            currentIndex - this.BACKWARD_PREFETCH_COUNT
        );
        for (
            let prevIdx = currentIndex - 1;
            prevIdx >= backwardLimit;
            prevIdx--
        ) {
            const prevUrl = playlist.segments[prevIdx];
            const prevNormUrl = this.normalizeUrl(prevUrl);

            if (
                !this.segmentCache.has(prevNormUrl) &&
                !this.inFlightRequests.has(prevNormUrl)
            ) {
                this.queuePrefetch(prevUrl, headers || playlist.headers, 30);
            }
        }
    }

    /**
     * Queue background prefetch with priority and concurrency control.
     */
    private queuePrefetch(
        segmentUrl: string,
        headers?: Record<string, string>,
        priority = 10
    ): void {
        let realUrl = segmentUrl;
        if (segmentUrl.includes('proxy?data=')) {
            try {
                const dataMatch = segmentUrl.match(/[?&]data=([^&\s]+)/);
                if (dataMatch) {
                    const decoded = decodeURIComponent(dataMatch[1]);
                    const parsed = JSON.parse(decoded);
                    if (parsed.url) {
                        realUrl = parsed.url;
                        headers = {
                            ...(headers || {}),
                            ...(parsed.headers || {})
                        };
                    }
                }
            } catch {}
        }

        const normUrl = this.normalizeUrl(realUrl);
        if (
            this.segmentCache.has(normUrl) ||
            this.inFlightRequests.has(normUrl)
        )
            return;

        // Check if already in queue
        if (
            this.prefetchQueue.some(
                (item) => this.normalizeUrl(item.url) === normUrl
            )
        )
            return;

        const task = async () => {
            if (
                this.segmentCache.has(normUrl) ||
                this.inFlightRequests.has(normUrl)
            )
                return;

            try {
                const controller = new AbortController();
                this.inFlightControllers.set(normUrl, controller);
                const timeoutId = setTimeout(() => controller.abort(), 20000);

                const reqHeaders: Record<string, string> = {
                    'User-Agent':
                        headers?.['User-Agent'] ||
                        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.6912.95 Safari/537.36',
                    ...(headers || {})
                };
                delete reqHeaders['range'];
                delete reqHeaders['Range'];

                const res = await fetch(realUrl, {
                    headers: reqHeaders,
                    signal: controller.signal
                });
                clearTimeout(timeoutId);

                if (res.ok) {
                    const arrayBuf = await res.arrayBuffer();
                    const buf = Buffer.from(arrayBuf);
                    const contentType =
                        res.headers.get('content-type') || 'video/mp2t';

                    this.putSegment(normUrl, {
                        data: buf,
                        contentType,
                        headers: {
                            'Content-Disposition': 'inline',
                            'Accept-Ranges': 'bytes',
                            'Cache-Control': 'public, max-age=7200'
                        },
                        statusCode: res.status,
                        cachedAt: Date.now()
                    });

                    const segShort =
                        realUrl.split('?')[0].split('/').pop() || 'segment';
                    console.log(
                        `[StreamBuffer] 📥 Background Prefetched: ${segShort} (${(buf.length / 1024 / 1024).toFixed(2)} MB)`
                    );
                }
            } catch {
                // Background prefetch cancellation / error is non-critical
            } finally {
                this.inFlightControllers.delete(normUrl);
            }
        };

        this.prefetchQueue.push({
            url: realUrl,
            headers,
            priority,
            task
        });

        // Keep queue sorted by highest priority first
        this.prefetchQueue.sort((a, b) => b.priority - a.priority);

        this.processPrefetchQueue();
    }

    /**
     * Process prefetch queue with worker limit.
     */
    private processPrefetchQueue(): void {
        while (
            this.activePrefetchWorkers < this.MAX_CONCURRENT_PREFETCH &&
            this.prefetchQueue.length > 0
        ) {
            const nextItem = this.prefetchQueue.shift();
            if (!nextItem) break;

            this.activePrefetchWorkers++;
            nextItem.task().finally(() => {
                this.activePrefetchWorkers--;
                this.processPrefetchQueue();
            });
        }
    }

    /**
     * Periodically clean up stale segment cache entries.
     */
    private cleanupStaleEntries(): void {
        const now = Date.now();
        for (const [key, segment] of this.segmentCache.entries()) {
            if (now - segment.cachedAt > this.SEGMENT_TTL_MS) {
                this.segmentCache.delete(key);
            }
        }

        for (const [id, playlist] of this.playlists.entries()) {
            if (now - playlist.lastActivity > this.SEGMENT_TTL_MS) {
                this.playlists.delete(id);
            }
        }
    }

    private normalizeUrl(rawUrl: string): string {
        try {
            const u = new URL(rawUrl);
            return `${u.origin}${u.pathname}`;
        } catch {
            return rawUrl;
        }
    }
}
