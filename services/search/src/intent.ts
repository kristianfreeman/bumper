/// What the app gets back: a filter it can apply directly (the same parts as
/// its filter sentence), or "this names a title — search for it".
export interface Intent {
  v: 1;
  kind: "title" | "browse";
  media: "any" | "movie" | "series";
  genre?: Genre;
  decade?: number;
  maxMinutes?: number;
  minRating?: number;
  watched: "any" | "unwatched" | "watched";
  added: "any" | "week" | "month" | "year";
}

export interface Response extends Intent {
  /// The normalized words (the cache key).
  key: string;
  source: "cache" | "jev" | "stub";
  /// For kind "title": what to search for (the request as typed).
  query: string;
}

/// Canonical genres. The app maps them onto the library's own genre names.
export const GENRES = {
  comedy: "Comedy: funny, light-hearted, laughs",
  horror: "Horror: scary, frightening",
  action: "Action: exciting, fights, explosions",
  adventure: "Adventure: quests, journeys, exploration",
  romance: "Romance: love stories, romantic",
  drama: "Drama: serious, emotional, moving",
  mystery: "Mystery: whodunits, detectives, puzzles",
  thriller: "Thriller: tense, suspense, edge of the seat",
  crime: "Crime: heists, gangsters, police",
  science_fiction: "Science fiction: space, the future, technology",
  fantasy: "Fantasy: magic, myths, other worlds",
  animation: "Animation: animated, cartoons, anime",
  documentary: "Documentary: true stories, real life, nature",
  family: "Family: for kids and children, all ages",
  western: "Western: cowboys, the frontier",
  war: "War: battles, soldiers",
  history: "History: historical, period pieces",
  music: "Music: musicals, concerts, bands",
} as const;
export type Genre = keyof typeof GENRES;

export const DECADES = [1950, 1960, 1970, 1980, 1990, 2000, 2010, 2020] as const;
