#!/usr/bin/env bash
# Generates a deterministic test-media set covering every playback path, plus
# a manifest.json the mock server reads. Run the app with:
#
#   -mock -mockMedia "$PWD/TestMedia"
#
# Requires ffmpeg on PATH (brew install ffmpeg).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/TestMedia"
FF="${FF:-$(command -v ffmpeg || true)}"
DUR="${DUR:-5}"
mkdir -p "$OUT"

[[ -x "$FF" ]] || { echo "needs ffmpeg on PATH (brew install ffmpeg)"; exit 1; }

# Subtitles (cues stay inside the clip; the engine itself also ignores
# subtitle tracks that outlast the picture when deciding end-of-media)
cat > "$OUT/subs.srt" <<'EOF'
1
00:00:00,500 --> 00:00:02,000
First line of <i>SubRip</i> text.

2
00:00:02,500 --> 00:00:04,500
Seek here and this should appear.
EOF
cat > "$OUT/subs.ass" <<'EOF'
[Script Info]
ScriptType: v4.00+
PlayResX: 1920
PlayResY: 1080

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Arial,64,&H00FFFFFF,&H000000FF,&H00000000,&H64000000,0,0,0,0,100,100,0,0,1,3,0,2,10,10,40,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:00.50,0:00:02.00,Default,,0,0,0,,{\i1}ASS styled{\i0} subtitle, with comma
Dialogue: 0,0:00:02.50,0:00:04.50,Default,,0,0,0,,Second\Nline break
EOF

VIDEO_1080="testsrc2=size=1920x1080:rate=24000/1001:duration=$DUR"
VIDEO_4K="testsrc2=size=3840x2160:rate=24000/1001:duration=$DUR"
TONE51="sine=frequency=440:duration=$DUR,aformat=channel_layouts=5.1"
TONE71="sine=frequency=330:duration=$DUR,aformat=channel_layouts=7.1"

run() { echo "  → $1"; "$FF" -hide_banner -loglevel error -y "${@:2}" "$OUT/$1"; }

echo "Generating test media in $OUT"
# 1. 4K HEVC Main10 HDR10 + E-AC-3 5.1 + SRT in MKV → VLCKit (MKV)
run hevc-hdr10-eac3.mkv -f lavfi -i "$VIDEO_4K" -f lavfi -i "$TONE51" -i "$OUT/subs.srt" \
  -map 0 -map 1 -map 2 -c:v hevc_videotoolbox -profile:v main10 -pix_fmt p010le -b:v 20M -tag:v hvc1 \
  -color_primaries bt2020 -color_trc smpte2084 -colorspace bt2020nc \
  -bsf:v hevc_metadata=colour_primaries=9:transfer_characteristics=16:matrix_coefficients=9 \
  -c:a eac3 -b:a 640k -c:s srt -metadata:s:s:0 language=eng
# The VideoToolbox encoder drops colour flags; stamp HDR10 signalling into the
# MKV Colour elements with a stream-copy remux.
"$FF" -hide_banner -loglevel error -y -i "$OUT/hevc-hdr10-eac3.mkv" -map 0 -c copy \
  -color_primaries bt2020 -color_trc smpte2084 -colorspace bt2020nc "$OUT/tmp.mkv" && mv "$OUT/tmp.mkv" "$OUT/hevc-hdr10-eac3.mkv"

# 2. H.264 + DTS 5.1 + ASS in MKV → VLCKit, DTS decode, styled ASS subs
run h264-dts-ass.mkv -f lavfi -i "$VIDEO_1080" -f lavfi -i "$TONE51" -i "$OUT/subs.ass" \
  -map 0 -map 1 -map 2 -c:v h264_videotoolbox -b:v 8M -c:a dca -strict -2 -b:a 1509k -c:s ass

# 3. H.264 + TrueHD in MKV → lossless LPCM
run h264-truehd.mkv -f lavfi -i "$VIDEO_1080" -f lavfi -i "$TONE51" \
  -map 0 -map 1 -c:v h264_videotoolbox -b:v 8M -c:a truehd -strict -2

# 4. MPEG-2 + AC-3 in MPEG-TS → software/VT-hwaccel decode, Annex-B
run mpeg2-ac3.ts -f lavfi -i "$VIDEO_1080" -f lavfi -i "$TONE51" \
  -map 0 -map 1 -c:v mpeg2video -b:v 12M -c:a ac3 -b:a 448k

# 6. True interlaced MPEG-2 1080i (59.94p squashed to fields + weave) + AC-3 in TS → VLCKit deinterlacing
run mpeg2-1080i.ts -f lavfi -i "testsrc2=size=1920x1080:rate=60000/1001:duration=$DUR,scale=1920:540,weave=first_field=top,setfield=tff,setsar=1" -f lavfi -i "$TONE51" \
  -map 0 -map 1 -c:v mpeg2video -flags +ilme+ildct -field_order tt -b:v 15M -c:a ac3 -b:a 448k

# 5. HEVC + AAC in MP4 → native AVPlayer direct play
run hevc-aac.mp4 -f lavfi -i "$VIDEO_1080" -f lavfi -i "sine=frequency=550:duration=$DUR" \
  -c:v hevc_videotoolbox -b:v 8M -tag:v hvc1 -c:a aac -b:a 192k -movflags +faststart

# 7. H.264 + AAC in MP4 → native AVPlayer direct play (works in the simulator too)
run h264-aac.mp4 -f lavfi -i "$VIDEO_1080" -f lavfi -i "sine=frequency=660:duration=$DUR" \
  -c:v h264_videotoolbox -b:v 8M -c:a aac -b:a 192k -movflags +faststart

# Series theme song (served for every series by the mock): a soft major chord.
"$FF" -hide_banner -loglevel error -y -f lavfi -i "sine=f=261.6:d=12,volume=0.3" -f lavfi -i "sine=f=329.6:d=12,volume=0.3" \
  -f lavfi -i "sine=f=392:d=12,volume=0.3" -filter_complex "amix=inputs=3,afade=t=in:d=1,afade=t=out:st=11:d=1" -c:a aac -b:a 128k "$OUT/theme.m4a"
echo "  → theme.m4a"

cat > "$OUT/manifest.json" <<EOF
[
  {"file":"hevc-hdr10-eac3.mkv","name":"4K HDR10 HEVC · E-AC-3 5.1 (MKV)","container":"mkv","duration":$DUR,
   "video":{"codec":"hevc","width":3840,"height":2160,"fps":23.976,"range":"HDR10","bitDepth":10},
   "audio":[{"codec":"eac3","channels":6,"title":"English - Dolby Digital+ 5.1"}],
   "subtitles":[{"codec":"subrip","title":"English (SRT)","language":"eng"}]},
  {"file":"h264-dts-ass.mkv","name":"H.264 · DTS 5.1 · ASS (MKV)","container":"mkv","duration":$DUR,
   "video":{"codec":"h264","width":1920,"height":1080,"fps":23.976,"range":"SDR","bitDepth":8},
   "audio":[{"codec":"dts","channels":6,"title":"English - DTS 5.1"}],
   "subtitles":[{"codec":"ass","title":"English (ASS)","language":"eng"}]},
  {"file":"h264-truehd.mkv","name":"H.264 · TrueHD 5.1 (MKV)","container":"mkv","duration":$DUR,
   "video":{"codec":"h264","width":1920,"height":1080,"fps":23.976,"range":"SDR","bitDepth":8},
   "audio":[{"codec":"truehd","channels":6,"title":"English - TrueHD 5.1"}],
   "subtitles":[]},
  {"file":"mpeg2-ac3.ts","name":"MPEG-2 · AC-3 (TS)","container":"mpegts","duration":$DUR,
   "video":{"codec":"mpeg2video","width":1920,"height":1080,"fps":23.976,"range":"SDR","bitDepth":8},
   "audio":[{"codec":"ac3","channels":6,"title":"English - Dolby Digital 5.1"}],
   "subtitles":[]},
  {"file":"mpeg2-1080i.ts","name":"MPEG-2 1080i interlaced · AC-3 (TS)","container":"mpegts","duration":$DUR,
   "video":{"codec":"mpeg2video","width":1920,"height":1080,"fps":29.97,"range":"SDR","bitDepth":8,"interlaced":true},
   "audio":[{"codec":"ac3","channels":6,"title":"English - Dolby Digital 5.1"}],
   "subtitles":[]},
  {"file":"hevc-aac.mp4","name":"HEVC · AAC (MP4, native)","container":"mov,mp4,m4a,3gp,3g2,mj2","duration":$DUR,
   "video":{"codec":"hevc","width":1920,"height":1080,"fps":23.976,"range":"SDR","bitDepth":8},
   "audio":[{"codec":"aac","channels":1,"title":"English - AAC"}],
   "subtitles":[]},
  {"file":"h264-aac.mp4","name":"H.264 · AAC (MP4, native AVPlayer)","container":"mov,mp4,m4a,3gp,3g2,mj2","duration":$DUR,
   "video":{"codec":"h264","width":1920,"height":1080,"fps":23.976,"range":"SDR","bitDepth":8},
   "audio":[{"codec":"aac","channels":1,"title":"English - AAC"}],
   "subtitles":[]}
]
EOF
ls -lh "$OUT"
