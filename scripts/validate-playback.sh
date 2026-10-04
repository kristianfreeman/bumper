#!/usr/bin/env bash
# Plays every clip in TestMedia/ through the real app on a tvOS simulator — over
# a real loopback HTTP server (-mockHTTP), so AVPlayer is exercised too — and
# reports per clip: backend chosen (and any AVPlayer → VLCKit fallback),
# time-to-first-frame, end position.
#
# Fast: 5 s clips, each hard-capped at clip+5 s. The app is polled every second. A crash is reported immediately
# with the top stack frames from the crash report (no waiting out a timeout).
#
#   scripts/make-test-media.sh && scripts/validate-playback.sh [clip-index ...]
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIM_NAME="${SIM_NAME:-Apple TV 4K (3rd generation)}"
UDID="${UDID:-$(xcrun simctl list devices available | grep "$SIM_NAME (" | grep -v 1080p | tail -1 | grep -oE '[0-9A-F-]{36}')}"
BUNDLE=com.kristianfreeman.bumper
MANIFEST="$ROOT/TestMedia/manifest.json"
REPORTS="$HOME/Library/Logs/DiagnosticReports"

# Leave the simulator clean however we exit (Ctrl-C included).
trap 'xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true; pkill -P $$ 2>/dev/null || true' EXIT

COUNT=$(python3 -c "import json;print(len(json.load(open('$MANIFEST'))))")
INDICES=${*:-$(seq 0 $((COUNT - 1)))}
fail=0
RESULTS=$(mktemp)          # clip → {playback.ttff} for regression tracking
echo '{}' > "$RESULTS"

newest_crash() { ls -t "$REPORTS"/Bumper*.ips 2>/dev/null | head -1; }
crash_frames() {
  python3 - "$1" <<'EOF'
import json, sys
d = json.loads(open(sys.argv[1]).read().split('\n', 1)[1])
exc = d.get('exception', {})
print(f"          crash:  {exc.get('type')} {d.get('termination', {}).get('indicator', '')}")
imgs = d['usedImages']
for t in d['threads']:
    if t.get('triggered'):
        frames = [f for f in t['frames'] if imgs[f.get('imageIndex', 0)]['name'].startswith('Bumper')][:5]
        for f in frames:
            loc = f"{f.get('sourceFile', '')}:{f.get('sourceLine', '')}" if f.get('sourceFile') else ''
            print(f"            at {f.get('symbol', '?')[:90]} {loc}")
EOF
}

for i in $INDICES; do
  name=$(python3 -c "import json;print(json.load(open('$MANIFEST'))[$i]['name'])")
  duration=$(python3 -c "import json;print(int(json.load(open('$MANIFEST'))[$i]['duration']))")
  echo "▶ [$i] $name"
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1
  # terminate returns before the process exits; wait until the old instance
  # (and its listening socket on :8097) is actually gone.
  for _ in $(seq 1 50); do lsof -nP -iTCP:8097 -sTCP:LISTEN >/dev/null 2>&1 || break; sleep 0.1; done
  before=$(newest_crash)
  # One log stream per clip, started *before* launch so nothing is missed;
  # lines are attributed by the exact PID simctl hands back.
  LOG=$(mktemp)
  xcrun simctl spawn "$UDID" log stream --level info --style compact \
    --predicate 'process == "Bumper" AND subsystem == "com.kristianfreeman.bumper"' >"$LOG" 2>/dev/null &
  STREAM=$!
  sleep 0.5
  start=$(date +%s)
  out=$(xcrun simctl launch "$UDID" "$BUNDLE" -mock -mockHTTP -mockMedia "$ROOT/TestMedia" -autoplay "media-$i")
  pid=${out##* }
  result="TIMEOUT"; logs=""; crash=""
  while (( $(date +%s) - start < duration + 5 )); do
    sleep 1
    logs=$(grep "\[$pid:" "$LOG" || true)
    if grep -q 'Finished item' <<<"$logs"; then result="OK"; break; fi
    if grep -q 'Playback failed' <<<"$logs"; then result="FAILED"; break; fi
    if ! kill -0 "$pid" 2>/dev/null; then
      sleep 2; crash=$(newest_crash)                  # reports land a moment after death
      [[ "$crash" != "$before" ]] && result="CRASH" || result="EXITED"
      break
    fi
  done
  kill "$STREAM" 2>/dev/null
  if [[ "$result" != OK ]]; then
    echo "          last app log lines (pid $pid):"
    grep "\[$pid:" "$LOG" | tail -4 | cut -c 60-230 | sed 's/^/            /'
    [[ -s "$LOG" ]] || echo "            (log stream captured nothing)"
    echo "          pids seen in log: $(grep -oE 'Bumper\[[0-9]+' "$LOG" | sort -u | tr '\n' ' ')"
  fi
  rm -f "$LOG"
  plan=$(grep -o 'Plan: .*' <<<"$logs" | head -1 | cut -c7-)
  switched=$(grep -o 'AVPlayer → VLCKit.*' <<<"$logs" | head -1)
  ttff=$(grep -oiE 'first frame in [0-9.]+' <<<"$logs" | head -1 | grep -oE '[0-9.]+$')
  ended=$(grep -oE 'Finished item at [0-9.]+' <<<"$logs" | head -1 | grep -oE '[0-9.]+$')
  printf '  %-7s plan:   %s\n          ttff:   %s ms   ended at: %ss of %ss\n' \
    "$result" "${plan:-—}" "${ttff:-?}" "${ended:-?}" "$duration"
  [[ -n "$switched" ]] && echo "          fallback: $switched"
  [[ "$result" == CRASH ]] && crash_frames "$crash"
  if [[ "$result" == OK && -n "${ttff:-}" ]]; then
    python3 - "$RESULTS" "$i" "$ttff" <<'PY'
import json, sys
p, clip, ttff = sys.argv[1], sys.argv[2], float(sys.argv[3])
d = json.load(open(p)); d[f"clip{clip}"] = {"playback.ttff": {"p50": ttff, "p95": ttff, "max": ttff, "last": ttff, "count": 1}}
json.dump(d, open(p, "w"))
PY
  fi
  [[ "$result" == OK ]] || fail=1
done
echo "DONE ($([[ $fail == 0 ]] && echo 'all passed' || echo 'FAILURES'))"
# Time-to-first-frame must not regress per clip (only on full runs).
if [[ $# -eq 0 && $fail == 0 ]]; then
  python3 "$ROOT/scripts/perf-compare.py" "playback-${SIM_TAG:-tvos27}" "$RESULTS" ${ACCEPT:+--accept} || fail=1
fi
exit $fail
