#!/usr/bin/env bash
# Plays the untagged calibration clips through both engines and samples the
# rendered pixels (expected: gray 128, dark 32, light 224 for correct SDR BT.709).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
U="${UDID:-936FC8D0-431D-4F91-B80F-12BC89DDEFFA}"
FF="${FF:-$(command -v ffmpeg)}"
sample() { $FF -hide_banner -loglevel error -i "$1" -vf "crop=4:4:$2:$3,scale=1:1" -f rawvideo -pix_fmt rgb24 - | od -An -tu1 | tr -s ' ' | sed 's/^ //'; }
for idx in $(python3 -c "import json;m=json.load(open('TestMedia/manifest.json'));print(' '.join(str(i) for i,x in enumerate(m) if x['file'].startswith('calib-')))"); do
  name=$(python3 -c "import json;print(json.load(open('TestMedia/manifest.json'))[$idx]['name'])")
  xcrun simctl terminate "$U" com.kristianfreeman.bumper >/dev/null 2>&1
  xcrun simctl launch "$U" com.kristianfreeman.bumper -mock -mockHTTP -mockMedia "$ROOT/TestMedia" -autoplay "media-$idx" >/dev/null
  sleep 3
  shot=$(mktemp).png; xcrun simctl io "$U" screenshot "$shot" >/dev/null 2>&1
  # screenshot is 3840x2160 (2x points): gray @ (960,300)pt, dark @ (360,470)pt, light @ (1560,470)pt
  printf '%-30s gray=%-12s dark=%-12s light=%s\n' "$name" "$(sample "$shot" 1920 600)" "$(sample "$shot" 720 940)" "$(sample "$shot" 3120 940)"
  rm -f "$shot"
done
xcrun simctl terminate "$U" com.kristianfreeman.bumper >/dev/null 2>&1
echo "expected (correct SDR):        gray=128 128 128 dark=32 32 32   light=224 224 224"
