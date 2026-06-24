import { useState, useEffect } from "react";
import "./Hero.css";

export default function Hero({ items, onSelect }) {
  const [current, setCurrent] = useState(0);

  useEffect(() => {
    if (items.length <= 1) return;
    const timer = setInterval(() => {
      setCurrent((c) => (c + 1) % items.length);
    }, 7000);
    return () => clearInterval(timer);
  }, [items.length]);

  if (!items.length) return <div className="hero hero--empty" />;

  const item = items[current];

  return (
    <div className="hero">
      <div
        className="hero__backdrop"
        style={{ backgroundImage: `url(${item.backdrop})` }}
      />
      <div className="hero__overlay" />

      <div className="hero__content">
        <div className="hero__badge">{item.type === "show" ? "SERIES" : "FILM"}</div>
        <h1 className="hero__title">{item.title}</h1>
        <div className="hero__meta">
          <span className="hero__rating">★ {item.rating}</span>
          <span className="hero__year">{item.year}</span>
          {item.type === "show" ? (
            <span>{item.seasons} Seasons</span>
          ) : (
            <span>{item.duration}</span>
          )}
          <span className="hero__genre">{item.genre[0]}</span>
        </div>
        <p className="hero__description">{item.description}</p>
        <div className="hero__actions">
          <button className="hero__btn hero__btn--play" onClick={() => onSelect(item)}>
            <PlayIcon /> Play
          </button>
          <button className="hero__btn hero__btn--info" onClick={() => onSelect(item)}>
            <InfoIcon /> More Info
          </button>
        </div>
      </div>

      {items.length > 1 && (
        <div className="hero__indicators">
          {items.map((_, i) => (
            <button
              key={i}
              className={`hero__dot ${i === current ? "hero__dot--active" : ""}`}
              onClick={() => setCurrent(i)}
              aria-label={`Slide ${i + 1}`}
            />
          ))}
        </div>
      )}
    </div>
  );
}

function PlayIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor">
      <polygon points="5 3 19 12 5 21 5 3" />
    </svg>
  );
}

function InfoIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
      <circle cx="12" cy="12" r="10" />
      <line x1="12" y1="8" x2="12" y2="8" strokeLinecap="round" strokeWidth="3" />
      <line x1="12" y1="12" x2="12" y2="16" />
    </svg>
  );
}
