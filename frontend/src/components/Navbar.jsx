import { useState, useEffect } from "react";
import "./Navbar.css";

export default function Navbar({ onSearch, searchQuery }) {
  const [scrolled, setScrolled] = useState(false);
  const [searchOpen, setSearchOpen] = useState(false);
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 50);
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  useEffect(() => {
    if (!mobileMenuOpen) return;
    const closeMenu = () => setMobileMenuOpen(false);
    window.addEventListener("click", closeMenu);
    return () => window.removeEventListener("click", closeMenu);
  }, [mobileMenuOpen]);

  function handleSearchChange(e) {
    onSearch(e.target.value);
  }

  function toggleSearch() {
    setSearchOpen((v) => !v);
    if (searchOpen) onSearch("");
  }

  function toggleMobileMenu(e) {
    e.stopPropagation();
    setMobileMenuOpen((v) => !v);
  }

  return (
    <nav className={`navbar ${scrolled ? "navbar--scrolled" : ""}`}>
      <div className="navbar__left">
        <div className="navbar__logo">
          <span className="navbar__logo-star">★</span>
          <span className="navbar__logo-text">STARFLIX V2</span>
        </div>
        <ul className="navbar__links">
          <li className="navbar__link navbar__link--active">Home</li>
          <li className="navbar__link">Movies</li>
          <li className="navbar__link">TV Shows</li>
          <li className="navbar__link">New &amp; Popular</li>
          <li className="navbar__link">My List</li>
        </ul>
        <div className="navbar__mobile-nav">
          <button className="navbar__mobile-btn" onClick={toggleMobileMenu} aria-label="Browse Categories">
            Browse <span className={`navbar__mobile-arrow ${mobileMenuOpen ? "navbar__mobile-arrow--open" : ""}`}>▼</span>
          </button>
          {mobileMenuOpen && (
            <ul className="navbar__mobile-menu">
              <li className="navbar__mobile-link navbar__mobile-link--active">Home</li>
              <li className="navbar__mobile-link">Movies</li>
              <li className="navbar__mobile-link">TV Shows</li>
              <li className="navbar__mobile-link">New &amp; Popular</li>
              <li className="navbar__mobile-link">My List</li>
            </ul>
          )}
        </div>
      </div>
      <div className="navbar__right">
        <div className={`navbar__search ${searchOpen ? "navbar__search--open" : ""}`}>
          <button className="navbar__icon-btn" onClick={toggleSearch} aria-label="Search">
            <SearchIcon />
          </button>
          {searchOpen && (
            <input
              className="navbar__search-input"
              type="text"
              placeholder="Titles, genres..."
              value={searchQuery}
              onChange={handleSearchChange}
              autoFocus
            />
          )}
        </div>
        <button className="navbar__icon-btn" aria-label="Notifications">
          <BellIcon />
        </button>
        <div className="navbar__avatar">A</div>
      </div>
    </nav>
  );
}

function SearchIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="11" cy="11" r="8" />
      <line x1="21" y1="21" x2="16.65" y2="16.65" />
    </svg>
  );
}

function BellIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
      <path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9" />
      <path d="M13.73 21a2 2 0 0 1-3.46 0" />
    </svg>
  );
}
