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

const c = (fileId: number, over: Partial<Candidate> = {}): Candidate =>
  ({ fileId, language: "en", release: "Movie.2012.1080p.BluRay.x264-SPARKS", fps: 23.976, downloads: 100, hearingImpaired: false, machineTranslated: false, trusted: false, hashMatch: false, ...over });

describe("ranking", () => {
  const req = { title: "Movie", year: 2012, languages: ["en"], fileName: "Movie.2012.1080p.BluRay.x264-SPARKS.mkv", fps: 23.976 };

  it("trusts a hash match, and marks down the wrong frame rate and machine translation", () => {
    const ranked = rank(req, [c(1, { release: "Movie.2012.WEB-OTHER", fps: 25, downloads: 9000 }), c(2, { hashMatch: true, downloads: 5 }), c(3, { machineTranslated: true })], null);
    expect(ranked[0]!.fileId).toBe(2);
    expect(ranked[0]!.confidence).toBeGreaterThanOrEqual(0.97);
    expect(ranked[0]!.reasons[0]).toBe("Made for this exact file");
    const wrongFps = ranked.find((r) => r.fileId === 1)!;
    expect(wrongFps.reasons).toContain("Made for 25 fps");
  });

  it("uses Jev's probabilities when it answered", () => {
    const ranked = rank(req, [c(1), c(2, { release: "Movie.2012.720p-OTHER" })], { "1": 0.2, "2": 0.8 });
    expect(ranked.map((r) => r.fileId)).toEqual([2, 1]);
    expect(ranked[0]!.confidence).toBe(0.8);
  });
});

describe("worker /v1/subtitles", () => {
  const env = (): Env => ({ INTENTS: memoryKV(), SEARCH_ENABLED: "true", SUBTITLES_MODE: "stub", JEV_MODE: "stub" });
  const post = (path: string, body: unknown) => new Request(`https://search.local${path}`, { method: "POST", body: JSON.stringify(body) });

  it("searches, ranks, caches; downloads once then from KV", async () => {
    const e = env();
    const search = { title: "Movie", year: 2012, languages: ["en"], fileName: "Movie.2012.1080p.BluRay.x264-SPARKS.mkv", fps: 23.976 };
    const first = await (await worker.fetch(post("/v1/subtitles/search", search), e)).json() as { results: Array<{ fileId: number; confidence: number; reasons: string[] }>; source: string };
    expect(first.source).toMatch(/^stub/);
    expect(first.results[0]!.reasons).toContain("Same release group (SPARKS)");
    const again = await (await worker.fetch(post("/v1/subtitles/search", search), e)).json() as { source: string };
    expect(again.source).toMatch(/^cache/);

    const file = await worker.fetch(post("/v1/subtitles/download", { fileId: first.results[0]!.fileId }), e);
    expect(file.headers.get("X-Source")).toBe("stub");
    expect(await file.text()).toContain("00:00:01,000 --> 00:00:04,000");
    const cached = await worker.fetch(post("/v1/subtitles/download", { fileId: first.results[0]!.fileId }), e);
    expect(cached.headers.get("X-Source")).toBe("cache");
  });

  it("says it's off without an OpenSubtitles key", async () => {
    const head = new Request("https://search.local/v1/subtitles/search", { method: "HEAD" });
    expect((await worker.fetch(head, { INTENTS: memoryKV(), SEARCH_ENABLED: "true" })).status).toBe(503);
    expect((await worker.fetch(head, env())).status).toBe(204);
  });
});
