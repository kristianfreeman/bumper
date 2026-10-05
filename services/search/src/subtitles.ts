import { ENDPOINT as JEV_ENDPOINT } from "./jev";

/// Which subtitle fits this file? The app gets the candidates from the
/// person's own Jellyfin server (its subtitle providers, e.g. the
/// OpenSubtitles plugin, on the server owner's account); this only judges
/// them, with Jev, so the Jev key stays here. Judgements are cached in KV.

export interface SubtitleEnv {
  INTENTS: KVNamespace;
  TYPESAFE_API_KEY?: string;
  JEV_MODE?: string;
}

/// What the app knows about the file it's playing.
export interface FileInfo {
  title: string;
  year?: number;
  season?: number;
  episode?: number;
  fileName?: string;                     // The.Dark.Knight.Rises.2012.1080p.BluRay.x264-SPARKS.mkv
  fps?: number;
  durationSeconds?: number;
}

/// One subtitle the server found.
export interface Candidate {
  id: string;
  name: string;                          // usually the release it was made for
  provider?: string;
  fps?: number;
  downloads?: number;
  hearingImpaired?: boolean;
  machineTranslated?: boolean;
  hashMatch?: boolean;                   // the provider matched the file's hash
}

export interface Ranked { id: string; confidence: number; reasons: string[] }

export const LIMITS = { candidates: 60, text: 240 };
const YEAR = 60 * 60 * 24 * 365;

export async function rankRequest(file: FileInfo, raw: Candidate[], env: SubtitleEnv, fetcher: typeof fetch = fetch): Promise<{ results: Ranked[]; source: string }> {
  const candidates = raw.slice(0, LIMITS.candidates).map((c) => ({ ...c, id: String(c.id).slice(0, LIMITS.text), name: String(c.name ?? "").slice(0, LIMITS.text) }));
  const key = `s2:rank:${await digest(JSON.stringify([file.fileName, file.fps, file.durationSeconds, file.title, file.season, file.episode, candidates.map((c) => [c.id, c.name, c.fps])]))}`;
  const cached = await env.INTENTS.get<Ranked[]>(key, "json");
  if (cached) return { results: cached, source: "cache" };
  const fit = await jevFit(file, candidates, env, fetcher).catch(() => null);
  const results = rank(file, candidates, fit);
  // Only Jev's judgements are worth keeping; the app can redo the heuristic itself.
  if (fit) await env.INTENTS.put(key, JSON.stringify(results), { expirationTtl: YEAR });
  return { results, source: fit ? "jev" : "heuristic" };
}

/// Jev's probabilities (by candidate id) that each was made for this file.
async function jevFit(file: FileInfo, cands: Candidate[], env: SubtitleEnv, fetcher: typeof fetch): Promise<Record<string, number> | null> {
  if (env.JEV_MODE === "stub" || !env.TYPESAFE_API_KEY || cands.length < 2) return null;
  const criteria: Record<string, string> = {};
  cands.forEach((c, i) => { criteria[`c${i}`] = describe(c); });
  const state = [
    `Video: ${file.title}${file.year ? ` (${file.year})` : ""}${file.season != null ? ` season ${file.season} episode ${file.episode}` : ""}.`,
    file.fileName ? `File name: ${file.fileName}.` : "",
    file.fps ? `Frame rate: ${file.fps.toFixed(3)} fps.` : "",
    file.durationSeconds ? `Running time: ${Math.round(file.durationSeconds / 60)} minutes.` : "",
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
  for (const [k, v] of Object.entries(probabilities)) {
    const c = cands[Number(k.replace(/^c/, ""))];
    if (c) out[c.id] = v;
  }
  return out;
}

function describe(c: Candidate): string {
  return [
    c.name || "untitled",
    c.fps ? `${c.fps} fps` : null,
    c.hearingImpaired ? "hearing impaired (SDH)" : null,
    c.machineTranslated ? "machine translated" : null,
    c.downloads != null ? `${c.downloads} downloads` : null,
  ].filter(Boolean).join("; ");
}

/// Jev's judgement (when there is one), adjusted by what's certain: a hash
/// match is the same file; a different frame rate won't be in sync. The app
/// has the same heuristic for when this service is unreachable.
export function rank(file: FileInfo, cands: Candidate[], fit: Record<string, number> | null): Ranked[] {
  const group = file.fileName?.replace(/\.(mkv|mp4|avi|m4v|ts)$/i, "").split(/[-.\s]/).pop()?.toLowerCase();
  const maxDownloads = Math.max(1, ...cands.map((c) => c.downloads ?? 0));
  return cands.map((c) => {
    const reasons: string[] = [];
    let score = fit ? fit[c.id] ?? 0.01 : 0.15 + 0.35 * Math.log10(1 + (c.downloads ?? 0)) / Math.log10(1 + maxDownloads);
    if (group && group.length > 2 && c.name.toLowerCase().includes(group)) {
      reasons.push(`Same release group (${group.toUpperCase()})`);
      if (!fit) score += 0.3;
    }
    if (file.fps && c.fps) {
      if (Math.abs(file.fps - c.fps) < 0.01) reasons.push("Frame rate matches");
      else { reasons.push(`Made for ${c.fps} fps`); score *= 0.35; }
    }
    if (c.machineTranslated) { reasons.push("Machine translated"); score *= 0.5; }
    if (c.hashMatch) { reasons.unshift("Made for this exact file"); score = Math.max(score, 0.97); }
    else score = Math.min(score, fit ? 0.96 : 0.85);
    return { id: c.id, confidence: Math.round(score * 100) / 100, reasons, downloads: c.downloads ?? 0 };
  })
    .sort((a, b) => b.confidence - a.confidence || b.downloads - a.downloads)
    .map(({ downloads: _, ...r }) => r);
}

async function digest(s: string): Promise<string> {
  const bytes = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s)));
  return [...bytes.slice(0, 12)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

