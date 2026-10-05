import { normalize } from "./normalize";
import { ask, stubAnswers, toIntent } from "./jev";
import type { Intent, Response } from "./intent";
import { LIMITS, rankRequest, type Candidate, type FileInfo, type SubtitleEnv } from "./subtitles";

export interface Env extends SubtitleEnv {
  INTENTS: KVNamespace;
  SEARCH_ENABLED?: string;
  JEV_MODE?: string;
  TYPESAFE_API_KEY?: string;
  CLIENT_TOKEN?: string;
}

const CACHE_VERSION = "i1";
const TTL = 60 * 60 * 24 * 90;            // 90 days: the questions don't change often

/// POST /v1/interpret {"query": "a funny 80s comedy"} → Response (a filter,
/// or "search for this title"). HEAD /v1/interpret → 204 when enabled
/// (the app checks before relying on it), 503 when not.
export default {
  async fetch(request: Request, env: Env): Promise<globalThis.Response> {
    const url = new URL(request.url);
    if (env.SEARCH_ENABLED !== "true") return new globalThis.Response(null, { status: 503 });
    if (env.CLIENT_TOKEN && request.headers.get("Authorization") !== `Bearer ${env.CLIENT_TOKEN}`) {
      return new globalThis.Response(null, { status: 401 });
    }
    if (url.pathname.startsWith("/v1/subtitles/")) return subtitles(url.pathname, request, env);
    if (url.pathname !== "/v1/interpret") return new globalThis.Response("Not found", { status: 404 });
    // Up only when it can answer: stub mode, or a Jev key to ask with.
    const ready = env.JEV_MODE === "stub" || !!env.TYPESAFE_API_KEY;
    if (request.method === "HEAD") return new globalThis.Response(null, { status: ready ? 204 : 503 });
    if (request.method !== "POST") return new globalThis.Response(null, { status: 405 });

    const body = (await request.json().catch(() => ({}))) as { query?: unknown };
    const query = typeof body.query === "string" ? body.query.trim().slice(0, 300) : "";
    const { tokens, key } = normalize(query);
    if (tokens.length === 0) return json({ error: "empty" }, 400);

    const cacheKey = `${CACHE_VERSION}:${key}`;
    const cached = await env.INTENTS.get<Intent>(cacheKey, "json");
    if (cached) return json({ ...cached, key, source: "cache", query } satisfies Response);

    let intent: Intent;
    let source: Response["source"];
    try {
      if (env.JEV_MODE === "stub") {
        intent = toIntent(stubAnswers(tokens));
        source = "stub";
      } else {
        if (!env.TYPESAFE_API_KEY) return new globalThis.Response(null, { status: 503 });
        intent = toIntent(await ask(query, env.TYPESAFE_API_KEY));
        source = "jev";
      }
    } catch {
      return new globalThis.Response(null, { status: 502 });         // the app falls back
    }
    await env.INTENTS.put(cacheKey, JSON.stringify(intent), { expirationTtl: TTL });
    return json({ ...intent, key, source, query } satisfies Response);
  },
};

/// POST /v1/subtitles/rank {"file": FileInfo, "candidates": [Candidate]} →
/// {"results": [{id, confidence, reasons}], "source"}. HEAD: 204 when Jev
/// can answer (or in stub mode). Only this one fixed question, with capped
/// sizes: the Jev key isn't useful for anything else through here.
async function subtitles(path: string, request: Request, env: Env): Promise<globalThis.Response> {
  if (path !== "/v1/subtitles/rank") return new globalThis.Response("Not found", { status: 404 });
  const ready = env.JEV_MODE === "stub" || !!env.TYPESAFE_API_KEY;
  if (request.method === "HEAD") return new globalThis.Response(null, { status: ready ? 204 : 503 });
  if (request.method !== "POST") return new globalThis.Response(null, { status: 405 });
  const body = (await request.json().catch(() => ({}))) as { file?: FileInfo; candidates?: Candidate[] };
  if (!body.file || typeof body.file.title !== "string" || !Array.isArray(body.candidates) || body.candidates.length === 0) {
    return json({ error: "file and candidates" }, 400);
  }
  if (body.candidates.length > LIMITS.candidates * 2) return json({ error: "too many candidates" }, 413);
  try {
    return json(await rankRequest({ ...body.file, title: body.file.title.slice(0, LIMITS.text), fileName: body.file.fileName?.slice(0, LIMITS.text) }, body.candidates, env));
  } catch (error) {
    return json({ error: String(error) }, 502);
  }
}

function json(value: unknown, status = 200): globalThis.Response {
  return new globalThis.Response(JSON.stringify(value), { status, headers: { "Content-Type": "application/json" } });
}
