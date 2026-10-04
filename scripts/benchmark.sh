#!/usr/bin/env bash
# Harness-free smoothness benchmark: a Release build scrolls itself through
# every home shelf (down and back, 3×) with the hitch monitor scoring frames.
# No XCUITest in the loop, so the numbers are the app's alone.
set -euo pipefail
cd "$(dirname "$0")/.."
SIM_NAME="${SIM_NAME:-Apple TV 4K (3rd generation)}"
UDID="${UDID:-$(xcrun simctl list devices available | grep "$SIM_NAME (" | grep -v 1080p | tail -1 | grep -oE '[0-9A-F-]{36}')}"
DD="${DD:-build/test/app}"

# Leave the simulator clean however we exit (Ctrl-C included).
trap 'xcrun simctl terminate "${UDID:-booted}" app.jellyfinapp.tv >/dev/null 2>&1 || true' EXIT

scripts/with-timeout.sh 300 xcodebuild -project JellyfinApp.xcodeproj -scheme JellyfinApp -configuration Release \
  -destination "platform=tvOS Simulator,id=$UDID" -derivedDataPath "$DD" build -quiet
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl terminate "$UDID" app.jellyfinapp.tv 2>/dev/null || true
xcrun simctl install "$UDID" "$DD/Build/Products/Release-appletvsimulator/JellyfinApp.app"
CONTAINER=$(xcrun simctl get_app_container "$UDID" app.jellyfinapp.tv data)
OUT="$CONTAINER/Library/Caches/perf/benchmark.json"
rm -f "$OUT"
xcrun simctl launch "$UDID" app.jellyfinapp.tv -mock -reset -benchmark >/dev/null

# The app writes its metrics snapshot to a file when the scroll pass ends
# (os_log would truncate it).
for _ in $(seq 1 40); do [[ -s "$OUT" ]] && break; sleep 0.5; done
[[ -s "$OUT" ]] || { echo "benchmark produced no result"; exit 1; }
line="BENCHMARK $(cat "$OUT")"
mkdir -p perf-results
RESULT="perf-results/benchmark-$(date +%Y%m%d-%H%M%S).json"
echo "${line#BENCHMARK }" > "$RESULT"
echo "${line#BENCHMARK }" | python3 -c '
import json, sys
d = json.load(sys.stdin)
for k in ["ui.hitchRatio", "ui.frameTime", "image.decode", "image.blurhash", "image.fetch", "api.decode"]:
    if k in d:
        v = d[k]
        print("%-16s n=%5d  p50=%7.2f  p95=%7.2f  max=%7.2f" % (k, v["count"], v["p50"], v["p95"], v["max"]))
'
# Fail if the app-wide hitch ratio blows its budget (Apple: < 5 ms/s is good).
echo "${line#BENCHMARK }" | python3 -c '
import json, sys
v = json.load(sys.stdin).get("ui.hitchRatio", {}).get("last")
if v is None: sys.exit("no hitch data")
print("hitch ratio: %.2f ms/s (budget < 5)" % v)
sys.exit(0 if v < 5 else 1)
'
# …and must not regress vs the accepted baseline (ACCEPT=1 to re-baseline).
python3 scripts/perf-compare.py benchmark "$RESULT" ${ACCEPT:+--accept}
