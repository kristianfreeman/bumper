#!/usr/bin/env bash
# The playback matrix on the real Apple TV: every clip in TestMedia/matrix
# (scripts/make-matrix-media.sh), streamed from this Mac, played ~12 s (4-s windows).
# Per clip: the engine and method chosen, why, time to first frame, and the
# frames shown, dropped and late per second — against the clip's own rate.
#
#   scripts/device-matrix.sh [clip-index ...]
#
# Writes perf-results/matrix-<date>/{report.md,results.json}; ~20 s a clip.
set -uo pipefail
cd "$(dirname "$0")/.."
OUT="perf-results/matrix-$(date +%Y%m%d-%H%M%S)"; mkdir -p "$OUT"
source scripts/lib/device.sh
require_device
MEDIA=TestMedia/matrix
[[ -s "$MEDIA/manifest.json" ]] || { echo "no clips: run scripts/make-matrix-media.sh"; exit 1; }
COUNT=$(python3 -c "import json;print(len(json.load(open('$MEDIA/manifest.json'))))")
CLIPS="${*:-$(seq 0 $((COUNT - 1)))}"
[[ -n "${SKIP_BUILD:-}" ]] || build_and_install
start_media_server "$MEDIA" 8097
echo "$COUNT clips streamed from $MEDIA_URL → $OUT"

for i in $CLIPS; do
  name=$(python3 -c "import json;print(json.load(open('$MEDIA/manifest.json'))[$i]['name'])")
  printf '▶ %-3s %-60s' "$i" "$name"
  launch_app 75 -mock -mockHTTP -mockMediaURL "$MEDIA_URL" -autoplay "media-$i" -statsWindow 4
  trace="$OUT/trace-$i.log"; result=TIMEOUT
  for _ in $(seq 1 40); do
    sleep 1
    if pull Library/Caches/perf/trace.log "$trace" && grep -q -- "-autoplay media-$i\b" "$trace"; then
      grep -qE "Playback failed|could not play" "$trace" && { result=FAILED; break; }
      [[ $(grep -cE "\[(vlc|native)\] [0-9]+ s:" "$trace") -ge 3 ]] && { result=MEASURED; break; }
      grep -q "Finished item" "$trace" && { result=ENDED; break; }
    fi
    kill -0 "$LAUNCHER" 2>/dev/null || { result=EXITED; break; }
  done
  kill "$LAUNCHER" 2>/dev/null; wait "$LAUNCHER" 2>/dev/null
  echo " $result"
  echo "$result" > "$OUT/result-$i.txt"
done

python3 scripts/matrix-report.py "$MEDIA/manifest.json" "$OUT" $CLIPS
echo "report: $OUT/report.md"
