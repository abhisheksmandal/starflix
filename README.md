# ★ Starflix

A Netflix-inspired full-stack streaming platform built with Node.js — no database required.

---

## Project Structure

```
starflix/
├── backend/                        # Express.js REST API
│   ├── src/
│   │   ├── data/
│   │   │   └── mockData.js         # In-memory movies & shows (12 movies, 8 shows)
│   │   ├── middleware/
│   │   │   └── errorHandler.js     # Global error handler
│   │   ├── routes/
│   │   │   ├── content.js          # /api/content — featured, trending, categories, search
│   │   │   ├── movies.js           # /api/movies
│   │   │   └── shows.js            # /api/shows
│   │   └── index.js                # Express app entry point
│   ├── .dockerignore
│   ├── .env.example
│   ├── Dockerfile
│   └── package.json
│
├── frontend/                       # React + Vite SPA
│   ├── public/
│   │   └── favicon.svg
│   ├── src/
│   │   ├── api/
│   │   │   └── client.js           # Typed fetch wrapper for all API calls
│   │   ├── components/
│   │   │   ├── ContentRow.jsx/css  # Horizontally scrollable content row
│   │   │   ├── Hero.jsx/css        # Auto-rotating featured banner
│   │   │   ├── Modal.jsx/css       # Content detail sheet
│   │   │   ├── MovieCard.jsx/css   # Hover card with overlay
│   │   │   ├── Navbar.jsx/css      # Sticky nav with search
│   │   │   └── SearchResults.jsx/css
│   │   ├── App.css
│   │   ├── App.jsx                 # Root component — state & routing
│   │   ├── index.css               # Global design tokens & reset
│   │   └── main.jsx
│   ├── .dockerignore
│   ├── .env.example
│   ├── Dockerfile
│   ├── index.html
│   ├── nginx.conf                  # SPA fallback + /api proxy to backend
│   ├── package.json
│   └── vite.config.js
│
└── docker-compose.yml              # Orchestrates both services
```

---

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Health check |
| GET | `/api/movies` | All movies (optional `?genre=` `?year=`) |
| GET | `/api/movies/:id` | Single movie |
| GET | `/api/shows` | All TV shows (optional `?genre=`) |
| GET | `/api/shows/:id` | Single show |
| GET | `/api/content/featured` | Featured/hero items |
| GET | `/api/content/trending` | Trending content |
| GET | `/api/content/categories` | Available category list |
| GET | `/api/content/category/:slug` | Content by category |
| GET | `/api/content/search?q=` | Full-text search across title, description, genre |

---

## Dev Mode Setup

### Prerequisites

- Node.js 20+
- npm 9+

### 1. Backend

```bash
cd backend
npm install
cp .env.example .env
```

Open `.env` and add your free TMDB API key to get real MCU posters and backdrops:

```
TMDB_API_KEY=your_key_here   # https://www.themoviedb.org/settings/api
```

```bash
npm run dev
```

Runs on **http://localhost:4000**. On startup, if `TMDB_API_KEY` is set the server fetches official artwork for all 37 released MCU films from the TMDB CDN and holds them in memory. Without a key it falls back to placeholder images.

Uses `nodemon` for hot reload.

### 2. Frontend

Open a second terminal:

```bash
cd frontend
npm install
cp .env.example .env       # sets VITE_API_URL=http://localhost:4000
npm run dev
```

Runs on **http://localhost:5173**. Vite proxies `/api/*` requests to the backend.

---

## Docker Setup

### Prerequisites

- Docker 24+
- Docker Compose v2

### Build & Run

```bash
docker compose up --build
```

| Service | URL |
|---------|-----|
| Frontend | http://localhost:3000 |
| Backend | http://localhost:4000 |

In Docker, the frontend nginx container proxies all `/api/*` requests to the backend container over the internal `starflix-net` bridge network — no CORS issues, no hardcoded URLs in the built JS bundle.

### Useful commands

```bash
# Run in background
docker compose up --build -d

# View logs
docker compose logs -f

# Stop and remove containers
docker compose down

# Rebuild a single service
docker compose up --build backend
```

---

## Tech Stack

| Layer | Technology |
|-------|------------|
| Frontend | React 18, Vite 5 |
| Backend | Node.js 20, Express 4 |
| Styling | Plain CSS with custom properties |
| Container | Docker + nginx (frontend), node:alpine (backend) |
| Data | In-memory MCU dataset (no database) |

---

## Content Dataset

All 41 MCU theatrical films are included in `backend/src/data/mockData.js`, organized by category:

| Category | Films |
|----------|-------|
| `trending` | Phase 5–6 latest releases (Quantumania → Fantastic Four) |
| `popular` | All-time fan favorites (Endgame, Infinity War, No Way Home…) |
| `top_rated` | Highest-rated entries (Winter Soldier, Ragnarok, GotG Vol. 3…) |
| `classics` | Phase 1–4 classics (Iron Man through Black Widow) |
| `upcoming` | Confirmed future releases (Blade, Doomsday, Secret Wars) |

### Upcoming films (rating TBA)

| Title | Release Date |
|-------|-------------|
| Blade | November 7, 2025 |
| Avengers: Doomsday | May 1, 2026 |
| Spider-Man: Brand New Day | July 24, 2026 |
| Avengers: Secret Wars | May 7, 2027 |

Upcoming films render a red **Coming Soon** badge on cards, and a **Remind Me** button (instead of Play) in the detail modal.
