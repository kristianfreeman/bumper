#!/usr/bin/env bash
# Frame timing while flicking through Home and a collection page on a real
# iPhone (ProMotion: a 120 Hz frame is 8.3 ms). The `-mock` profile: the
# real sign-in is never touched. Reinstall your own build afterwards.
#
#   DEVICE=<iPhone udid> scripts/phone-scroll-check.sh [testFlickHome|testFlickACollectionPage]
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/device.sh
DEVICE="${PHONE:-${DEVICE:-}}"
[[ -n "$DEVICE" ]] || { echo "set DEVICE (or PHONE) to the iPhone's udid (xcrun devicectl list devices)"; exit 1; }
OUT="perf-results/phone-scroll-$(date +%Y%m%d-%H%M%S)"; mkdir -p "$OUT"
tests=("${1:-testFlickHome}")
[[ $# -eq 0 ]] && tests=(testFlickHome testFlickACollectionPage)
for t in "${tests[@]}"; do
  echo "== $t"
  scripts/with-timeout.sh 600 xcodebuild test -project Bumper.xcodeproj -scheme BumperPhone -destination "id=$DEVICE" \
    -derivedDataPath build/phone-ui -allowProvisioningUpdates -only-testing:"BumperPhoneUITests/PhoneScrollTests/$t" >"$OUT/$t.log" 2>&1 \
    || { echo "test run failed (see $OUT/$t.log)"; grep -m3 "error:" "$OUT/$t.log" || true; }
  pull Library/Caches/perf/metrics.json "$OUT/$t-metrics.json" && python3 - "$OUT/$t-metrics.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for k in ["ui.frameTime", "ui.hitchRatio", "image.decode"]:
    if k in d: v = d[k]; print("%-15s n=%5d  p50=%6.1f  p95=%6.1f  max=%6.1f" % (k, v["count"], v["p50"], v["p95"], v["max"]))
if "ui.frameTime" not in d: print("no frames scored")
PY
done
echo "results: $OUT"
