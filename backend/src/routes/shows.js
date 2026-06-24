const express = require("express");
const router = express.Router();
const { getShows } = require("../data/store");

router.get("/", (req, res) => {
  const { genre } = req.query;
  let result = getShows();
  if (genre) result = result.filter((s) => s.genre.includes(genre));
  res.json({ data: result, total: result.length });
});

router.get("/:id", (req, res) => {
  const show = getShows().find((s) => s.id === parseInt(req.params.id, 10));
  if (!show) return res.status(404).json({ error: "Show not found" });
  res.json({ data: show });
});

module.exports = router;
