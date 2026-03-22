#!/usr/bin/env node
/**
 * Test which Invincible episodes the web scraper can find sources for.
 * Run: node backend/test-invincible-episodes.mjs [baseUrl]
 * Ensure backend is running first: cd backend && npm run dev
 */

const BASE_URL = process.argv[2] ?? 'http://localhost:3000';
const INVINCIBLE_TMDB_ID = 95557;

async function testEpisode(season, episode) {
  const url = `${BASE_URL}/v1/tv/${INVINCIBLE_TMDB_ID}/seasons/${season}/episodes/${episode}`;
  try {
    const res = await fetch(url);
    const data = await res.json().catch(() => ({}));
    const sources = data.sources ?? [];
    const playable = sources.filter(
      (s) => ['hls', 'mp4'].includes((s.type ?? '').toLowerCase())
    );
    if (res.ok && playable.length > 0) {
      return { ok: true, playable: playable.length, quality: playable[0]?.quality };
    }
    if (res.ok) {
      return { ok: true, playable: 0, total: sources.length };
    }
    const errMsg = data?.error?.message ?? `HTTP ${res.status}`;
    return { ok: false, error: errMsg };
  } catch (e) {
    return { ok: false, error: e.message || 'Unknown' };
  }
}

async function main() {
  console.log(`Testing Invincible (TMDb ID: ${INVINCIBLE_TMDB_ID}) episodes...`);
  console.log(`Backend: ${BASE_URL}\n`);

  const tests = [
    [1, 1], [1, 2], [1, 3], [1, 4], [1, 5], [1, 8],
    [2, 1], [2, 2], [2, 4],
    [3, 1], [3, 4],
    [0, 1],
  ];

  let found = 0;
  let failed = 0;

  for (const [season, episode] of tests) {
    const label = season === 0 ? `Specials E${episode}` : `S${season}E${episode}`;
    const result = await testEpisode(season, episode);
    if (result.ok && result.playable > 0) {
      console.log(`  ${label}: ✓ ${result.playable} playable (${result.quality ?? '?'})`);
      found++;
    } else if (result.ok) {
      console.log(`  ${label}: ○ No playable (${result.total ?? 0} sources)`);
    } else {
      console.log(`  ${label}: ✗ ${result.error}`);
      failed++;
    }
  }

  console.log(`\nSummary: ${found} with sources, ${failed} errors`);
  console.log('\nIf many episodes show ✗ or "Unknown" → likely backend/scraper issue');
  console.log('If this script works but app shows "Unknown" when switching seasons → TMDb rate limit');
}

main().catch(console.error);
