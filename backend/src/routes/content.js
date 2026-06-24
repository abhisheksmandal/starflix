const express = require("express");
const router = express.Router();
const { getAllContent, getCategories } = require("../data/store");

router.get("/featured", (req, res) => {
  const featured = getAllContent().filter((c) => c.featured);
  res.json({ data: featured });
});

router.get("/trending", (req, res) => {
  const trending = getAllContent().filter((c) => c.category === "trending");
  res.json({ data: trending });
});

router.get("/categories", (req, res) => {
  res.json({ data: getCategories() });
});

router.get("/category/:slug", (req, res) => {
  const { slug } = req.params;
  const items = getAllContent().filter((c) => c.category === slug);
  if (!items.length) {
    return res.status(404).json({ error: "Category not found" });
  }
  res.json({ data: items });
});

router.get("/search", (req, res) => {
  const q = (req.query.q || "").toLowerCase().trim();
  if (!q) {
    return res.status(400).json({ error: "Query parameter 'q' is required" });
  }
  const results = getAllContent().filter(
    (c) =>
      c.title.toLowerCase().includes(q) ||
      c.description.toLowerCase().includes(q) ||
      c.genre.some((g) => g.toLowerCase().includes(q))
  );
  res.json({ data: results, query: q, total: results.length });
});

module.exports = router;
