#!/usr/bin/env python3
"""Compare a perf run against its accepted baseline; fail on regressions.

    perf-compare.py <name> <current.json>            compare (exit 1 on regression)
    perf-compare.py <name> <current.json> --accept   make current the new baseline

Baselines live in perf-baselines/<name>.json (committed). A metric regresses
when it is worse than baseline by more than BOTH its relative tolerance and its
absolute noise floor — so 0.2 ms of jitter on a 1 ms metric never fails, but a
real 15 % slowdown always does. Lower is better for every tracked metric.
"""
import json, os, shutil, sys

# metric (key.stat) → (relative tolerance, absolute floor in the metric's unit)
RULES = {
    "ui.hitchRatio.last":      (0.10, 1.0),
    "ui.frameTime.p95":        (0.10, 1.0),
    "image.decode.p95":        (0.10, 0.5),
    "launch.firstContent.max": (0.10, 40.0),
    "home.load.p95":           (0.10, 20.0),
    "playback.ttff.p50":       (0.25, 25.0),   # per-clip TTFF is noisier
    "playback.tapToMoving.prepared.p50": (0.25, 40.0),
    "playback.tapToMoving.cold.p50":     (0.25, 40.0),
    # Seek benchmark (ms): noisy, so a 25 % / 40 ms band.
    "seek.skip.frame.p50":     (0.25, 40.0),
    "seek.skip.resume.p50":    (0.25, 40.0),
    "seek.skip.resume.p95":    (0.25, 60.0),
    "seek.jump.frame.p50":     (0.25, 40.0),
    "seek.jump.resume.p50":    (0.25, 40.0),
    "seek.burst.resume.last":  (0.25, 60.0),
    "seek.skip.dropped.max":   (0.0, 3.0),
    "seek.jump.dropped.max":   (0.0, 3.0),
}

def flatten(d):
    """Accepts a metrics snapshot ({key: summary}) or {clip: {key: summary}}."""
    out = {}
    for k, v in d.items():
        if isinstance(v, dict) and "p50" in v:
            for stat in ("p50", "p95", "max", "last"):
                out[f"{k}.{stat}"] = v[stat]
        elif isinstance(v, dict):
            for kk, vv in flatten(v).items():
                out[f"{k}/{kk}"] = vv
    return out

def rule_for(key):
    base = key.split("/")[-1]
    return RULES.get(base)

def main():
    name, current_path = sys.argv[1], sys.argv[2]
    root = os.path.join(os.path.dirname(__file__), "..", "perf-baselines")
    os.makedirs(root, exist_ok=True)
    baseline_path = os.path.join(root, f"{name}.json")
    if "--accept" in sys.argv or not os.path.exists(baseline_path):
        # Merge at the top level: accepting a run of some clips keeps the others.
        merged = json.load(open(baseline_path)) if os.path.exists(baseline_path) else {}
        current = json.load(open(current_path))
        if isinstance(merged, dict) and isinstance(current, dict) and all(isinstance(v, dict) for v in current.values()):
            merged.update(current)
        else:
            merged = current
        json.dump(merged, open(baseline_path, "w"), indent=1)
        print(f"baseline {'created' if '--accept' not in sys.argv else 'updated'}: perf-baselines/{name}.json")
        return 0
    base, cur = flatten(json.load(open(baseline_path))), flatten(json.load(open(current_path)))
    # Real hardware over Wi-Fi is noisier than the simulator: device scripts
    # scale every tolerance by PERF_NOISE (e.g. 3).
    noise = float(os.environ.get("PERF_NOISE", "1"))
    regressions, improvements = [], []
    for key, b in base.items():
        rule = rule_for(key)
        if not rule or key not in cur:
            continue
        rel, floor = rule
        rel, floor = rel * noise, floor * noise
        c = cur[key]
        if c > b * (1 + rel) and c - b > floor:
            regressions.append(f"  ✘ {key}: {b:.1f} → {c:.1f} (+{(c / b - 1) * 100 if b else 0:.0f}%)")
        elif c < b * (1 - rel) and b - c > floor:
            improvements.append(f"  ✔ {key}: {b:.1f} → {c:.1f}")
    for line in improvements: print(line)
    if regressions:
        print(f"PERF REGRESSION vs perf-baselines/{name}.json:")
        for line in regressions: print(line)
        print(f"(intentional? re-run with --accept: scripts/perf-compare.py {name} {current_path} --accept)")
        return 1
    print(f"no regressions vs perf-baselines/{name}.json")
    return 0

sys.exit(main())
