import { useRef } from "react";
import MovieCard from "./MovieCard";
import "./ContentRow.css";

export default function ContentRow({ title, items, onSelect }) {
  const rowRef = useRef(null);

  function scroll(dir) {
    const el = rowRef.current;
    if (!el) return;
    const amount = el.clientWidth * 0.75;
    el.scrollBy({ left: dir === "left" ? -amount : amount, behavior: "smooth" });
  }

  if (!items || items.length === 0) return null;

  return (
    <section className="content-row">
      <h2 className="content-row__title">{title}</h2>
      <div className="content-row__wrapper">
        <button
          className="content-row__arrow content-row__arrow--left"
          onClick={() => scroll("left")}
          aria-label="Scroll left"
        >
          <ChevronLeft />
        </button>
        <div className="content-row__track" ref={rowRef}>
          {items.map((item) => (
            <MovieCard key={`${item.type}-${item.id}`} item={item} onClick={onSelect} />
          ))}
        </div>
        <button
          className="content-row__arrow content-row__arrow--right"
          onClick={() => scroll("right")}
          aria-label="Scroll right"
        >
          <ChevronRight />
        </button>
      </div>
    </section>
  );
}

function ChevronLeft() {
  return (
    <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round">
      <polyline points="15 18 9 12 15 6" />
    </svg>
  );
}

function ChevronRight() {
  return (
    <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round">
      <polyline points="9 18 15 12 9 6" />
    </svg>
  );
}
