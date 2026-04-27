#!/usr/bin/env node
/**
 * Quick diagnostics for OMSS stream chains.
 *
 * Usage:
 *   node scripts/check-stream-signatures.mjs 550 1327819
 *   BASE_URL=https://example.awsapprunner.com node scripts/check-stream-signatures.mjs 550
 */

const BASE_URL = (process.env.BASE_URL ?? "https://9seg4wum9n.us-east-1.awsapprunner.com").replace(/\/$/, "");
const ids = process.argv.slice(2);

if (!ids.length) {
  console.error("Provide at least one TMDb movie id.");
  process.exit(1);
}

const PNG_MAGIC = "89504e470d0a1a0a";

function firstMediaLine(text) {
  return text
    .split("\n")
    .map((l) => l.trim())
    .find((l) => l && !l.startsWith("#"));
}

function toAbsolute(base, maybeRelative) {
  if (!maybeRelative) return "";
  if (maybeRelative.startsWith("http")) return maybeRelative;
  return new URL(maybeRelative, base).toString();
}

async function readJson(url) {
  const res = await fetch(url);
  const body = await res.json();
  return { status: res.status, body };
}

async function readText(url) {
  const res = await fetch(url);
  return { status: res.status, text: await res.text() };
}

async function readBytes(url, range = "bytes=0-15") {
  const res = await fetch(url, { headers: { Range: range } });
  const ab = await res.arrayBuffer();
  const bytes = Buffer.from(ab);
  return {
    status: res.status,
    contentType: res.headers.get("content-type") ?? "",
    size: bytes.length,
    hex16: bytes.subarray(0, 16).toString("hex")
  };
}

for (const id of ids) {
  try {
    console.log(`\n=== TMDb ${id} ===`);
    const api = `${BASE_URL}/v1/movies/${id}`;
    const { status, body } = await readJson(api);
    const diagnostics = (body?.diagnostics ?? [])
      .map((d) => d?.message)
      .filter(Boolean);

    console.log(`API status: ${status}`);
    console.log(`sources: ${body?.sources?.length ?? 0}`);
    if (diagnostics.length) {
      console.log("diagnostics:");
      for (const d of diagnostics) console.log(`  - ${d}`);
    }

    const sourceUrl = body?.sources?.[0]?.url;
    if (!sourceUrl) {
      console.log("result: no sources");
      continue;
    }

    const { status: mStatus, text: master } = await readText(sourceUrl);
    const childLine = firstMediaLine(master);
    const childUrl = toAbsolute(sourceUrl, childLine);
    console.log(`master status: ${mStatus}`);
    if (!childUrl) {
      console.log("result: invalid master playlist");
      continue;
    }

    const { status: cStatus, text: child } = await readText(childUrl);
    const segLine = firstMediaLine(child);
    const segUrl = toAbsolute(childUrl, segLine);
    console.log(`child status: ${cStatus}`);
    if (!segUrl) {
      console.log("result: invalid child playlist");
      continue;
    }

    const seg = await readBytes(segUrl, "bytes=0-15");
    const isPng = seg.hex16.startsWith(PNG_MAGIC);
    console.log(`segment status: ${seg.status}`);
    console.log(`segment content-type: ${seg.contentType || "(missing)"}`);
    console.log(`segment hex16: ${seg.hex16}`);
    console.log(`segment bytes fetched: ${seg.size}`);
    console.log(`result: ${isPng ? "BAD (png payload)" : "LIKELY PLAYABLE (not png signature)"}`);
  } catch (err) {
    console.log(`result: error (${err?.message ?? String(err)})`);
  }
}

