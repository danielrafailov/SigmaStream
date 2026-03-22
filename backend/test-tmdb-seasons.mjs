#!/usr/bin/env node
/**
 * Test TMDb API season details directly (bypasses Swift app).
 * Run: node backend/test-tmdb-seasons.mjs
 * Requires: backend/.env with TMDB_API_KEY
 * Or: TMDB_API_KEY=xxx node backend/test-tmdb-seasons.mjs
 *
 * Logs to .cursor/debug-075389.log for debug session analysis.
 */

import { readFileSync, appendFileSync, existsSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = join(__dirname, '..');
const LOG_PATH = join(PROJECT_ROOT, '.cursor', 'debug-075389.log');

// Load .env from backend
try {
  const envPath = join(__dirname, '.env');
  if (existsSync(envPath)) {
    const content = readFileSync(envPath, 'utf8');
    for (const line of content.split('\n')) {
      const m = line.match(/^\s*TMDB_API_KEY\s*=\s*(.+)$/);
      if (m) process.env.TMDB_API_KEY = m[1].trim().replace(/^["']|["']$/g, '');
    }
  }
} catch (_) {}

const API_KEY = process.env.TMDB_API_KEY;
const INVINCIBLE_ID = 95557;

function log(payload) {
  const line = JSON.stringify({ sessionId: '075389', ...payload, timestamp: Date.now() }) + '\n';
  appendFileSync(LOG_PATH, line, 'utf8');
}

async function fetchSeason(seriesId, seasonNumber, language = null) {
  const params = new URLSearchParams({ api_key: API_KEY });
  if (language) params.set('language', language);
  const url = `https://api.themoviedb.org/3/tv/${seriesId}/season/${seasonNumber}?${params}`;
  const res = await fetch(url);
  const data = await res.json().catch(() => ({}));
  return { status: res.status, ok: res.ok, data };
}

async function main() {
  if (!API_KEY) {
    console.error('TMDB_API_KEY not set. Add to backend/.env or pass as env var.');
    process.exit(1);
  }

  log({
    hypothesisId: 'A',
    location: 'test-tmdb-seasons.mjs:main',
    message: 'TMDb season test started',
    data: { seriesId: INVINCIBLE_ID, hasKey: !!API_KEY },
  });

  const seasons = [0, 1, 2, 3];
  for (const sn of seasons) {
    // Test WITHOUT language (same as Swift app: language: nil)
    const r1 = await fetchSeason(INVINCIBLE_ID, sn, null);
    log({
      hypothesisId: 'B',
      location: 'test-tmdb-seasons.mjs:fetchSeason',
      message: `Season ${sn} (no language)`,
      data: {
        seasonNumber: sn,
        status: r1.status,
        ok: r1.ok,
        episodeCount: r1.data?.episodes?.length,
        statusMessage: r1.data?.status_message,
        hasEpisodes: Array.isArray(r1.data?.episodes),
      },
    });
    if (!r1.ok && r1.data?.status_message) {
      log({
        hypothesisId: 'C',
        location: 'test-tmdb-seasons.mjs:fetchSeason',
        message: `TMDb API error for season ${sn}`,
        data: { statusMessage: r1.data.status_message, statusCode: r1.status },
      });
    }

    // Test WITH language en-US (hypothesis: nil language causes issues)
    const r2 = await fetchSeason(INVINCIBLE_ID, sn, 'en-US');
    log({
      hypothesisId: 'D',
      location: 'test-tmdb-seasons.mjs:fetchSeason',
      message: `Season ${sn} (en-US)`,
      data: {
        seasonNumber: sn,
        status: r2.status,
        ok: r2.ok,
        episodeCount: r2.data?.episodes?.length,
        statusMessage: r2.data?.status_message,
      },
    });
  }

  log({
    hypothesisId: 'E',
    location: 'test-tmdb-seasons.mjs:main',
    message: 'TMDb season test finished',
    data: {},
  });

  console.log('Done. Check', LOG_PATH, 'for NDJSON logs.');
}

main().catch((e) => {
  log({
    hypothesisId: 'F',
    location: 'test-tmdb-seasons.mjs:main',
    message: 'Script error',
    data: { error: String(e) },
  });
  console.error(e);
  process.exit(1);
});
