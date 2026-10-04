# Bumper

An open-source, ambient media player for Apple TV (and, growing from its companion, iPhone): it keeps
things playing. Today it plays a [Jellyfin](https://jellyfin.org) library — the **fastest** way to browse
one, and it **plays every file you throw at it** without making your server transcode.

- **Open source.** Playback, every codec, every feature: free, forever.
- **The only purchase is cosmetic:** a one-time "Themes & Customization" unlock (StoreKit 2).
- **Modern:** Swift 6.4 (strict concurrency, strict memory safety in core modules), tvOS 26+ (so the
  2017 Apple TV 4K is supported; tvOS 27 APIs behind `#available`), Jellyfin 10.11+.

> The name lives in exactly one place: `APP_DISPLAY_NAME` / `PRODUCT_BUNDLE_IDENTIFIER` in
> [`project.yml`](project.yml) (read at runtime via `Brand`). The Apple TV and iPhone apps share one
> bundle ID, `com.kristianfreeman.bumper` (universal purchase: one listing, one themes unlock).
> Module names are brand-free.

## Getting started

```bash
brew install xcodegen ffmpeg   # ffmpeg only generates test clips
scripts/fetch-vlckit.sh        # one-time: VideoLAN's VLCKit 4 xcframework → Vendor/ (checksum-pinned)
xcodegen generate              # → Bumper.xcodeproj
open Bumper.xcodeproj
```

Run with the `-mock` launch argument to use the built-in fake server (600 movies, 48 series,
generated artwork), no Jellyfin needed. Add `-perfHUD` for the live performance overlay.

## How playback works

One player interface, two backends. The UI asks for play, pause, seek, rate and track selection and
never knows which backend is active. [`PlaybackPlanner`](Packages/JellyfinAppKit/Sources/PlaybackCore/PlaybackPlanner.swift)
routes each item at play time from the media info Jellyfin already returned:

| Backend | When | Why |
|---|---|---|
| **AVPlayer** | Container MP4/M4V/MOV (or the server's HLS) **and** video H.264/HEVC **and** audio AAC/AC-3/E-AC-3 **and** no subtitle selected or a WebVTT one | Picture in Picture, AirPlay, system Dolby Vision |
| **VLCKit** | Everything else — MKV, AVI, TS, ASS/SSA, PGS, DTS, TrueHD, MPEG-2, VC-1, AV1, … | Plays anything without the server transcoding |
| **Server transcode** (fMP4 HLS → AVPlayer) | Only over a bitrate cap, for pure Dolby Vision (profile 5) outside MP4, or video this Apple TV can't decode in real time | — |

- **Per track, not per file:** choosing a PGS/ASS/SRT subtitle (or a DTS track) on an AVPlayer item
  hands it to VLCKit from the current position.
- **Fallback:** if AVPlayer fails to open or errors mid-playback, VLCKit takes the item over from where
  it was and keeps it.
- **Device profile:** we always declare what VLCKit can Direct Play, so the server never transcodes a
  file one of our backends can play.
- **Fast starts:** the TV's HDMI mode switch is requested from server metadata *before* opening the
  file, and PlaybackInfo is prewarmed as soon as Play gets focus.
- **Fast seeks:** skips coalesce (five presses = one seek to +50 s), the position on screen moves
  instantly, and `scripts/seek-bench.sh` measures time-to-picture and time-to-playing per backend.

VLCKit is VideoLAN's official build (LGPL 2.1), fetched and checksum-verified by
[`scripts/fetch-vlckit.sh`](scripts/fetch-vlckit.sh).

## Audiobooks

Jellyfin's audiobook libraries (AudioBook items): one-file books with embedded chapters (M4B) and
folders of files (parts) played back to back, with resume synced to the server.

    Jellyfin MP3 stream (from any position) → packets → PCM → Smart Speed → AVAudioEngine (time-pitch)

- **Speed** 0.8–3×, pitch kept. **Chapters**, ±15/30 s, sleep timer (minutes or end of chapter),
  Now Playing / Control Center, background audio.
- **Smart Speed** ([`SmartSpeed.swift`](Packages/JellyfinAppKit/Sources/PlaybackCore/Audiobook/SmartSpeed.swift)):
  shortens silences, never speech. 10 ms frames; an adaptive threshold from the recording's own noise
  floor and speech level; pauses under 0.3 s untouched, longer ones keep 0.3 s + 25 % of the rest
  (≤ 0.9 s), cut from the middle with 10 ms fades.
- The server transcodes to MP3 because Smart Speed needs the decoded audio (and the server's
  transcoder makes every position an instant start). Downloaded audio stays in memory (~30 min), so
  skips back are instant.
- Press → first sound on an Apple TV 4K (2017): ~0.6 s (`scripts/device-audiobook-check.sh`).

## Browsing: shelves, not grids

Every browse surface is a vertical stack of horizontally scrolling **shelves** ("Netflix style"). The
tvOS focus engine is built for rows: one swipe moves one card, rows provide context for free, and a
stack of lazy rows renders far fewer views than a grid. The single exception is a library's exhaustive
"See All" view, which is a paginated grid using the same cards and metrics.

Speed tricks: stale-while-revalidate content cache (home paints from disk before the network answers),
server-side image resizing to the exact pixel size, ImageIO thumbnail decoding off-main, a synchronous
LRU memory cache (no placeholder flash on scroll-back), BlurHash placeholders, visibility-driven
prefetch, and minimal `fields=` on every request.

## Performance is a feature (and a test)

| Tool | What it does |
|---|---|
| `Perf.measure` / `Span` | Every hot path is an `os_signpost` interval **and** a recorded metric |
| [`PerformanceBudget`](Packages/JellyfinAppKit/Sources/Instrumentation/PerformanceBudget.swift) | Hard limits (launch, TTFF, seek, image decode, hitch ratio…) |
| Perf HUD (`-perfHUD` or Settings → Diagnostics) | Live p50/p95 vs budget, memory, hitch rate; engine stats in the player |
| `HitchMonitor` | CADisplayLink hitch-time ratio (Apple's smoothness metric) |
| Unit tests (Swift Testing) | Correctness + micro-benchmarks with budgets, run on tvOS simulator |
| UI tests | Launch metric, CPU/memory, and **in-app budgets read from the HUD**; failing budget = failing build |
| `scripts/profile.sh` | Instruments trace with Points of Interest of a Release build |

```bash
scripts/test.sh                 # fast: core logic on macOS (Swift Testing)
scripts/test.sh smoke|player|profile   # focused UI checks against the mock server
scripts/test.sh seek            # seek/skip speed per backend (EXTENSIVE=1: every clip, two latencies)
scripts/test.sh ui              # UI + performance suite (mock server, deterministic)
scripts/make-test-media.sh      # real MKV/TS/MP4 clips: HDR10 HEVC, DTS, TrueHD, E-AC-3, MPEG-2…
scripts/make-seek-media.sh      # two-minute clips for the seek benchmark
scripts/make-long-media.sh      # a 20-minute MKV for resume checks (device-resume-bench.sh)
scripts/make-audiobook-media.sh # two audiobooks (synthesized speech, scripted pauses)
scripts/test.sh books|shots     # audiobook UI test; screenshots of every screen for review
scripts/validate-playback.sh    # plays every clip end-to-end in the app; reports backend, TTFF
scripts/profile.sh              # Instruments trace (Release build)
```

Launch arguments: `-mock` (fake server), `-mockMedia <dir>` (serve real clips with HTTP Range),
`-autoplay <itemId>`, `-perfHUD`, `-reset`, `-mockLatency <ms>`, `-mockHTTP` (real loopback server),
`-mediaLatency <ms>` (simulated server time-to-first-byte), `-seekBench`, `-route <item:|library:|settings:|profile:>`.

## Layout

```
App/                      tvOS app target (entry point, assets, StoreKit config)
Packages/JellyfinAppKit/
  Instrumentation/        signposts, metrics, budgets, hitch monitor
  JellyfinAPI/            hand-written Jellyfin 10.11 client (fast explicit-key decoding, discovery)
  AppCore/                accounts/keychain, settings, image pipeline, blurhash, content cache, Brand
  PlaybackCore/           player interface, routing, device profiles, AVPlayer backend, subtitles, reporting
  VLCPlayback/            the VLCKit backend
  DesignSystem/           themes (+ StoreKit), artwork, cards, shelves, grid
  AppFeatures/            screens: onboarding, home, library, detail, search, settings, player
  JellyfinMocks/          in-process mock Jellyfin server for tests, previews and `-mock`
UITests/                  smoke + performance tests
scripts/                  fetch-vlckit, test tiers, benchmarks, test media, profiling
```

## Status & known gaps

Playback is tested on a real **Apple TV 4K (2017, A10X, tvOS 26.6)** — `scripts/test.sh device`
(clips stream from the Mac over the LAN; results, `trace.log` and VLC's log are pulled back from the
app's container):

| Clip | Backend | First frame |
|---|---|---|
| 4K HDR10 HEVC + E-AC-3 (MKV) | VLCKit | ~520 ms |
| H.264 + DTS 5.1 + ASS (MKV) | VLCKit | ~350 ms |
| H.264 + TrueHD (MKV) | VLCKit | ~160 ms |
| MPEG-2 (TS) / MPEG-2 1080i (TS) | VLCKit | ~300–430 ms |
| HEVC + AAC (MP4) | AVPlayer | ~570 ms |
| H.264 + AAC (MP4) | AVPlayer | ~480 ms |

Press Play → picture moving, same Apple TV (`scripts/device-start-bench.sh`). Focusing the detail
page's Play button prepares VLCKit items (opened, buffered, paused on the first frame):

| | Prepared (Play focused first) | Cold |
|---|---|---|
| VLCKit (MKV, TS) | ~110–280 ms | ~150–570 ms |
| AVPlayer (MP4) | ~460–530 ms (not prepared — measured no faster) | same |

Seeking on the same Apple TV (playing again at the new position):

| | ±10 s skip | Jump anywhere | 5 rapid presses (+50 s) |
|---|---|---|---|
| AVPlayer (MP4) | ~0.5 s | ~0.5 s | ~1.0–1.4 s |
| VLCKit (MKV) | ~0.3 s | ~0.4 s (max ~0.6 s) | ~0.6 s |

Resuming partway into a 20-minute, 1 GB MKV (`scripts/device-resume-bench.sh`): ~0.8–1.0 s at any
position.

Two VLC 4 behaviours the backend works around:
- **MKV Cues:** VLC's default MKV demuxer treats a file's Cues as unconfirmed, and over HTTP (no fast
  seek to check them) seeks from the first cluster instead, reading everything up to the target. The
  backend opens MKV with `mkv_trusted`: resuming 15 minutes in went from a 20 s timeout to 0.8 s.
- **`:start-time`** makes the start point the clip's in-point: the clock, length and every later seek
  become relative to it. Resume is a seek right after play() instead.

Known gaps:
- **VLCKit runs its clock on the system clock** (`clock-master=monotonic`) — it removed ~1 s from every
  seek on device; VLC keeps sync by resampling audio slightly. Bitstreamed Dolby audio to a receiver
  and very long sessions are still to be verified.
- **VLCKit subtitles sit under the transport bar** while it's visible (VLC draws them in the video).
- **Dolby Vision mode switching / frame-rate matching** not yet verified on a DV/HDR display.
