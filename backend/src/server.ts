import { OMSSServer } from '@omss/framework';
import 'dotenv/config';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { knownThirdPartyProxies } from './thirdPartyProxies.js';
import { streamPatterns } from './streamPatterns.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Runs before main(): if this never appears in Railway logs, the running image is not this build.
console.log(`[Server] entrypoint loaded pid=${process.pid} file=${__filename}`);

/** Public base URL for proxy links (required when listening on 0.0.0.0, else OMSS falls back to localhost). */
function resolvePublicUrl(): string | undefined {
    const explicit = process.env.PUBLIC_URL?.trim();
    if (explicit) return explicit.replace(/\/$/, '');
    const railwayDomain = process.env.RAILWAY_PUBLIC_DOMAIN?.trim();
    if (railwayDomain) return `https://${railwayDomain.replace(/\/$/, '')}`;
    return undefined;
}

process.on('uncaughtException', (err) => {
    console.error('[Server] uncaughtException:', err);
    if (err instanceof Error && err.stack) console.error(err.stack);
    process.exit(1);
});

process.on('unhandledRejection', (reason) => {
    console.error('[Server] unhandledRejection:', reason);
    if (reason instanceof Error && reason.stack) console.error(reason.stack);
});

async function main() {
    const host = process.env.HOST ?? 'localhost';
    const port = Number(process.env.PORT ?? 3000);
    const publicUrl = resolvePublicUrl();

    console.log(
        `[Server] bootstrap host=${host} port=${port} publicUrl=${publicUrl ?? '(unset — OMSS may use localhost for proxy base)'}`,
    );
    console.log(
        `[Server] env replica=${process.env.RAILWAY_REPLICA_ID ?? 'n/a'} deployment=${process.env.RAILWAY_DEPLOYMENT_ID ?? 'n/a'}`,
    );

    const tmdbApiKey = process.env.TMDB_API_KEY?.trim();
    if (!tmdbApiKey) {
        console.error(
            '[Server] TMDB_API_KEY is not set. In Railway: open this backend service → Variables → add TMDB_API_KEY (your TMDb API v3 auth key). ' +
                'Use the same environment (e.g. Production) as the deployment. Redeploy after saving.',
        );
        process.exit(1);
    }

    const server = new OMSSServer({
        name: 'CinePro',
        version: '1.0.0',

        // Network
        host,
        port,
        publicUrl,

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

        // TMDB (OMSS also reads process.env.TMDB_API_KEY; we pass explicitly after guard above)
        tmdb: {
            apiKey: tmdbApiKey,
            cacheTTL: 24 * 60 * 60 // 24h
        },

        // Third Party Proxy removal
        proxyConfig: {
            knownThirdPartyProxies: knownThirdPartyProxies,
            streamPatterns
        }
    });

    // Register providers
    const registry = server.getRegistry();
    const providersDir = path.join(__dirname, './providers/');
    console.log(`[Server] discovering providers under ${providersDir}`);
    await registry.discoverProviders(providersDir);
    console.log(`[Server] provider discovery done (count=${registry.count})`);

    console.log('[Server] starting HTTP listener…');
    await server.start();
}

main().catch((err) => {
    // Temporary: surface startup failures on Railway (remove once stable).
    console.error('[Server] Fatal startup error:', err);
    console.log('[Server] Fatal startup error (stdout copy):', err);
    if (err instanceof Error && err.stack) {
        console.error(err.stack);
        console.log(err.stack);
    }
    process.exit(1);
});
