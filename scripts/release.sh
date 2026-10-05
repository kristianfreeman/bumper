#!/usr/bin/env bash
# Archives the TV, iPhone/iPad and Mac apps (Release) and uploads each to
# App Store Connect (TestFlight). Signing and upload use the Xcode account.
#
#   scripts/release.sh [tvos|ios|macos ...]      (default: all three)
#   ARCHIVE_ONLY=1 scripts/release.sh            archive, don't upload
#   ARCHIVES=build/release/<run> scripts/release.sh   upload those archives (no rebuild)
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="build/release/$(date +%Y%m%d-%H%M%S)"; mkdir -p "$OUT"
platforms=("$@"); [[ ${#platforms[@]} -eq 0 ]] && platforms=(tvos ios macos)
for p in "${platforms[@]}"; do
  case "$p" in
    tvos)  scheme=Bumper;      dest="generic/platform=tvOS" ;;
    ios)   scheme=BumperPhone; dest="generic/platform=iOS" ;;
    macos) scheme=BumperMac;   dest="generic/platform=macOS" ;;
    *) echo "unknown platform $p"; exit 1 ;;
  esac
  if [[ -n "${ARCHIVES:-}" ]]; then
    cp -R "$ARCHIVES/$p.xcarchive" "$OUT/$p.xcarchive"
  else
  echo "== $p: archiving $scheme"
  scripts/with-timeout.sh 1800 xcodebuild archive -project Bumper.xcodeproj -scheme "$scheme" -configuration Release \
    -destination "$dest" -archivePath "$OUT/$p.xcarchive" -allowProvisioningUpdates -quiet >"$OUT/$p-archive.log" 2>&1 \
    || { echo "$p: archive failed ($OUT/$p-archive.log)"; grep -m5 "error:" "$OUT/$p-archive.log" || true; exit 1; }
  fi
  [[ -n "${ARCHIVE_ONLY:-}" ]] && { echo "$p: archived ($OUT/$p.xcarchive)"; continue; }
  echo "== $p: uploading"
  scripts/with-timeout.sh 1800 xcodebuild -exportArchive -archivePath "$OUT/$p.xcarchive" -exportOptionsPlist scripts/ExportOptions-AppStore.plist \
    -exportPath "$OUT/$p-export" -allowProvisioningUpdates >"$OUT/$p-upload.log" 2>&1 \
    || { echo "$p: upload failed ($OUT/$p-upload.log)"; grep -m8 -iE "error|failed|No suitable|not found" "$OUT/$p-upload.log" || true; exit 1; }
  echo "$p: uploaded"
done
echo "logs: $OUT"
