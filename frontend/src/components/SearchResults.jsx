import MovieCard from "./MovieCard";
import "./SearchResults.css";

export default function SearchResults({ query, results, loading, onSelect }) {
  if (loading) {
    return (
      <div className="search-results">
        <div className="search-results__loading">
          <div className="spinner" />
        </div>
      </div>
    );
  }

  return (
    <div className="search-results">
      <h2 className="search-results__heading">
        {results.length > 0
          ? `Results for "${query}"`
          : `No results for "${query}"`}
      </h2>
      {results.length === 0 && (
        <p className="search-results__empty">
          Try different keywords or browse categories below.
        </p>
      )}
      <div className="search-results__grid">
        {results.map((item) => (
          <MovieCard key={`${item.type}-${item.id}`} item={item} onClick={onSelect} />
        ))}
      </div>
    </div>
  );
}
