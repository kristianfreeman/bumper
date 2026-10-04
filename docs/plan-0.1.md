# Version 0.1 plan

**Status (2026-10-04):** all four phases have a first working version (see the commits on
`wip/v0.1`). Still to do: the iPhone companion on a real iPhone (connect it to this Mac), and
feedback from using it all on the Living Room TV.

The last product changes before 0.1, in the order they'll land. Each phase ships on its own
(tests + device check), so we can stop and release at the end of any of them.

## 1. Polish and the pill control

**Transition glitches**
- *Hero logo*: the old logo vanished at once and the new one appeared inside the old one's
  animating frame, so its first frame was drawn at the wrong size (the flicker). Keep the
  resize, but crossfade two images, each at its own size, inside a container whose size
  animates. The old logo stays until the new one has loaded: no empty frame.
- *Backdrop*: the dimming was applied to each stacked image, not to the group, so the outgoing
  image showed through the incoming one and disappeared at the end (the flicker). Dim once,
  above the stack.

**The pill control** — the app's one button shape (`DesignSystem/Pill.swift`)
- At rest: a circle with an icon (or an image: the profile picture, a cover).
- Focused: it opens into a capsule showing its title; white, lifted.
- States: active (on: accent ring / fill), disabled (dimmed, not focusable), prominent (the
  primary action: accent fill).
- Used by: the top-right cluster (all icons: sleep timer, profile), the detail page's actions
  (play, start over, audio and subtitles, watched, favourite), the video player's icon row,
  and the audiobook player's controls.

## 2. Editorial home: collections, not carousels

**Collections replace rows.** Each one is a grid preview — four across, two rows on a TV — with
a written title and a line of copy, and a "View all" pill that opens the full collection.

**The copy is written, not labelled.** "Good evening, Kristian." "22 minutes left in Ancient
Aliens — finish it tonight?" "Added this week: three films and a season of Lost." On the TV this
comes from templates fed by what we know (time of day, weekday, what's in progress, what's new,
genres you watch). Apple's on-device language model doesn't exist on tvOS; the phone (phase 4)
can write richer copy where Apple Intelligence is available.

**A collection page explains itself.** Opening "View all" shows the full grid under a sentence
describing it — *Movies · added in the last month · unwatched* — where every part is a pill you
can change, remove or add to (genre, decade, rating, length, watched). The phone can drive it
by voice ("something lighter, under 90 minutes").

## 3. Tonight: a plan, not a queue

What the app is really doing is helping plan what to watch. **Tonight** is the first collection
on Home:
- Things you've added ("Add to Tonight" from any card or page), in order, with the time each
  starts and when the whole plan ends.
- *Done by…*: set when you want to stop ("done by 11:30"). Tonight then fits the plan to it,
  and it replaces the sleep timer: playback stops when the plan ends.
- Ambient suggestions fill in after the last item (next episode, more like it), clearly marked.
- The player plays the plan in order.

## 4. iPhone companion (proof of concept)

A separate iOS app that connects to the Apple TV over the local network (Bonjour, one JSON
message stream; a shared `Companion` module defines the messages).
- **Live:** what's focused on the TV and what's playing appear on the phone as they change.
- **Plan from the phone:** browse, add to Tonight, reorder, play on the TV.
- **Voice / words:** on iPhones with Apple Intelligence, the on-device model turns a request
  into a collection filter (or a plan) and sends it to the TV; elsewhere a keyword parser does.

Both apps ask for local-network access the first time (a system prompt on each device).

## Not in 0.1
The full iOS app (browsing, playback, downloads), recommendations beyond simple "more like
this", and multi-user plans.
