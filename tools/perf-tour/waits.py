#!/usr/bin/env python3
"""Every wait a painter sits through in one run's -tourLog, as a timeline (painting-company row 361's spike).

    waits.py <tour-log.tsv>...

summary.py cuts a log into segments and judges their frames; this prints when each step of a wait
happened, in seconds from the first one, so a run of the create flow reads as: the photo loading,
decoded, analyzed (Vision and the line-art maps), each draft started and shown, the settings chosen,
the full picture shown, Start Painting, the hand-off, the canvas's first frame, and with The
Making-of on its show's build (`making-of-build begin`/`end`). A gallery open (`run.sh
gallery-open`) reads `open begin`, `open end` and the canvas's first drawn tick after the begin.
The marks are the app's own (`TourLog`, Debug and ReleaseTests builds, `-tourLog YES`).
"""
import sys


def main(paths):
    for path in paths:
        events = []
        for line in open(path):
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 2:
                events.append((float(parts[0]), parts[1], parts[2:]))
        print(path)
        steps = []
        launch = next((t for t, k, f in events if k == "launch"), None)
        for t, k, f in events:
            if k == "create" and f:
                steps.append((t, f[0]))
            elif k == "mark" and f:
                steps.append((t, f[0]))
        opened = next((t for t, label in steps if label == "open begin"), None)
        if opened is not None:
            first = next((t for t, k, f in events if k == "tick" and t > opened and "drew=1" in f), None)
            if first is not None:
                steps.append((first, "canvas's first drawn frame after open begin"))
        steps.sort()
        if not steps:
            print("  no waits in this log")
            continue
        t0 = steps[0][0]
        if launch is not None:
            print(f"  (app init {t0 - launch:+.3f} s before the first step)")
        for t, label in steps:
            print(f"  {t - t0:8.3f}  {label}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    main(sys.argv[1:])
