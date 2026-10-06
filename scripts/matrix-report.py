#!/usr/bin/env python3
"""The playback matrix's report: from each clip's trace, what the app chose
and how it played. A clip is smooth when it shows at least 97% of its own
frame rate with (almost) nothing dropped or late.

    scripts/matrix-report.py <manifest.json> <results dir> [clip-index ...]
"""
import json, os, re, sys

manifest = json.load(open(sys.argv[1]))
out = sys.argv[2]
clips = [int(c) for c in sys.argv[3:]] or range(len(manifest))
rows, results = [], {}

for i in clips:
    m = manifest[i]
    path = os.path.join(out, f"trace-{i}.log")
    trace = open(path).read() if os.path.exists(path) else ""
    status = open(os.path.join(out, f"result-{i}.txt")).read().strip() if os.path.exists(os.path.join(out, f"result-{i}.txt")) else "?"
    plan = re.search(r"Plan: (\w+) (\w+) — ([^\n]*)", trace)
    engine, method, why = (plan.group(1), plan.group(2), plan.group(3).split(" — /")[0]) if plan else ("—", "—", "")
    ttff = re.search(r"Tap → playing in (\d+) ms", trace) or re.search(r"First frame in (\d+) ms", trace)
    fps = (m.get("video") or {}).get("fps") or 0
    # Windows judged: after the first (it holds the start), each timed by the
    # trace's own clock, and only while the clip was still playing.
    first = re.search(r"^\s*([\d.]+) \[(?:vlc|player)\] (?:First frame|Tap → playing)", trace, re.M)
    t0 = float(first.group(1)) if first else 0
    end = t0 + m["duration"] - 0.5
    vlc = [(float(t), *map(int, v)) for t, *v in re.findall(r"^\s*([\d.]+) \[vlc\] 10 s: (\d+) decoded, (\d+) shown, (\d+) dropped, (\d+) late", trace, re.M)]
    native = [(float(t), int(d), int(st)) for t, d, st in re.findall(r"^\s*([\d.]+) \[native\] 10 s: (\d+) dropped, (\d+) stalls", trace, re.M)]
    shown = dropped = late = seconds = 0.0
    for (pt, *_), (t, dec, s, dr, l) in zip(vlc, vlc[1:]):
        if t > end: break
        shown += s; dropped += dr; late += l; seconds += t - pt
    for (pt, *_), (t, dr, st) in zip(native, native[1:]):
        if t > end: break
        dropped += dr; shown += max(0, fps * (t - pt) - dr); seconds += t - pt
    windows = seconds > 0
    if windows:
        per_s = shown / seconds
        drop_s = dropped / seconds
        late_s = late / seconds
        smooth = fps == 0 or (per_s >= 0.97 * fps and drop_s <= 0.3 and late_s <= 0.3)
        verdict = "smooth" if smooth else "DROPS"
    else:
        per_s = drop_s = late_s = None
        verdict = {"FAILED": "FAILED", "EXITED": "CRASHED", "TIMEOUT": "NO FRAMES"}.get(status, status)
    results[f"media-{i}"] = {"name": m["name"], "file": m["file"], "engine": engine, "method": method, "why": why,
                             "ttffMs": int(ttff.group(1)) if ttff else None, "fps": fps, "shownPerSecond": per_s,
                             "droppedPerSecond": drop_s, "latePerSecond": late_s, "verdict": verdict}
    fmt = lambda v: "—" if v is None else f"{v:.1f}"
    rows.append(f"| {i} | {m['name']} | {engine} {method} | {ttff.group(1) + ' ms' if ttff else '—'} | {fmt(per_s)} / {fps:g} | {fmt(drop_s)} | {fmt(late_s)} | **{verdict}** |")

json.dump(results, open(os.path.join(out, "results.json"), "w"), indent=1)
smooth = sum(1 for r in results.values() if r["verdict"] == "smooth")
with open(os.path.join(out, "report.md"), "w") as f:
    f.write(f"# Playback matrix\n\n{smooth} of {len(results)} smooth.\n\n")
    f.write("| # | Clip | Played by | First frame | Shown/s / fps | Dropped/s | Late/s | |\n|---|---|---|---|---|---|---|---|\n")
    f.write("\n".join(rows) + "\n")
print(open(os.path.join(out, "report.md")).read())
