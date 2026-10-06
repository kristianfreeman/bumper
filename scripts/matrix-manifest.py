#!/usr/bin/env python3
"""The matrix manifest, from ffprobe: each clip described as Jellyfin's own
probe would (codec names, frame rate, field order, bit depth, range), so the
app plans these the way it would a real server's files.

    scripts/matrix-manifest.py TestMedia/matrix
"""
import json, os, subprocess, sys
from fractions import Fraction

d = sys.argv[1]
# Jellyfin's container names (what its probe reports for each extension).
CONTAINERS = {".mkv": "mkv", ".mp4": "mp4", ".mov": "mov", ".avi": "avi", ".ts": "ts", ".m2ts": "m2ts",
              ".mpg": "mpeg", ".wmv": "asf", ".flv": "flv", ".webm": "webm"}
AUDIO = {"dts": "DTS", "truehd": "TrueHD", "eac3": "Dolby Digital+", "ac3": "Dolby Digital", "aac": "AAC", "flac": "FLAC",
         "mp3": "MP3", "opus": "Opus", "vorbis": "Vorbis", "wmav2": "WMA", "pcm_s16le": "PCM", "pcm_s24le": "PCM", "pcm_bluray": "PCM"}
LAYOUT = {1: "Mono", 2: "Stereo", 6: "5.1", 8: "7.1"}


def probe(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", path],
                         capture_output=True, text=True, check=True).stdout
    return json.loads(out)


def describe(f):
    p = probe(os.path.join(d, f))
    v = next((s for s in p["streams"] if s["codec_type"] == "video"), None)
    entry = {"file": f, "container": CONTAINERS.get(os.path.splitext(f)[1], "unknown"),
             "duration": round(float(p["format"].get("duration", 20)), 2), "audio": [], "subtitles": []}
    if v:
        fps = float(Fraction(v.get("r_frame_rate", "24/1")))
        pix = v.get("pix_fmt", "")
        depth = 10 if "10" in pix else 12 if "12" in pix else 8
        hdr = v.get("color_transfer") == "smpte2084"
        interlaced = v.get("field_order") in ("tt", "bb", "tb", "bt")
        entry["video"] = {"codec": v["codec_name"], "width": v["width"], "height": v["height"], "fps": round(fps, 3),
                          "range": "HDR10" if hdr else "SDR", "bitDepth": depth, "interlaced": interlaced}
    for a in (s for s in p["streams"] if s["codec_type"] == "audio"):
        ch = a.get("channels", 2)
        name = AUDIO.get(a["codec_name"], a["codec_name"])
        entry["audio"].append({"codec": a["codec_name"], "channels": ch, "title": f"English - {name} {LAYOUT.get(ch, f'{ch}ch')}"})
    for s in (s for s in p["streams"] if s["codec_type"] == "subtitle"):
        codec = {"subrip": "subrip", "ass": "ass", "dvd_subtitle": "dvdsub", "mov_text": "mov_text"}.get(s["codec_name"], s["codec_name"])
        entry["subtitles"].append({"codec": codec, "title": f"English ({codec})", "language": "eng"})
    # "H.264 1080p23.976 · AC-3 5.1 (MKV)"
    vid = entry.get("video")
    pic = f"{vid['codec']} {vid['height']}{'i' if vid['interlaced'] else 'p'}{vid['fps']:g}" + (f" {vid['bitDepth']}-bit" if vid['bitDepth'] > 8 else "") + (" HDR10" if vid["range"] == "HDR10" else "") if vid else "no video"
    snd = entry["audio"][0]["title"].removeprefix("English - ") if entry["audio"] else "no audio"
    sub = f" · {entry['subtitles'][0]['codec']} subs" if entry["subtitles"] else ""
    entry["name"] = f"{pic} · {snd}{sub} ({os.path.splitext(f)[1][1:].upper()})"
    return entry


files = sorted(f for f in os.listdir(d) if not f.startswith(".") and os.path.splitext(f)[1] in CONTAINERS)
manifest = [describe(f) for f in files]
json.dump(manifest, open(os.path.join(d, "manifest.json"), "w"), indent=1)
print(f"manifest: {len(manifest)} clips")
for i, m in enumerate(manifest):
    print(f"  media-{i:<3} {m['name']}")
