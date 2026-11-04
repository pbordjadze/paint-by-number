#!/usr/bin/env python3
"""Checks one pose's layout on the iPhone Duo against its fold (ci/duo.sh, after each pose).

  ci/duo/check.py <layout.json> <label>     exit 1 when a control lies on the fold
  ci/duo/check.py --self-test

The app writes the layout in Debug demo launches (`DuoLayoutProbe`, tmp/duo-layout.json in its
data container), in the window's points: its size, the fold's active reserved regions (division
regions, margins included) and the frames of the controls that report themselves. A control
crossing a fold by more than a point either way is on it: the crease is where a finger can't
reliably tap and the eye can't see flat.
"""
import json
import sys

SLACK = 1.0


def overlap(a, b):
    """How far rectangles [x, y, w, h] overlap along x and along y (0 when apart)."""
    dx = min(a[0] + a[2], b[0] + b[2]) - max(a[0], b[0])
    dy = min(a[1] + a[3], b[1] + b[3]) - max(a[1], b[1])
    return max(dx, 0.0), max(dy, 0.0)


def problems(layout):
    found = []
    for name, frame in sorted(layout.get("controls", {}).items()):
        for fold in layout.get("folds", []):
            dx, dy = overlap(frame, fold)
            if dx > SLACK and dy > SLACK:
                found.append(f"{name} {fmt(frame)} lies on the fold {fmt(fold)}")
    return found


def fmt(rect):
    return "(" + ", ".join(f"{v:.0f}" for v in rect) + ")"


def main(argv):
    if argv[1:] == ["--self-test"]:
        return self_test()
    path, label = argv[1], argv[2]
    try:
        with open(path) as f:
            layout = json.load(f)
    except (OSError, ValueError) as error:
        print(f"layout {label}: none ({error.__class__.__name__})")
        return 0
    size = layout.get("size", [0, 0])
    print(f"layout {label}: {layout.get('screen', '?')} {size[0]:.0f}×{size[1]:.0f}, "
          f"folds {[fmt(r) for r in layout.get('folds', [])]}, controls {sorted(layout.get('controls', {}))}")
    found = problems(layout)
    for problem in found:
        print(f"FOLD {label}: {problem}")
    return 1 if found else 0


def self_test():
    fold = [470, 0, 12, 669]
    assert problems({"folds": [fold], "controls": {"bar": [12, 6, 400, 44]}}) == []
    assert problems({"folds": [fold], "controls": {"bar": [12, 6, 900, 44]}}) == [
        "bar (12, 6, 900, 44) lies on the fold (470, 0, 12, 669)"]
    # Touching the fold's edge is not lying on it.
    assert problems({"folds": [fold], "controls": {"palette": [482, 60, 300, 500]}}) == []
    assert problems({"controls": {"bar": [0, 0, 900, 44]}}) == []
    print("duo check: self-test ok")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
