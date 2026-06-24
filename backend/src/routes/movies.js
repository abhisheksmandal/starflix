const express = require("express");
const router = express.Router();
const { getMovies } = require("../data/store");

router.get("/", (req, res) => {
  const { genre, year } = req.query;
  let result = getMovies();
  if (genre) result = result.filter((m) => m.genre.includes(genre));
  if (year)  result = result.filter((m) => m.year === parseInt(year, 10));
  res.json({ data: result, total: result.length });
});

router.get("/:id", (req, res) => {
  const movie = getMovies().find((m) => m.id === parseInt(req.params.id, 10));
  if (!movie) return res.status(404).json({ error: "Movie not found" });
  res.json({ data: movie });
});

module.exports = router;
