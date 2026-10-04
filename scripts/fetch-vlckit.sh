#!/usr/bin/env bash
# Fetches VideoLAN's official VLCKit 4 xcframework (the build their own
# Package.swift points at) into Vendor/, verified by SHA-256. Re-run after
# bumping URL/SHA256 to upgrade. Resumable; idempotent.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
URL="https://download.videolan.org/cocoapods/unstable/VLCKit-4.0-20260929-1631.zip"
SHA256="f37c8dbdd4427d1a3f5d75dc4b8bd1ae863cef4426f9a405a2fd1c5c9012f1fb"
DEST="$ROOT/Vendor"
CACHE="$ROOT/build/vlckit"
mkdir -p "$DEST" "$CACHE"

if [[ -d "$DEST/VLCKit.xcframework" && "$(cat "$DEST/VLCKit.VERSION" 2>/dev/null)" == "$URL" ]]; then
  echo "VLCKit up to date ($DEST/VLCKit.xcframework)"; exit 0
fi
echo "Downloading $URL"
curl -fL -C - --retry 3 -o "$CACHE/VLCKit.zip" "$URL"
echo "$SHA256  $CACHE/VLCKit.zip" | shasum -a 256 -c - || { echo "checksum mismatch — delete $CACHE/VLCKit.zip and retry"; exit 1; }
rm -rf "$CACHE/unzipped" && mkdir -p "$CACHE/unzipped"
unzip -q "$CACHE/VLCKit.zip" -d "$CACHE/unzipped"
FRAMEWORK="$(find "$CACHE/unzipped" -maxdepth 3 -name 'VLCKit.xcframework' -type d | head -1)"
[[ -n "$FRAMEWORK" ]] || { echo "VLCKit.xcframework not found in archive"; exit 1; }
# Keep only the tvOS slices (device + simulator): ~0.7 GB instead of ~2.8 GB.
python3 - "$FRAMEWORK" <<'PY'
import plistlib, shutil, sys, os
root = sys.argv[1]
info = os.path.join(root, "Info.plist")
plist = plistlib.load(open(info, "rb"))
keep = [lib for lib in plist["AvailableLibraries"] if lib.get("SupportedPlatform") == "tvos"]
for lib in plist["AvailableLibraries"]:
    if lib not in keep:
        shutil.rmtree(os.path.join(root, lib["LibraryIdentifier"]), ignore_errors=True)
plist["AvailableLibraries"] = keep
plistlib.dump(plist, open(info, "wb"))
PY
rm -rf "$DEST/VLCKit.xcframework"
mv "$FRAMEWORK" "$DEST/VLCKit.xcframework"
find "$CACHE/unzipped" -maxdepth 2 -iname 'COPYING*' -exec cp {} "$DEST/VLCKit.COPYING.txt" \; -quit
echo "$URL" > "$DEST/VLCKit.VERSION"
rm -rf "$CACHE/unzipped"
echo "VLCKit → $DEST/VLCKit.xcframework"
