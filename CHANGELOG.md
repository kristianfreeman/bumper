# Changelog

What changed in each Bumper release, written for the people using it. The
newest release is first. `scripts/release.sh` won't upload a version that
has no entry here, and the entry becomes the build's "What to Test" in
TestFlight.

## Unreleased

- Up Next under the picture: what plays after this one and when each ends,
  with Add to Up Next for the rest of the show, things like it, and what's
  next in your other shows. On the Apple TV it's in the player's menu row.
- At the credits: keep going (it counts down, then goes on by itself),
  something different, or done for tonight. Keep the Credits lets them roll.
- iPad on its side and wide Mac windows: Show Details puts the picture on
  the left and Up Next down the right.
- The chapter row under the picture is gone; About has what it's about and
  who's in it.
- Search finds a show by its name even when lots of its episodes match too,
  and puts the closest name first ("Simpsons" finds "The Simpsons").

## 0.2.1

- Fixed: playback could stop and close Bumper partway through episodes
  whose subtitles have heavy styling (typeset signs, karaoke in anime
  openings), most often on the 2017 Apple TV 4K. When memory runs low,
  Bumper now switches to plain subtitles for the rest of the episode and
  keeps playing, with a short note on screen.
- iPhone held upright: play, skip and the timeline sit on the video again;
  tap the picture to show or hide them.
- iPhone on its side: the picture stays full screen, with no split button.

## 0.2.0

- Picture in Picture on iPhone and iPad, from the PiP button or by leaving
  the app while a video plays; on the Mac for MP4 files.
- Cast and crew: pick an actor or director to see their page and what of
  theirs is in your library.
- Trailers and extras (behind the scenes, deleted scenes, featurettes) on a
  film's page.
- Chapters: marks on the timeline, the chapter's name while scrubbing, and
  a list to jump between them.
- A message while a slow file gets going ("Getting to 42:10…"), instead of
  a spinner on a black screen.
- iPhone and iPad held upright, and tall Mac windows: the video sits on top
  with the details, chapters and queue below. On iPhone Duo the split
  follows the fold.

## 0.1.0

The first TestFlight release, for Apple TV, iPhone, iPad and Mac.

- Plays your Jellyfin library directly, without the server converting it:
  Apple's player for what it handles, VLCKit for everything else (MKV, AVI,
  HEVC, AV1, DTS, TrueHD, ASS and PGS subtitles, and more).
- Home and libraries as collections with a line of copy each, and pages you
  can narrow by genre, decade, rating, length or when it was added.
- Search in plain words, subtitles found for the exact file, a Queue with a
  finish time, and Untracked playback that leaves your progress alone.
- Downloads on iPhone, iPad and Mac.
- Your phone as a remote for Bumper on your Apple TV.
- Sign in once: other Apple TVs on your iCloud account sign themselves in,
  and your settings follow you.
- Top Shelf, frame-rate matching and a sleep timer on the Apple TV.
