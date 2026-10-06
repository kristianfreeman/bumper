#!/usr/bin/env bash
# The playback matrix on real files: the app (signed in on the Apple TV)
# picks one item for each kind of file in the library (`-libraryMatrix`),
# then each plays ~12 s from a couple of minutes in, as Background — which
# tells the server nothing (no progress, nothing marked watched).
#
#   scripts/device-library-matrix.sh            pick, then play every kind
#   PICKS=<library-matrix.json> scripts/device-library-matrix.sh   reuse a pick
#
# Writes perf-results/library-matrix-<date>/report.md.
set -uo pipefail
cd "$(dirname "$0")/.."
OUT="perf-results/library-matrix-$(date +%Y%m%d-%H%M%S)"; mkdir -p "$OUT"
source scripts/lib/device.sh
require_device
[[ -n "${SKIP_BUILD:-}" ]] || build_and_install

if [[ -n "${PICKS:-}" ]]; then cp "$PICKS" "$OUT/picks.json"; else
  echo "picking one item per kind of file…"
  launch_app 240 -libraryMatrix
  for _ in $(seq 1 110); do
    sleep 2
    pull Library/Caches/perf/library-matrix.json "$OUT/picks.json" && break
  done
  kill "$LAUNCHER" 2>/dev/null; wait "$LAUNCHER" 2>/dev/null
fi
[[ -s "$OUT/picks.json" ]] || { echo "no picks (is the TV signed in?)"; exit 1; }
# The clip matrix's report reads a manifest: one entry per pick.
python3 - "$OUT" <<'PY'
import json, sys
out = sys.argv[1]
picks = json.load(open(f"{out}/picks.json"))
json.dump([{"file": p["id"], "name": f'{p["kind"]} — {p["name"]}', "duration": 40, "video": {"fps": round(p["fps"], 3)}} for p in picks],
          open(f"{out}/manifest.json", "w"), indent=1)
print(f"{len(picks)} kinds of file")
PY
COUNT=$(python3 -c "import json;print(len(json.load(open('$OUT/picks.json'))))")

for i in $(seq 0 $((COUNT - 1))); do
  id=$(python3 -c "import json;print(json.load(open('$OUT/picks.json'))[$i]['id'])")
  start=$(python3 -c "import json;p=json.load(open('$OUT/picks.json'))[$i];print(int(min(120, p['seconds'] * 0.3)))")
  name=$(python3 -c "import json;print(json.load(open('$OUT/manifest.json'))[$i]['name'][:70])")
  printf '▶ %-3s %-72s' "$i" "$name"
  subs=$(python3 -c "import json;print(json.load(open('$OUT/picks.json'))[$i].get('subtitles',''))")
  launch_app 75 -autoplay "$id" -autoplayBackground -statsWindow 4 -startAt "$start" ${subs:+-autoplaySubtitles "$subs"}
  trace="$OUT/trace-$i.log"; result=TIMEOUT
  for _ in $(seq 1 40); do
    sleep 1
    if pull Library/Caches/perf/trace.log "$trace" && grep -q -- "-autoplay $id " "$trace"; then
      grep -qE "Playback failed|could not play" "$trace" && { result=FAILED; break; }
      [[ $(grep -cE "\[(vlc|native)\] [0-9]+ s:" "$trace") -ge 3 ]] && { result=MEASURED; break; }
    fi
    kill -0 "$LAUNCHER" 2>/dev/null || { result=EXITED; break; }
  done
  kill "$LAUNCHER" 2>/dev/null; wait "$LAUNCHER" 2>/dev/null
  echo " $result"
  echo "$result" > "$OUT/result-$i.txt"
done
python3 scripts/matrix-report.py "$OUT/manifest.json" "$OUT"
echo "report: $OUT/report.md"
