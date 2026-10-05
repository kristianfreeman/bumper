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
  scripts/with-timeout.sh 600 xcodebuild test -project "${PROJECT:-Bumper.xcodeproj}" -scheme Bumper -destination "id=$DEVICE" \
    -derivedDataPath build/device-ui -allowProvisioningUpdates -only-testing:"BumperUITests/RapidScrollTests/$t" >"$OUT/$t.log" 2>&1 \
    || { echo "test run failed (see $OUT/$t.log)"; grep -m3 "error:" "$OUT/$t.log" || true; }
  if grep -q "System is asleep" "$OUT/$t.log"; then echo "the Apple TV is asleep: press a button on its remote, then run this again"; exit 1; fi
  pull Library/Caches/perf/trace.log "$OUT/$t-trace.log"
  pull Library/Caches/perf/metrics.json "$OUT/$t-metrics.json" && python3 - "$OUT/$t-metrics.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for k in ["ui.frameTime", "ui.hitchRatio", "image.decode", "image.blurhash"]:
    if k in d: v = d[k]; print("%-15s n=%5d  p50=%6.1f  p95=%6.1f  max=%6.1f" % (k, v["count"], v["p50"], v["p95"], v["max"]))
PY
  # Pull-backs from the focus positions alone: the test presses Down, then
  # Up, so focus should only move down until its lowest point and only up
  # after it. (UI-test presses don't reach the app's press log on device.)
  python3 - "$OUT/$t-trace.log" <<'PY'
import re, sys
pts = []
for l in open(sys.argv[1]):
    m = re.match(r"\s*([\d.]+) \[focus\*\] (\S+) '(.*)' (-?\d+),(-?\d+) (\d+)x(\d+)", l)
    if m and m[2] != 'none' and int(m[7]) > 150:            # cards, not the sidebar's tab button
        pts.append((float(m[1]), m[3][:40], int(m[5])))
if len(pts) < 2: print("too few focus moves to judge"); sys.exit()
ys = [p[2] for p in pts]
turn = ys.index(max(ys))
backs = [(a, b) for a, b in zip(pts[:turn + 1], pts[1:turn + 1]) if b[2] < a[2] - 40] + \
        [(a, b) for a, b in zip(pts[turn:], pts[turn + 1:]) if b[2] > a[2] + 40]
gaps = sorted(b[0] - a[0] for a, b in zip(pts, pts[1:]))
print(f"focus moves: {turn} down, {len(pts) - 1 - turn} up; median {gaps[len(gaps) // 2] * 1000:.0f} ms apart")
print(f"pull-backs: {len(backs)}")
for a, b in backs[:12]: print(f"  {a[0]:.2f}s y {a[2]} -> {b[0]:.2f}s y {b[2]} ({b[1]})")
PY
done
echo "trace: $OUT"
