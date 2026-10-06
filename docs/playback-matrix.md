# Playback matrix

What Bumper does with each kind of file, and how it plays — measured on an
Apple TV 4K (2017), the oldest Apple TV 4K, the weakest Bumper supports.
Every clip is 35 s of constant motion; a clip is **smooth** when it shows its
full frame rate with nothing dropped or late.

```bash
scripts/make-matrix-media.sh   # the clips (ffmpeg), into TestMedia/matrix/
scripts/device-matrix.sh       # plays each on the Apple TV, ~45 s a clip → perf-results/matrix-<date>/report.md
```

## Results (2026-10-06, tvOS 26.6, no server transcoding)

28 of 31 smooth.

| File | Played by | First frame | Result |
|---|---|---|---|
| H.264 1080p, MP4 · AAC | AVPlayer | 150 ms | smooth |
| H.264 480p, MP4 · AAC | AVPlayer | 235 ms | smooth |
| HEVC 1080p, MP4 · E-AC-3 5.1 | AVPlayer | 215 ms | smooth |
| H.264 1080p, MP4 · AAC · mov_text subtitles | AVPlayer | 200 ms | smooth (was: froze, see below) |
| H.264 1080p, MKV · AAC / AC-3 / DTS / TrueHD / FLAC 7.1 | VLCKit | 0.4–1.2 s | smooth |
| H.264 1080p 10-bit (Hi10P), MKV | VLCKit | 1.0 s | smooth |
| H.264 1080i, MKV | VLCKit | 1.2 s | smooth |
| H.264 1080p59.94, 720p50, MKV | VLCKit | 0.7–1.5 s | smooth |
| H.264 1080p, M2TS · AC-3 5.1 | VLCKit | 0.4 s | smooth |
| H.264 1080p, MKV · SRT subtitles | VLCKit | 0.9 s | smooth |
| H.264 1080p, MKV · ASS subtitles | VLCKit | 0.9 s | ~1 frame/s late |
| HEVC 1080p 10-bit, MKV | VLCKit | 0.9 s | smooth |
| HEVC 2160p HDR10, MKV · E-AC-3 | VLCKit | 1.2 s | smooth |
| HEVC 2160p59.94, MKV | VLCKit | 1.2 s | smooth |
| AV1 1080p, MKV · Opus | VLCKit | 0.6 s | smooth |
| **AV1 2160p, MKV** | VLCKit | 0.8 s | **12 of 24 fps** — no AV1 hardware on this model |
| VP9 1080p, WebM · Opus | VLCKit | 0.6 s | smooth |
| MPEG-4 Part 2 (Xvid/DivX) 480p, AVI · MP3 | VLCKit | 0.7–0.9 s | smooth (was: half the frames dropped, see below) |
| MS-MPEG-4 v3 (DivX 3) 480p25, AVI | VLCKit | 1.1 s | ~1 frame/s late |
| MPEG-2 480i (DVD), MPG · AC-3 | VLCKit | 0.8 s | smooth |
| MPEG-2 1080i, TS · AC-3 | VLCKit | 0.5 s | smooth |
| WMV2 480p, WMV · WMA | VLCKit | 1.1 s | smooth |
| Sorenson (FLV1) 360p, FLV · MP3 | VLCKit | 0.3 s | smooth |
| MJPEG 720p, AVI · PCM | VLCKit | 2.1 s | smooth |
| ProRes 422 1080p, MOV · PCM | VLCKit | 0.7 s | smooth |

Not covered (no encoder for them here): VC-1, Dolby Vision, DTS-HD MA,
PGS and VobSub subtitles, Theora. Real files from a library can be played
through the same runner from the server.

## What it found and fixed

- **AVI dropped over half its frames** (an SD sitcom at 15 fps). VLC's own
  AVI reader gives packed-B-frame DivX/Xvid display times a frame or two
  early ("picture is too late"); AVIs now go through FFmpeg's reader.
- **MP4 with text subtitles froze on its first frame.** Text subtitles
  handed AVPlayer's items to VLCKit, which then started paused. Text
  subtitles now stay on AVPlayer (the server sends them as WebVTT), and a
  hand-off only keeps a pause the person made.

## Guidance

- **Match Frame Rate on** (Settings → Video and Audio → Match Content) for
  film: 23.976 fps on a 60 Hz screen judders on pans. The cost is a 1–3 s
  blank as the TV changes mode when playback starts and stops. Bumper asks
  for the switch and waits for it before the picture starts.
- **MP4 with H.264 or HEVC and AAC/AC-3/E-AC-3** starts fastest (AVPlayer,
  ~0.2 s) and gets Picture in Picture and AirPlay. Everything else plays in
  VLCKit, starting in 0.3–2 s.
- **AV1 at 4K is too heavy for an Apple TV 4K (2017)**, which has no AV1
  decoder; 1080p AV1 is fine. Newer Apple TVs decode AV1 in hardware.
- Old formats (DivX, DVD, WMV, Flash, MJPEG) play as they are; nothing needs
  the server to convert them.
