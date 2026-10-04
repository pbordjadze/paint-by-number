#!/usr/bin/env python3
"""Before/after comparison of two eval.py runs (quality metrics and template bytes).

    tools/compare.py BEFORE_DIR AFTER_DIR [--sheets OUT_DIR]

Prints per-image metric changes, corpus totals, and which templates are byte-identical.
With --sheets, writes OUT_DIR/<name>.png stacking the two painted-outlined previews
(before above after) for every image whose template changed, for visual review.
"""
import hashlib
import json
import os
import sys

KEYS = ["regions", "meanDeltaE", "p95DeltaE", "regionsUnderRadius2", "regionsUnderRadius3",
        "minInscribedRadius", "minPaletteDistance", "colors"]


def digest(path):
    try:
        return hashlib.sha1(open(path, "rb").read()).hexdigest()
    except OSError:
        return None


def main():
    args = sys.argv[1:]
    sheets = None
    if "--sheets" in args:
        i = args.index("--sheets")
        sheets = args[i + 1]
        args = args[:i] + args[i + 2:]
    before_dir, after_dir = args
    before = json.load(open(os.path.join(before_dir, "summary.json")))
    after = json.load(open(os.path.join(after_dir, "summary.json")))
    names = sorted(set(before) & set(after))
    totals = {k: [0.0, 0.0] for k in KEYS + ["totalMs"]}
    changed = []
    for name in names:
        a, b = before[name], after[name]
        for k in totals:
            totals[k][0] += a[k]
            totals[k][1] += b[k]
        same = digest(os.path.join(before_dir, name, "template.pbnt")) == digest(os.path.join(after_dir, name, "template.pbnt"))
        if not same:
            changed.append(name)
        diffs = [f"{k} {a[k]:.4g}→{b[k]:.4g}" for k in KEYS if a[k] != b[k]]
        print(f"{name:18s} {'identical' if same else 'changed  '} {'  '.join(diffs)}")
    print(f"\n{len(names) - len(changed)}/{len(names)} templates byte-identical")
    for k, (a, b) in totals.items():
        mean = k in ("meanDeltaE", "p95DeltaE", "totalMs")
        a, b = (a / len(names), b / len(names)) if mean else (a, b)
        print(f"  {'mean' if mean else 'sum '} {k:22s} {a:10.4f} → {b:10.4f}  ({(b - a) / a * 100 if a else 0:+.2f}%)")
    if sheets and changed:
        from PIL import Image
        os.makedirs(sheets, exist_ok=True)
        for name in changed:
            top = Image.open(os.path.join(before_dir, name, "painted-outlined.png")).convert("RGB")
            bottom = Image.open(os.path.join(after_dir, name, "painted-outlined.png")).convert("RGB")
            sheet = Image.new("RGB", (max(top.width, bottom.width), top.height + bottom.height + 8), "white")
            sheet.paste(top, (0, 0))
            sheet.paste(bottom, (0, top.height + 8))
            sheet.thumbnail((1600, 2400))
            sheet.save(os.path.join(sheets, name + ".png"))


if __name__ == "__main__":
    main()
