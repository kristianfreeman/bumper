#!/usr/bin/env bash
# Tiered test loop. Pick the smallest tier that covers your change.
#
# House rule: one focused, quick test per behaviour (exhaustive variants are
# opt-in, e.g. EXTENSIVE=1). Every step is hang-protected by a tree-killing
# timeout sized to the step, so a stall fails in seconds, not minutes.
#
#   scripts/test.sh                 fast   ~5 s   core logic on macOS (swift test, debug)
#   scripts/test.sh perf                   ~20 s  same tests optimized: timing budgets enforced
#   scripts/test.sh unit                   ~1 min core tests on the tvOS simulator
#   scripts/test.sh smoke [test]           ~25 s  deep-linked UI checks (optionally one test)
#   scripts/test.sh player [test]          ~15 s  player controls on real clips (TestMedia/)
#   scripts/test.sh tabs [test]            ~15 s  the tab bar along the top, and Up/Down/Menu focus routing
#   scripts/test.sh profile [test]         ~15 s  Home profile corner: menu, sleep timer, stats
#   scripts/test.sh settings [test]        ~15 s  Settings tab navigation
#   scripts/test.sh people [test]          ~40 s  cast and crew pages, trailers and extras on a film's page
#   scripts/test.sh search [test]          ~20 s  global search, with the search service running locally
#   scripts/test.sh one Class[/test]       any one TV UI test class or test
#   scripts/test.sh phone [Class[/test]]   ~2 min the iPhone UI tests (not the companion: companion-check.sh)
#   scripts/test.sh device                 playback + seek speed on the real Apple TV (the playback truth)
#   scripts/test.sh seek                   seek/skip speed in the simulator (EXTENSIVE=1: every clip)
#   scripts/test.sh ui                     full UI + performance suite (CI)
#   scripts/test.sh bench                  harness-free scroll smoothness benchmark
#   scripts/test.sh all                    everything (CI)
#
# On failure xcodebuild normally runs `simctl diagnose` for minutes (the
# simulator idles on its home screen meanwhile); that's off by default. The
# log, screenshot and .xcresult are still kept. COLLECT_DIAGNOSTICS=on-failure
# to turn it back on.
#
# Stopping: Ctrl-C, or `kill <pid>` (printed if you start a second run). Either
# tears down xcodebuild AND the app / UI-test runner inside the simulator.
set -euo pipefail
cd "$(dirname "$0")/.."

SIM_NAME="${SIM_NAME:-Apple TV 4K (3rd generation)}"
OS="${OS:-27.0}"
DEST="platform=tvOS Simulator,name=$SIM_NAME,OS=$OS"
DD="build/test"
OUT="perf-results/$(date +%Y%m%d-%H%M%S)"
PKG=Packages/JellyfinAppKit
LOCK="build/.test.lock"
BUNDLE=com.kristianfreeman.bumper

# ── Single run at a time ─────────────────────────────────────────────────────
# Concurrent runs fight over the simulator (each launches/terminates the app
# under the other) and wedge both.
mkdir -p build
if ! mkdir "$LOCK" 2>/dev/null; then
  holder=$(cat "$LOCK/pid" 2>/dev/null || true)
  if [[ -n "$holder" ]] && kill -0 "$holder" 2>/dev/null; then
    echo "Another test run is active (pid $holder). Stop it with: kill $holder" >&2
    exit 2
  fi
  rm -rf "$LOCK"; mkdir "$LOCK"                       # stale lock from a crashed run
fi
echo $$ > "$LOCK/pid"

# ── Teardown ─────────────────────────────────────────────────────────────────
booted_udid() {
  xcrun simctl list devices booted 2>/dev/null | grep "$SIM_NAME (" | grep -oE '[0-9A-F-]{36}' | head -1 || true
}

stop_sim_apps() {
  # The app and the XCTest runner live under the *simulator's* launchd: host
  # signals never reach them, so terminate them explicitly.
  local udid; udid=$(booted_udid)
  [[ -n "$udid" ]] || return 0
  xcrun simctl terminate "$udid" "$BUNDLE" >/dev/null 2>&1 || true
  # Bumper in any other booted simulator (iPhone, iPad) shares the Mac's
  # loopback: its mock server would hold port 8097 and the TV's can't start.
  for other in $(xcrun simctl list devices booted 2>/dev/null | grep -oE '[0-9A-F-]{36}'); do
    xcrun simctl terminate "$other" "$BUNDLE" >/dev/null 2>&1 || true
  done
  xcrun simctl terminate "$udid" "$BUNDLE.uitests.xctrunner" >/dev/null 2>&1 || true
  # xcodebuild's failure diagnostics (`simctl diagnose`) hang off the simulator
  # service, not our process tree, and can grind on for minutes.
  pkill -f "simctl diagnose" 2>/dev/null || true
}

kill_tree() {
  local child
  for child in $(pgrep -P "$1" 2>/dev/null); do kill_tree "$child"; done
  kill -TERM "$1" 2>/dev/null || true
}

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  local child
  for child in $(pgrep -P $$ 2>/dev/null); do kill_tree "$child"; done
  stop_sim_apps
  rm -rf "$LOCK"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Run a step as a background child and `wait` for it: bash defers traps while a
# *foreground* child runs, but `wait` is interruptible — so Ctrl-C / kill act now.
step() { "$@" & wait $!; }

# Hang protection per kind of step (tree-killing; override with CAP=n).
CAP="${CAP:-}"
capped() { local t="$1"; shift; scripts/with-timeout.sh "${CAP:-$t}" "$@"; }

summarize() { grep -E '✔ Test run|✘|error:|Test Case .*(passed|failed)|TEST (SUCCEEDED|FAILED)|measured' || true; }
need_vlckit() { [[ -d Vendor/VLCKit.xcframework ]] || scripts/fetch-vlckit.sh; }
need_project() { [[ -d Bumper.xcodeproj ]] || xcodegen generate; }

# ── Tiers ────────────────────────────────────────────────────────────────────
fast() { need_vlckit; (cd "$PKG" && ../../scripts/with-timeout.sh "${CAP:-90}" swift test 2>&1) | sed 's/\x1b\[[0-9;]*m//g' | summarize; }

perf() { need_vlckit; (cd "$PKG" && ../../scripts/with-timeout.sh "${CAP:-180}" swift test -c release -Xswiftc -enable-testing 2>&1) | sed 's/\x1b\[[0-9;]*m//g' | summarize; }

unit() {
  need_vlckit
  (cd "$PKG" && ../../scripts/with-timeout.sh "${CAP:-180}" xcodebuild test -scheme JellyfinAppKit -destination "$DEST" -derivedDataPath "../../$DD/pkg" -quiet 2>&1) | summarize
}

# Build the app + UI test bundle once; later runs reuse it with test-without-building.
# Debug for smoke (fast incremental builds); Release for the perf tier (`ui`).
CONFIG="${CONFIG:-Debug}"

build_for_testing() {
  need_vlckit; need_project
  capped 300 xcodebuild build-for-testing -project Bumper.xcodeproj -scheme Bumper -configuration "$CONFIG" \
    -destination "$DEST" -derivedDataPath "$DD/app" -quiet
}

# The newest available simulator with this name (no machine's ids in here).
sim_id() { xcrun simctl list devices available | grep -E "^    $1 \([0-9A-F-]{36}\)" | tail -1 | grep -oE '[0-9A-F-]{36}'; }
PHONE_DEST="id=${PHONE_SIM:-$(sim_id "${PHONE_SIM_NAME:-iPhone 17 Pro}")}"

build_for_testing_phone() {
  need_vlckit; need_project
  capped 400 xcodebuild build-for-testing -project Bumper.xcodeproj -scheme BumperPhone -configuration "$CONFIG" \
    -destination "$PHONE_DEST" -derivedDataPath "$DD/phone" -quiet
}

# The same cut-offs as the TV's: a stuck test fails in a minute, not ten.
phone_run() {
  mkdir -p "$OUT"
  capped 600 xcodebuild test-without-building -project Bumper.xcodeproj -scheme BumperPhone -configuration "$CONFIG" -destination "$PHONE_DEST" \
    -derivedDataPath "$DD/phone" -resultBundlePath "$OUT/phone.xcresult" \
    -test-timeouts-enabled YES -default-test-execution-time-allowance 60 -maximum-test-execution-time-allowance 120 \
    -collect-test-diagnostics "${COLLECT_DIAGNOSTICS:-never}" \
    "$@" 2>&1 | tee "$OUT/phone.log" | summarize
  echo "log: $OUT/phone.log   results: $OUT/phone.xcresult"
}

ui_run() {
  mkdir -p "$OUT"
  stop_sim_apps                                       # clean slate on the simulator
  # Raw log kept for diagnosis. Each test is cut off at a minute (a stall
  # fails fast); the whole run at 15 (tiers have grown past 2).
  TEST_RUNNER_PERF_ITERATIONS="${PERF_ITERATIONS:-1}" \
  capped 900 xcodebuild test-without-building -project Bumper.xcodeproj -scheme Bumper -configuration "$CONFIG" -destination "$DEST" \
    -derivedDataPath "$DD/app" -resultBundlePath "$OUT/ui.xcresult" \
    -test-timeouts-enabled YES -default-test-execution-time-allowance 60 -maximum-test-execution-time-allowance 120 \
    -collect-test-diagnostics "${COLLECT_DIAGNOSTICS:-never}" \
    "$@" 2>&1 | tee "$OUT/ui.log" | summarize
  echo "log: $OUT/ui.log   results: $OUT/ui.xcresult"
}

case "${1:-fast}" in
  fast) step fast ;;
  perf) step perf ;;
  unit) step unit ;;
  smoke) step build_for_testing; step ui_run -only-testing:"BumperUITests/SmokeTests${2:+/$2}" -only-testing:"BumperUITests/TabBarTests" -only-testing:"BumperUITests/ScrollTests" ;;
  profile) step build_for_testing; step ui_run -only-testing:"BumperUITests/ProfileTests${2:+/$2}" ;;
  settings) step build_for_testing; step ui_run -only-testing:"BumperUITests/SettingsTests${2:+/$2}" ;;
  player) step build_for_testing; step ui_run -only-testing:"BumperUITests/PlayerTests${2:+/$2}" ;;
  queue) step build_for_testing; step ui_run -only-testing:"BumperUITests/QueueTests" ;;
  scroll) step build_for_testing; step ui_run -only-testing:"BumperUITests/ScrollTests" ;;
  tabs|sidebar) step build_for_testing; step ui_run -only-testing:"BumperUITests/TabBarTests${2:+/$2}" ;;
  collection) step build_for_testing; step ui_run -only-testing:"BumperUITests/CollectionTests" ;;
  people) step build_for_testing; step ui_run -only-testing:"BumperUITests/PeopleTests${2:+/$2}" ;;
  search)
    # The search service, locally, answering without Jev.
    step build_for_testing
    (cd services/search && [[ -d node_modules ]] || npm install --silent)
    (cd services/search && exec npx wrangler dev --port 8787 --var JEV_MODE:stub >"$PWD/../../build/wrangler.log" 2>&1) &
    WRANGLER=$!
    for _ in $(seq 1 60); do curl -s -o /dev/null -w '%{http_code}' -I localhost:8787/v1/interpret | grep -q 204 && break; sleep 0.5; done
    step ui_run -only-testing:"BumperUITests/SearchTests${2:+/$2}"
    kill_tree "$WRANGLER" ;;
  one) step build_for_testing; step ui_run -only-testing:"BumperUITests/$2" ;;   # any TV UI test: one Class[/test]
  phone) step build_for_testing_phone
         if [[ -n "${2:-}" ]]; then step phone_run -only-testing:"BumperPhoneUITests/$2"
         else step phone_run -skip-testing:BumperPhoneUITests/CompanionTests -skip-testing:BumperPhoneUITests/PhoneScrollTests; fi ;;
  books) step build_for_testing; step ui_run -only-testing:"BumperUITests/AudiobookTests${2:+/$2}" ;;
  shots) step build_for_testing; SHOTS="$PWD/perf-results/shots"; rm -rf "$SHOTS"; TEST_RUNNER_SHOTS_DIR="$SHOTS" step ui_run -only-testing:"BumperUITests/PlayerShots" -only-testing:"BumperUITests/SettingsShots" -only-testing:"BumperUITests/HomeShots" -only-testing:"BumperUITests/BookShots"; echo "shots: $SHOTS" ;;
  ui) CONFIG=Release; step build_for_testing; PERF_ITERATIONS="${PERF_ITERATIONS:-5}" step ui_run ;;
  bench) step scripts/benchmark.sh ;;
  seek) step scripts/seek-bench.sh ;;
  device) step scripts/device-validate.sh; step scripts/device-start-bench.sh; step scripts/device-seek-bench.sh; [[ -s TestMedia/long/manifest.json ]] && step scripts/device-resume-bench.sh ;;
  all) step fast; step perf; step unit; CONFIG=Release; step build_for_testing; PERF_ITERATIONS=5 step ui_run; step scripts/benchmark.sh ;;
  *) sed -n '2,14p' "$0"; exit 1 ;;
esac
