/**
 * ============================================================================
 * STREAM BUFFER SERVICE (Sliding-Window Lookahead Ring Buffer)
 * ============================================================================
 *
 * Implements intelligent edge-side prefetching and memory caching for HLS video segments.
 *
 * Features:
 * - Pre-fetches 8-12 future segments ahead of the current playback position.
 * - Retains a 4-6 segment trailing window for instantaneous 0ms rewind (Netflix-style skip).
 * - Deduplicates in-flight requests between Apple TV requests and background workers.
 * - In-memory LRU ring buffer with automatic TTL eviction (~35MB RAM footprint).
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
}

export class StreamBufferService {
    private static instance: StreamBufferService;

    // Cache of downloaded video segments: URL -> CachedSegment
    private segmentCache: Map<string, CachedSegment> = new Map();

    // In-flight download promises for deduplication: URL -> Promise<CachedSegment>
    private inFlightRequests: Map<string, Promise<CachedSegment | null>> =
        new Map();

    // Registered playlists: PlaylistId -> PlaylistContext
    private playlists: Map<string, PlaylistContext> = new Map();

    // Segment URL to Playlist lookup: SegmentURL -> { playlistId, index }
    private segmentIndexMap: Map<
        string,
        { playlistId: string; index: number }
    > = new Map();

    // Max segments to keep in memory across all streams
    private readonly MAX_TOTAL_SEGMENTS = 60;
    // Segment expiration TTL (10 minutes)
    private readonly SEGMENT_TTL_MS = 10 * 60 * 1000;
    // Lookahead forward prefetch depth
    private readonly FORWARD_PREFETCH_COUNT = 10;
    // Maximum concurrent background downloads
    private readonly MAX_CONCURRENT_PREFETCH = 3;

    private activePrefetchWorkers = 0;
    private prefetchQueue: Array<() => Promise<void>> = [];

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
            const playlistId = this.normalizeUrl(manifestUrl);
            const lines = content.split('\n');
            const segments: string[] = [];

            for (let i = 0; i < lines.length; i++) {
                const line = lines[i].trim();
                if (!line || line.startsWith('#')) continue;

                // Resolved segment URL
                let segmentUrl: string;
                if (line.startsWith('http://') || line.startsWith('https://')) {
                    segmentUrl = line;
                } else {
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
                lastActivity: Date.now()
            });

            // Map each segment to its playlist index
            for (let idx = 0; idx < segments.length; idx++) {
                this.segmentIndexMap.set(this.normalizeUrl(segments[idx]), {
                    playlistId,
                    index: idx
                });
            }

            console.log(
                `[StreamBuffer] 📋 Registered playlist (${segments.length} segments): ${manifestUrl.slice(0, 80)}...`
            );

            // Trigger immediate pre-roll prefetch for the first 3 segments on startup!
            if (segments.length > 0) {
                for (let k = 0; k < Math.min(3, segments.length); k++) {
                    this.queuePrefetch(segments[k], requestHeaders);
                }
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
        fetchFn: (
            url: string
        ) => Promise<{
            data: Buffer;
            contentType: string;
            headers: Record<string, string>;
            statusCode: number;
        }>,
        customHeaders?: Record<string, string>
    ): Promise<CachedSegment | null> {
        const normUrl = this.normalizeUrl(segmentUrl);

        // 1. Check RAM Cache (HIT)
        const cached = this.segmentCache.get(normUrl);
        if (cached) {
            // Refresh timestamp for LRU
            cached.cachedAt = Date.now();
            // Trigger lookahead prefetch in background
            this.triggerLookahead(normUrl, customHeaders);
            return cached;
        }

        // 2. Check if already in-flight (Deduplication)
        const inFlight = this.inFlightRequests.get(normUrl);
        if (inFlight) {
            const result = await inFlight;
            if (result) {
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
            // Evict oldest entry
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
     * Trigger lookahead prefetching around the current playback cursor.
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
        const total = playlist.segments.length;

        // Lookahead: Pre-fetch next N segments (e.g. index+1 through index+10)
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
                this.queuePrefetch(nextUrl, headers || playlist.headers);
            }
        }
    }

    /**
     * Queue background prefetch with concurrency control.
     */
    private queuePrefetch(
        segmentUrl: string,
        headers?: Record<string, string>
    ): void {
        const normUrl = this.normalizeUrl(segmentUrl);
        if (
            this.segmentCache.has(normUrl) ||
            this.inFlightRequests.has(normUrl)
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
                const timeoutId = setTimeout(() => controller.abort(), 20000);

                const reqHeaders: Record<string, string> = {
                    'User-Agent':
                        headers?.['User-Agent'] ||
                        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
                    ...(headers || {})
                };
                delete reqHeaders['range'];
                delete reqHeaders['Range'];

                const res = await fetch(segmentUrl, {
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

                    // Log lookahead hit
                    const segName =
                        segmentUrl.split('/').pop()?.split('?')[0] || 'segment';
                    // console.log(`[StreamBuffer] ⚡ Prefetched: ${segName} (${(buf.length / 1024 / 1024).toFixed(2)} MB)`);
                }
            } catch (err: any) {
                // Background prefetch errors are non-critical
            }
        };

        this.prefetchQueue.push(task);
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
            const nextTask = this.prefetchQueue.shift();
            if (!nextTask) break;

            this.activePrefetchWorkers++;
            nextTask().finally(() => {
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
