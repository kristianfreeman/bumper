#!/usr/bin/env bash
# Press Play → picture moving, on the real Apple TV, per clip: "prepared" (the detail
# page's Play button had focus for a few seconds, so the item was opened and
# buffered ahead) vs "cold" (-noPrepare). Compared against
# perf-baselines/device-start-<model>.json.
#
#   scripts/device-start-bench.sh [clip-index ...]    default: every TestMedia clip; ACCEPT=1 to re-baseline
set -uo pipefail
cd "$(dirname "$0")/.."
OUT="perf-results/device-start-$(date +%Y%m%d-%H%M%S)"; mkdir -p "$OUT"
source scripts/lib/device.sh
require_device
MEDIA=TestMedia
COUNT=$(python3 -c "import json;print(len(json.load(open('$MEDIA/manifest.json'))))")
CLIPS="${*:-$(seq 0 $((COUNT - 1)))}"
build_and_install
start_media_server "$MEDIA" 8099
echo '{}' > "$OUT/results.json"
fail=0
measure() {   # measure <clip> <mode> <extra args…> → echoes "<tap-ms>" or "?"
  local i="$1" mode="$2"; shift 2
  launch_app 40 -mock -mockHTTP -mockMediaURL "$MEDIA_URL" -route "item:media-$i" -autoplay "media-$i" -autoplayAfter 4 -traceFile "$@"
  local trace="$OUT/trace-$i-$mode.log" ms="?"
  for _ in $(seq 1 15); do
    sleep 2
    if pull Library/Caches/perf/trace.log "$trace" && grep -q -- "-autoplay media-$i " "$trace"; then
      ms=$(grep -oE 'Tap → moving in [0-9]+' "$trace" | head -1 | grep -oE '[0-9]+$') && [[ -n "$ms" ]] && break
      grep -q "Playback failed" "$trace" && break
    fi
  done
  kill "$LAUNCHER" 2>/dev/null; wait "$LAUNCHER" 2>/dev/null
  echo "${ms:-?}"
}
printf '%-46s %10s %10s\n' "clip" "prepared" "cold"
for i in $CLIPS; do
  name=$(python3 -c "import json;print(json.load(open('$MEDIA/manifest.json'))[$i]['name'])")
  warm=$(measure "$i" prepared)
  cold=$(measure "$i" cold -noPrepare)
  note=""; grep -q "prepared media-$i" "$OUT/trace-$i-prepared.log" 2>/dev/null || note="  (not prepared: AVPlayer item)"
  printf '%-46s %8s ms %8s ms%s\n' "${name:0:46}" "$warm" "$cold" "$note"
  [[ "$warm" =~ ^[0-9]+$ && "$cold" =~ ^[0-9]+$ ]] || fail=1
  python3 -c "
import json,sys; p='$OUT/results.json'; d=json.load(open(p))
for k,v in (('playback.tapToMoving.prepared','$warm'),('playback.tapToMoving.cold','$cold')):
    if v.isdigit(): d.setdefault('clip$i',{})[k]={'p50':float(v),'p95':float(v),'max':float(v),'last':float(v),'count':1}
json.dump(d,open(p,'w'))"
done
[[ $fail == 0 ]] && { PERF_NOISE="${PERF_NOISE:-3}" python3 scripts/perf-compare.py "device-start-${MODEL:-device}" "$OUT/results.json" ${ACCEPT:+--accept} || fail=1; }
echo "results: $OUT"
exit $fail
