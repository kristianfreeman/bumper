#!/usr/bin/env bash
# One item on the Apple TV, as Background (the server is told nothing):
# when it started, then frames shown/dropped/late in 4-s windows. For
# trying a fix on a real file in seconds.
#
#   scripts/device-try.sh <item id> [start seconds] [extra app arguments…]
#   e.g. scripts/device-try.sh 42d33794… 120 -vlcMediaOptions ":demux=avi"
set -uo pipefail
cd "$(dirname "$0")/.."
OUT="perf-results/try-$(date +%Y%m%d-%H%M%S)"; mkdir -p "$OUT"
source scripts/lib/device.sh
require_device
id="$1"; start="${2:-120}"; shift $(( $# >= 2 ? 2 : 1 ))
# The trace streams back through the launch's console (no file copies: those
# hang while the TV is busy decoding).
launch_app 60 -autoplay "$id" -autoplayBackground -statsWindow 4 -startAt "$start" -traceStderr "$@"
log="$OUT/console.log"
for _ in $(seq 1 40); do
  sleep 1
  grep -qE "Playback failed" "$log" && break
  [[ $(grep -cE "\] [0-9]+ s:" "$log") -ge 3 ]] && break
done
kill "$LAUNCHER" 2>/dev/null; wait "$LAUNCHER" 2>/dev/null
grep -E "Plan:|Tap → moving|\] [0-9]+ s:|Playback failed" "$log" | cut -c1-150
