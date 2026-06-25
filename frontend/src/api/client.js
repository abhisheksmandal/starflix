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
  getFeatured: () => apiFetch("/content/featured"),
  getTrending: () => apiFetch("/content/trending"),
  getCategories: () => apiFetch("/content/categories"),
  getByCategory: (slug) => apiFetch(`/content/category/${slug}`),
  search: (q) => apiFetch(`/content/search?q=${encodeURIComponent(q)}`),
  getMovie: (id) => apiFetch(`/movies/${id}`),
  getShow: (id) => apiFetch(`/shows/${id}`),
  getMovies: () => apiFetch("/movies"),
  getShows: () => apiFetch("/shows"),
};
