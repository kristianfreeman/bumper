import { normalize } from "./normalize";
import { ask, stubAnswers, toIntent } from "./jev";
import type { Intent, Response } from "./intent";

export interface Env {
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
    if (url.pathname !== "/v1/interpret") return new globalThis.Response("Not found", { status: 404 });
    if (env.SEARCH_ENABLED !== "true") return new globalThis.Response(null, { status: 503 });
    if (env.CLIENT_TOKEN && request.headers.get("Authorization") !== `Bearer ${env.CLIENT_TOKEN}`) {
      return new globalThis.Response(null, { status: 401 });
    }
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

function json(value: unknown, status = 200): globalThis.Response {
  return new globalThis.Response(JSON.stringify(value), { status, headers: { "Content-Type": "application/json" } });
}
