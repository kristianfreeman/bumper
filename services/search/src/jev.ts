import { DECADES, GENRES, type Genre, type Intent } from "./intent";

/// Jev (TypeSafe AI's "System One" model) answers a fixed set of typed
/// questions about the request, all in one call: which kind of request it
/// is, which genre / decade / length / … it asks for. Answers come with
/// probabilities; anything below CONFIDENT is ignored (left unset).
export const ENDPOINT = "https://api.typesafe.ai/v1/systemone";
export const CONFIDENT = 0.55;

type Criteria = Record<string, string>;
type Question = { type: "choice"; instructions: string; criteria: Criteria } | { type: "noul"; instructions: string };

export function questions(): Record<string, Question> {
  const decades: Criteria = { none: "No particular era or decade" };
  for (const d of DECADES) decades[`d${d}`] = `The ${d}s (${d}–${d + 9})`;
  return {
    kind: {
      type: "choice",
      instructions: "Is the viewer naming a specific film, show or person to find, or describing what kind of thing they want to watch?",
      criteria: { title: "Names a specific film, show, franchise or person", browse: "Describes a mood, genre, era, length or kind of thing" },
    },
    media: {
      type: "choice",
      instructions: "Does the request ask for films or for TV shows?",
      criteria: { any: "Doesn't say, or either", movie: "A film / movie", series: "A TV show, series or episodes" },
    },
    genre: {
      type: "choice",
      instructions: "Which genre or mood does the request ask for?",
      criteria: { none: "No genre or mood mentioned", ...GENRES },
    },
    decade: { type: "choice", instructions: "Which era does the request ask for?", criteria: decades },
    length: {
      type: "choice",
      instructions: "How long should it be?",
      criteria: {
        any: "Length not mentioned",
        under_60: "Short: under an hour, quick, an episode",
        under_90: "Not too long: under about 90 minutes",
        under_120: "Under two hours",
      },
    },
    watched: {
      type: "choice",
      instructions: "Has the viewer seen it before?",
      criteria: { any: "Not mentioned", unwatched: "Something new to them, not seen yet", watched: "Something seen before, a rewatch, a favourite" },
    },
    added: {
      type: "choice",
      instructions: "Does the request ask for things recently added to the library?",
      criteria: { any: "Not mentioned", week: "New this week, just added", month: "Added recently, this month", year: "Added this year" },
    },
    acclaimed: { type: "noul", instructions: "Does the request ask for highly rated, acclaimed or the best?" },
  };
}

type ChoiceAnswer = { type: "choice"; choice: string; confidence: number; probabilities?: Record<string, number> };
type NoulAnswer = { type: "noul"; noul: number };
export type Answers = Record<string, ChoiceAnswer | NoulAnswer | undefined>;

function chosen(a: ChoiceAnswer | NoulAnswer | undefined, unset: string): string | undefined {
  if (!a || a.type !== "choice") return undefined;
  const p = a.probabilities?.[a.choice] ?? a.confidence;
  return p >= CONFIDENT && a.choice !== unset ? a.choice : undefined;
}

/// Jev's answers → the app's filter.
export function toIntent(answers: Answers): Intent {
  const intent: Intent = {
    v: 1,
    kind: chosen(answers.kind, "") === "title" ? "title" : "browse",
    media: (chosen(answers.media, "any") as Intent["media"] | undefined) ?? "any",
    watched: (chosen(answers.watched, "any") as Intent["watched"] | undefined) ?? "any",
    added: (chosen(answers.added, "any") as Intent["added"] | undefined) ?? "any",
  };
  const genre = chosen(answers.genre, "none");
  if (genre && genre in GENRES) intent.genre = genre as Genre;
  const decade = chosen(answers.decade, "none");
  if (decade) intent.decade = Number(decade.slice(1));
  const length = chosen(answers.length, "any");
  if (length) intent.maxMinutes = Number(length.split("_")[1]);
  const acclaimed = answers.acclaimed;
  if (acclaimed?.type === "noul" && acclaimed.noul >= CONFIDENT) intent.minRating = 7.5;
  return intent;
}

export async function ask(query: string, apiKey: string, fetcher: typeof fetch = fetch): Promise<Answers> {
  const response = await fetcher(ENDPOINT, {
    method: "POST",
    headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({ model: "jev-latest", state: query, questions: questions() }),
  });
  if (!response.ok) throw new Error(`Jev ${response.status}`);
  const body = (await response.json()) as { answers?: Answers };
  return body.answers ?? {};
}

/// Local development / UI tests: plausible answers without calling Jev.
export function stubAnswers(tokens: string[]): Answers {
  const has = (...w: string[]) => w.some((x) => tokens.includes(x));
  const c = (choice: string): ChoiceAnswer => ({ type: "choice", choice, confidence: 0.9 });
  const genre = has("funny", "comedy", "comedies", "laugh") ? "comedy" : has("scary", "horror") ? "horror" : has("space", "scifi", "sci") ? "science_fiction" : "none";
  const decade = tokens.find((t) => /^(19|20)?[0-9]0s$/.test(t));
  const year = decade ? (decade.length === 3 ? (Number(decade[0]) >= 3 ? 1900 : 2000) + Number(decade[0]) * 10 : Number(decade.slice(0, 4))) : undefined;
  return {
    kind: c(genre === "none" && !year && !has("new", "unwatched", "short") ? "title" : "browse"),
    media: c(has("show", "shows", "series", "episode", "episodes") ? "series" : has("film", "films", "movie", "movies") ? "movie" : "any"),
    genre: c(genre),
    decade: c(year ? `d${year}` : "none"),
    length: c(has("short", "quick") ? "under_90" : "any"),
    watched: c(has("unwatched", "new", "haven't", "havent") ? "unwatched" : "any"),
    added: c(has("week") ? "week" : "any"),
    acclaimed: { type: "noul", noul: has("best", "acclaimed", "good") ? 0.9 : 0.1 },
  };
}
