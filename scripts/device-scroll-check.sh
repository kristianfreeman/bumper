#!/usr/bin/env bash
# Fast scrolling on the real Apple TV: presses Down 24 times as fast as the
# remote API allows (then Up), on Home and on a collection page, and reads the
# app's focus trace for pull-backs (focus moving against the presses) and
# dropped presses. The simulator's GPU hides this; the A10X doesn't.
#
#   scripts/device-scroll-check.sh [testRapidDownOnHome|testRapidDownOnACollectionPage]
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/device.sh
require_device
OUT="perf-results/scroll-$(date +%Y%m%d-%H%M%S)"; mkdir -p "$OUT"
tests=("${1:-testRapidDownOnHome}")
[[ $# -eq 0 ]] && tests=(testRapidDownOnHome testRapidDownOnACollectionPage)
for t in "${tests[@]}"; do
  echo "== $t"
  scripts/with-timeout.sh 600 xcodebuild test -project Bumper.xcodeproj -scheme Bumper -destination "id=$DEVICE" \
    -derivedDataPath build/device-ui -allowProvisioningUpdates -only-testing:"BumperUITests/RapidScrollTests/$t" >"$OUT/$t.log" 2>&1 \
    || { echo "test run failed (see $OUT/$t.log)"; grep -m3 "error:" "$OUT/$t.log" || true; }
  pull Library/Caches/perf/trace.log "$OUT/$t-trace.log"
  python3 - "$OUT/$t-trace.log" <<'PY'
import re, sys
lines = open(sys.argv[1]).read().splitlines()
events = []
for l in lines:
    m = re.match(r'\s*([\d.]+) \[(press|focus\*)\] (.*)', l)
    if not m: continue
    t, kind, rest = float(m[1]), m[2], m[3]
    if kind == 'press': events.append((t, 'press', rest.strip()))
    else:
        f = re.search(r"'(.*)' (-?\d+),(-?\d+) (\d+)x(\d+)", rest)
        if f: events.append((t, 'focus', (f[1][:40], int(f[2]), int(f[3]))))
presses = [e for e in events if e[1] == 'press']
downs = sum(1 for e in presses if e[2] == 'down'); ups = sum(1 for e in presses if e[2] == 'up')
direction, pullbacks, focus_moves, last_y = None, [], 0, None
for t, kind, v in events:
    if kind == 'press': direction = v; continue
    label, x, y = v
    if last_y is not None and direction in ('down', 'up'):
        if (direction == 'down' and y < last_y - 40) or (direction == 'up' and y > last_y + 40):
            pullbacks.append(f"{t:.2f}s pressing {direction}: y {last_y} -> {y} ({label})")
    focus_moves += 1
    last_y = y
print(f"presses: {downs} down, {ups} up; focus moves: {focus_moves}")
print(f"pull-backs: {len(pullbacks)}")
for p in pullbacks[:12]: print("  " + p)
PY
done
echo "trace: $OUT"
