/// Words that carry no meaning for a search ("I want to watch something …").
/// Kept on purpose: negations (not, no, without), numbers, decades.
export const FILLER = new Set([
  "a", "an", "the", "some", "something", "anything", "any", "i", "im", "i'm", "me", "my", "we", "us", "our",
  "want", "wanna", "would", "like", "love", "to", "watch", "watching", "see", "find", "please",
  "kind", "kinds", "of", "sort", "type", "maybe", "really", "just", "bit", "little", "that", "this", "is", "it", "its",
  "in", "for", "with", "and", "or", "on", "at", "can", "could", "you", "give", "get", "put", "play", "lets", "let's",
  "feel", "feeling", "mood", "tonight", "now", "um", "uh", "hmm", "so", "be", "do", "something's", "one", "ones",
]);

export interface Normalized {
  /// The meaningful words, deduplicated and sorted: word order doesn't change the key.
  tokens: string[];
  /// The cache key.
  key: string;
}

export function normalize(query: string): Normalized {
  const words = query
    .toLowerCase()
    .replace(/[’']/g, "'")
    .replace(/[^a-z0-9' ]+/g, " ")
    .split(/\s+/)
    .map((w) => w.replace(/^'+|'+$/g, ""))
    .filter((w) => w.length > 0 && !FILLER.has(w));
  const tokens = [...new Set(words)].sort();
  return { tokens, key: tokens.join(" ") };
}
