# Bumper search

A Cloudflare Worker that turns what someone types or says ("a funny 80s comedy",
"something short I haven't seen") into a filter the app applies to the library.

1. **Normalize**: lowercase, drop punctuation and filler words, dedupe, sort.
   "I want a funny 80s comedy" and "comedy, 80s, funny" are the same key.
2. **Cache**: Workers KV, keyed `i1:<words>`. A hit answers in a few milliseconds.
3. **Classify** on a miss: one request to [Jev](https://typesafe.ai) with a fixed set of
   typed questions (title or browse? films or shows? which genre, decade, length, watched,
   recently added, acclaimed?). Answers under 55% confidence are left unset.
   The result is cached.

`POST /v1/interpret {"query": "…"}` →

```json
{"v":1,"kind":"browse","media":"any","genre":"comedy","decade":1980,
 "watched":"any","added":"any","key":"80s comedy funny","source":"jev","query":"…"}
```

`kind: "title"` means "this names something": the app runs a normal Jellyfin search.

`HEAD /v1/interpret` is the health check: 204 when on, 503 when `SEARCH_ENABLED` isn't
`"true"` (the feature flag). The app checks it, and whenever the service is off,
slow (over 1.5 s) or failing, it uses its own word parser, then a plain Jellyfin search.

## Develop

```bash
npm install
npm test
npx wrangler dev --var JEV_MODE:stub   # no Jev calls; the app's UI test uses this
```

## Deploy (once)

```bash
npx wrangler login
npx wrangler kv namespace create INTENTS      # put the id in wrangler.toml
npx wrangler secret put TYPESAFE_API_KEY
npx wrangler secret put CLIENT_TOKEN          # optional: the app sends it as a bearer token
npx wrangler deploy
```

Deployed at `https://bumper-search.signalnerve.workers.dev/v1/interpret` (set as
`BumperSearchEndpoint` in project.yml). Until `TYPESAFE_API_KEY` is set, the health check
answers 503 and the app reads requests on the device.
Changing the questions in `src/jev.ts`? Bump `CACHE_VERSION` in `src/index.ts`.
