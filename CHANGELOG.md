# Changelog

What changed in each Bumper release, written for the people using it. The
newest release is first. `scripts/release.sh` won't upload a version that
has no entry here, and the entry becomes the build's "What to Test" in
TestFlight.

## Unreleased

- Apple TV: a new player, without the row of icons. Up and Down first
  bring up the controls, and press again: Up is Audio & Subtitles (both
  lists side by side, and Find Subtitles), Down is More along the bottom:
  Info, Up Next (when you've lined something up) and Playback (the sleep
  timer, Speakers when it's on, and a reminder that your iPhone can
  control it). Left and Right skip 10 seconds, and during an intro Right
  skips it. The time under the timeline is quieter.
- iPhone, iPad and Mac: the same in their own form: one Audio & Subtitles
  menu, and More (Info, Up Next, Playback) in a sheet, or in the panel
  beside the picture. Forward skips 10 seconds, as Back does, and so does
  the → key. On a keyboard, ↓ shows the controls, then opens More.
- Chapters are gone from the player: no menu, no marks on the timeline.
- At the credits, more to choose from and more to go on: the next episode
  of another show you're watching joins Keep Going, Something Different and
  Done for Tonight, and each says how long it is, when it would end, its
  rating and what it's about.
- Home opens on one pick, nearly the whole screen: what you'd most likely
  carry on with now (your queue, something nearly finished, the next
  episode) big over its picture, with Play ready — "Resume · 18m left" and
  Start Over when you've started it. An episode shows its show's logo and
  which episode it is, and Go to Episode opens it. Along its foot, its own
  list of five: moving along it (the remote, the Mac's pointer, a tap)
  brings each one up, and selecting it plays. Late at night the short ones
  come first. The greeting is gone.
- Below it, Continue Watching, Next Up and the rest are rows of their own:
  moving along them never changes the pick.
- Every row's title sits the same distance above its cards, with or without
  a line under it, and clear of a focused card's lift on the Apple TV. A row
  scrolled along comes to rest under its title, with no cut-off card at the
  left.
- Play from Beginning is called Start Over in a thing's menu, as it is on
  Home.
- Home's rows are one row each, sideways, so the page is far shorter: what's
  new, playlists and your queue scroll like Next Up.
- Hidden libraries stay off Home's new rows too (Continue Watching and Next
  Up still come from every library).
- Apple TV: Next Up's titles move down as a poster lifts, so it never covers
  them.
- Continue Watching only keeps what you've played lately: Settings → Keep
  in Continue Watching (a week, a month, or forever). Anything older still
  resumes where you left it from its page.
- Remove from Continue Watching, in a thing's menu, takes it out on all
  your devices until you play it again. Start Over Next Time keeps it but
  forgets where you were.
- Settings → Libraries: Show All and Hide All, and a line saying what's
  left when every library is hidden.
- Apple TV: choosing a subtitle size, font or style keeps focus on that
  setting (it used to jump up to Libraries).
- Settings, tidied: the Player choice is under About with the other
  diagnostics, the Speakers Button is under Picture and Sound, and Find
  Missing Theme Songs only shows while theme music is on.
- Play Untracked is gone for now.
- Up Next under the picture: what plays after this one and when each ends,
  with Add to Up Next for the rest of the show, things like it, and what's
  next in your other shows. On the Apple TV and the iPhone remote, Up Next
  is only what you've lined up yourself, and isn't there when you haven't.
- At the credits: keep going (it counts down, then goes on by itself),
  something different, or done for tonight. Keep the Credits lets them roll.
- iPad on its side and wide Mac windows: Show Details puts the picture on
  the left and Up Next down the right.
- The chapter row under the picture is gone; About has what it's about and
  who's in it.
- Apple TV: opening a show's page, focus lands on Play and stays there
  (it used to hop to More and back while the episodes loaded).
- Apple TV: the season bar, episodes and cast stop at the page's right
  margin, and a long-running show's 30-odd seasons scroll inside the bar.
- At the credits, moving the remote stops the countdown: it waits for you.
- Apple TV with its sound on AirPlay speakers (a Sonos, a HomePod): no more
  sound cutting in and out on files VLCKit plays. The TV only says it's
  AirPlaying once sound plays; Bumper checks then, and remembers.
- Mac: resizing the window is smooth — pages lay out in steps while you
  drag, the video settles when you pause, and nothing re-lays out under the
  player (a typical step 13 ms → 6 ms; Home's half-second freeze is gone).
- Settings → Speakers Button: the player gets the system's speaker picker
  (AirPlay speakers, a HomePod, the TV) — no more Control Center on the
  Apple TV. Off unless you turn it on, and set per device.
- Apple TV: the places move into the system's sidebar (press Menu or swipe
  left from a page), with you at its top; your profile page is in Settings.
  The top row had run off the screen.
- Apple TV: a show's page leads with a big Play that says what it plays, and
  up from the episodes lands on it.
- Search asks your server one thing at a time: asked several searches at
  once it answered wrongly ("21" found episodes, not the film). Films,
  shows, playlists, collections and videos come before episodes.
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
