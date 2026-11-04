#!/usr/bin/env python3
"""Pairs of Tool Guide pages for blind reading (painting-company row 230).

For each page of Refine's Tool Guide, writes <out>/<page>.txt holding the page as it reads at
two revisions of the string catalog, as VERSION A and VERSION B in a seeded random order, and
<out>/key.json saying which is which; also <out>/all.txt, every page at the newer revision, for
a newcomer's read of the whole guide. A reader who hasn't seen the brief is asked which version
reads as if a person wrote it and why, and to quote what still reads as machine-written.

    tools/guide_blind.py --old origin/main --new HEAD --out /tmp/blind [--pages pen,merge] [--seed 230]

A page's words are `refine.guide.<page>.text` (since row 230); a revision before that is read
from its slots (summary, about, steps, try, notes, procreate), laid out as the guide showed
them. Links (`[Merge](guide:merge)`) read as their names.
"""
import argparse
import json
import random
import re
import subprocess
from pathlib import Path

CATALOG = "App/PaintByNumber/Resources/Localizable.xcstrings"
NAMES = {
    "basics": "The Basics", "layers": "Layers", "procreate": "Coming from Procreate", "pen": "Pen",
    "shape": "Shapes", "eraser": "Eraser", "smartEraser": "Line Eraser", "bendLine": "Bend Line",
    "select": "Select", "cellEdge": "Cell Edge", "merge": "Merge", "moveEdge": "Move Edge",
    "fill": "Make Cell", "bucket": "Bucket", "brush": "Paint Brush", "eyedropper": "Eyedropper",
    "editPaint": "Edit Paint", "looks": "Looks", "moveNumber": "Move Number", "text": "Writing",
    "tryPainting": "Try Painting",
}


def catalog(revision):
    raw = subprocess.run(["git", "show", f"{revision}:{CATALOG}"], capture_output=True, text=True, check=True).stdout
    strings = json.loads(raw)["strings"]

    def value(key):
        entry = strings.get(key)
        return entry["localizations"]["en"]["stringUnit"]["value"] if entry else None
    return value


def page(value, key):
    """The page as a reader sees it, or None where the revision has no such page."""
    text = value(f"refine.guide.{key}.text")
    if text is not None:
        return f"# {NAMES.get(key, key)}\n\n" + re.sub(r"\[([^\]]+)\]\(guide:[A-Za-z]+\)", r"\1", text)
    about = value(f"refine.guide.{key}.about")
    if about is None:
        return None
    lines = [f"# {NAMES.get(key, key)}", value(f"refine.guide.{key}.summary") or "", "", about, "", "How to Use It"]
    n = 1
    while value(f"refine.guide.{key}.step{n}"):
        lines.append(f"{n}. " + value(f"refine.guide.{key}.step{n}"))
        n += 1
    if value(f"refine.guide.{key}.try"):
        lines += ["", "Try This", value(f"refine.guide.{key}.try"), "(Reset puts the picture back whenever you like.)"]
    notes, n = [], 1
    while value(f"refine.guide.{key}.note{n}"):
        notes.append("• " + value(f"refine.guide.{key}.note{n}"))
        n += 1
    if notes:
        lines += ["", "Good to Know"] + notes
    if value(f"refine.guide.{key}.procreate"):
        lines += ["", "In Procreate", value(f"refine.guide.{key}.procreate")]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--old", default="origin/main")
    parser.add_argument("--new", default="HEAD")
    parser.add_argument("--out", required=True)
    parser.add_argument("--pages", help="comma-separated page keys (default: every page at --new)")
    parser.add_argument("--seed", type=int, default=230)
    args = parser.parse_args()
    old, new = catalog(args.old), catalog(args.new)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    keys = args.pages.split(",") if args.pages else [k for k in NAMES if page(new, k) is not None]
    rng = random.Random(args.seed)
    key, everything = {}, []
    for k in keys:
        before, after = page(old, k), page(new, k)
        if after is None:
            continue
        everything.append(after)
        if before is None:
            continue
        a, b = (before, after) if rng.random() < 0.5 else (after, before)
        key[k] = "A=old" if a is before else "A=new"
        (out / f"{k}.txt").write_text(f"=== VERSION A ===\n{a}\n\n=== VERSION B ===\n{b}\n")
    (out / "all.txt").write_text("\n\n".join(everything) + "\n")
    (out / "key.json").write_text(json.dumps(key, indent=1) + "\n")
    print(f"{len(key)} pairs and the whole guide in {out}")


if __name__ == "__main__":
    main()
