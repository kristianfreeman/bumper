#!/usr/bin/env bash
# Seek/skip speed benchmark on long clips (scripts/make-seek-media.sh), through
# the real app over loopback HTTP with simulated server latency.
#
#   scripts/seek-bench.sh               quick: MKV/VLCKit + MP4/AVPlayer, 20 ms server latency
#   EXTENSIVE=1 scripts/seek-bench.sh   every clip, at 0 ms and 25 ms latency
#   ACCEPT=1 …                          accept results as the new baseline
#
# Per move: frame = first frame at the new position ready; resume = playing
# again there; dropped = frames dropped in the second after (catch-up stutter).
set -uo pipefail
cd "$(dirname "$0")/.."
SIM_NAME="${SIM_NAME:-Apple TV 4K (3rd generation)}"
UDID="${UDID:-$(xcrun simctl list devices available | grep "$SIM_NAME (" | grep -v 1080p | tail -1 | grep -oE '[0-9A-F-]{36}')}"
BUNDLE=app.jellyfinapp.tv
MEDIA="${MEDIA:-$PWD/TestMedia/seek}"
[[ -f "$MEDIA/manifest.json" ]] || { echo "no seek media: run scripts/make-seek-media.sh"; exit 1; }
trap 'xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true' EXIT

if [[ -n "${EXTENSIVE:-}" ]]; then CLIPS="${CLIPS:-0 1 2 3}"; LATENCIES="${LATENCIES:-0 25}"; else CLIPS="${CLIPS:-0 2}"; LATENCIES="${LATENCIES:-20}"; fi

scripts/with-timeout.sh 300 xcodebuild -project JellyfinApp.xcodeproj -scheme JellyfinApp -configuration Release \
  -destination "platform=tvOS Simulator,id=$UDID" -derivedDataPath build/test/app build -quiet || { echo "BUILD FAILED"; exit 1; }
xcrun simctl install "$UDID" build/test/app/Build/Products/Release-appletvsimulator/JellyfinApp.app
CONTAINER=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)
OUT="$CONTAINER/Library/Caches/perf/seekbench.json"
mkdir -p perf-results
RESULT="perf-results/seek-$(date +%Y%m%d-%H%M%S).json"
echo '{}' > "$RESULT"
fail=0

for lat in $LATENCIES; do
  for i in $CLIPS; do
    name=$(python3 -c "import json;print(json.load(open('$MEDIA/manifest.json'))[$i]['name'])")
    xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1
    for _ in $(seq 1 50); do lsof -nP -iTCP:8097 -sTCP:LISTEN >/dev/null 2>&1 || break; sleep 0.1; done
    rm -f "$OUT"
    xcrun simctl launch "$UDID" "$BUNDLE" -mock -mockHTTP -mockMedia "$MEDIA" -autoplay "media-$i" -seekBench -mediaLatency "$lat" >/dev/null
    for _ in $(seq 1 120); do [[ -s "$OUT" ]] && break; sleep 0.5; done   # one clip ≈ 25 s
    if [[ ! -s "$OUT" ]]; then echo "✘ [$i] $name @ ${lat}ms: no result (hung?)"; fail=1; continue; fi
    python3 - "$OUT" "$RESULT" "$i" "$lat" "$name" <<'EOF'
import json, sys
out, result, i, lat, name = sys.argv[1:]
d = json.load(open(out))
m = d["metrics"]
print(f"▶ [{i}] {name} @ {lat} ms — {d['engine']} · {d['video']}")
for kind in ["skip", "jump", "burst"]:
    f, r, dr = m.get(f"seek.{kind}.frame"), m.get(f"seek.{kind}.resume"), m.get(f"seek.{kind}.dropped")
    fmt = lambda s: f"p50 {s['p50']:6.0f}  p95 {s['p95']:6.0f} ms" if s else "      –"
    failed = m.get(f"seek.{kind}.failed")
    print(f"   {kind:6} frame {fmt(f)} │ resume {fmt(r)} │ dropped max {int(dr['max']) if dr else 0}" + (f"  ✘ {int(failed['last'])} never resumed" if failed else ""))
all_ = json.load(open(result))
all_[f"clip{i}@{lat}ms"] = m
json.dump(all_, open(result, "w"), indent=1)
EOF
    grep -q '"seek\.[a-z]*\.failed"' "$OUT" && fail=1
  done
done
variant="seek${EXTENSIVE:+-extensive}"
python3 scripts/perf-compare.py "$variant" "$RESULT" ${ACCEPT:+--accept} || fail=1
exit $fail
