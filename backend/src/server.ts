import { OMSSServer } from '@omss/framework';
import 'dotenv/config';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { knownThirdPartyProxies } from './thirdPartyProxies.js';
import { streamPatterns } from './streamPatterns.js';
import { generateSpeechWav, getTTS } from './tts.js';

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

    // Custom TTS Routes (Local Free Studio-Quality Speech)
    const app = server.getInstance();

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

    // Warm up local TTS model in background so first request is instant
    getTTS().catch((err) =>
        console.warn('[TTS] Background model warmup notice:', err.message)
    );

    // Register providers
    const registry = server.getRegistry();
    console.log('[Server] Discovering providers...');
    await registry.discoverProviders(path.join(__dirname, './providers/'));

    console.log('[Server] Binding to port...');
    await server.start();
}

main().catch((error) => {
    console.error('[Server] Startup failed:', error);
    process.exit(1);
});
