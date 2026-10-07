# Version 0.2 plan

0.1 is the fast player that plays nearly everything. 0.2 closes the gaps people notice first
next to Plex and Infuse, without giving up speed. Every item lands on TV, iPhone, iPad and Mac
together (see CLAUDE.md), with tests against `-mock`.

## Done

**The split player.** When the space is taller than wide (a phone or iPad upright, a tall Mac
window) or iPhone Duo is half folded on its side, the picture sits on top and the controls,
details, Up Next and the queue sit below it. A button switches to full screen and back. On
iOS 27.1 the split follows the fold (`reservedRegions(kind: .division)`); built with an older
SDK it goes by shape alone. Duo work builds with the Xcode 27.1 beta; releases stay on the
released Xcode (`scripts/release.sh` refuses a beta).

**Picture in Picture** (§1), **people, trailers and extras** (§2), **chapters** (§3) and **the
slow-start message** (§4) are built and merged. Still to see on a real device: an MKV floating
through VLCKit, PiP on the Mac (AVPlayer only; VLCKit's Mac build has none), and person pages and
chapters with the Siri Remote. Subtitles don't float with the picture yet.

**Faster tests.** Screens are checked in-process in the fast tier (`Tests/AppFeaturesTests`:
real views, the mock server and a fake player, 40–250 ms a check); the simulator tiers keep what
needs the TV's focus engine and remote, with the app's timers at a fifth (`-quickTimers`).

## 1. Picture in Picture

iPhone, iPad and Mac. Leave the player (swipe home, switch apps, close the window's player)
and the picture keeps playing in a floating window; tap it to come back to the player where
it was.
- AVPlayer: `AVPictureInPictureController` on the player's layer.
- VLCKit: its picture-in-picture drawable, so MKV and the rest float too. If VLCKit can't on
  a platform, that platform says so instead of failing silently.
- One PiP button in the player's controls, shown where PiP is possible. Starts on its own when
  you leave the app while playing (the system's setting).
- The TV has no PiP: nothing changes there.
- Fix the README, which claims PiP today.

## 2. People, trailers and extras

The server already returns all three; the app doesn't show them.
- **People.** Tapping a cast or crew card opens their page: photo, what they're known for, and
  their films and shows in your library as a collection (sorted by year, newest first).
- **Trailers.** A Trailer button on a film or show's page when it has one: local trailers from
  the library first, then the server's remote trailers (YouTube links open in the YouTube app or
  the browser on iPhone, iPad and Mac; on the TV only local trailers play).
- **Extras.** Behind the scenes, deleted scenes, featurettes and the like as a row on the
  page, playable like anything else.

## 3. Chapters

- Chapter marks on the timeline, on every platform.
- A Chapters list in the player: name, start time and thumbnail (trickplay image when there's
  no chapter image), current chapter marked. On the TV a card from the icon row; elsewhere a
  menu or the split's panel.
- On the TV, while scrubbing, the chapter name under the thumbnail.

## 4. A message for slow starts

When opening or resuming takes longer than a second, say what's happening: "Getting to
42:10…" for a resume, "Getting ready…" otherwise. Nothing when it's quick.

## 5. Home theatre: Atmos, DTS:X and Dolby Vision

Measured on the Living Room setup (Apple TV 4K, Sonos Arc), not guessed:
- What the receiver actually gets for TrueHD Atmos, E-AC-3 Atmos, DTS-HD MA and DTS:X, from
  each player. Fix what isn't passed through where tvOS allows it.
- Dolby Vision profile 5, 7 and 8 files: which play without the server, which need it, and
  whether VLCKit can show profile 5 itself.
- The results go into `docs/playback-matrix.md`.

## Later in 0.2, if there's room

- Siri and Shortcuts: "Play the next episode of …", "Continue watching".
- A Continue Watching widget (iPhone, iPad, Mac).
- A profile PIN, so a shared TV can't switch into an adult's profile.
- ASS subtitles a frame per second late; DivX 3 dropping frames.

## Not in 0.2

Music libraries, Live TV and DVR, SharePlay. Each is a project of its own; decided after 0.2.
