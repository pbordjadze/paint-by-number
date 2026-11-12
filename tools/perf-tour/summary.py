#!/usr/bin/env python3
"""What one run's -tourLog file says, by itself: no trace, no UI test (painting-company row 292).

    summary.py <tour-log.tsv>... [--json]

The log is the app's own (`-tourLog YES`, Debug and ReleaseTests builds: App/PaintByNumber/App/TourLog.swift),
copied from the app's tmp folder. A run is cut into segments by what the log itself holds:

    launch    the process's start to the first screen refresh the app answers (`mark first refresh`:
              its first frame's, give or take one); `init_ms` is the part before the app's init
    forming   the create flow's first draft started, to its full picture shown
    <name>    a `mark <name> begin` line to its `mark <name> end` (`maps`: the photo's line-art maps,
              computed or from the demo launches' cache; a demo's own, `zen-30`; and `start`, Start
              Painting tapped to the create flow gone, which is given a second more for the selected
              color to ease in)

For each: its length; the main thread's hitches (the log's pulse: refreshes it came to late, the time
past a frame summed, the longest gap); the canvas's drawn frames, the 60 Hz frames it missed (drawn
ticks 25 to 200 ms apart: each 16.7 ms past the first is one; longer gaps are the display link
resting) and its ticks' own work; camera flights and how late they landed; sounds and haptics; the
memory footprint's peak; the thermal state and Low Power Mode. `what` is a digest of the segment's
flights, sounds and haptics, in order: two runs of one demo that fly, sound and feel alike have the
same one. One line a segment, or --json.
"""
import hashlib, json, sys


def fields(parts):
    return dict(p.split("=", 1) for p in parts if "=" in p)


def summarize(path):
    events = []
    for line in open(path):
        parts = line.rstrip("\n").split("\t")
        if len(parts) >= 2:
            events.append((float(parts[0]), parts[1], parts[2:]))
    if not events:
        return {"log": path, "segments": []}
    segments = []
    launch = next(((t, f) for t, k, f in events if k == "launch"), None)
    init_ms = None
    if launch:
        started = float(fields(launch[1]).get("started", launch[0]))
        first = next((t for t, k, f in events if k == "mark" and f and f[0] == "first refresh"), launch[0])
        segments.append(("launch", started, first))
        init_ms = round((launch[0] - started) * 1000, 1)
    creates = [(t, f[0]) for t, k, f in events if k == "create" and f]
    drafted = next((t for t, f in creates if f.startswith("Draft") and "started" in f), None)
    shown = next((t for t, f in creates if f.startswith("Full") and f.endswith("shown")), None)
    if drafted is not None and shown is not None:
        segments.append(("forming", drafted, shown))
    opened = {}
    for t, k, f in events:
        if k != "mark" or not f:
            continue
        words = f[0].split()
        if len(words) >= 2 and words[1] == "begin":
            opened[words[0]] = t
        elif len(words) >= 2 and words[1] == "end" and words[0] in opened:
            segments.append((words[0], opened.pop(words[0]), t + (1.0 if words[0] == "start" else 0.0)))
    out = []
    for name, t0, t1 in sorted(segments, key=lambda s: s[1]):
        inside = [(t, k, f) for t, k, f in events if t0 <= t < t1]
        hitches = [fields(f) for _, k, f in inside if k == "hitch"]
        late = [max(float(h["gap"]) - float(h["frame"]), 0) for h in hitches]
        ticks = [fields(f) for _, k, f in inside if k == "tick"]
        gaps = [float(x["gap"]) for x in ticks if x.get("drew") == "1"]
        work = sorted(float(x["work"]) for x in ticks)
        flights = [f for _, k, f in inside if k == "flight"]
        lands = [float(fields(f).get("late", 0)) for _, k, f in inside if k == "land"]
        sounds = [f for _, k, f in inside if k == "sound"]
        haptics = [f for _, k, f in inside if k == "haptic"]
        device = [fields(f) for _, k, f in inside if k == "device"]
        what = hashlib.sha1("\n".join(
            ["flight " + " ".join(f) for f in flights] + ["sound " + " ".join(f) for f in sounds]
            + ["haptic " + " ".join(f) for f in haptics]).encode()).hexdigest()[:12]
        out.append({
            "segment": name, "begin": t0, "seconds": round(t1 - t0, 3),
            "hitches": len(hitches), "hitch_ms": round(sum(late), 1), "worst_gap_ms": round(max((float(h["gap"]) for h in hitches), default=0), 1),
            "frames": len(gaps), "missed_60hz_frames": sum(round(g / 16.667) - 1 for g in gaps if 25 < g <= 200),
            "worst_frame_gap_ms": round(max((g for g in gaps if g <= 200), default=0), 1),
            "tick_work_median_ms": work[len(work) // 2] if work else None,
            "tick_work_p99_ms": work[int(len(work) * 0.99) - 1] if len(work) > 10 else None,
            "tick_work_max_ms": work[-1] if work else None,
            "flights": len(flights), "latest_landing_ms": round(max(lands, default=0), 1),
            "sounds": len(sounds), "haptics": len(haptics), "what": what,
            "footprint_mb_max": max((int(d["footprintMB"]) for d in device if "footprintMB" in d), default=None),
            # The kernel's own peak since launch, as the segment ended: nothing between two samples is missed.
            "peak_mb_since_launch": max((int(d["peakMB"]) for d in device if "peakMB" in d), default=None),
            "thermal_max": max((int(d["thermal"]) for d in device if "thermal" in d), default=None),
            "low_power": any(d.get("lowPower") == "true" for d in device),
        })
    marks = [f[0] for _, k, f in events if k == "mark" and f]
    return {"log": path, "init_ms": init_ms, "marks": marks, "segments": out}


def main():
    paths = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not paths:
        sys.exit(__doc__)
    runs = [summarize(p) for p in paths]
    if "--json" in sys.argv:
        print(json.dumps(runs, indent=1))
        return
    for run in runs:
        print("%s  (process start to the app's init: %s ms)" % (run["log"], run.get("init_ms")))
        for s in run["segments"]:
            print("  %-9s %7.2f s  hitches %2d (%6.1f ms, worst gap %6.1f)  frames %5d missed %3d  work %s/%s/%s ms  "
                  "flights %2d sounds %2d haptics %2d  what %s  footprint %s MB (peak since launch %s)  thermal %s%s" % (
                      s["segment"], s["seconds"], s["hitches"], s["hitch_ms"], s["worst_gap_ms"], s["frames"],
                      s["missed_60hz_frames"], s["tick_work_median_ms"], s["tick_work_p99_ms"], s["tick_work_max_ms"],
                      s["flights"], s["sounds"], s["haptics"], s["what"], s["footprint_mb_max"], s["peak_mb_since_launch"], s["thermal_max"],
                      " LOW POWER" if s["low_power"] else ""))


if __name__ == "__main__":
    main()
