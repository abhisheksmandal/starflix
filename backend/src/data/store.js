// Central in-memory data store.
// Call `initialize()` once at startup; after that all routes use the getters.

const { movies: rawMovies, shows: rawShows, categories } = require("./mockData");
const { enrichWithTMDB } = require("../services/tmdb");

let movies = [...rawMovies];
let shows  = [...rawShows];

async function initialize() {
  const key = process.env.TMDB_API_KEY;
  if (!key) {
    console.log("ℹ  TMDB_API_KEY not set — using placeholder images.");
    return;
  }

  console.log("🎬 Fetching TMDB artwork for all MCU titles...");
  try {
    [movies, shows] = await Promise.all([
      enrichWithTMDB(rawMovies),
      enrichWithTMDB(rawShows),
    ]);
    console.log(`✓  TMDB artwork loaded for ${movies.length} movies.`);
  } catch (err) {
    console.warn("⚠  TMDB enrichment failed, falling back to placeholders:", err.message);
  }
}

const getMovies    = () => movies;
const getShows     = () => shows;
const getAllContent = () => [...movies, ...shows];
const getCategories = () => categories;

module.exports = { initialize, getMovies, getShows, getAllContent, getCategories };
