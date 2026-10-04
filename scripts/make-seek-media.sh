#!/usr/bin/env bash
# Long clips for seek/skip benchmarking (scripts/seek-bench.sh), one per seek
# path, in TestMedia/seek/ with their own manifest — kept apart from the 5 s
# clips so the everyday playback checks stay fast.
#
# Keyframe spacing is deliberately realistic-to-unkind: seek cost is
# "network round trip + decode from the keyframe before the target".
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/TestMedia/seek"
FF="${FF:-$(command -v ffmpeg || true)}"
DUR="${DUR:-120}"
mkdir -p "$OUT"
[[ -x "$FF" ]] || { echo "needs ffmpeg on PATH (brew install ffmpeg)"; exit 1; }

V1080="testsrc2=size=1920x1080:rate=24000/1001:duration=$DUR"
V4K="testsrc2=size=3840x2160:rate=24000/1001:duration=$DUR"
TONE51="sine=frequency=440:duration=$DUR,aformat=channel_layouts=5.1"
TONE="sine=frequency=660:duration=$DUR"
run() { echo "  → $1"; "$FF" -hide_banner -loglevel error -y "${@:2}" "$OUT/$1"; }

echo "Generating seek media ($DUR s each) in $OUT"
# 0. MKV H.264 + DTS → VLCKit; 5 s GOPs (web-dl-ish worst case)
run seek-h264-dts.mkv -f lavfi -i "$V1080" -f lavfi -i "$TONE51" \
  -map 0 -map 1 -c:v h264_videotoolbox -b:v 8M -g 120 -c:a dca -strict -2 -b:a 768k
# 1. MKV 4K HEVC 10-bit + E-AC-3 → VLCKit, high bitrate; 2 s GOPs
run seek-hevc-4k.mkv -f lavfi -i "$V4K" -f lavfi -i "$TONE51" \
  -map 0 -map 1 -c:v hevc_videotoolbox -profile:v main10 -pix_fmt p010le -b:v 16M -g 48 -tag:v hvc1 -c:a eac3 -b:a 640k
# 2. MP4 H.264 + AAC → AVPlayer direct play; 2 s GOPs
run seek-h264.mp4 -f lavfi -i "$V1080" -f lavfi -i "$TONE" \
  -c:v h264_videotoolbox -b:v 8M -g 48 -c:a aac -b:a 192k -movflags +faststart
# 3. MPEG-2 TS + AC-3 → VLCKit software decode; broadcast-style 0.5 s GOPs
run seek-mpeg2.ts -f lavfi -i "$V1080" -f lavfi -i "$TONE51" \
  -map 0 -map 1 -c:v mpeg2video -b:v 10M -g 12 -c:a ac3 -b:a 448k

cat > "$OUT/manifest.json" <<EOF
[
  {"file":"seek-h264-dts.mkv","name":"Seek · MKV H.264 (5 s GOP) · DTS","container":"mkv","duration":$DUR,
   "video":{"codec":"h264","width":1920,"height":1080,"fps":23.976,"range":"SDR","bitDepth":8},
   "audio":[{"codec":"dts","channels":6,"title":"DTS 5.1"}],"subtitles":[]},
  {"file":"seek-hevc-4k.mkv","name":"Seek · MKV 4K HEVC 10-bit · E-AC-3","container":"mkv","duration":$DUR,
   "video":{"codec":"hevc","width":3840,"height":2160,"fps":23.976,"range":"SDR","bitDepth":10},
   "audio":[{"codec":"eac3","channels":6,"title":"DD+ 5.1"}],"subtitles":[]},
  {"file":"seek-h264.mp4","name":"Seek · MP4 H.264 · AAC (AVPlayer)","container":"mov,mp4,m4a,3gp,3g2,mj2","duration":$DUR,
   "video":{"codec":"h264","width":1920,"height":1080,"fps":23.976,"range":"SDR","bitDepth":8},
   "audio":[{"codec":"aac","channels":1,"title":"AAC"}],"subtitles":[]},
  {"file":"seek-mpeg2.ts","name":"Seek · MPEG-2 TS (software) · AC-3","container":"mpegts","duration":$DUR,
   "video":{"codec":"mpeg2video","width":1920,"height":1080,"fps":23.976,"range":"SDR","bitDepth":8},
   "audio":[{"codec":"ac3","channels":6,"title":"DD 5.1"}],"subtitles":[]}
]
EOF
ls -lh "$OUT"
