require("dotenv").config();
const express = require("express");
app.get("/health", (req, res) => {
  res.json({ status: "ok", service: "starflix-api", timestamp: new Date().toISOString() });
});

app.use("/api/movies",  moviesRouter);
app.use("/api/shows",   showsRouter);
app.use("/api/content", contentRouter);

app.use((req, res) => {
  res.status(404).json({ error: `Route ${req.path} not found` });
});joemjrogesj
wxrfhrow
app.use(errorHandler);

// Enrich artwork from TMDB before accepting requests
store.initialize().then(() => {
  app.listen(PORT, () => {
    console.log(`Starflix API running on http://localhost:${PORT}`);
  });
});
