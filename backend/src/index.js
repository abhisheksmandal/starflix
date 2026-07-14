require("dotenv").config();
const express = require("express");
const cors = require("cors");
const helmet = require("helmet");
const morgan = require("morgan");
const errorHandler = require("./middleware/errorHandler");
const store = require("./data/store");

const moviesRouter  = require("./routes/movies");
const showsRouter   = require("./routes/shows");
const contentRouter = require("./routes/content");

const app  = express();
const PORT = process.env.PORT || 4000;

app.use(helmet());
app.use(morgan("dev"));
app.use(
  cors({
    origin: process.env.FRONTEND_URL || "http://localhost:5173",
    methods: ["GET"],
  })
);
app.use(express.json());

app.get("/health", (req, res) => {
  res.json({ status: "ok", service: "starflix-api", timestamp: new Date().toISOString() });
});

app.use("/api/movies",  moviesRouter);
app.use("/api/shows",   showsRouter);
app.use("/api/content", contentRouter);

app.use((req, res) => {
  res.status(404).json({ error: `Route ${req.path} not found` });
});

app.use(errorHandler);

// Enrich artwork from TMDB before accepting requests
store.initialize().then(() => {
  app.listen(PORT, () => {
    console.log(`Starflix API running on http://localhost:${PORT}`);
  });
});
