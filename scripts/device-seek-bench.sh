#!/usr/bin/env bash
# Seek benchmark on the real Apple TV: hardware decode, real audio output, the
# real network (clips stream from this Mac). Compares against
# perf-baselines/device-seek-<model>.json.
#
#   scripts/device-seek-bench.sh [clip-index ...]   default: 0 2 (MKV/VLCKit, MP4/AVPlayer)
#   VLCLOG=1 …                                     also capture VLC's own log per clip
#   VLC_OPTS=":some-option" …                      A/B a VLC media option
#   ACCEPT=1 …                                     accept results as the new baseline
set -uo pipefail
cd "$(dirname "$0")/.."
OUT="perf-results/device-seek-$(date +%Y%m%d-%H%M%S)"; mkdir -p "$OUT"
source scripts/lib/device.sh
require_device
MEDIA=TestMedia/seek
CLIPS="${*:-0 2}"
build_and_install
start_media_server "$MEDIA" 8098
echo "Clips streamed from $MEDIA_URL"
echo '{}' > "$OUT/results.json"
fail=0
for i in $CLIPS; do
  name=$(python3 -c "import json;print(json.load(open('$MEDIA/manifest.json'))[$i]['name'])")
  tag="$(date +%s)-$i"
  extra=(); [[ -n "${VLCLOG:-}" ]] && extra+=(-vlcLog); [[ -n "${VLC_OPTS:-}" ]] && extra+=(-vlcMediaOptions "$VLC_OPTS")
  launch_app 120 -mock -mockHTTP -mockMediaURL "$MEDIA_URL" -autoplay "media-$i" -seekBench -benchTag "$tag" -traceFile ${extra[@]+"${extra[@]}"}
  result="$OUT/seek-$i.json"
  for _ in $(seq 1 40); do                       # one clip ≈ 40–60 s on device
    sleep 3
    pull "Library/Caches/perf/seekbench-$tag.json" "$result" && break
    kill -0 "$LAUNCHER" 2>/dev/null || break
  done
  kill "$LAUNCHER" 2>/dev/null; wait "$LAUNCHER" 2>/dev/null
  pull Library/Caches/perf/trace.log "$OUT/trace-$i.log"; pull Library/Caches/perf/vlc.log "$OUT/vlc-$i.log"
  if [[ ! -s "$result" ]]; then
    echo "✘ [$i] $name: no result — last trace lines:"; tail -6 "$OUT/trace-$i.log" 2>/dev/null | sed 's/^/      /'
    fail=1; continue
  fi
  python3 - "$result" "$i" "$name" "$OUT/results.json" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1])); m = d["metrics"]
print(f"▶ [{sys.argv[2]}] {sys.argv[3]} — {d['engine']} · {d['video']}")
for kind in ["skip", "jump", "burst"]:
    r, dr, failed = m.get(f"seek.{kind}.resume"), m.get(f"seek.{kind}.dropped"), m.get(f"seek.{kind}.failed")
    fmt = lambda s: f"p50 {s['p50']:6.0f}  p95 {s['p95']:6.0f}  max {s['max']:6.0f} ms" if s else "      –"
    print(f"   {kind:6} resume {fmt(r)} │ dropped max {int(dr['max']) if dr else 0}" + (f"  ✘ {int(failed['last'])} never resumed" if failed else ""))
allr = json.load(open(sys.argv[4])); allr[f"clip{sys.argv[2]}"] = m; json.dump(allr, open(sys.argv[4], "w"), indent=1)
EOF
done
PERF_NOISE="${PERF_NOISE:-3}" python3 scripts/perf-compare.py "device-seek-${MODEL:-device}" "$OUT/results.json" ${ACCEPT:+--accept} || fail=1
echo "results: $OUT"
exit $fail
