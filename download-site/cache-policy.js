import {
  VersionDeckManifestState,
  classifyVersionDeckManifest,
} from "./manifest-schema.js";

export const RELEASE_CACHE_SCHEMA_VERSION = 1;
export const RELEASE_CACHE_FRESH_MS = 6 * 60 * 60 * 1000;
const FUTURE_CLOCK_SKEW_MS = 5 * 60 * 1000;

export const ReleaseCacheState = Object.freeze({
  CACHED_FRESH: "cached-fresh",
  CACHED_STALE: "cached-stale",
  EXPIRED: "expired",
  INVALID: "invalid",
});

export function classifyReleaseCache(record, { now = Date.now() } = {}) {
  if (!record || typeof record !== "object") {
    return { state: ReleaseCacheState.INVALID, ageMs: Number.POSITIVE_INFINITY };
  }
  if (record.schemaVersion !== RELEASE_CACHE_SCHEMA_VERSION || !record.manifest) {
    return { state: ReleaseCacheState.INVALID, ageMs: Number.POSITIVE_INFINITY };
  }

  const fetchedAt = Date.parse(record.fetchedAt);
  const generatedAt = Date.parse(record.manifest.generatedAt);
  if (!Number.isFinite(fetchedAt) || !Number.isFinite(generatedAt)) {
    return { state: ReleaseCacheState.INVALID, ageMs: Number.POSITIVE_INFINITY };
  }
  if (fetchedAt > now + FUTURE_CLOCK_SKEW_MS || generatedAt > now + FUTURE_CLOCK_SKEW_MS) {
    return { state: ReleaseCacheState.INVALID, ageMs: Number.POSITIVE_INFINITY };
  }

  const manifestState = classifyVersionDeckManifest(record.manifest, { now });
  if (manifestState.state === VersionDeckManifestState.INVALID) {
    return { state: ReleaseCacheState.INVALID, ageMs: Number.POSITIVE_INFINITY };
  }

  const sourceTimestamp = Math.min(fetchedAt, generatedAt);
  const ageMs = Math.max(0, now - sourceTimestamp);
  if (manifestState.state === VersionDeckManifestState.EXPIRED) {
    return { state: ReleaseCacheState.EXPIRED, ageMs };
  }
  if (ageMs >= RELEASE_CACHE_FRESH_MS) {
    return { state: ReleaseCacheState.CACHED_STALE, ageMs };
  }
  return { state: ReleaseCacheState.CACHED_FRESH, ageMs };
}
