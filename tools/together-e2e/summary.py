#!/usr/bin/env python3
"""How smooth one Paint Together run was on both devices (tools/together-e2e/run.sh; painting-company
row 350).

    summary.py <name>=<tour-log.tsv> <name>=<tour-log.tsv> [--json]

Each log is a device's `-tourLog` (App/PaintByNumber/App/TourLog.swift). The window judged is the
time both were painting together: from the later `together join` to the earlier device's last
`together` line. For each device: its hitches in that window (refreshes the main thread came to
late: how many, the time past a frame summed and per second, the longest gap) and the canvas's
ticks that missed a 60 Hz frame. Then each way's latency: an area one device's `together paint`
line names, to the friend's `together receive` line naming it. The two clocks are the devices' own
(both set by the network, usually within tens of ms), so a latency is an estimate; one under zero
says the clocks disagree by at least that much. Areas painted but never received are counted as lost.
"""
import json, statistics, sys


def read(path):
    events = []
    for line in open(path, errors="replace"):
        parts = line.rstrip("\n").split("\t")
        if len(parts) >= 2:
            try:
                events.append((float(parts[0]), parts[1], parts[2:]))
            except ValueError:
                pass
    return events


def fields(parts):
    return dict(p.split("=", 1) for p in parts if "=" in p)


def together(events, word):
    return [(t, fields(p)) for t, k, p in events if k == "together" and p and p[0] == word]


def areas(f):
    return [int(a) for a in f.get("areas", "").split(",") if a]


def window(logs):
    joins = [together(e, "join") for e in logs.values()]
    if not all(joins):
        return None
    start = max(j[0][0] for j in joins)
    end = min(max(t for t, k, _ in e if k == "together") for e in logs.values())
    return (start, end) if end > start else None


def smoothness(events, start, end):
    hitches = [fields(p) for t, k, p in events if k == "hitch" and start <= t <= end]
    late = [float(h["gap"]) - float(h["frame"]) for h in hitches if "gap" in h and "frame" in h]
    gaps = [float(h["gap"]) for h in hitches if "gap" in h]
    ticks = [fields(p) for t, k, p in events if k == "tick" and start <= t <= end]
    drawn = [t for t in ticks if t.get("drew") == "1"]
    missed = sum(1 for t in drawn if 25 <= float(t.get("gap", 0)) <= 200 and t.get("rest") != "1")
    seconds = end - start
    return {
        "seconds": round(seconds, 1),
        "hitches": len(hitches),
        "late_ms": round(sum(late), 1),
        "late_ms_per_s": round(sum(late) / seconds, 2) if seconds else None,
        "longest_gap_ms": round(max(gaps), 1) if gaps else 0,
        "frames_drawn": len(drawn),
        "frames_missed": missed,
    }


def latency(sender, receiver):
    received = {}
    for t, f in together(receiver, "receive"):
        for a in areas(f):
            received.setdefault(a, t)
    times, lost = [], 0
    for t, f in together(sender, "paint"):
        for a in areas(f):
            if a in received:
                times.append((received.pop(a) - t) * 1000)
            else:
                lost += 1
    if not times:
        return {"areas": 0, "lost": lost}
    times.sort()
    return {
        "areas": len(times),
        "lost": lost,
        "p50_ms": round(statistics.median(times), 1),
        "p95_ms": round(times[min(len(times) - 1, int(len(times) * 0.95))], 1),
        "max_ms": round(times[-1], 1),
        "min_ms": round(times[0], 1),
    }


def main():
    args = [a for a in sys.argv[1:] if a != "--json"]
    logs = dict(a.split("=", 1) for a in args)
    if len(logs) != 2:
        sys.exit(__doc__)
    events = {name: read(path) for name, path in logs.items()}
    win = window(events)
    report = {"window": None}
    if win:
        report["window"] = {"start": win[0], "end": win[1], "seconds": round(win[1] - win[0], 1)}
        report["devices"] = {n: smoothness(e, *win) for n, e in events.items()}
    a, b = list(events)
    report["latency"] = {f"{a}->{b}": latency(events[a], events[b]), f"{b}->{a}": latency(events[b], events[a])}
    report["arrived"] = {n: bool(together(e, "arrived")) for n, e in events.items()}
    if "--json" in sys.argv:
        print(json.dumps(report, indent=2))
        return
    if not win:
        print("No window painted together: a log has no `together join` line.")
    else:
        print(f"Painted together for {report['window']['seconds']} s")
        for n, s in report["devices"].items():
            print(f"  {n}: {s['hitches']} hitches, {s['late_ms']} ms late ({s['late_ms_per_s']} ms/s), "
                  f"longest gap {s['longest_gap_ms']} ms; canvas drew {s['frames_drawn']} frames, missed {s['frames_missed']}")
    for way, l in report["latency"].items():
        if l["areas"]:
            print(f"  {way}: {l['areas']} areas, p50 {l['p50_ms']} ms, p95 {l['p95_ms']} ms, max {l['max_ms']} ms, lost {l['lost']}")
        else:
            print(f"  {way}: no areas matched, lost {l['lost']}")


if __name__ == "__main__":
    main()
