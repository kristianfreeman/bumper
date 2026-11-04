#!/usr/bin/env bash
# Every kind of file in the library on the real Apple TV, in one launch
# (`-sweep`): a few seconds each from a little way in, as a quiet Background
# play — the server is told nothing, nothing shows in Now Playing, nothing is
# remembered for the show. A line per file as it goes; the ones that didn't
# play gathered at the end.
#
#   scripts/device-sweep.sh                          the library's own pick
#   PICKS=<picks.json> scripts/device-sweep.sh       that list instead
#   EACH=2 FROM=40 SUBTITLES=1 scripts/device-sweep.sh   seconds each, carry on from, a subtitle on
#   AT=0.5 scripts/device-sweep.sh                   from halfway through each (deep resumes)
#
# Writes perf-results/sweep-<date>/{console.log,report.md}. Installs nothing
# unless BUILD=1.
set -uo pipefail
cd "$(dirname "$0")/.."
OUT="perf-results/sweep-$(date +%Y%m%d-%H%M%S)"; mkdir -p "$OUT"
source scripts/lib/device.sh
require_device
[[ -n "${BUILD:-}" ]] && build_and_install

# The list goes over as sweep-picks.json; an empty one has the app pick.
if [[ -n "${PICKS:-}" ]]; then cp "$PICKS" "$OUT/picks.json"; else echo "[]" > "$OUT/picks.json"; fi
dc device copy to --device "$DEVICE" --domain-type appDataContainer --domain-identifier "$BUNDLE" \
  --source "$OUT/picks.json" --destination Library/Caches/perf/sweep-picks.json >/dev/null 2>&1 \
  || { echo "couldn't copy the list to the TV (is the app installed?)"; exit 1; }

args=(-sweep -sweepSeconds "${EACH:-3}" -statsWindow 1 -traceStderr)
[[ -n "${FROM:-}" ]] && args+=(-sweepFrom "$FROM")
[[ -n "${SUBTITLES:-}" ]] && args+=(-sweepSubtitles)
[[ -n "${AT:-}" ]] && args+=(-sweepAt "$AT")
launch_app "${CAP:-14400}" "${args[@]}"

# The lines stream back through the launch's console (copying files off the
# TV hangs while it's busy decoding).
shown=0
while kill -0 "$LAUNCHER" 2>/dev/null; do
  sleep 2
  n=$(grep -c "\[sweep\]" "$OUT/console.log" 2>/dev/null)
  if (( n > shown )); then
    grep "\[sweep\]" "$OUT/console.log" | tail -n +$((shown + 1)) | sed -E 's/^ *[0-9.]+ \[sweep\] //' | cut -c1-200
    shown=$n
  fi
  grep -q "\[sweep\] done:" "$OUT/console.log" && break
done
kill "$LAUNCHER" 2>/dev/null; wait "$LAUNCHER" 2>/dev/null

{
  echo "# Playback sweep — $(date '+%Y-%m-%d %H:%M') — ${MODEL:-$DEVICE}"
  echo
  grep -E "\[sweep\] (done|[0-9]+ files)" "$OUT/console.log" | sed -E 's/^ *[0-9.]+ \[sweep\] /- /'
  echo
  echo "## Didn't play"
  echo
  grep -E "\[sweep\] [0-9]+/[0-9]+ " "$OUT/console.log" | grep -v " PLAYED " | sed -E 's/^ *[0-9.]+ \[sweep\] /- /'
} > "$OUT/report.md"
echo "report: $OUT/report.md"
