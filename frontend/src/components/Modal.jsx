import { useEffect } from "react";
import "./Modal.css";

export default function Modal({ item, onClose }) {
  useEffect(() => {
    function handleKey(e) {
      if (e.key === "Escape") onClose();
    }
    document.addEventListener("keydown", handleKey);
    document.body.style.overflow = "hidden";
    return () => {
      document.removeEventListener("keydown", handleKey);
      document.body.style.overflow = "";
    };
  }, [onClose]);

  if (!item) return null;

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <button className="modal__close" onClick={onClose} aria-label="Close">
          <CloseIcon />
        </button>

        <div className="modal__hero">
          <img src={item.backdrop} alt={item.title} className="modal__backdrop" />
          <div className="modal__hero-overlay" />
          <div className="modal__hero-content">
            <h2 className="modal__title">{item.title}</h2>
            <div className="modal__actions">
              {item.upcoming ? (
                <button className="modal__btn modal__btn--remind">
                  <BellIcon /> Remind Me
                </button>
              ) : (
                <button className="modal__btn modal__btn--play">
                  <PlayIcon /> Play
                </button>
              )}
              <button className="modal__btn modal__btn--list">
                <PlusIcon /> My List
              </button>
            </div>
          </div>
        </div>

        <div className="modal__body">
          <div className="modal__left">
            <div className="modal__meta">
              {item.upcoming ? (
                <span className="modal__coming-soon-badge">Coming Soon</span>
              ) : (
                <span className="modal__rating">★ {item.rating}</span>
              )}
              <span className="modal__year">{item.year}</span>
              {item.type === "show" ? (
                <>
                  <span>{item.seasons} Season{item.seasons > 1 ? "s" : ""}</span>
                  <span>{item.episodes} Episodes</span>
                </>
              ) : (
                !item.upcoming && <span>{item.duration}</span>
              )}
              <span className="modal__type-badge">
                {item.type === "show" ? "Series" : "Film"}
              </span>
              {item.phase && (
                <span className="modal__phase-badge">Phase {item.phase}</span>
              )}
            </div>
            <p className="modal__description">{item.description}</p>
          </div>
          <div className="modal__right">
            <div className="modal__detail">
              <span className="modal__detail-label">Genres:</span>
              <span>{item.genre.join(", ")}</span>
            </div>
            {item.upcoming ? (
              <div className="modal__detail">
                <span className="modal__detail-label">Release:</span>
                <span className="modal__rating-value">{item.releaseDate}</span>
              </div>
            ) : (
              <>
                <div className="modal__detail">
                  <span className="modal__detail-label">Duration:</span>
                  <span>{item.duration}</span>
                </div>
                <div className="modal__detail">
                  <span className="modal__detail-label">Rating:</span>
                  <span className="modal__rating-value">★ {item.rating} / 10</span>
                </div>
              </>
            )}
            <div className="modal__detail">
              <span className="modal__detail-label">Phase:</span>
              <span>{item.phase}</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

function CloseIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round">
      <line x1="18" y1="6" x2="6" y2="18" />
      <line x1="6" y1="6" x2="18" y2="18" />
    </svg>
  );
}

function PlayIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor">
      <polygon points="5 3 19 12 5 21 5 3" />
    </svg>
  );
}

function PlusIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round">
      <line x1="12" y1="5" x2="12" y2="19" />
      <line x1="5" y1="12" x2="19" y2="12" />
    </svg>
  );
}

function BellIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round">
      <path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9" />
      <path d="M13.73 21a2 2 0 0 1-3.46 0" />
    </svg>
  );
}
