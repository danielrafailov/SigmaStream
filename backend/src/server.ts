import { OMSSServer } from '@omss/framework';
import dotenv from 'dotenv';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import fs from 'node:fs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Explicitly load .env from backend root regardless of PM2 working directory
dotenv.config({ path: path.resolve(__dirname, '../.env') });
dotenv.config({ path: path.resolve(process.cwd(), '.env') });
dotenv.config();

import { setGlobalDispatcher, ProxyAgent, Dispatcher } from 'undici';

class RotatingProxyDispatcher extends Dispatcher {
    private agents: ProxyAgent[];
    private index = 0;

    constructor(urls: string[]) {
        super();
        this.agents = urls.map((u) => new ProxyAgent(u));
    }

    dispatch(options: any, handler: any): boolean {
        const agent = this.agents[this.index % this.agents.length];
        this.index = (this.index + 1) % this.agents.length;
        return agent.dispatch(options, handler);
    }

    close() {
        return Promise.all(this.agents.map((a) => a.close())) as any;
    }

    destroy() {
        return Promise.all(this.agents.map((a) => a.destroy())) as any;
    }
}
import { knownThirdPartyProxies } from './thirdPartyProxies.js';
import { streamPatterns } from './streamPatterns.js';
import { generateSpeechWav, getTTS } from './tts.js';
import { transcribeWav, getTranscriber } from './stt.js';
import { StreamBufferService } from './services/streamBufferService.js';

async function main() {
    console.log('[Server] Starting CinePro backend...');

    // Optional Outbound Forward Proxy Pool (e.g. Webshare.io)
    const forwardProxy =
        process.env.WEBSHARE_PROXY ||
        process.env.FORWARD_PROXY ||
        process.env.HTTPS_PROXY ||
        process.env.HTTP_PROXY;
    if (forwardProxy) {
        try {
            const urls = forwardProxy
                .split(',')
                .map((u) => u.trim())
                .filter(Boolean);
            if (urls.length === 1) {
                console.log(
                    `[Proxy] 🌐 Setting global outbound proxy: ${urls[0].replace(/:[^:@]+@/, ':****@')}`
                );
                setGlobalDispatcher(new ProxyAgent(urls[0]));
            } else if (urls.length > 1) {
                console.log(
                    `[Proxy] 🌐 Setting rotating proxy pool across ${urls.length} endpoints`
                );
                setGlobalDispatcher(new RotatingProxyDispatcher(urls));
            }
        } catch (err: any) {
            console.warn(
                '[Proxy] ⚠️ Failed to configure outbound proxy dispatcher:',
                err.message
            );
        }
    }

    const server = new OMSSServer({
        name: 'CinePro',
        version: '1.0.0',

        // Network
        host: process.env.HOST ?? '0.0.0.0',
        port: Number(process.env.PORT ?? 3000),
        publicUrl: process.env.PUBLIC_URL,

        // Cache (memory for dev, Redis for prod)
        cache: {
            type: (process.env.CACHE_TYPE as 'memory' | 'redis') ?? 'memory',
            ttl: {
                sources: 60 * 60,
                subtitles: 60 * 60 * 24
            },
            redis: {
                host: process.env.REDIS_HOST ?? 'localhost',
                port: Number(process.env.REDIS_PORT ?? 6379),
                password: process.env.REDIS_PASSWORD
            }
        },

        // TMDB
        tmdb: {
            apiKey: process.env.TMDB_API_KEY!,
            cacheTTL: 24 * 60 * 60 // 24h
        },

        // Third Party Proxy removal
        proxyConfig: {
            knownThirdPartyProxies: knownThirdPartyProxies,
            streamPatterns
        },

        cors: {
            origin: process.env.CORS_ORIGIN ?? '*',
            methods: ['GET', 'POST', 'OPTIONS'],
            allowedHeaders: ['Content-Type', 'Authorization'],
            exposedHeaders: ['Content-Range', 'Accept-Ranges', 'ETag'],
            preflightContinue: false,
            optionsSuccessStatus: 204
        },

        stremio: {
            // exposes a stremio addon on /stremio/manifest.json
            enableNativeAddon: process.env.STREMIO_ADDON === 'true',
            // allows adding custom stremio addons that can be used as providers.
            stremioAddons: [
                {
                    id: 'Streamify',
                    url: 'https://stremify.hayd.uk/manifest.json',
                    enabled: process.env.STREAMIFY_ADDON === 'true'
                }
            ]
        },

        // MCP for AI agents
        mcp: {
            enabled: process.env.MCP_ENABLED === 'true'
        }
    });

    const app = server.getInstance();
    const streamBuffer = StreamBufferService.getInstance();

    // 1. Intercept video segment requests (/v1/proxy?data=...) with Lookahead Ring Buffer
    app.addHook('onRequest', async (request, reply) => {
        if (request.url.startsWith('/v1/proxy')) {
            const query = request.query as { data?: string };
            if (!query?.data) return;

            try {
                const decoded = decodeURIComponent(query.data);
                const proxyData = JSON.parse(decoded);
                const targetUrl = proxyData.url;

                // Match HLS / DASH / MP4 video segments (.ts, .m4s, etc.)
                if (
                    /\.(ts|m4s)($|\?)/i.test(targetUrl) ||
                    targetUrl.includes('/segment') ||
                    targetUrl.includes('seg-')
                ) {
                    const cached = await streamBuffer.getOrFetchSegment(
                        targetUrl,
                        async (fetchUrl) => {
                            const controller = new AbortController();
                            const timer = setTimeout(
                                () => controller.abort(),
                                25000
                            );

                            const reqHeaders: Record<string, string> = {
                                'User-Agent':
                                    proxyData.headers?.['User-Agent'] ||
                                    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.6912.95 Safari/537.36',
                                ...(proxyData.headers || {})
                            };
                            delete reqHeaders['range'];
                            delete reqHeaders['Range'];

                            const res = await fetch(fetchUrl, {
                                method: 'GET',
                                headers: reqHeaders,
                                signal: controller.signal
                            });
                            clearTimeout(timer);

                            const arrayBuf = await res.arrayBuffer();
                            return {
                                data: Buffer.from(arrayBuf),
                                contentType:
                                    res.headers.get('content-type') ||
                                    'video/mp2t',
                                headers: {
                                    'Content-Disposition': 'inline',
                                    'Accept-Ranges': 'bytes',
                                    'Cache-Control': 'public, max-age=7200'
                                },
                                statusCode: res.status
                            };
                        },
                        proxyData.headers
                    );

                    if (cached) {
                        reply.header(
                            'Content-Type',
                            cached.contentType || 'video/mp2t'
                        );
                        reply.header('Content-Length', cached.data.length);
                        reply.header('Accept-Ranges', 'bytes');
                        reply.header('Cache-Control', 'public, max-age=7200');
                        reply.header('Access-Control-Allow-Origin', '*');
                        reply.header(
                            'Access-Control-Expose-Headers',
                            'Content-Disposition, Content-Length, Content-Range'
                        );
                        return reply
                            .status(cached.statusCode || 200)
                            .send(cached.data);
                    }
                }
            } catch (err) {
                // If decoding fails, fall through to framework default proxy handler
            }
        }
    });

    // 2. Register parsed M3U8 playlists in StreamBufferService to trigger pre-roll prefetching
    app.addHook('onSend', async (request, reply, payload) => {
        if (request.url.startsWith('/v1/proxy')) {
            const query = request.query as { data?: string };
            if (
                query?.data &&
                typeof payload === 'string' &&
                payload.includes('#EXTM3U')
            ) {
                try {
                    const decoded = decodeURIComponent(query.data);
                    const proxyData = JSON.parse(decoded);
                    streamBuffer.registerManifest(
                        proxyData.url,
                        payload,
                        proxyData.headers
                    );
                } catch (e) {
                    // Ignore parsing error
                }
            }
        }
        return payload;
    });

    // Hook into ProxyService to stream all video media instead of buffering into memory
    const proxyServiceInstance = (server as any).proxyService;
    if (proxyServiceInstance) {
        proxyServiceInstance.shouldStream = function (url: string) {
            if (
                this.isManifestFile('', url) ||
                /\.m3u8($|\?)/i.test(url) ||
                /\.mpd($|\?)/i.test(url) ||
                /\/playlist/i.test(url) ||
                /\/manifest/i.test(url) ||
                /\.(vtt|srt|key)($|\?)/i.test(url)
            ) {
                return false;
            }
            return true;
        };

        // Override fetchWithTimeout to manually follow cross-origin redirects while preserving headers (especially Referer)
        proxyServiceInstance.fetchWithTimeout = async function (
            url: string,
            init: any,
            timeoutMs = 30000
        ) {
            let currentUrl = url;
            let redirects = 0;
            const maxRedirects = 5;

            while (redirects < maxRedirects) {
                const controller = new AbortController();
                const timeoutId = setTimeout(
                    () => controller.abort(),
                    timeoutMs
                );

                try {
                    const response = await fetch(currentUrl, {
                        ...init,
                        signal: controller.signal,
                        redirect: 'manual'
                    });

                    if (
                        [301, 302, 303, 307, 308].includes(response.status) &&
                        response.headers.get('location')
                    ) {
                        clearTimeout(timeoutId);
                        const redirectLocation =
                            response.headers.get('location')!;
                        currentUrl = new URL(
                            redirectLocation,
                            currentUrl
                        ).toString();
                        redirects++;
                        continue;
                    }

                    clearTimeout(timeoutId);
                    return response;
                } catch (err) {
                    clearTimeout(timeoutId);
                    throw err;
                }
            }

            throw new Error(`Too many redirects (max: ${maxRedirects})`);
        };
    }

    // Hook into ProxyService to ensure Content-Length header is correct when manifest data is rewritten
    const origProxyRequest = (server as any).proxyService.proxyRequest.bind(
        (server as any).proxyService
    );

    (server as any).proxyService.proxyRequest = async function (
        encodedData: string
    ) {
        let proxyData: any;
        try {
            const decoded = decodeURIComponent(encodedData);
            proxyData = JSON.parse(decoded);
        } catch {
            return origProxyRequest(encodedData);
        }

        const res = await origProxyRequest(encodedData);

        // Fix Content-Length header if buffered data length changed (e.g. manifest rewriting)
        if ('data' in res && Buffer.isBuffer(res.data)) {
            if (res.headers) {
                res.headers['Content-Length'] = String(res.data.length);
            }
        }

        return res;
    };

    // In-memory High Performance Stream Cache (4-hour TTL)
    const streamResolutionCache = new Map<
        string,
        { result: any[]; expiresAt: number }
    >();

    // Hook into SourceService for Instant First-Success Stream Resolution
    const sourceService = (server as any).sourceService;
    if (sourceService) {
        sourceService.fetchFromProviders = async function (
            type: 'movie' | 'tv',
            media: any
        ) {
            const mediaId =
                media.tmdbId || media.id || media.imdbId || 'unknown';
            const season = media.season || 0;
            const episode = media.episode || 0;
            const cacheKey = `${type}_${mediaId}_${season}_${episode}`;

            // Check in-memory fast cache
            const cached = streamResolutionCache.get(cacheKey);
            if (
                cached &&
                cached.expiresAt > Date.now() &&
                cached.result.length > 0
            ) {
                console.log(
                    `[SourceService] ⚡ Cache HIT for ${cacheKey} (returning in 1ms)`
                );
                return cached.result;
            }

            const providers = this.registry.getProviders();
            if (providers.length === 0) {
                console.warn('[SourceService] No providers registered');
                return [];
            }

            // Prioritize fast, direct-API providers first with working HLS (VixSrc)
            const FAST_PROVIDERS = [
                'vixsrc',
                'vidsrc',
                'fsharetv',
                'vidapi',
                'cinesu',
                'popr',
                'vidnest',
                'streammafia'
            ];
            const supportedProviders = providers
                .filter((p: any) =>
                    p.capabilities.supportedContentTypes.includes(
                        type === 'movie' ? 'movies' : 'tv'
                    )
                )
                .filter((p: any) => p.enabled)
                .sort((a: any, b: any) => {
                    const aKey = (a.id || a.name || '').toLowerCase();
                    const bKey = (b.id || b.name || '').toLowerCase();
                    const aIdx = FAST_PROVIDERS.indexOf(aKey);
                    const bIdx = FAST_PROVIDERS.indexOf(bKey);
                    const aRank = aIdx !== -1 ? aIdx : 999;
                    const bRank = bIdx !== -1 ? bIdx : 999;
                    return aRank - bRank;
                });

            console.log(
                `[SourceService] 🚀 Concurrent fast fetch across ${supportedProviders.length} provider(s)`
            );

            return new Promise((resolve) => {
                let isResolved = false;
                let pendingCount = supportedProviders.length;
                const collectedResults: any[] = [];
                let gatheringTimer: NodeJS.Timeout | null = null;

                if (supportedProviders.length === 0) {
                    return resolve([]);
                }

                const finishWithResult = (res: any[]) => {
                    if (isResolved) return;
                    isResolved = true;
                    if (gatheringTimer) clearTimeout(gatheringTimer);
                    clearTimeout(hardDeadlineTimer);

                    // Ensure every result object has valid arrays for OMSS buildResponse
                    res.forEach((r: any) => {
                        if (!Array.isArray(r.sources)) r.sources = [];
                        if (!Array.isArray(r.subtitles)) r.subtitles = [];
                        if (!Array.isArray(r.diagnostics)) r.diagnostics = [];
                    });

                    if (res.length > 0) {
                        // Prioritize providers with HLS streams so native AVPlayer can play immediately
                        res.sort((a: any, b: any) => {
                            const aHls = a.sources?.some((s: any) => s.type === 'hls') ? 0 : 1;
                            const bHls = b.sources?.some((s: any) => s.type === 'hls') ? 0 : 1;
                            return aHls - bHls;
                        });

                        streamResolutionCache.set(cacheKey, {
                            result: res,
                            expiresAt: Date.now() + 4 * 60 * 60 * 1000 // 4 hour cache
                        });
                    }
                    resolve(res);
                };

                // Hard safety deadline: guarantee total wait time is strictly < 7.5 seconds
                const hardDeadlineTimer = setTimeout(() => {
                    if (!isResolved) {
                        console.log(
                            `[SourceService] ⏱️ Hard 7.5s deadline reached for ${cacheKey}. Returning ${collectedResults.length} collected results.`
                        );
                        finishWithResult(collectedResults);
                    }
                }, 7500);

                supportedProviders.forEach(async (provider: any) => {
                    try {
                        const startTime = Date.now();

                        // Per-provider 5.5s timeout race
                        const providerPromise =
                            type === 'movie'
                                ? provider.getMovieSources(media)
                                : provider.getTVSources(media);

                        const timeoutPromise = new Promise((_, reject) =>
                            setTimeout(
                                () => reject(new Error('Provider timeout')),
                                5500
                            )
                        );

                        const result: any = await Promise.race([
                            providerPromise,
                            timeoutPromise
                        ]);

                        if (
                            result &&
                            result.sources &&
                            result.sources.length > 0
                        ) {
                            const duration = Date.now() - startTime;
                            console.log(
                                `[SourceService] ⚡ Provider '${provider.name}' (${provider.id}) returned ${result.sources.length} sources in ${duration}ms`
                            );
                            collectedResults.push(result);

                            const hasHls = result.sources.some((s: any) => s.type === 'hls');

                            // If this provider returned HLS streams (like VixSrc), finalize immediately!
                            if (hasHls) {
                                if (gatheringTimer) clearTimeout(gatheringTimer);
                                finishWithResult(collectedResults);
                                return;
                            }

                            // If only non-HLS streams returned so far (e.g. MP4), allow up to 2500ms
                            // for higher-quality HLS providers (like VixSrc) to finish
                            if (!gatheringTimer && !isResolved) {
                                gatheringTimer = setTimeout(() => {
                                    if (!isResolved) {
                                        console.log(
                                            `[SourceService] 🎯 Aggregation window complete for ${cacheKey}. Returning ${collectedResults.length} provider result(s).`
                                        );
                                        finishWithResult(collectedResults);
                                    }
                                }, 2500);
                            }

                            // If we have collected results from multiple providers, finalize
                            if (collectedResults.length >= 2) {
                                if (gatheringTimer) clearTimeout(gatheringTimer);
                                finishWithResult(collectedResults);
                                return;
                            }
                        }
                    } catch {
                        // Provider error or 5.5s timeout
                    } finally {
                        pendingCount--;
                        if (!isResolved && pendingCount === 0) {
                            finishWithResult(collectedResults);
                        }
                    }
                });
            });
        };
    }

    // Support raw audio buffers for Fastify
    app.addContentTypeParser(
        ['audio/wav', 'audio/x-wav', 'application/octet-stream'],
        { parseAs: 'buffer' },
        (req, body, done) => done(null, body)
    );

    // Custom TTS Routes (Local Free Studio-Quality Speech)
    app.get('/api/tts', async (request, reply) => {
        const { text, voice } =
            (request.query as { text?: string; voice?: string }) || {};
        if (!text || text.trim() === '') {
            return reply.status(400).send({ error: 'Missing text parameter' });
        }
        try {
            const wavBuffer = await generateSpeechWav(
                text,
                voice || 'af_heart'
            );
            reply.header('Content-Type', 'audio/wav');
            reply.header('Content-Length', wavBuffer.length);
            reply.header('Cache-Control', 'public, max-age=86400');
            return reply.send(wavBuffer);
        } catch (err: any) {
            console.error('[TTS] Error generating speech:', err);
            return reply
                .status(500)
                .send({ error: err.message || 'TTS failed' });
        }
    });

    app.post('/api/tts', async (request, reply) => {
        const { text, voice } =
            (request.body as { text?: string; voice?: string }) || {};
        if (!text || text.trim() === '') {
            return reply
                .status(400)
                .send({ error: 'Missing text parameter in body' });
        }

        // 1. Try Local Zero-Shot Voice Cloning Engine (Port 5050)
        try {
            const cloneResponse = await fetch('http://127.0.0.1:5050/api/tts', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ text, voice: voice || 'trump' }),
                signal: AbortSignal.timeout(30000)
            });

            if (cloneResponse.ok) {
                const arrayBuffer = await cloneResponse.arrayBuffer();
                const buffer = Buffer.from(arrayBuffer);
                reply.header('Content-Type', 'audio/wav');
                reply.header('Content-Length', buffer.length);
                reply.header('Cache-Control', 'public, max-age=86400');
                return reply.send(buffer);
            }
        } catch (cloneErr) {
            // Local clone server offline or loading, fallback gracefully
        }

        // 2. If voice is a native Kokoro neural voice (e.g. af_heart, am_adam, af_bella, am_michael, etc.) synthesize directly
        if (
            voice &&
            (voice.startsWith('af_') ||
                voice.startsWith('am_') ||
                voice.startsWith('bf_') ||
                voice.startsWith('bm_'))
        ) {
            try {
                const wavBuffer = await generateSpeechWav(text, voice);
                reply.header('Content-Type', 'audio/wav');
                reply.header('Content-Length', wavBuffer.length);
                reply.header('Cache-Control', 'public, max-age=86400');
                return reply.send(wavBuffer);
            } catch (err: any) {
                console.error('[TTS] Error generating speech:', err);
                return reply
                    .status(500)
                    .send({ error: err.message || 'TTS failed' });
            }
        }

        // 3. For celebrity voices when local clone engine is offline, return 503 so client's VoiceAssistantService falls back to Voice.ai (the real celebrity clone API)
        return reply.status(503).send({
            error: 'Local voice cloning engine not available; client will use Voice.ai fallback'
        });
    });

    // Direct Pre-generated Voice Sample Route (Instant <10ms playback for Settings previews)
    app.get('/api/sample/:slug', async (request, reply) => {
        const { slug } = request.params as { slug: string };
        const cleanSlug = slug.replace(/[^a-zA-Z0-9_-]/g, '');

        const candidatePaths = [
            path.resolve(__dirname, '../voices', `${cleanSlug}.wav`),
            path.resolve(__dirname, '../../voices', `${cleanSlug}.wav`),
            path.resolve(
                process.cwd(),
                'backend',
                'voices',
                `${cleanSlug}.wav`
            ),
            path.resolve(process.cwd(), 'voices', `${cleanSlug}.wav`),
            path.resolve(__dirname, 'voices', `${cleanSlug}.wav`)
        ];

        for (const candidate of candidatePaths) {
            if (fs.existsSync(candidate)) {
                const data = fs.readFileSync(candidate);
                reply.header('Content-Type', 'audio/wav');
                reply.header('Content-Length', data.length);
                reply.header('Cache-Control', 'public, max-age=86400');
                return reply.send(data);
            }
        }

        // If not found on disk, generate a preview sample dynamically
        try {
            const sampleText = `Hello! This is a preview of the ${cleanSlug.replace(/_/g, ' ')} voice.`;
            const wavBuffer = await generateSpeechWav(sampleText, 'af_heart');
            reply.header('Content-Type', 'audio/wav');
            reply.header('Content-Length', wavBuffer.length);
            return reply.send(wavBuffer);
        } catch {
            return reply.status(404).send({ error: 'Sample not found' });
        }
    });

    // Speech-to-Text Transcription Route (Local Whisper Transcription)
    app.post('/api/transcribe', async (request, reply) => {
        try {
            let buffer: Buffer | null = null;
            if (Buffer.isBuffer(request.body)) {
                buffer = request.body;
            } else if ((request.body as any)?.audioBase64) {
                buffer = Buffer.from(
                    (request.body as any).audioBase64,
                    'base64'
                );
            } else if (typeof request.body === 'string') {
                buffer = Buffer.from(request.body, 'base64');
            }

            if (!buffer || buffer.length === 0) {
                return reply
                    .status(400)
                    .send({ error: 'Missing audio payload' });
            }

            const text = await transcribeWav(buffer);
            console.log(`[STT] 🎙️ Transcribed audio prompt: "${text}"`);
            return reply.send({ text });
        } catch (err: any) {
            console.error('[STT] ❌ Error transcribing audio:', err);
            return reply
                .status(500)
                .send({ error: err.message || 'Transcription failed' });
        }
    });

    // Register providers
    const registry = server.getRegistry();
    console.log('[Server] Discovering providers...');
    await registry.discoverProviders(path.join(__dirname, './providers/'));

    console.log('[Server] Binding to port...');
    await server.start();

    // Warm up local TTS and STT models in background only if explicitly enabled
    if (process.env.WARMUP_VOICE_AI === 'true') {
        setTimeout(() => {
            getTTS().catch((err) =>
                console.warn(
                    '[TTS] Background model warmup notice:',
                    err.message
                )
            );
            getTranscriber().catch((err) =>
                console.warn(
                    '[STT] Background model warmup notice:',
                    err.message
                )
            );
        }, 2000);
    }
}

main().catch((error) => {
    console.error('[Server] Startup failed:', error);
    process.exit(1);
});
