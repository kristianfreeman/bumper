import { describe, expect, it, vi } from "vitest";
import worker, { type Env } from "../src/index";
import { normalize } from "../src/normalize";
import { toIntent, questions, type Answers } from "../src/jev";

function memoryKV(): KVNamespace {
  const store = new Map<string, string>();
  return {
    get: async (k: string, type?: string) => (store.has(k) ? (type === "json" ? JSON.parse(store.get(k)!) : store.get(k)) : null),
    put: async (k: string, v: string) => void store.set(k, v),
  } as unknown as KVNamespace;
}

const post = (query: string) => new Request("https://search.local/v1/interpret", { method: "POST", body: JSON.stringify({ query }) });

describe("normalize", () => {
  it("drops filler and ignores word order", () => {
    expect(normalize("I want to watch a funny 1980s comedy").key).toBe("1980s comedy funny");
    expect(normalize("Comedy — funny, 1980s!").key).toBe("1980s comedy funny");
    expect(normalize("not too long").tokens).toEqual(["long", "not", "too"]);   // negations survive
    expect(normalize("a show I haven't seen").tokens).toEqual(["haven't", "seen", "show"]);
  });
});

describe("Jev answers → filter", () => {
  it("keeps confident answers and drops the rest", () => {
    const answers: Answers = {
      kind: { type: "choice", choice: "browse", confidence: 0.98 },
      genre: { type: "choice", choice: "comedy", confidence: 0.91 },
      decade: { type: "choice", choice: "d1980", confidence: 0.83 },
      length: { type: "choice", choice: "under_90", confidence: 0.4 },          // unsure: ignored
      watched: { type: "choice", choice: "unwatched", confidence: 0.7 },
      added: { type: "choice", choice: "any", confidence: 0.9 },
      acclaimed: { type: "noul", noul: 0.12 },
    };
    expect(toIntent(answers)).toEqual({ v: 1, kind: "browse", media: "any", genre: "comedy", decade: 1980, watched: "unwatched", added: "any" });
    for (const q of Object.values(questions())) if (q.type === "choice") expect(Object.keys(q.criteria).length).toBeLessThanOrEqual(255);
  });
});

describe("worker", () => {
  it("asks Jev once, then answers from the cache — for any word order", async () => {
    const env: Env = { INTENTS: memoryKV(), SEARCH_ENABLED: "true", TYPESAFE_API_KEY: "test" };
    const jev = vi.fn(async () => new Response(JSON.stringify({ answers: {
      kind: { type: "choice", choice: "browse", confidence: 0.95 },
      genre: { type: "choice", choice: "comedy", confidence: 0.9 },
      decade: { type: "choice", choice: "d1980", confidence: 0.9 },
    } })));
    vi.stubGlobal("fetch", jev);
    const first = await (await worker.fetch(post("a funny 1980s comedy"), env)).json() as { source: string; genre: string; decade: number };
    expect(first).toMatchObject({ source: "jev", genre: "comedy", decade: 1980 });
    const second = await (await worker.fetch(post("comedy, funny, 1980s"), env)).json() as { source: string };
    expect(second.source).toBe("cache");
    expect(jev).toHaveBeenCalledTimes(1);
    vi.unstubAllGlobals();
  });

  it("health check and flag: 204 when on, 503 when off; 502 when Jev fails", async () => {
    const head = new Request("https://search.local/v1/interpret", { method: "HEAD" });
    expect((await worker.fetch(head, { INTENTS: memoryKV(), SEARCH_ENABLED: "true" })).status).toBe(204);
    expect((await worker.fetch(head, { INTENTS: memoryKV(), SEARCH_ENABLED: "false" })).status).toBe(503);
    vi.stubGlobal("fetch", vi.fn(async () => new Response("down", { status: 500 })));
    expect((await worker.fetch(post("scary"), { INTENTS: memoryKV(), SEARCH_ENABLED: "true", TYPESAFE_API_KEY: "k" })).status).toBe(502);
    vi.unstubAllGlobals();
  });
});
