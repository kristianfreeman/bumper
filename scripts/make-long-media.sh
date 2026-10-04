#!/usr/bin/env bash
# A 20-minute, ~1 GB MKV (H.264 6 Mb/s, AC-3, Cues at the end as ffmpeg and
# mkvmerge write them) for resume / far-seek checks: TestMedia/long/.
set -euo pipefail
cd "$(dirname "$0")/.."
FF="${FF:-$(command -v ffmpeg || true)}"
[[ -x "$FF" ]] || { echo "needs ffmpeg on PATH (brew install ffmpeg)"; exit 1; }
mkdir -p TestMedia/long
"$FF" -hide_banner -loglevel error -y -f lavfi -i "testsrc2=size=1920x1080:rate=24000/1001" -f lavfi -i "sine=frequency=440:sample_rate=48000" \
  -t 1200 -c:v libx264 -preset ultrafast -b:v 6M -maxrate 6M -bufsize 12M -g 48 -pix_fmt yuv420p -c:a ac3 -b:a 384k -ac 2 TestMedia/long/long-h264-ac3.mkv
cat > TestMedia/long/manifest.json <<'JSON'
[{"file":"long-h264-ac3.mkv","name":"Long · MKV H.264 · AC-3 (20 min)","container":"mkv","duration":1200,
  "video":{"codec":"h264","width":1920,"height":1080,"fps":23.976,"range":"SDR","bitDepth":8},
  "audio":[{"codec":"ac3","channels":2,"title":"AC-3 Stereo"}],"subtitles":[]}]
JSON
