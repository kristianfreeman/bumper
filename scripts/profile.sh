#!/usr/bin/env bash
# Records an Instruments trace of the Release build browsing the mock server.
# Every hot path emits os_signpost intervals (Points of Interest), so the
# trace shows network → JSON → image decode → first frame on one timeline.
#
#   scripts/profile.sh                 # Time Profiler + Points of Interest, 30 s
#   TEMPLATE="Animation Hitches" scripts/profile.sh
set -euo pipefail
cd "$(dirname "$0")/.."

TEMPLATE="${TEMPLATE:-Time Profiler}"
DURATION="${DURATION:-30s}"
SIM_NAME="${SIM_NAME:-Apple TV 4K (3rd generation)}"
OUT="perf-results/trace-$(date +%Y%m%d-%H%M%S).trace"
mkdir -p perf-results

xcodebuild build -project Bumper.xcodeproj -scheme Bumper -configuration Release \
  -destination "platform=tvOS Simulator,name=$SIM_NAME" -derivedDataPath build/profile -quiet
APP=$(find build/profile/Build/Products/Release-appletvsimulator -maxdepth 1 -name '*.app' | head -1)
UDID=$(xcrun simctl list devices available | grep "$SIM_NAME (" | head -1 | grep -oE '[0-9A-F-]{36}')
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"

xcrun xctrace record --template "$TEMPLATE" --device "$UDID" --time-limit "$DURATION" --output "$OUT" \
  --launch -- "$APP" -mock -perfHUD
echo "Trace: $OUT"
open "$OUT"
