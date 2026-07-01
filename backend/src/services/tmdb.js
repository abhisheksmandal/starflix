// Enriches movie/show records with real artwork from TMDB.
// Requires TMDB_API_KEY in environment. No-ops silently if the key is absent.
// TMDB free account: https://www.themoviedb.org/settings/api

const TMDB_API   = "https://api.themoviedb.org/3";
const TMDB_IMAGE = "https://image.tmdb.org/t/p";

const POSTER_SIZE   = "w500";
const BACKDROP_SIZE = "w1280";

async function fetchImages(tmdbId, type = "movie") {
  const key = process.env.TMDB_API_KEY;
  if (!key || !tmdbId) return null;

  try {
    const endpointType = type === "show" ? "tv" : "movie";
    const res = await fetch(
      `${TMDB_API}/${endpointType}/${tmdbId}?api_key=${key}&language=en-US`,
      { signal: AbortSignal.timeout(5000) }
    );
    if (!res.ok) return null;

    const { poster_path, backdrop_path } = await res.json();
    return {
      poster:   poster_path   ? `${TMDB_IMAGE}/${POSTER_SIZE}${poster_path}`   : null,
      backdrop: backdrop_path ? `${TMDB_IMAGE}/${BACKDROP_SIZE}${backdrop_path}` : null,
    };
  } catch {
    return null;
  }
}

// Enriches each item in `items` that has a `tmdbId`.
// Items without a tmdbId, or when the TMDB fetch fails, keep their existing
// poster/backdrop values (the picsum fallbacks from mockData).
async function enrichWithTMDB(items) {
  const key = process.env.TMDB_API_KEY;
  if (!key) return items;

  const results = await Promise.allSettled(
    items.map((item) => fetchImages(item.tmdbId, item.type))
  );

  return items.map((item, i) => {
    const res = results[i];
    if (res.status !== "fulfilled" || !res.value) return item;
    const { poster, backdrop } = res.value;
    return {
      ...item,
      poster:   poster   ?? item.poster,
      backdrop: backdrop ?? item.backdrop,
    };
  });
}

module.exports = { enrichWithTMDB };
