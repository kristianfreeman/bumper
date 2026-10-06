# Bumper

A native Jellyfin player for Apple TV, iPhone, iPad and Mac. Nearly all code
is shared in `Packages/JellyfinAppKit`; the app targets (`App/` for the TV,
`iPhone/`, `Mac/`, `TopShelfExtension/`) are thin shells.

## Every change works the same on every platform

The TV, iPhone, iPad and Mac apps are one app. A change made for one of them
is made for all of them, in the same change:

- Behaviour and features match everywhere. Where a platform needs its own
  form (the Mac's window toolbar, the TV's focus, a phone's narrower grid),
  build that form too — don't leave a platform on the old behaviour.
- Put shared behaviour in shared code; platform differences go through the
  helpers in `DesignSystem/Platform.swift` (and `Layout.device`), not
  scattered `#if`s.
- Verify on every platform before calling it done: build TV, iPhone (and
  iPad) and Mac; screenshot the affected screens on each (TV and iPad/iPhone
  simulators, the Mac app); run the TV UI tiers that cover it
  (`scripts/test.sh smoke|tabs|settings|profile|player`). Playback and
  scrolling feel are checked on the real Apple TV (`scripts/device-*.sh`).
- Tests use `-mock`, never a real Jellyfin sign-in.

## Layout

- Pages read their width from `@Environment(\.pageWidth)` (set around every
  page by the shared navigation stack and each tab). Never measure a page
  from its own content or keep its width as state.
- Prefer the platform's own behaviour (focus scrolling, toolbars, sidebars)
  over custom machinery; custom scroll/focus code has repeatedly felt janky.
