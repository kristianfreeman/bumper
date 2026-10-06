#!/usr/bin/env bash
# The iPhone companion against the Apple TV app, both in simulators on this
# Mac (Bonjour works between them): one tap connects, Play on the phone
# starts on the TV, and the TV's live status (and play/pause) shows on the phone.
#   scripts/companion-check.sh
set -uo pipefail
cd "$(dirname "$0")/.."
OUT="perf-results/companion-$(date +%Y%m%d-%H%M%S)"; mkdir -p "$OUT"
# The newest available simulator with this name (no machine's ids in here).
sim_id() { xcrun simctl list devices available | grep -E "^    $1 \([0-9A-F-]{36}\)" | tail -1 | grep -oE '[0-9A-F-]{36}'; }
TV="${TV_SIM:-$(sim_id "Apple TV 4K \(3rd generation\)")}"
PHONE="${PHONE_SIM:-$(sim_id "iPhone 17 Pro")}"
BID=com.kristianfreeman.bumper
for d in "$TV" "$PHONE"; do xcrun simctl boot "$d" 2>/dev/null; done
echo "building…"
scripts/with-timeout.sh 400 xcodebuild build -project Bumper.xcodeproj -scheme Bumper -configuration Debug -destination "id=$TV" -derivedDataPath build/test/app -quiet >"$OUT/tv-build.log" 2>&1 || { echo "TV build failed ($OUT/tv-build.log)"; exit 1; }
scripts/with-timeout.sh 400 xcodebuild build-for-testing -project Bumper.xcodeproj -scheme BumperPhone -destination "id=$PHONE" -derivedDataPath build/test/companion -quiet >"$OUT/phone-build.log" 2>&1 || { echo "phone build failed ($OUT/phone-build.log)"; exit 1; }
xcrun simctl install "$TV" build/test/app/Build/Products/Debug-appletvsimulator/Bumper.app
xcrun simctl terminate "$TV" "$BID" 2>/dev/null
MEDIA="$PWD/TestMedia/long"
xcrun simctl launch "$TV" "$BID" -mock -mockHTTP -reset -mockMedia "$MEDIA" -route item:media-0 ${TV_ARGS:-} >/dev/null   # -mockHTTP: artwork the phone can load
sleep 4
TEST_RUNNER_EXPECT_TITLE="Long" TEST_RUNNER_MEDIA="$MEDIA" TEST_RUNNER_ITEM=media-0 TEST_RUNNER_SHOTS_DIR="$PWD/$OUT" scripts/with-timeout.sh 180 xcodebuild test-without-building -project Bumper.xcodeproj -scheme BumperPhone \
  -destination "id=$PHONE" -derivedDataPath build/test/companion -collect-test-diagnostics never \
  -only-testing:BumperPhoneUITests/CompanionTests >"$OUT/phone-test.log" 2>&1
grep -E "Test Case.*(passed|failed)|error:" "$OUT/phone-test.log" | cut -c1-220
C=$(xcrun simctl get_app_container "$TV" "$BID" data 2>/dev/null)
grep -E "companion|player" "$C/Library/Caches/perf/trace.log" 2>/dev/null | tail -8
echo "results: $OUT"
grep -q "Test Case.*passed" "$OUT/phone-test.log" && ! grep -q "Test Case.*failed" "$OUT/phone-test.log"
