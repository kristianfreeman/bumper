#!/usr/bin/env bash
# Resume (start mid-file) on the real Apple TV: a 20-minute MKV started at
# several positions — time to picture moving, and where playback really began.
# A start that scales with the position means the demuxer is reading up to it.
#
#   scripts/device-resume-bench.sh [seconds ...]     default: 0 300 900
#   (needs TestMedia/long — scripts/make-long-media.sh)
set -uo pipefail
cd "$(dirname "$0")/.."
OUT="perf-results/device-resume-$(date +%Y%m%d-%H%M%S)"; mkdir -p "$OUT"
source scripts/lib/device.sh
require_device
MEDIA=TestMedia/long
[[ -s $MEDIA/manifest.json ]] || { echo "no $MEDIA — run scripts/make-long-media.sh"; exit 1; }
POSITIONS="${*:-0 300 900}"
[[ -n "${NO_INSTALL:-}" ]] || build_and_install
start_media_server "$MEDIA" 8097
fail=0
printf '%8s %12s %16s\n' "start" "tap→moving" "playing from"
for pos in $POSITIONS; do
  extra=(); [[ -n "${VLC_OPTS:-}" ]] && extra+=(-vlcMediaOptions "$VLC_OPTS")
  launch_app 60 -mock -mockHTTP -mockMediaURL "$MEDIA_URL" -autoplay media-0 -startAt "$pos" -vlcLog ${extra[@]+"${extra[@]}"}
  trace="$OUT/trace-$pos.log"; ms="?"; from="?"
  for _ in $(seq 1 20); do
    sleep 2
    if pull Library/Caches/perf/trace.log "$trace" && grep -q -- "-startAt $pos" "$trace"; then
      ms=$(grep -oE 'Tap → moving in [0-9]+' "$trace" | head -1 | grep -oE '[0-9]+$') && [[ -n "$ms" ]] && break
      grep -q "Playback failed" "$trace" && { ms="failed"; break; }
    fi
  done
  sleep 3                                                    # let the playhead settle
  pull Library/Caches/perf/trace.log "$trace"; pull Library/Caches/perf/vlc.log "$OUT/vlc-$pos.log"
  kill "$LAUNCHER" 2>/dev/null; wait "$LAUNCHER" 2>/dev/null
  from=$(grep -oE 'state 3 at [0-9]+' "$trace" | tail -1 | grep -oE '[0-9]+$')
  printf '%7ss %10s ms %14s\n' "$pos" "${ms:-?}" "${from:+$((from / 1000))s}"
  [[ "$ms" =~ ^[0-9]+$ ]] || fail=1
done
echo "results: $OUT"
exit $fail
