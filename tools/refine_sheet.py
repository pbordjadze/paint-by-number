#!/usr/bin/env python3
"""A sheet of a `pbn refine` run, for judging Refine's behavior by eye.

    tools/refine_sheet.py DIR [--out sheet.png]

DIR is a `pbn refine <photo> <gestures.json> --out DIR` output (refine.json, photo.ppm,
before.ppm, after.ppm, steps/*.ppm). Writes `DIR/sheet.png` (or --out): the photo, the coloring
book before and after, then a row per gesture: the spot it was made in (its `focus`) before and
after it, the touches in magenta, with what Refine made of it (the edit, what it did, the toast
it shows) beside them.

Requires Pillow.
"""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

WIDTH = 1500
GAP = 12
LINE = 20
TEXT_W = 460
INK = (30, 26, 34)
GREY = (110, 105, 115)
RED = (180, 30, 40)


def font(size):
    for name in ("DejaVuSans.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", "Arial.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def fit(image, width):
    return image.resize((width, max(1, round(image.height * width / image.width))), Image.LANCZOS)


def describe(step):
    edit = step.get("edit") or {}
    kind = edit.get("kind")
    lines = []
    head = f"{step['tool']}" + (f" ({kind})" if kind and kind != step["tool"] else "")
    lines.append((head + f": {step['verdict']}", INK))
    if step.get("caption"):
        lines.append((step["caption"], GREY))
    did = []
    for key, label in (("regionsSplit", "areas cut"), ("recolored", "recolored"), ("paintsAdded", "new paints"),
                       ("regionsMerged", "merged"), ("joins", "ends joined"), ("strokes", "strokes"),
                       ("tooSmall", "slivers left")):
        if step.get(key):
            did.append(f"{step[key]} {label}")
    if did:
        lines.append((", ".join(did), INK))
    if kind == "draw":
        lines.append((f"{len(edit['points'])} points, {len(edit.get('paints') or [])} paints"
                      + (", closed" if edit.get("closed") else ""), GREY))
    if step.get("toast"):
        lines.append((f"Toast: “{step['toast']}”", RED))
    if step.get("declined"):
        lines.append((step["declined"][:70], GREY))
    lines.append((f"{step['milliseconds']:.0f} ms", GREY))
    return lines


def main(argv):
    if not argv or argv[0].startswith("-"):
        print(__doc__)
        return 2
    run = argv[0]
    out = argv[argv.index("--out") + 1] if "--out" in argv else os.path.join(run, "sheet.png")
    report = json.load(open(os.path.join(run, "refine.json")))
    scale = Image.open(os.path.join(run, "before.ppm")).width / report["width"]
    big, small = font(18), font(15)

    tiles = [Image.open(os.path.join(run, n)).convert("RGB") for n in ("photo.ppm", "before.ppm", "after.ppm")]
    top_w = (WIDTH - 2 * GAP) // 3
    tiles = [fit(t, top_w) for t in tiles]
    rows = []
    head = Image.new("RGB", (WIDTH, tiles[0].height + LINE + GAP), "white")
    d = ImageDraw.Draw(head)
    for k, (tile, label) in enumerate(zip(tiles, ("Photo", "Before", "After"))):
        head.paste(tile, (k * (top_w + GAP), LINE + 4))
        d.text((k * (top_w + GAP), 0), label, fill=INK, font=big)
    rows.append(head)

    previous = Image.open(os.path.join(run, "before.ppm")).convert("RGB")
    crop_w = (WIDTH - TEXT_W - 3 * GAP) // 2
    for k, step in enumerate(report["steps"]):
        current = Image.open(os.path.join(run, step["picture"])).convert("RGB")
        touched = Image.open(os.path.join(run, step["touches"])).convert("RGB")
        box = step.get("focus") or [0, 0, report["width"], report["height"]]
        px = tuple(round(v * scale) for v in box)
        pair = [fit(previous.crop(px), crop_w), fit(touched.crop(px), crop_w)]
        text = describe(step)
        height = max(pair[0].height, len(text) * LINE + LINE)
        row = Image.new("RGB", (WIDTH, height + GAP), "white")
        d = ImageDraw.Draw(row)
        row.paste(pair[0], (0, 0))
        row.paste(pair[1], (crop_w + GAP, 0))
        x = 2 * (crop_w + GAP)
        d.text((x, 0), f"{k + 1}.", fill=INK, font=big)
        for i, (line, color) in enumerate(text):
            d.text((x + 34, i * LINE), line, fill=color, font=big if i == 0 else small)
        rows.append(row)
        previous = current
    foot = Image.new("RGB", (WIDTH, LINE + GAP), "white")
    ImageDraw.Draw(foot).text(
        (0, 0), f"{report['regions']} areas, {report['palette']} paints, "
        + ("valid" if report["valid"] else "INVALID: " + report["validation"]), fill=INK if report["valid"] else RED, font=small)
    rows.append(foot)
    sheet = Image.new("RGB", (WIDTH, sum(r.height for r in rows)), "white")
    y = 0
    for r in rows:
        sheet.paste(r, (0, y))
        y += r.height
    sheet.save(out)
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
