const BASE_URL = import.meta.env.VITE_API_URL || "";

async function apiFetch(path) {
  const res = await fetch(`${BASE_URL}${path}`);
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err.error || `HTTP ${res.status}`);
  }
  return res.json();
}

export const api = {
  getFeatured: () => apiFetch("/api/content/featured"),
  getTrending: () => apiFetch("/api/content/trending"),
  getCategories: () => apiFetch("/api/content/categories"),
  getByCategory: (slug) => apiFetch(`/api/content/category/${slug}`),
  search: (q) => apiFetch(`/api/content/search?q=${encodeURIComponent(q)}`),
  getMovie: (id) => apiFetch(`/api/movies/${id}`),
  getShow: (id) => apiFetch(`/api/shows/${id}`),
  getMovies: () => apiFetch("/api/movies"),
  getShows: () => apiFetch("/api/shows"),
};
