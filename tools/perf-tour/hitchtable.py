#!/usr/bin/env python3
"""Every `hitch` line inside a run's scenario segment, with what the app logged just before it
(painting-company row 299): where summary.py counts a segment's hitches, this says which fill
each belongs to.

    hitchtable.py <segment> <tour-log.tsv>...      (finish, zen-30, colors, start, ...)

A hitch line is written at the late refresh; its gap began `gap` ms earlier. Offsets are seconds
after `<segment> begin`. zen-30 and colors: fill k is the k-th tap (a `sound` line with
delay=0.000), its window from 0.5 s before that tap to 0.5 s before the next; the nominal number
(begin + 3 + 3.3 (k-1) s) is shown beside it, and a tap whose sound is a chord finished a color.
Events within 100 ms before the gap's start or inside the gap are listed; ticks only as a count,
their largest work and the last one. The hitches between `first refresh` and the begin mark (the
launch's, the painting screen's first build, any warm-up's) are listed first."""
import sys

seg = sys.argv[1]
for path in sys.argv[2:]:
    lines = []
    for raw in open(path):
        p = raw.rstrip("\n").split("\t")
        if len(p) >= 2:
            try:
                lines.append((float(p[0]), p[1], "\t".join(p[2:])))
            except ValueError:
                pass
    begin = next((t for t, k, r in lines if k == "mark" and r.startswith(f"{seg} begin")), None)
    end = next((t for t, k, r in lines if k == "mark" and r.startswith(f"{seg} end")), None)
    print(f"== {path.split('/')[-1]}  {seg} begin={begin} end={end} ({(end or 0) - (begin or 0):.2f} s)")
    if begin is None:
        continue
    sounds = [t for t, k, r in lines if k == "sound" and begin <= t <= (end or 1e18)]
    flights = [t for t, k, r in lines if k == "flight" and begin <= t <= (end or 1e18)]
    taps = [t for t, k, r in lines if k == "sound" and "delay=0.000" in r and begin <= t <= (end or 1e18)]
    hitches = [(t, k, r) for t, k, r in lines if k == "hitch" and begin <= t <= (end or 1e18)]
    # before the segment: from `first refresh` to its begin mark (the launch's and any warm-up's cost)
    first = next((t for t, k, r in lines if k == "mark" and r.startswith("first refresh")), None)
    if first is not None:
        pre = [(t, float(r.split("gap=")[1].split()[0])) for t, k, r in lines if k == "hitch" and first <= t < begin]
        print(f"  before {seg} begin (first refresh at {first - begin:+.3f} s): {len(pre)} hitches, {sum(g for _, g in pre):.0f} ms: "
              + ", ".join(f"{t - begin:+.3f} ({g:.0f})" for t, g in pre))
    # a hitch whose gap starts before begin but ends after it is counted too
    for t, k, r in hitches:
        gap = float(r.split("gap=")[1].split()[0])
        start = t - gap / 1000
        off = start - begin
        head = f"  hitch at +{t - begin:7.3f} s (gap {gap:5.1f} ms, began +{off:7.3f})"
        if seg in ("zen-30", "colors"):
            k_nom = int((off - 3) // 3.3) + 1 if off >= 3 else 0
            # the fill: the k-th tap (a `sound` with delay=0.000), its window from 0.5 s before that tap to 0.5 s
            # before the next; its flight is the first `flight` after the tap (usually 0.37 s, later when the
            # tap's sound is a chord)
            k = sum(1 for x in taps if x - 0.5 <= start)
            if k:
                tap = taps[k - 1]
                f = next((x for x in flights if x >= tap), None)
                chord = sum(1 for u, kk, rr in lines if kk == "sound" and abs(u - tap) < 0.01)
                head += (f"  fill {k} (nominal {k_nom}{', 4-note chord' if chord > 1 else ''}): {start - tap:+.3f} s from its tap sound"
                         + (f", {start - f:+.3f} s from its flight ({f - tap:.2f} s after the tap)" if f else ""))
            else:
                head += f"  before fill 1 (nominal {k_nom})"
        print(head)
        near = [(u, kk, rr) for u, kk, rr in lines if start - 0.1 <= u <= t and kk != "hitch"]
        ticks = [x for x in near if x[1] == "tick"]
        for u, kk, rr in near:
            if kk != "tick":
                print(f"      {u - start:+.3f}  {kk:7} {rr[:110]}")
        if ticks:
            work = lambda x: float(x[2].split("work=")[1].split()[0]) if "work=" in x[2] else 0
            big = max(ticks, key=work)
            print(f"      ticks: {len(ticks)}, max work {work(big):.2f} ms at {big[0] - start:+.3f}; last {ticks[-1][0] - start:+.3f} {ticks[-1][2]}")
        else:
            print("      ticks: none in the window")
        prior = [x for x in lines if x[0] < start - 0.1 and x[1] not in ("tick", "device", "hitch")]
        if prior:
            u, kk, rr = prior[-1]
            print(f"      (last non-tick event before the window: {u - start:+.3f} {kk} {rr[:80]})")
    print(f"  {len(hitches)} hitches in segment, {sum(float(r.split('gap=')[1].split()[0]) for _, _, r in hitches):.0f} ms of gaps")
