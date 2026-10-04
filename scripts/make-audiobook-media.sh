#!/usr/bin/env bash
# Two small audiobooks for the mock server: real (synthesized) speech with
# natural pauses and some long silences — what Smart Speed has to find.
#   book-0: one MP3 with three chapters;  book-1: three MP3 parts.
# Constant-bitrate MP3 without Xing/ID3 headers, so the mock can start a
# stream at any time by byte offset (as Jellyfin's transcoder does by time).
set -euo pipefail
cd "$(dirname "$0")/.."
FF="${FF:-$(command -v ffmpeg || true)}"
[[ -x "$FF" ]] || { echo "needs ffmpeg on PATH (brew install ffmpeg)"; exit 1; }
OUT=TestMedia/books; TMP=$(mktemp -d); mkdir -p "$OUT"
speak() {  # speak <name> <text>
  say -o "$TMP/$1.aiff" "$2"
  "$FF" -hide_banner -loglevel error -y -i "$TMP/$1.aiff" -ar 44100 -ac 1 -c:a libmp3lame -b:a 64k -write_xing 0 -id3v2_version 0 "$TMP/$1.mp3"
}
dur() { "${FF%ffmpeg}ffprobe" -v error -show_entries format=duration -of csv=p=0 "$1"; }

speak c1 "Chapter one. The call came at midnight. [[slnc 1800]] Nobody at the station expected it. The line crackled, then a voice, quiet and careful, asked for the inspector by name. [[slnc 700]] He was not there. He had not been there for a week. [[slnc 2500]] The night clerk wrote the message down twice, to be sure."
speak c2 "Chapter two. By morning the rain had stopped. [[slnc 1200]] The inspector read the note at his kitchen table, and then he read it again. [[slnc 3000]] Three words, and a time. Half past four, the old pier. [[slnc 600]] He put on his coat."
speak c3 "Chapter three. The pier was empty. [[slnc 2000]] Gulls, a coil of rope, the smell of salt and diesel. [[slnc 900]] He waited until five, and then until six. [[slnc 4000]] At ten past six a small boat came around the point, and he knew."
for c in c1 c2 c3; do echo "file '$TMP/$c.mp3'"; done > "$TMP/list.txt"
"$FF" -hide_banner -loglevel error -y -f concat -safe 0 -i "$TMP/list.txt" -c copy "$OUT/the-old-pier.mp3"
d1=$(dur "$TMP/c1.mp3"); d2=$(dur "$TMP/c2.mp3"); d3=$(dur "$TMP/c3.mp3")

speak p1 "Part one. The tide tables were wrong that year. [[slnc 1500]] Everyone said so, and nobody changed them."
speak p2 "Part two. The harbour master kept his own notes, in pencil, in a book with a green cover. [[slnc 2200]] He trusted the moon more than the printers."
speak p3 "Part three. When the storm came, only one boat was out. [[slnc 1000]] It was his."
for p in p1 p2 p3; do cp "$TMP/$p.mp3" "$OUT/tide-$p.mp3"; done

python3 - "$OUT" "$d1" "$d2" "$d3" "$(dur "$OUT/tide-p1.mp3")" "$(dur "$OUT/tide-p2.mp3")" "$(dur "$OUT/tide-p3.mp3")" <<'PY'
import json, sys
out, d1, d2, d3, p1, p2, p3 = sys.argv[1], *map(float, sys.argv[2:])
books = [
  {"id": "book-0", "title": "The Old Pier", "author": "A. N. Author", "narrator": "Samantha",
   "parts": [{"file": "the-old-pier.mp3", "duration": d1 + d2 + d3}],
   "chapters": [{"name": "The Call", "start": 0}, {"name": "The Note", "start": d1}, {"name": "The Boat", "start": d1 + d2}]},
  {"id": "book-1", "title": "Tide Tables", "author": "B. Writer", "narrator": "Samantha",
   "parts": [{"file": "tide-p1.mp3", "duration": p1}, {"file": "tide-p2.mp3", "duration": p2}, {"file": "tide-p3.mp3", "duration": p3}],
   "chapters": []},
]
json.dump(books, open(f"{out}/manifest.json", "w"), indent=1)
print("\n".join(f'{b["id"]}: {sum(p["duration"] for p in b["parts"]):.1f}s' for b in books))
PY
rm -rf "$TMP"
