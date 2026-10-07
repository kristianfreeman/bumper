#!/usr/bin/env bash
# Archives the TV, iPhone/iPad and Mac apps (Release) and uploads each to
# App Store Connect (TestFlight). Signing and upload use the Xcode account.
#
#   scripts/release.sh [tvos|ios|macos ...]      (default: all three)
#   ARCHIVE_ONLY=1 scripts/release.sh            archive, don't upload
#   ARCHIVES=build/release/<run> scripts/release.sh   upload those archives (no rebuild)
#   BUILD=202610070100 scripts/release.sh       a build number of your own (default: the time, yyyyMMddHHmm)
#   ASC_KEY_ID=… ASC_ISSUER_ID=… scripts/release.sh   upload with an App Store Connect API key
#     (~/.appstoreconnect/private_keys/AuthKey_<id>.p8) instead of Xcode's account
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="build/release/$(date +%Y%m%d-%H%M%S)"; mkdir -p "$OUT"
# Every upload needs a build number App Store Connect hasn't seen: the time
# it was built (always increasing), the same for all three apps and the Top Shelf.
BUILD="${BUILD:-$(date +%Y%m%d%H%M)}"
echo "build $BUILD"
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
    -destination "$dest" -archivePath "$OUT/$p.xcarchive" -allowProvisioningUpdates CURRENT_PROJECT_VERSION="$BUILD" -quiet >"$OUT/$p-archive.log" 2>&1 \
    || { echo "$p: archive failed ($OUT/$p-archive.log)"; grep -m5 "error:" "$OUT/$p-archive.log" || true; exit 1; }
  fi
  [[ -n "${ARCHIVE_ONLY:-}" ]] && { echo "$p: archived ($OUT/$p.xcarchive)"; continue; }
  if [[ -n "${ASC_KEY_ID:-}" ]]; then
    [[ -f "$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8" ]] || { echo "no API key at ~/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"; exit 1; }
  fi
  echo "== $p: uploading"
  if [[ -n "${ASC_KEY_ID:-}" ]]; then
    # Sign with the Xcode account (cloud signing needs its rights), then upload
    # with the key: Xcode's own upload failed on this account ("Unexpected nil
    # property at path: 'Actor/relationships/providerId'"), and a key with App
    # Manager access may upload but not sign.
    sed 's#<string>upload</string>#<string>export</string>#' scripts/ExportOptions-AppStore.plist >"$OUT/export-only.plist"
    scripts/with-timeout.sh 1800 xcodebuild -exportArchive -archivePath "$OUT/$p.xcarchive" -exportOptionsPlist "$OUT/export-only.plist" \
      -exportPath "$OUT/$p-export" -allowProvisioningUpdates >"$OUT/$p-export.log" 2>&1 \
      || { echo "$p: signing failed ($OUT/$p-export.log)"; grep -m8 -iE "error|failed" "$OUT/$p-export.log" || true; exit 1; }
    pkg=$(find "$OUT/$p-export" -maxdepth 1 \( -name '*.ipa' -o -name '*.pkg' \) | head -1)
    kind=$p; [[ "$p" == tvos ]] && kind=appletvos
    scripts/with-timeout.sh 1800 xcrun altool --upload-app -f "$pkg" -t "$kind" --apiKey "$ASC_KEY_ID" --apiIssuer "${ASC_ISSUER_ID:?set ASC_ISSUER_ID}" >"$OUT/$p-upload.log" 2>&1 \
      || { echo "$p: upload failed ($OUT/$p-upload.log)"; grep -m8 -iE "error|failed" "$OUT/$p-upload.log" || true; exit 1; }
  else
  scripts/with-timeout.sh 1800 xcodebuild -exportArchive -archivePath "$OUT/$p.xcarchive" -exportOptionsPlist scripts/ExportOptions-AppStore.plist \
    -exportPath "$OUT/$p-export" -allowProvisioningUpdates >"$OUT/$p-upload.log" 2>&1 \
    || { echo "$p: upload failed ($OUT/$p-upload.log)"; grep -m8 -iE "error|failed|No suitable|not found" "$OUT/$p-upload.log" || true; exit 1; }
  fi
  echo "$p: uploaded"
done
echo "logs: $OUT"
