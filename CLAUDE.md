# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Starflix** is a Netflix-inspired full-stack streaming platform featuring 41 MCU theatrical films and TV shows. It's a monorepo with separate frontend (React + Vite SPA) and backend (Express REST API) services, both containerized with Docker and deployable to AWS ECS.

## Architecture

### Monorepo Structure

```
starflix/
├── backend/          # Express REST API (Node.js 20+)
├── frontend/         # React 18 + Vite SPA
├── docker-compose.yml
├── buildspec.yml     # AWS CodeBuild configuration
└── deploy.md         # AWS ECS deployment guide
```

### Data Flow

1. **Frontend** (`frontend/src/App.jsx`): React root component manages home page state (featured items, category rows, search). Uses `api/client.js` for all backend calls.
2. **API Client** (`frontend/src/api/client.js`): Typed fetch wrapper providing methods like `api.getFeatured()`, `api.search(q)`, `api.getByCategory()`.
3. **Backend** (`backend/src/index.js`): Express server with three route namespaces:
   - `/api/movies` — movie CRUD
   - `/api/shows` — show CRUD
   - `/api/content` — featured, trending, categories, search
4. **Data Store** (`backend/src/data/store.js`): In-memory store initialized at startup. On initialization, if `TMDB_API_KEY` is set, enriches all movies/shows with real artwork from TMDB; otherwise uses picsum placeholder images.

### Frontend Architecture

- **App.jsx**: Root component. Fetches featured + category data on mount; manages search state with debounced (350ms) API calls; conditionally renders Hero + ContentRows or SearchResults.
- **Components**:
  - `Navbar.jsx`: Sticky header with search toggle and scroll-based styling
  - `Hero.jsx`: Auto-rotating carousel (7s interval) for featured items
  - `ContentRow.jsx`: Horizontally scrollable category section with left/right chevron controls
  - `MovieCard.jsx`: Clickable poster card with hover overlay; shows play button or "Coming Soon" badge for upcoming releases
  - `Modal.jsx`: Full-screen detail sheet; displays "Play" for released content, "Remind Me" for upcoming
  - `SearchResults.jsx`: Grid of results; displays message when no matches found
- **Styling**: Plain CSS with CSS custom properties (design tokens in `index.css`). Dark Netflix-inspired theme (accent: `#e50914` red).

### Backend Architecture

- **Express app** (`src/index.js`): Configures middleware (helmet, CORS, morgan), mounts routers, starts server on port 4000 after store initialization.
- **Routes**:
  - `movies.js`: GET `/` (all movies, filterable by genre/year), GET `/:id`
  - `shows.js`: GET `/` (all shows, filterable by genre), GET `/:id`
  - `content.js`: GET `/featured`, `/trending`, `/categories`, `/category/:slug`, `/search?q=`
- **Middleware**: Global error handler in `errorHandler.js` catches exceptions and returns JSON errors.
- **Data**: All 41 MCU films + upcoming releases hardcoded in `mockData.js` with categories (classics, popular, top_rated, trending, upcoming) and phases (1–6).
- **TMDB Integration** (`data/tmdb.js`): On startup, fetches real posters/backdrops from TMDB API (via `tmdbId` field) and updates the in-memory store. Gracefully falls back to picsum URLs if TMDB key is missing or requests fail.

## Development Commands

### Backend
```bash
cd backend
npm install
cp .env.example .env
npm run dev           # Runs on http://localhost:4000 with nodemon hot reload
npm start             # Production start
```

**Environment**: `TMDB_API_KEY` (optional) — free tier from https://www.themoviedb.org/settings/api. Without it, placeholder images are used.

### Frontend
```bash
cd frontend
npm install
cp .env.example .env  # Sets VITE_API_URL=http://localhost:4000
npm run dev           # Runs on http://localhost:5173 with Vite proxy to /api
npm run build         # Builds to dist/
npm run preview       # Previews production build
```

**Vite Dev Server**: Proxies `/api/*` requests to the backend via `vite.config.js`. In production (Docker), nginx handles this.

### Docker
```bash
docker compose up --build       # Runs both services; frontend on :3000, backend on :4000
docker compose logs -f          # View logs
docker compose down             # Stop and remove containers
docker compose up --build backend  # Rebuild single service
```

**Network**: Both services communicate over internal `starflix-net` bridge. Frontend nginx proxies `/api/*` to backend via service name.

## Key Files & Patterns

### Content Data Model
All items (movies & shows) have this shape:
```javascript
{
  id, tmdbId,
  title, description, year, rating,
  genre: ["Action", "Sci-Fi", ...],
  category: "classics" | "popular" | "top_rated" | "trending" | "upcoming",
  phase: 1-6,
  poster, backdrop,
  featured: boolean,
  upcoming: boolean,
  type: "movie" | "show",
  // For movies:
  duration: "2h 6m",
  // For shows:
  seasons, episodes
}
```

### Store Initialization
Backend's `store.js` calls `initialize()` in `index.js` before listening. This function:
1. Loads raw mock data
2. Calls `enrichWithTMDB()` in parallel for both movies and shows
3. Updates the in-memory store
4. Server only starts after initialization completes

### API Response Format
All routes return `{ data: [...], ...extra }`:
```javascript
// Featured
{ data: [item, ...] }

// Categories
{ data: [{id: "classics", label: "Classics"}, ...] }

// Search
{ data: [item, ...], query: "iron man", total: 2 }

// Error
{ error: "Movie not found" }  // With appropriate HTTP status
```

### Frontend State Management
App.jsx uses React hooks (useState, useEffect, useCallback). No Redux/Zustand — state is lifted to the root component. Search has a 350ms debounce to avoid excessive API calls.

### Styling Approach
- Global design tokens in `index.css` (colors, spacing, transitions, shadow, border-radius)
- Component-scoped CSS modules (e.g., `Navbar.css` for `Navbar.jsx`)
- Flexbox/CSS Grid for layouts
- Smooth scroll, passive event listeners, lazy image loading for performance

## Deployment

**AWS ECS (EC2 launch type)**: Infrastructure set up in `deploy.md`. The `buildspec.yml` is used by AWS CodeBuild to:
1. Build Docker images for both frontend and backend
2. Push to ECR
3. Update ECS services (EC2 launch type — `target_type = "instance"` in ALB target groups)

Both services run in the same ECS cluster on EC2 hosts. Each service has its own public-facing ALB: frontend ALB on port 80/443, backend ALB on port 4000.

## Notes for Future Development

1. **No Database**: All data is in-memory. Persisting new content requires updating `mockData.js` and redeploying.
2. **TMDB Enrichment**: Optional but recommended for real artwork. Free tier has rate limits; consider caching or CDN in production.
3. **Search**: Client-side debounce + server-side full-text search across title, description, and genre.
4. **Upcoming Films**: Render "Coming Soon" badge on cards and "Remind Me" button in modal instead of "Play".
5. **Error Handling**: Backend returns JSON errors; frontend displays error state if initial data load fails.
6. **CORS**: Backend allows requests from `FRONTEND_URL` env var (default `http://localhost:5173`). In Docker, CORS is not needed because nginx proxies internally.
