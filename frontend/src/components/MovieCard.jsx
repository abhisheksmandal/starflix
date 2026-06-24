import { useState } from "react";
import "./MovieCard.css";

export default function MovieCard({ item, onClick }) {
  const [imgError, setImgError] = useState(false);

  return (
    <div className="movie-card" onClick={() => onClick(item)}>
      <div className="movie-card__poster">
        {!imgError ? (
          <img
            src={item.poster}
            alt={item.title}
            loading="lazy"
            onError={() => setImgError(true)}
          />
        ) : (
          <div className="movie-card__fallback">
            <span>{item.title.slice(0, 2).toUpperCase()}</span>
          </div>
        )}
        {item.upcoming && (
          <div className="movie-card__coming-soon">Coming Soon</div>
        )}
        <div className="movie-card__overlay">
          <div className="movie-card__overlay-content">
            {item.upcoming ? (
              <div className="movie-card__release-date">{item.releaseDate}</div>
            ) : (
              <button className="movie-card__play-btn" aria-label="Play">
                <PlayIcon />
              </button>
            )}
            <div className="movie-card__info">
              {item.rating ? (
                <div className="movie-card__rating">★ {item.rating}</div>
              ) : (
                <div className="movie-card__rating movie-card__rating--tba">Rating TBA</div>
              )}
              <div className="movie-card__year">{item.year}</div>
            </div>
            <div className="movie-card__genres">
              {item.genre.slice(0, 2).map((g) => (
                <span key={g} className="movie-card__genre-tag">{g}</span>
              ))}
            </div>
          </div>
        </div>
      </div>
      <div className="movie-card__title">{item.title}</div>
    </div>
  );
}

function PlayIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor">
      <polygon points="5 3 19 12 5 21 5 3" />
    </svg>
  );
}
