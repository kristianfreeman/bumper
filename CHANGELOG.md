# Changelog

What changed in each Bumper release, written for the people using it. The
newest release is first. `scripts/release.sh` won't upload a version that
has no entry here, and the entry becomes the build's "What to Test" in
TestFlight.

## Unreleased

- Home and the Movies and Shows pages are made of rows, Netflix style, and
  far more of them: every collection, the genres you have most of,
  Because You Watched, Highest Rated, Films You Haven't Seen, Something
  Different, your favourites, and on Movies and Shows the decades too.
  Each row scrolls sideways through all of it and ends in View all.
- Rows load and are built as they come into view, so a long page costs
  nothing until you get there (smooth on a 2017 Apple TV), and a row with
  nothing in it isn't shown.
- Apple TV: holding Left to run back along a row stops at its start
  instead of running into the sidebar, and back from the sidebar focus
  returns to the row you left, not the top of the page.
- Home's pick is the top of the page, not all of it: Continue Watching and
  the next row show beneath it.
- Movies and Shows: Continue Watching from that library leads the page,
  and All Movies (All Shows) is a button by the title that opens every
  one, A to Z, with its filters.
- Fixed: pressing Play after a long pause (overnight, say) said the film
  was over. Bumper now opens it again where you were, and a stream that
  drops part-way picks up from the same place instead of ending.
- Back from a recommendation, a person or an episode, a page stays where
  you were instead of jumping to the top.
- Audio & Subtitles on a film's or episode's page: choose them before you
  play, and Play, Resume and Start Over use them.
- Apple TV player: Down is Info, centred under the timeline. Its panel
  stays one height on every tab, Playback's rows scroll inside it, and
  Info's words aren't cut short.

## 0.3.0

Home
- Home opens on one pick, nearly the whole screen: what you'd most likely
  carry on with now (your queue, something nearly finished, the next
  episode), with Play ready — "Resume · 18m left" and Start Over when
  you've started it. An episode shows its show's logo and which episode it
  is; Go to Episode opens it. Along its foot, a list of five: moving along
  it brings each one up, and selecting it plays. Late at night the short
  ones come first.
- Below it, Continue Watching, Next Up and the rest are rows of their own,
  one row each, sideways, so the page is far shorter. Next Up shows the
  shows' posters with their names.
- Every row's title sits the same distance above its cards, and a row
  scrolled along comes to rest under its title.
- Continue Watching only keeps what you've played lately: Settings → Keep
  in Continue Watching (a week, a month, or forever). Anything older still
  resumes from its page.
- In a thing's menu: Remove from Continue Watching (on all your devices,
  until you play it again), Start Over Next Time, and Start Over (which
  was Play from Beginning).
- Marking something watched updates Home and your libraries at once.
- Hidden libraries stay off Home's new rows too.

The player
- Apple TV: a new player, without the row of icons. Up and Down bring up
  the controls, and press again: Up is Audio & Subtitles (both lists side
  by side, and Find Subtitles); Down is More along the bottom: Info, Up
  Next (when you've lined something up) and Playback (the sleep timer,
  Speakers when it's on, and a reminder that your iPhone can control it).
  Left and Right skip 10 seconds; during an intro Right skips it.
- iPhone, iPad and Mac: the same in their own form: one Audio & Subtitles
  menu, and More in a sheet or in the panel beside the picture. Forward
  skips 10 seconds, as Back does, and so does the → key.
- At the credits: Keep Going (it counts down, and moving the remote stops
  it), the next episode of another show, Something Different, or Done for
  Tonight, each with how long it is and when it would end. Keep the
  Credits lets them roll.
- Chapters are gone from the player.
- Settings → Speakers Button: the system's speaker picker in the player
  (AirPlay speakers, a HomePod, the TV), so no trip to Control Center.
  Off unless you turn it on, and set per device.
- Play Untracked is gone for now.

Apple TV
- The places are in the system's sidebar (press Menu or swipe left from a
  page), with you at its top; your profile page is in Settings.
- Browsing, the background takes the focused thing's colours at once,
  instead of fading in its picture.
- Collections and libraries show their cards' places while loading, with
  no flicker.
- A show's page puts focus on Play, and up from the episodes lands on it.
  The season bar, episodes and cast stop at the page's right margin, and a
  long-running show's seasons scroll inside the bar.
- Cast pictures: no line across the top when one lifts, and names move
  down with it.
- Playlists' pictures fill their cards without stretching.
- Sound on AirPlay speakers (a Sonos, a HomePod): no more sound cutting in
  and out, and no black picture at the start until you skip.

Settings
- Libraries: Show All and Hide All, and a line saying what's left when
  every library is hidden.
- Choosing a subtitle size, font or style keeps focus on that setting.
- Tidied: the Player choice is under About, the Speakers Button under
  Picture and Sound, and Find Missing Theme Songs only shows while theme
  music is on.

Search
- Films, shows, playlists, collections and videos come before episodes,
  and a show is found by its name ("21" finds the film, "Simpsons" finds
  "The Simpsons").

Mac
- Resizing the window is smooth: pages lay out in steps while you drag and
  nothing re-lays out under the player.

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
