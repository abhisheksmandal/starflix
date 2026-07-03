import { useState, useEffect, useCallback } from "react";
import Navbar from "./components/Navbar";
import Hero from "./components/Hero";
import ContentRow from "./components/ContentRow";
import Modal from "./components/Modal";
import SearchResults from "./components/SearchResults";
import { api } from "./api/client";
import "./App.css";

export default function App() {
  const [featured, setFeatured] = useState([]);
  const [rows, setRows] = useState([]);
  const [selectedItem, setSelectedItem] = useState(null);
  const [searchQuery, setSearchQuery] = useState("");
  const [searchResults, setSearchResults] = useState([]);
  const [searching, setSearching] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    async function loadHome() {
      try {
        const [featuredRes, categoriesRes] = await Promise.all([
          api.getFeatured(),
          api.getCategories(),
        ]);
        setFeatured(featuredRes.data);

        const rowData = await Promise.all(
          categoriesRes.data.map(async (cat) => {
            const res = await api.getByCategory(cat.id);
            return { label: cat.label, items: res.data };
          })
        );
        setRows(rowData.filter((r) => r.items.length > 0));
      } catch (err) {
        setError(err.message);
      } finally {
        setLoading(false);
      }
    }
    loadHome();
  }, []);

  useEffect(() => {
    if (!searchQuery.trim()) {
      setSearchResults([]);
      setSearching(false);
      return;
    }
    setSearching(true);
    const timer = setTimeout(async () => {
      try {
        const res = await api.search(searchQuery);
        setSearchResults(res.data);
      } catch {
        setSearchResults([]);
      } finally {
        setSearching(false);
      }
    }, 350);
    return () => clearTimeout(timer);
  }, [searchQuery]);

  const handleSelect = useCallback((item) => setSelectedItem(item), []);
  const handleCloseModal = useCallback(() => setSelectedItem(null), []);

  const isSearching = searchQuery.trim().length > 0;

  if (loading) {
    return (
      <div className="app-loading">
        <div className="app-loading__logo">
          <span className="app-loading__star">★</span>
          <span>STARFLIXXX</span>
        </div>
        <div className="spinner" />
      </div>
    );
  }

  if (error) {
    return (
      <div className="app-error">
        <h2>Unable to connect to Starflix API</h2>
        <p>{error}</p>
        <button onClick={() => window.location.reload()}>Retry</button>
      </div>
    );
  }

  return (
    <div className="app">
      <Navbar onSearch={setSearchQuery} searchQuery={searchQuery} />

      {isSearching ? (
        <SearchResults
          query={searchQuery}
          results={searchResults}
          loading={searching}
          onSelect={handleSelect}
        />
      ) : (
        <>
          <Hero items={featured} onSelect={handleSelect} />
          <div className="app__rows">
            {rows.map((row) => (
              <ContentRow
                key={row.label}
                title={row.label}
                items={row.items}
                onSelect={handleSelect}
              />
            ))}
          </div>
        </>
      )}

      {selectedItem && <Modal item={selectedItem} onClose={handleCloseModal} />}
    </div>
  );
}
