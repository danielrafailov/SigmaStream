import { OMSSServer } from '@omss/framework';
import 'dotenv/config';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import fs from 'node:fs';
import { knownThirdPartyProxies } from './thirdPartyProxies.js';
import { streamPatterns } from './streamPatterns.js';
import { generateSpeechWav, getTTS } from './tts.js';
import { transcribeWav, getTranscriber } from './stt.js';
import { StreamBufferService } from './services/streamBufferService.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

async function main() {
    console.log('[Server] Starting CinePro backend...');

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

    // Hook into ProxyService for Sliding-Window Lookahead Segment Buffering
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

        const targetUrl = proxyData.url;

        // 1. If it's a TS / M4S video or audio segment, serve via Lookahead Ring Buffer
        if (
            /\.(ts|m4s)($|\?)/i.test(targetUrl) ||
            targetUrl.includes('/segment') ||
            targetUrl.includes('seg-')
        ) {
            const cached = await streamBuffer.getOrFetchSegment(
                targetUrl,
                async (fetchUrl: string) => {
                    const res = await origProxyRequest(encodedData);
                    if ('data' in res) {
                        return {
                            data: res.data,
                            contentType: res.contentType,
                            headers: res.headers,
                            statusCode: res.statusCode
                        };
                    }
                    const chunks: Buffer[] = [];
                    for await (const chunk of res.stream) {
                        chunks.push(
                            Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk)
                        );
                    }
                    return {
                        data: Buffer.concat(chunks),
                        contentType: res.contentType,
                        headers: res.headers,
                        statusCode: res.statusCode
                    };
                },
                proxyData.headers
            );

            if (cached) {
                return {
                    data: cached.data,
                    contentType: cached.contentType,
                    statusCode: cached.statusCode || 200,
                    headers: {
                        ...(cached.headers || {}),
                        'Content-Length': String(cached.data.length),
                        'Accept-Ranges': 'bytes',
                        'Cache-Control': 'public, max-age=7200',
                        'Access-Control-Allow-Origin': '*'
                    }
                };
            }
        }

        // 2. Run original proxy request for manifests / keys / subtitles
        const res = await origProxyRequest(encodedData);

        // 3. If it's an M3U8 manifest, register its segments in StreamBufferService
        if ('data' in res && Buffer.isBuffer(res.data)) {
            const text = res.data.toString('utf-8');
            if (text.includes('#EXTM3U')) {
                streamBuffer.registerManifest(
                    targetUrl,
                    text,
                    proxyData.headers
                );
            }
        }

        return res;
    };

    // Hook into SourceService for Instant First-Success Stream Resolution
    const sourceService = (server as any).sourceService;
    if (sourceService) {
        sourceService.fetchFromProviders = async function (
            type: 'movie' | 'tv',
            media: any
        ) {
            const providers = this.registry.getProviders();
            if (providers.length === 0) {
                console.warn('[SourceService] No providers registered');
                return [];
            }

            const supportedProviders = providers
                .filter((p: any) =>
                    p.capabilities.supportedContentTypes.includes(
                        type === 'movie' ? 'movies' : 'tv'
                    )
                )
                .filter((p: any) => p.enabled);

            console.log(
                `[SourceService] 🚀 Concurrent fetch across ${supportedProviders.length} provider(s) (first-working-stream wins)`
            );

            return new Promise((resolve) => {
                let isResolved = false;
                let pendingCount = supportedProviders.length;
                const collectedResults: any[] = [];

                if (supportedProviders.length === 0) {
                    return resolve([]);
                }

                supportedProviders.forEach(async (provider: any) => {
                    try {
                        const startTime = Date.now();
                        let result: any;
                        if (type === 'movie') {
                            result = await provider.getMovieSources(media);
                        } else {
                            result = await provider.getTVSources(media);
                        }

                        if (
                            result &&
                            result.sources &&
                            result.sources.length > 0
                        ) {
                            // Parallel validation of returned sources
                            const validatedSources = await Promise.allSettled(
                                result.sources.map(async (source: any) => {
                                    try {
                                        const urlObj = new URL(source.url);
                                        const data =
                                            urlObj.searchParams.get('data');
                                        if (!data) return source;
                                        const proxyData = (
                                            server as any
                                        ).proxyService.constructor.decodeProxyData(
                                            data
                                        );
                                        const isValid =
                                            await sourceService.validateSourceUrl(
                                                proxyData
                                            );
                                        return isValid ? source : null;
                                    } catch {
                                        return source;
                                    }
                                })
                            );

                            const validSources = validatedSources
                                .filter(
                                    (r: any) =>
                                        r.status === 'fulfilled' && r.value
                                )
                                .map((r: any) => r.value);

                            if (validSources.length > 0) {
                                result.sources = validSources;
                                const duration = Date.now() - startTime;
                                console.log(
                                    `[SourceService] ⚡ First working stream found by '${provider.name}' (${validSources.length} sources) in ${duration}ms! Returning immediately.`
                                );
                                if (!isResolved) {
                                    isResolved = true;
                                    return resolve([result]);
                                }
                            }
                        }

                        if (result) collectedResults.push(result);
                    } catch (err: any) {
                        // Provider error
                    } finally {
                        pendingCount--;
                        if (!isResolved && pendingCount === 0) {
                            isResolved = true;
                            resolve(collectedResults);
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

    // Warm up local TTS and STT models in background after server is live
    setTimeout(() => {
        getTTS().catch((err) =>
            console.warn('[TTS] Background model warmup notice:', err.message)
        );
        getTranscriber().catch((err) =>
            console.warn('[STT] Background model warmup notice:', err.message)
        );
    }, 500);
}

main().catch((error) => {
    console.error('[Server] Startup failed:', error);
    process.exit(1);
});
