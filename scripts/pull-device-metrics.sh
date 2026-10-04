#!/usr/bin/env bash
# Copies the app's performance snapshots off a device or simulator — no root,
# no Instruments. The app writes them to Library/Caches/perf/ (PerfRecorder).
#
#   scripts/pull-device-metrics.sh                   # first paired physical Apple TV
#   scripts/pull-device-metrics.sh <device-udid>
#   scripts/pull-device-metrics.sh --sim [udid]      # booted simulator
set -euo pipefail
cd "$(dirname "$0")/.."
BUNDLE=com.kristianfreeman.bumper
OUT="perf-results/device-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"

if [[ "${1:-}" == "--sim" ]]; then
  udid="${2:-booted}"
  container=$(xcrun simctl get_app_container "$udid" "$BUNDLE" data)
  cp "$container"/Library/Caches/perf/*.json "$OUT"/ 2>/dev/null || { echo "no snapshots yet (launch the app first)"; exit 1; }
else
  udid="${1:-$(xcrun devicectl list devices 2>/dev/null | awk '/physical/ && /connected/ {print $3; exit}')}"
  [[ -n "$udid" ]] || { echo "no connected device"; exit 1; }
  scripts/with-timeout.sh 30 xcrun devicectl device copy from --device "$udid" \
    --domain-type appDataContainer --domain-identifier "$BUNDLE" \
    --source Library/Caches/perf --destination "$OUT" >/dev/null
fi

python3 - "$OUT" <<'PY'
import json, glob, os, sys
files = sorted(glob.glob(os.path.join(sys.argv[1], "*.json")), key=os.path.getmtime)
if not files: sys.exit("no snapshots copied")
s = json.load(open(os.path.join(sys.argv[1], "latest.json")) if os.path.exists(os.path.join(sys.argv[1], "latest.json")) else open(files[-1]))
print(f"{s['device']} · {s['os']} · app {s['app']}")
for k in ["launch.firstContent", "home.load", "detail.load", "image.decode", "ui.hitchRatio", "playback.ttff", "playback.seek", "engine.droppedFrames"]:
    v = s["metrics"].get(k)
    if v: print(f"  {k:22} n={v['count']:4}  p50={v['p50']:8.1f}  p95={v['p95']:8.1f}  max={v['max']:8.1f}")
print("  budget failures:", ", ".join(s["budgetFailures"]) or "none")
print(f"  ({len(files)} files in {sys.argv[1]})")
PY
