#!/usr/bin/env bash
# Audiobooks on the real Apple TV: TestMedia/books streamed from this Mac,
# decoded and played in-app. Reports press → first sound (start and a
# resume), Smart Speed's savings, and any pipeline error.
#   scripts/device-audiobook-check.sh        (needs scripts/make-audiobook-media.sh)
set -uo pipefail
cd "$(dirname "$0")/.."
OUT="perf-results/device-audiobook-$(date +%Y%m%d-%H%M%S)"; mkdir -p "$OUT"
source scripts/lib/device.sh
require_device
[[ -s TestMedia/books/manifest.json ]] || { echo "no TestMedia/books — run scripts/make-audiobook-media.sh"; exit 1; }
[[ -n "${NO_INSTALL:-}" ]] || build_and_install
start_media_server TestMedia/books 8096
fail=0
for start in 0 30; do
  launch_app 60 -mock -mockHTTP -mockBooksURL "$MEDIA_URL" -reset -autoplay book-0 -startAt "$start"
  trace="$OUT/trace-$start.log"
  for _ in $(seq 1 10); do
    sleep 2
    pull Library/Caches/perf/trace.log "$trace" && grep -q "first sound\|error" "$trace" && break
  done
  sleep 1; pull Library/Caches/perf/trace.log "$trace"
  kill "$LAUNCHER" 2>/dev/null; wait "$LAUNCHER" 2>/dev/null
  line=$(grep -E "first sound|audiobook\] error" "$trace" | head -1)
  echo "start ${start}s: ${line:-no sound — see $trace}"
  grep -q "first sound" "$trace" || fail=1
done
echo "results: $OUT"
exit $fail
