#!/usr/bin/env bash
# The playback matrix's clips: one per kind of file people actually have —
# containers, codecs, frame rates, interlacing, bit depths, audio and
# subtitle formats — 35 s of constant motion each. The manifest is written from ffprobe,
# as Jellyfin's own probe would describe each file.
#
#   scripts/make-matrix-media.sh            → TestMedia/matrix/ (skips clips already made)
#   FORCE=1 scripts/make-matrix-media.sh    remake them all
#
# Not encodable here (no encoder in ffmpeg): VC-1, Theora, real DTS-HD MA,
# Dolby Vision, bitmap subtitles (PGS, VobSub). Noted in the report as untested.
set -uo pipefail
cd "$(dirname "$0")/.."
FF="${FF:-$(command -v ffmpeg || true)}"
[[ -x "$FF" ]] || { echo "needs ffmpeg on PATH (brew install ffmpeg)"; exit 1; }
OUT=TestMedia/matrix; mkdir -p "$OUT"
LEN=35

# A picture that moves every frame (the frame counts come from the player).
src() {  # size rate
  echo "testsrc2=size=$1:rate=$2"
}
tone() {  # channel layout
  echo "sine=frequency=440:sample_rate=48000,aformat=channel_layouts=$1"
}

made=0; failed=()
clip() {  # file  size rate  -- ffmpeg output options
  local file=$1 size=$2 rate=$3 layout=$4; shift 4
  [[ -s "$OUT/$file" && -z "${FORCE:-}" ]] && return
  printf '  %-40s' "$file"
  if "$FF" -v error -y -f lavfi -i "$(src "$size" "$rate")" -f lavfi -i "$(tone "$layout")" -t $LEN "$@" "$OUT/$file" 2>"$OUT/.err"; then
    echo ok; made=$((made + 1))
  else
    echo "FAILED: $(head -1 "$OUT/.err")"; failed+=("$file"); rm -f "$OUT/$file"
  fi
}

echo "encoding into $OUT…"
# H.264 — the common case, every way it comes.
clip h264-1080p23-aac.mp4        1920x1080 24000/1001 stereo  -c:v libx264 -preset fast -pix_fmt yuv420p -c:a aac -b:a 192k
clip h264-1080p23-ac3.mkv        1920x1080 24000/1001 5.1     -c:v libx264 -preset fast -pix_fmt yuv420p -c:a ac3 -b:a 448k
clip h264-1080p24-dts.mkv        1920x1080 24         5.1     -c:v libx264 -preset fast -pix_fmt yuv420p -c:a dca -strict -2 -b:a 1536k
clip h264-1080p23-truehd.mkv     1920x1080 24000/1001 5.1     -c:v libx264 -preset fast -pix_fmt yuv420p -c:a truehd -strict -2
clip h264-1080p23-flac71.mkv     1920x1080 24000/1001 7.1     -c:v libx264 -preset fast -pix_fmt yuv420p -c:a flac
clip h264-1080p23-ac3.m2ts       1920x1080 24000/1001 5.1     -c:v libx264 -preset fast -pix_fmt yuv420p -c:a ac3 -b:a 640k -f mpegts -mpegts_m2ts_mode 1
clip h264-1080p23-hi10p.mkv      1920x1080 24000/1001 stereo  -c:v libx264 -preset fast -pix_fmt yuv420p10le -c:a aac
clip h264-1080i29-ac3.mkv        1920x1080 30000/1001 stereo  -c:v libx264 -preset fast -pix_fmt yuv420p -flags +ildct+ilme -x264opts tff=1 -field_order tt -c:a ac3
clip h264-1080p59-aac.mkv        1920x1080 60000/1001 stereo  -c:v libx264 -preset fast -pix_fmt yuv420p -c:a aac
clip h264-720p50-aac.mkv         1280x720  50         stereo  -c:v libx264 -preset fast -pix_fmt yuv420p -c:a aac
clip h264-1080p23-80mbps.mkv     1920x1080 24000/1001 stereo  -c:v libx264 -preset veryfast -b:v 80M -maxrate 80M -bufsize 80M -pix_fmt yuv420p -c:a aac
clip h264-480p29-aac.mp4         720x480   30000/1001 stereo  -c:v libx264 -preset fast -pix_fmt yuv420p -c:a aac
# HEVC — SDR and HDR, 1080p and 4K.
clip hevc-1080p23-eac3.mp4       1920x1080 24000/1001 5.1     -c:v libx265 -preset fast -tag:v hvc1 -pix_fmt yuv420p -c:a eac3
clip hevc-1080p23-10bit-aac.mkv  1920x1080 24000/1001 stereo  -c:v libx265 -preset fast -pix_fmt yuv420p10le -c:a aac
clip hevc-2160p23-hdr10-eac3.mkv 3840x2160 24000/1001 5.1     -c:v libx265 -preset ultrafast -pix_fmt yuv420p10le -x265-params "colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc:hdr10=1" -color_primaries bt2020 -color_trc smpte2084 -colorspace bt2020nc -c:a eac3
clip hevc-2160p59-sdr-aac.mkv    3840x2160 60000/1001 stereo  -c:v libx265 -preset ultrafast -pix_fmt yuv420p -c:a aac
# Newer codecs without hardware on an Apple TV 4K (2017).
clip av1-1080p23-opus.mkv        1920x1080 24000/1001 stereo  -c:v libsvtav1 -preset 10 -pix_fmt yuv420p -c:a libopus
clip av1-2160p23-opus.mkv        3840x2160 24000/1001 stereo  -c:v libsvtav1 -preset 12 -pix_fmt yuv420p10le -c:a libopus
clip vp9-1080p23-opus.webm       1920x1080 24000/1001 stereo  -c:v libvpx-vp9 -deadline realtime -cpu-used 8 -b:v 4M -c:a libopus
# The older library: DivX/Xvid AVIs, DVD, WMV, Flash, MJPEG, ProRes.
clip mpeg4-480p29-bframes-mp3.avi 720x480  30000/1001 stereo  -c:v mpeg4 -vtag XVID -bf 2 -q:v 4 -c:a libmp3lame -b:a 128k
clip mpeg4-480p23-mp3.avi        720x480   24000/1001 stereo  -c:v mpeg4 -vtag DX50 -bf 0 -q:v 4 -c:a libmp3lame -b:a 128k
clip msmpeg4-480p25-mp3.avi      640x480   25         stereo  -c:v msmpeg4 -q:v 4 -c:a libmp3lame -b:a 128k
clip mpeg2-480i29-ac3.mpg        720x480   30000/1001 stereo  -c:v mpeg2video -b:v 6M -flags +ildct+ilme -top 1 -c:a ac3 -f vob
clip mpeg2-1080i29-ac3.ts        1920x1080 30000/1001 stereo  -c:v mpeg2video -b:v 18M -flags +ildct+ilme -top 1 -c:a ac3 -f mpegts
clip wmv2-480p29-wma.wmv         640x480   30000/1001 stereo  -c:v wmv2 -b:v 2M -c:a wmav2 -b:a 128k
clip flv1-360p29-mp3.flv         640x360   30000/1001 stereo  -c:v flv -b:v 1M -c:a libmp3lame -ar 44100
clip mjpeg-720p29-pcm.avi        1280x720  30000/1001 stereo  -c:v mjpeg -q:v 4 -c:a pcm_s16le
clip prores-1080p23-pcm.mov      1920x1080 24000/1001 stereo  -c:v prores_ks -profile:v 2 -c:a pcm_s24le

# Subtitles: muxed into an H.264 clip, one format each.
subs() {  # file  codec  [-f]
  local file=$1 codec=$2; shift 2
  [[ -s "$OUT/$file" && -z "${FORCE:-}" ]] && return
  printf '  %-40s' "$file"
  cat > "$OUT/.subs.srt" <<'SRT'
1
00:00:01,000 --> 00:00:09,000
The quick brown fox jumps over the lazy dog.

2
00:00:10,000 --> 00:00:19,000
<i>Second line,</i> in italics, and a longer one that has to wrap across the picture.
SRT
  if "$FF" -v error -y -f lavfi -i "$(src 1920x1080 24000/1001)" -f lavfi -i "$(tone stereo)" -i "$OUT/.subs.srt" -t $LEN \
       -map 0 -map 1 -map 2 -c:v libx264 -preset fast -pix_fmt yuv420p -c:a aac -c:s "$codec" -metadata:s:s:0 language=eng "$@" "$OUT/$file" 2>"$OUT/.err"; then
    echo ok; made=$((made + 1))
  else
    echo "FAILED: $(head -1 "$OUT/.err")"; failed+=("$file"); rm -f "$OUT/$file"
  fi
}
subs subs-srt.mkv    srt
subs subs-ass.mkv    ass
subs subs-movtext.mp4 mov_text
rm -f "$OUT/.err" "$OUT/.subs.srt"

echo "made $made${failed:+, failed: ${failed[*]}}"
python3 scripts/matrix-manifest.py "$OUT"
