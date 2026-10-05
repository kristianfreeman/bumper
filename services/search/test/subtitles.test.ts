import { describe, expect, it, vi } from "vitest";
import worker, { type Env } from "../src/index";
import { rank, type Candidate } from "../src/subtitles";

function memoryKV(): KVNamespace {
  const store = new Map<string, string>();
  return {
    get: async (k: string, type?: string) => (store.has(k) ? (type === "json" ? JSON.parse(store.get(k)!) : store.get(k)) : null),
    put: async (k: string, v: string) => void store.set(k, v),
  } as unknown as KVNamespace;
}

const file = { title: "Movie", year: 2012, fileName: "Movie.2012.1080p.BluRay.x264-SPARKS.mkv", fps: 23.976 };
const c = (id: string, over: Partial<Candidate> = {}): Candidate => ({ id, name: "Movie.2012.1080p.BluRay.x264-SPARKS", fps: 23.976, downloads: 100, ...over });

describe("ranking", () => {
  it("trusts a hash match, and marks down the wrong frame rate and machine translation", () => {
    const ranked = rank(file, [c("a", { name: "Movie.2012.WEB-OTHER", fps: 25, downloads: 9000 }), c("b", { hashMatch: true, downloads: 5 }), c("c", { machineTranslated: true })], null);
    expect(ranked[0]).toMatchObject({ id: "b", reasons: ["Made for this exact file", "Same release group (SPARKS)", "Frame rate matches"] });
    expect(ranked.find((r) => r.id === "a")!.reasons).toContain("Made for 25 fps");
  });

  it("uses Jev's probabilities when it answered", () => {
    const ranked = rank(file, [c("a"), c("b", { name: "Movie.2012.720p-OTHER" })], { a: 0.2, b: 0.8 });
    expect(ranked.map((r) => r.id)).toEqual(["b", "a"]);
    expect(ranked[0]!.confidence).toBe(0.8);
  });
});

describe("worker /v1/subtitles/rank", () => {
  const post = (body: unknown) => new Request("https://search.local/v1/subtitles/rank", { method: "POST", body: JSON.stringify(body) });

  it("asks Jev once per file and candidate set, then answers from KV", async () => {
    const env: Env = { INTENTS: memoryKV(), SEARCH_ENABLED: "true", TYPESAFE_API_KEY: "k" };
    const jev = vi.fn(async () => new Response(JSON.stringify({ answers: { fit: { type: "choice", choice: "c1", confidence: 0.9, probabilities: { c0: 0.1, c1: 0.9 } } } })));
    vi.stubGlobal("fetch", jev);
    const body = { file, candidates: [c("x"), c("y", { name: "Movie.2012.1080p.BluRay.x264-SPARKS.EXTENDED" })] };
    const first = await (await worker.fetch(post(body), env)).json() as { results: Array<{ id: string; confidence: number }>; source: string };
    expect(first.source).toBe("jev");
    expect(first.results[0]).toMatchObject({ id: "y", confidence: 0.9 });
    const again = await (await worker.fetch(post(body), env)).json() as { source: string };
    expect(again.source).toBe("cache");
    expect(jev).toHaveBeenCalledTimes(1);
    vi.unstubAllGlobals();
  });

  it("health: 204 with Jev, 503 without; rejects junk", async () => {
    const head = new Request("https://search.local/v1/subtitles/rank", { method: "HEAD" });
    expect((await worker.fetch(head, { INTENTS: memoryKV(), SEARCH_ENABLED: "true", TYPESAFE_API_KEY: "k" })).status).toBe(204);
    expect((await worker.fetch(head, { INTENTS: memoryKV(), SEARCH_ENABLED: "true" })).status).toBe(503);
    expect((await worker.fetch(post({ file }), { INTENTS: memoryKV(), SEARCH_ENABLED: "true", JEV_MODE: "stub" })).status).toBe(400);
  });
});
