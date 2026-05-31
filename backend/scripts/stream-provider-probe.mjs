#!/usr/bin/env node
/**
 * Probes OMSS /v1/movies/:id responses and does lightweight HTTP checks on proxy URLs.
 * Proxy for AVPlayer success — validates upstream reachable through OMSS proxy with plausible media prelude.
 *
 * Usage: PROBE_BASE_URL=http://127.0.0.1:3000 node scripts/stream-provider-probe.mjs
 */

const BASE = (process.env.PROBE_BASE_URL ?? 'http://127.0.0.1:3000').replace(/\/$/, '');
const OMSS_TIMEOUT_MS = Number(process.env.PROBE_OMSS_TIMEOUT_MS ?? 180000);
const URL_TIMEOUT_MS = Number(process.env.PROBE_URL_TIMEOUT_MS ?? 20000);
const MAX_BODY_SAMPLE = 65536;

/** Popular / varied TMDB movie IDs (override: PROBE_MOVIE_IDS=936075,27205,...) */
const MOVIE_IDS = process.env.PROBE_MOVIE_IDS
    ? process.env.PROBE_MOVIE_IDS.split(/[, ]+/).map(Number).filter(Boolean)
    : [936075, 27205, 550, 603692, 76600, 438631];

function providerKey(s) {
    const p = s.provider ?? {};
    return String(p.id ?? p.name ?? 'unknown').trim() || 'unknown';
}

function classifyOk(type, buf, status) {
    if (!status || status >= 400) return false;
    const head = buf.slice(0, 8192);
    const text = new TextDecoder('utf8', { fatal: false }).decode(head);
    const t = (type ?? '').toLowerCase();
    if (t === 'hls') return text.includes('#EXTM3U') || text.includes('.m3u8');
    if (t === 'mp4') {
        const u8 = new Uint8Array(buf.buffer, buf.byteOffset, Math.min(buf.length, 32));
        const hasFtyp = buf.length >= 12 && String.fromCharCode(...u8.slice(4, 8)) === 'ftyp';
        return hasFtyp || text.includes('ftyp');
    }
    if (t === 'dash') return text.includes('<MPD') || text.includes('<?xml');
    // fallback
    return text.includes('#EXTM3U') || text.includes('<MPD') || buf.length > 100;
}

async function fetchOmssMovies(tmdbId) {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), OMSS_TIMEOUT_MS);
    const started = Date.now();
    const res = await fetch(`${BASE}/v1/movies/${tmdbId}`, {
        signal: ctrl.signal,
        headers: { Accept: 'application/json' },
    });
    clearTimeout(t);
    const elapsed = Date.now() - started;
    if (!res.ok) {
        const txt = await res.text().catch(() => '');
        throw new Error(`OMSS ${res.status} for movie ${tmdbId}: ${txt.slice(0, 200)}`);
    }
    const json = await res.json();
    return { json, omssMs: elapsed };
}

async function probeSourceUrl(url, type) {
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), URL_TIMEOUT_MS);
    const t0 = Date.now();
    try {
        const res = await fetch(url, {
            signal: ctrl.signal,
            redirect: 'follow',
            headers: {
                Range: 'bytes=0-65535',
                Accept: '*/*',
            },
        });
        const headersMs = Date.now() - t0;
        const reader = res.body?.getReader();
        let chunks = [];
        let total = 0;
        if (reader) {
            while (total < MAX_BODY_SAMPLE) {
                const { done, value } = await reader.read();
                if (done) break;
                if (value) {
                    chunks.push(value);
                    total += value.length;
                }
            }
            reader.releaseLock?.();
        }
        const buf = Buffer.concat(chunks.map((c) => Buffer.from(c)));
        const ok = classifyOk(type, buf, res.status);
        return {
            ok,
            status: res.status,
            headersMs,
            totalMs: Date.now() - t0,
            bytes: buf.length,
        };
    } catch (e) {
        return {
            ok: false,
            status: 0,
            headersMs: Date.now() - t0,
            totalMs: Date.now() - t0,
            bytes: 0,
            err: e instanceof Error ? e.message : String(e),
        };
    } finally {
        clearTimeout(timer);
    }
}

async function main() {
    console.log(`Base: ${BASE}`);
    console.log(`Movies: ${MOVIE_IDS.join(', ')}`);
    console.log(`OMSS timeout: ${OMSS_TIMEOUT_MS}ms, URL timeout: ${URL_TIMEOUT_MS}ms\n`);

    /** @type {Map<string, { ok: number; fail: number; sumHeadersMs: number; sumTotalMs: number; probes: number }>} */
    const byProvider = new Map();

    function bump(key, probe) {
        let row = byProvider.get(key);
        if (!row) {
            row = { ok: 0, fail: 0, sumHeadersMs: 0, sumTotalMs: 0, probes: 0 };
            byProvider.set(key, row);
        }
        row.probes++;
        if (probe.ok) row.ok++;
        else row.fail++;
        row.sumHeadersMs += probe.headersMs;
        row.sumTotalMs += probe.totalMs;
    }

    for (const id of MOVIE_IDS) {
        let omssMs = 0;
        let sources = [];
        try {
            const r = await fetchOmssMovies(id);
            omssMs = r.omssMs;
            sources = r.json.sources ?? [];
        } catch (e) {
            console.log(`[movie ${id}] OMSS FAILED: ${e.message}`);
            continue;
        }
        console.log(`[movie ${id}] OMSS ${omssMs}ms — ${sources.length} source row(s)`);

        /** first URL per provider for this title */
        const seenProv = new Set();
        const toProbe = [];
        for (const s of sources) {
            const pk = providerKey(s);
            if (seenProv.has(pk)) continue;
            seenProv.add(pk);
            if (!s.url) continue;
            const abs = s.url.startsWith('http') ? s.url : `${BASE}${s.url.startsWith('/') ? '' : '/'}${s.url}`;
            toProbe.push({ pk, url: abs, type: s.type });
        }

        for (const { pk, url, type } of toProbe) {
            const probe = await probeSourceUrl(url, type);
            bump(pk, probe);
            const tag = probe.ok ? 'OK ' : 'FAIL';
            const extra = probe.err ? ` ${probe.err}` : '';
            console.log(
                `  ${tag} ${pk.padEnd(22)} type=${String(type).padEnd(6)} http=${probe.status} hdr=${probe.headersMs}ms tot=${probe.totalMs}ms B=${probe.bytes}${extra}`,
            );
        }
        console.log('');
    }

    const rows = [...byProvider.entries()]
        .map(([provider, s]) => ({
            provider,
            rate: s.probes ? s.ok / s.probes : 0,
            avgHdr: s.probes ? s.sumHeadersMs / s.probes : 0,
            avgTot: s.probes ? s.sumTotalMs / s.probes : 0,
            ok: s.ok,
            fail: s.fail,
            probes: s.probes,
        }))
        .sort((a, b) => b.rate - a.rate || a.avgTot - b.avgTot);

    console.log('=== Aggregate by provider (first source per provider per movie) ===');
    console.log(
        ['provider'.padEnd(24), 'success%', 'avgHdrMs', 'avgTotMs', 'ok/fail', 'n'].join('\t'),
    );
    for (const r of rows) {
        console.log(
            [
                r.provider.padEnd(24),
                `${(100 * r.rate).toFixed(0)}%`.padStart(6),
                `${r.avgHdr.toFixed(0)}`.padStart(8),
                `${r.avgTot.toFixed(0)}`.padStart(8),
                `${r.ok}/${r.fail}`.padStart(8),
                String(r.probes).padStart(3),
            ].join('\t'),
        );
    }
}

main().catch((e) => {
    console.error(e);
    process.exit(1);
});
