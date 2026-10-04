#!/usr/bin/env bash
# The iPhone companion against the Apple TV app, both in simulators on this
# Mac (Bonjour works between them): the phone finds the TV, shows what's
# focused on it, and adds it to Tonight.
#   scripts/companion-check.sh
set -uo pipefail
cd "$(dirname "$0")/.."
OUT="perf-results/companion-$(date +%Y%m%d-%H%M%S)"; mkdir -p "$OUT"
TV="${TV_SIM:-936FC8D0-431D-4F91-B80F-12BC89DDEFFA}"        # Apple TV 4K (3rd gen), tvOS 27
PHONE="${PHONE_SIM:-1A0FD3DB-4719-4459-9EC9-C0B989A6FFA1}"  # iPhone 17 Pro
BID=com.kristianfreeman.bumper
for d in "$TV" "$PHONE"; do xcrun simctl boot "$d" 2>/dev/null; done
echo "building…"
scripts/with-timeout.sh 400 xcodebuild build -project Bumper.xcodeproj -scheme Bumper -configuration Debug -destination "id=$TV" -derivedDataPath build/test/app -quiet >"$OUT/tv-build.log" 2>&1 || { echo "TV build failed ($OUT/tv-build.log)"; exit 1; }
scripts/with-timeout.sh 400 xcodebuild build-for-testing -project Bumper.xcodeproj -scheme BumperPhone -destination "id=$PHONE" -derivedDataPath build/test/companion -quiet >"$OUT/phone-build.log" 2>&1 || { echo "phone build failed ($OUT/phone-build.log)"; exit 1; }
xcrun simctl install "$TV" build/test/app/Build/Products/Debug-appletvsimulator/Bumper.app
xcrun simctl terminate "$TV" "$BID" 2>/dev/null
xcrun simctl launch "$TV" "$BID" -mock -mockHTTP -reset -route item:movie-0001   # -mockHTTP: artwork the phone can load >/dev/null
sleep 4
TEST_RUNNER_EXPECT_TITLE="Endless Voyage" TEST_RUNNER_SHOTS_DIR="$PWD/$OUT" scripts/with-timeout.sh 180 xcodebuild test-without-building -project Bumper.xcodeproj -scheme BumperPhone \
  -destination "id=$PHONE" -derivedDataPath build/test/companion -collect-test-diagnostics never >"$OUT/phone-test.log" 2>&1
grep -E "Test Case.*(passed|failed)|error:" "$OUT/phone-test.log" | cut -c1-220
C=$(xcrun simctl get_app_container "$TV" "$BID" data 2>/dev/null)
grep -E "companion|tonight" "$C/Library/Caches/perf/trace.log" 2>/dev/null | tail -6
echo "results: $OUT"
grep -q "Test Case.*passed" "$OUT/phone-test.log"
