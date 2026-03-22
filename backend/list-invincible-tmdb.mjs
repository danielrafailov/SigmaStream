#!/usr/bin/env node
/**
 * List all Invincible episodes available on TMDb.
 * Run: node backend/list-invincible-tmdb.mjs
 * Requires: backend/.env with TMDB_API_KEY
 */

import { readFileSync, existsSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));

try {
  const envPath = join(__dirname, '.env');
  if (existsSync(envPath)) {
    for (const line of readFileSync(envPath, 'utf8').split('\n')) {
      const m = line.match(/^\s*TMDB_API_KEY\s*=\s*(.+)$/);
      if (m) process.env.TMDB_API_KEY = m[1].trim().replace(/^["']|["']$/g, '');
    }
  }
} catch (_) {}

const API_KEY = process.env.TMDB_API_KEY;
const INVINCIBLE_ID = 95557;

async function fetch(url) {
  const res = await globalThis.fetch(url);
  return res.json().catch(() => ({}));
}

async function main() {
  if (!API_KEY) {
    console.error('TMDB_API_KEY not set. Add to backend/.env');
    process.exit(1);
  }

  const base = `https://api.themoviedb.org/3`;
  const q = `api_key=${API_KEY}`;

  // 1. TV series details
  const series = await fetch(`${base}/tv/${INVINCIBLE_ID}?${q}`);
  if (series.id === undefined) {
    console.error('Failed to fetch series:', series.status_message || 'Unknown');
    process.exit(1);
  }

  const seasons = series.seasons || [];
  const numSeasons = series.number_of_seasons ?? seasons.length;

  console.log(`\n=== INVINCIBLE (TMDb ID: ${INVINCIBLE_ID}) on TMDb ===\n`);
  console.log(`Series: ${series.name}`);
  console.log(`TMDb reports: ${numSeasons} season(s), ${seasons.length} season entries in seasons array`);
  console.log('');

  for (const s of seasons.sort((a, b) => a.season_number - b.season_number)) {
    const sn = s.season_number;
    const name = s.name || `Season ${sn}`;
    const epCount = s.episode_count ?? '?';
    console.log(`Season ${sn} (${name}): ${epCount} episodes listed in series response`);
  }

  console.log('\n--- Fetching per-season episode details ---\n');

  for (const s of seasons.sort((a, b) => a.season_number - b.season_number)) {
    const sn = s.season_number;
    const res = await fetch(`${base}/tv/${INVINCIBLE_ID}/season/${sn}?${q}`);
    if (res.id === undefined) {
      console.log(`Season ${sn}: FAILED - ${res.status_message || res.status_code || 'Unknown'}`);
      continue;
    }
    const episodes = res.episodes || [];
    console.log(`Season ${sn} (${res.name || ''}): ${episodes.length} episodes`);
    for (const ep of episodes) {
      const air = ep.air_date ? ` (${ep.air_date})` : '';
      console.log(`  E${String(ep.episode_number).padStart(2)}: ${ep.name || 'TBA'}${air}`);
    }
    console.log('');
  }

  console.log('=== End TMDb data ===\n');
}

main().catch(console.error);
