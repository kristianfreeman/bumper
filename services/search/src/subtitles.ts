import { ENDPOINT as JEV_ENDPOINT } from "./jev";

/// Subtitles for a video: OpenSubtitles finds the candidates, Jev judges which
/// was made for *this* file (same release, cut and frame rate), and Workers KV
/// keeps everything — searches for a week, rankings and the files themselves
/// for good — so the same request never costs an OpenSubtitles download twice.

export interface SubtitleEnv {
  INTENTS: KVNamespace;
  TYPESAFE_API_KEY?: string;
  JEV_MODE?: string;
  SUBTITLES_MODE?: string;               // "stub": canned candidates (tests, local dev)
  OPENSUBTITLES_API_KEY?: string;
  OPENSUBTITLES_USERNAME?: string;
  OPENSUBTITLES_PASSWORD?: string;
}

/// What the app knows about the file it's playing.
export interface SearchRequest {
  imdbId?: string;
  tmdbId?: string;
  title: string;
  year?: number;
  season?: number;
  episode?: number;
  languages: string[];                   // ISO 639-1: ["en"]
  fileName?: string;                     // The.Dark.Knight.Rises.2012.1080p.BluRay.x264-SPARKS.mkv
  fps?: number;
  durationSeconds?: number;
  moviehash?: string;                    // OpenSubtitles hash (16 hex), when the app could compute it
}

export interface Candidate {
  fileId: number;
  language: string;
  release: string;
  fileName?: string;
  fps?: number;
  downloads: number;
  hearingImpaired: boolean;
  machineTranslated: boolean;
  trusted: boolean;
  hashMatch: boolean;
  uploader?: string;
}

export interface Ranked extends Candidate {
  /// 0…1: how sure we are this one fits the file.
  confidence: number;
  reasons: string[];
}

const OS = "https://api.opensubtitles.com/api/v1";
const UA = "Bumper v0.1";
const WEEK = 60 * 60 * 24 * 7;
const YEAR = 60 * 60 * 24 * 365;
const MAX_FOR_JEV = 40;

export async function search(req: SearchRequest, env: SubtitleEnv, fetcher: typeof fetch = fetch): Promise<{ results: Ranked[]; source: string }> {
  const langs = [...new Set(req.languages.map((l) => l.toLowerCase().slice(0, 2)))].sort();
  const what = req.imdbId ? `imdb${req.imdbId.replace(/^tt/, "")}` : req.tmdbId ? `tmdb${req.tmdbId}` : `q${req.title.toLowerCase()}-${req.year ?? ""}`;
  const searchKey = `s1:search:${what}:${req.season ?? ""}:${req.episode ?? ""}:${langs.join(",")}:${req.moviehash ?? ""}`;

  let source = "cache";
  let candidates = await env.INTENTS.get<Candidate[]>(searchKey, "json");
  if (!candidates) {
    candidates = env.SUBTITLES_MODE === "stub" ? stubCandidates(req) : await openSubtitlesSearch(req, langs, env, fetcher);
    source = env.SUBTITLES_MODE === "stub" ? "stub" : "opensubtitles";
    await env.INTENTS.put(searchKey, JSON.stringify(candidates), { expirationTtl: WEEK });
  }
  if (candidates.length === 0) return { results: [], source };

  // The judgement depends on the file too: cache it per file + candidate set.
  const top = [...candidates].sort((a, b) => Number(b.hashMatch) - Number(a.hashMatch) || b.downloads - a.downloads).slice(0, MAX_FOR_JEV);
  const rankKey = `s1:rank:${await digest([req.fileName ?? "", req.fps ?? "", req.durationSeconds ?? "", ...top.map((c) => c.fileId)].join("|"))}`;
  const cachedRank = await env.INTENTS.get<Ranked[]>(rankKey, "json");
  if (cachedRank) return { results: cachedRank, source };

  const fit = await jevFit(req, top, env, fetcher).catch(() => null);
  const ranked = rank(req, top, fit);
  await env.INTENTS.put(rankKey, JSON.stringify(ranked), { expirationTtl: YEAR });
  return { results: ranked, source: fit ? source : `${source}+heuristic` };
}

/// Jev's probabilities (by fileId) that each candidate was made for this file.
async function jevFit(req: SearchRequest, cands: Candidate[], env: SubtitleEnv, fetcher: typeof fetch): Promise<Record<string, number> | null> {
  if (env.JEV_MODE === "stub" || !env.TYPESAFE_API_KEY || cands.length < 2) return null;
  const criteria: Record<string, string> = {};
  for (const c of cands) criteria[`f${c.fileId}`] = describe(c);
  const state = [
    `Video: ${req.title}${req.year ? ` (${req.year})` : ""}${req.season != null ? ` season ${req.season} episode ${req.episode}` : ""}.`,
    req.fileName ? `File name: ${req.fileName}.` : "",
    req.fps ? `Frame rate: ${req.fps.toFixed(3)} fps.` : "",
    req.durationSeconds ? `Running time: ${Math.round(req.durationSeconds / 60)} minutes.` : "",
  ].filter(Boolean).join(" ");
  const response = await fetcher(JEV_ENDPOINT, {
    method: "POST",
    headers: { Authorization: `Bearer ${env.TYPESAFE_API_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model: "jev-latest",
      state,
      questions: {
        fit: {
          type: "choice",
          instructions: "Which subtitle file was made for exactly this video file: the same release (group, source, cut) and frame rate, so it will be in sync?",
          criteria,
        },
      },
    }),
  });
  if (!response.ok) throw new Error(`Jev ${response.status}`);
  const body = (await response.json()) as { answers?: { fit?: { probabilities?: Record<string, number>; choice?: string; confidence?: number } } };
  const fit = body.answers?.fit;
  if (!fit) return null;
  const probabilities = fit.probabilities ?? (fit.choice ? { [fit.choice]: fit.confidence ?? 1 } : {});
  const out: Record<string, number> = {};
  for (const [k, v] of Object.entries(probabilities)) out[k.replace(/^f/, "")] = v;
  return out;
}

function describe(c: Candidate): string {
  return [
    c.release || c.fileName || "untitled",
    c.fps ? `${c.fps} fps` : null,
    c.hearingImpaired ? "hearing impaired (SDH)" : null,
    c.machineTranslated ? "machine translated" : null,
    c.trusted ? "trusted uploader" : null,
    `${c.downloads} downloads`,
  ].filter(Boolean).join("; ");
}

/// Jev's judgement (when there is one), adjusted by what's certain: a file
/// hash match is the same file; a different frame rate won't be in sync.
export function rank(req: SearchRequest, cands: Candidate[], fit: Record<string, number> | null): Ranked[] {
  const groupOf = (s?: string) => s?.replace(/\.(mkv|mp4|avi|m4v|srt)$/i, "").split(/[-.\s]/).pop()?.toLowerCase();
  const group = groupOf(req.fileName);
  const maxDownloads = Math.max(1, ...cands.map((c) => c.downloads));
  const scored = cands.map((c) => {
    const reasons: string[] = [];
    // Without Jev: popularity, and the release group appearing in its name.
    let score = fit ? fit[String(c.fileId)] ?? 0.01 : 0.15 + 0.35 * Math.log10(1 + c.downloads) / Math.log10(1 + maxDownloads);
    if (group && group.length > 2 && (c.release + " " + (c.fileName ?? "")).toLowerCase().includes(group)) {
      reasons.push(`Same release group (${group.toUpperCase()})`);
      if (!fit) score += 0.3;
    }
    if (req.fps && c.fps) {
      if (Math.abs(req.fps - c.fps) < 0.01) reasons.push("Frame rate matches");
      else { reasons.push(`Made for ${c.fps} fps`); score *= 0.35; }
    }
    if (c.machineTranslated) { reasons.push("Machine translated"); score *= 0.5; }
    if (c.trusted) reasons.push("Trusted uploader");
    if (c.hashMatch) { reasons.unshift("Made for this exact file"); score = Math.max(score, 0.97); }
    return { ...c, confidence: score, reasons };
  });
  // Jev's probabilities are already shares of the whole; a heuristic score
  // never claims to be sure. Only a hash match is.
  for (const s of scored) {
    if (!s.hashMatch) s.confidence = Math.min(s.confidence, fit ? 0.96 : 0.85);
    s.confidence = Math.round(s.confidence * 100) / 100;
  }
  return scored.sort((a, b) => b.confidence - a.confidence || b.downloads - a.downloads);
}

async function openSubtitlesSearch(req: SearchRequest, langs: string[], env: SubtitleEnv, fetcher: typeof fetch): Promise<Candidate[]> {
  if (!env.OPENSUBTITLES_API_KEY) throw new Error("no OpenSubtitles key");
  const q = new URLSearchParams({ languages: langs.join(","), order_by: "download_count" });
  if (req.imdbId) q.set(req.season != null ? "parent_imdb_id" : "imdb_id", req.imdbId.replace(/^tt/, ""));
  else if (req.tmdbId) q.set(req.season != null ? "parent_tmdb_id" : "tmdb_id", req.tmdbId);
  else { q.set("query", req.title); if (req.year) q.set("year", String(req.year)); }
  if (req.season != null) q.set("season_number", String(req.season));
  if (req.episode != null) q.set("episode_number", String(req.episode));
  if (req.moviehash) q.set("moviehash", req.moviehash);
  const response = await fetcher(`${OS}/subtitles?${q}`, { headers: { "Api-Key": env.OPENSUBTITLES_API_KEY, "User-Agent": UA } });
  if (!response.ok) throw new Error(`OpenSubtitles ${response.status}`);
  const body = (await response.json()) as { data?: Array<{ attributes: OSAttributes }> };
  return (body.data ?? []).flatMap(({ attributes: a }) => a.files.slice(0, 1).map((f) => ({
    fileId: f.file_id,
    fileName: f.file_name,
    language: a.language,
    release: a.release ?? "",
    fps: a.fps || undefined,
    downloads: a.download_count ?? 0,
    hearingImpaired: !!a.hearing_impaired,
    machineTranslated: !!(a.machine_translated || a.ai_translated),
    trusted: !!a.from_trusted,
    hashMatch: !!a.moviehash_match,
    uploader: a.uploader?.name,
  })));
}

interface OSAttributes {
  language: string; release?: string; fps?: number; download_count?: number; hearing_impaired?: boolean;
  machine_translated?: boolean; ai_translated?: boolean; from_trusted?: boolean; moviehash_match?: boolean;
  uploader?: { name?: string }; files: Array<{ file_id: number; file_name?: string }>;
}

/// The subtitle file (SRT text), from KV after the first time.
export async function download(fileId: number, env: SubtitleEnv, fetcher: typeof fetch = fetch): Promise<{ text: string; source: string }> {
  const key = `s1:file:${fileId}`;
  const cached = await env.INTENTS.get(key);
  if (cached) return { text: cached, source: "cache" };
  let text: string;
  if (env.SUBTITLES_MODE === "stub") {
    text = stubFile(fileId);
  } else {
    if (!env.OPENSUBTITLES_API_KEY) throw new Error("no OpenSubtitles key");
    const headers: Record<string, string> = { "Api-Key": env.OPENSUBTITLES_API_KEY, "User-Agent": UA, "Content-Type": "application/json", Accept: "application/json" };
    const token = await login(env, fetcher);
    if (token) headers.Authorization = `Bearer ${token}`;
    const link = await fetcher(`${OS}/download`, { method: "POST", headers, body: JSON.stringify({ file_id: fileId, sub_format: "srt" }) });
    if (!link.ok) throw new Error(`OpenSubtitles download ${link.status}`);
    const { link: url } = (await link.json()) as { link?: string };
    if (!url) throw new Error("no download link");
    const file = await fetcher(url);
    if (!file.ok) throw new Error(`subtitle file ${file.status}`);
    text = await file.text();
  }
  await env.INTENTS.put(key, text, { expirationTtl: YEAR });
  return { text, source: env.SUBTITLES_MODE === "stub" ? "stub" : "opensubtitles" };
}

/// A user token raises OpenSubtitles' download limit; kept for 23 hours.
async function login(env: SubtitleEnv, fetcher: typeof fetch): Promise<string | null> {
  if (!env.OPENSUBTITLES_USERNAME || !env.OPENSUBTITLES_PASSWORD || !env.OPENSUBTITLES_API_KEY) return null;
  const cached = await env.INTENTS.get("s1:os-token");
  if (cached) return cached;
  const response = await fetcher(`${OS}/login`, {
    method: "POST",
    headers: { "Api-Key": env.OPENSUBTITLES_API_KEY, "User-Agent": UA, "Content-Type": "application/json", Accept: "application/json" },
    body: JSON.stringify({ username: env.OPENSUBTITLES_USERNAME, password: env.OPENSUBTITLES_PASSWORD }),
  });
  if (!response.ok) return null;
  const { token } = (await response.json()) as { token?: string };
  if (token) await env.INTENTS.put("s1:os-token", token, { expirationTtl: 60 * 60 * 23 });
  return token ?? null;
}

async function digest(s: string): Promise<string> {
  const bytes = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s)));
  return [...bytes.slice(0, 12)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function stubCandidates(req: SearchRequest): Candidate[] {
  const lang = req.languages[0] ?? "en";
  const group = req.fileName?.replace(/\.\w+$/, "").split(/[-.]/).pop() ?? "GROUP";
  return [
    { fileId: 1001, language: lang, release: `${req.title}.${req.year ?? ""}.1080p.BluRay.x264-${group}`, fps: req.fps, downloads: 4200, hearingImpaired: false, machineTranslated: false, trusted: true, hashMatch: !!req.moviehash },
    { fileId: 1002, language: lang, release: `${req.title}.${req.year ?? ""}.720p.WEB-DL.DD5.1.H264-OTHER`, fps: 25, downloads: 9100, hearingImpaired: false, machineTranslated: false, trusted: false, hashMatch: false },
    { fileId: 1003, language: lang, release: `${req.title} (SDH)`, fps: req.fps, downloads: 1300, hearingImpaired: true, machineTranslated: false, trusted: false, hashMatch: false },
  ];
}

function stubFile(fileId: number): string {
  return `1\n00:00:01,000 --> 00:00:04,000\nBumper subtitle ${fileId}: line one.\n\n2\n00:00:05,000 --> 00:00:08,000\nAnd line two.\n`;
}
