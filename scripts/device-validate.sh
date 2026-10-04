#!/usr/bin/env bash
# Plays every TestMedia clip end to end on the real Apple TV and reports the
# backend chosen, time-to-first-frame and where it ended — the device version
# of validate-playback.sh. TTFF compared against
# perf-baselines/device-playback-<model>.json.
#
#   scripts/device-validate.sh [clip-index ...]    ACCEPT=1 to accept a new baseline
set -uo pipefail
cd "$(dirname "$0")/.."
OUT="perf-results/device-validate-$(date +%Y%m%d-%H%M%S)"; mkdir -p "$OUT"
source scripts/lib/device.sh
require_device
MEDIA=TestMedia
COUNT=$(python3 -c "import json;print(len(json.load(open('$MEDIA/manifest.json'))))")
CLIPS="${*:-$(seq 0 $((COUNT - 1)))}"
build_and_install
start_media_server "$MEDIA" 8099
echo "Clips streamed from $MEDIA_URL"
echo '{}' > "$OUT/results.json"
fail=0
for i in $CLIPS; do
  name=$(python3 -c "import json;print(json.load(open('$MEDIA/manifest.json'))[$i]['name'])")
  duration=$(python3 -c "import json;print(int(json.load(open('$MEDIA/manifest.json'))[$i]['duration']))")
  launch_app $((duration + 30)) -mock -mockHTTP -mockMediaURL "$MEDIA_URL" -autoplay "media-$i" -traceFile
  trace="$OUT/trace-$i.log"; result="TIMEOUT"
  for _ in $(seq 1 $(( (duration + 25) / 2 ))); do
    sleep 2
    if pull Library/Caches/perf/trace.log "$trace" && grep -q -- "-autoplay media-$i " "$trace"; then   # this launch's trace, not the last clip's
      grep -q "Finished item" "$trace" && { result=OK; break; }
      grep -qE "Playback failed|could not play" "$trace" && { result=FAILED; break; }
    fi
    kill -0 "$LAUNCHER" 2>/dev/null || { result=EXITED; break; }
  done
  kill "$LAUNCHER" 2>/dev/null; wait "$LAUNCHER" 2>/dev/null
  plan=$(grep -o 'Plan: [a-z]* [A-Za-z]* — [^—]*' "$trace" 2>/dev/null | head -1 | cut -c7-)
  ttff=$(grep -oE 'First frame in [0-9]+' "$trace" 2>/dev/null | head -1 | grep -oE '[0-9]+$')
  ended=$(grep -oE 'Finished item at [0-9.]+' "$trace" 2>/dev/null | head -1 | grep -oE '[0-9.]+$')
  switched=$(grep -o 'AVPlayer → VLCKit.*' "$trace" 2>/dev/null | head -1)
  echo "▶ [$i] $name"
  printf '  %-7s %s\n          ttff: %s ms   ended at: %ss of %ss\n' "$result" "${plan:-—}" "${ttff:-?}" "${ended:-?}" "$duration"
  [[ -n "$switched" ]] && echo "          fallback: $switched"
  [[ "$result" == OK ]] || { tail -4 "$trace" 2>/dev/null | sed 's/^/          │ /'; fail=1; }
  if [[ "$result" == OK && -n "$ttff" ]]; then
    python3 -c "
import json; p='$OUT/results.json'; d=json.load(open(p)); v=float('$ttff')
d['clip$i']={'playback.ttff':{'p50':v,'p95':v,'max':v,'last':v,'count':1}}; json.dump(d,open(p,'w'))"
  fi
done
echo "DONE ($([[ $fail == 0 ]] && echo 'all passed' || echo 'FAILURES'))"
[[ $# -eq 0 && $fail == 0 ]] && { PERF_NOISE="${PERF_NOISE:-3}" python3 scripts/perf-compare.py "device-playback-${MODEL:-device}" "$OUT/results.json" ${ACCEPT:+--accept} || fail=1; }
echo "results: $OUT"
exit $fail
