#!/usr/bin/env python3
"""Converts the drawing test set (or any drawings) with `pbn drawing` and lays each out for a look.

    tools/drawings/convert.py --out <dir> [drawings...] [-- <pbn drawing options>]

Without drawings it takes every `Tests/Drawings/*.png|jpg`: each drawing and, beside it, its
`<name>-photo.jpg`. Each input is written as PPM, converted (pbn drawing: the sheet cleaned,
the ink traced, the areas laid with paints), its template.svg and painted-outlined.svg rendered
with tools/svg2png.mjs, and laid out in `<dir>/sheets/<name>.jpg`: the input, the cleaned sheet,
the template with its numbers and the painting finished, side by side. `<dir>/contact.jpg` holds
every painting at a glance and `<dir>/summary.json` each conversion's counts (areas, paints,
validity, the drawing report). Needs the release pbn (`tools/swift.sh build -c release` or a
native toolchain), node with tools/node_modules (`cd tools && npm ci`), Pillow.
"""
import argparse
import glob
import json
import os
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PBN = os.path.join(ROOT, ".build", "release", "pbn")
SVG2PNG = os.path.join(ROOT, "tools", "svg2png.mjs")


def render_svg(svg, png, width):
    subprocess.run(["node", SVG2PNG, svg, png, str(width)], check=True)


def convert(path, out_dir, options, width=900):
    name = os.path.splitext(os.path.basename(path))[0]
    work = os.path.join(out_dir, "runs", name)
    os.makedirs(work, exist_ok=True)
    ppm = os.path.join(work, "input.ppm")
    Image.open(path).convert("RGB").save(ppm)
    result = subprocess.run([PBN, "drawing", ppm, work] + options, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"{name}: pbn failed: {result.stderr.strip()}", file=sys.stderr)
        return name, None
    stats = json.loads(result.stdout)
    render_svg(os.path.join(work, "template.svg"), os.path.join(work, "template.png"), width)
    render_svg(os.path.join(work, "painted-outlined.svg"), os.path.join(work, "painted.png"), width)
    panels = [Image.open(path).convert("RGB"), Image.open(os.path.join(work, "cleaned.ppm")).convert("RGB"),
              Image.open(os.path.join(work, "template.png")).convert("RGB"),
              Image.open(os.path.join(work, "painted.png")).convert("RGB")]
    height = max(int(p.height * width / p.width) for p in panels)
    sheet = Image.new("RGB", (width * 4 + 30, height + 40), "white")
    draw = ImageDraw.Draw(sheet)
    titles = ["input", "cleaned", "template", "painted"]
    for i, (p, title) in enumerate(zip(panels, titles)):
        p = p.resize((width, int(p.height * width / p.width)), Image.LANCZOS)
        sheet.paste(p, (i * (width + 10), 30))
        draw.text((i * (width + 10) + 4, 8), f"{name} — {title}", fill="black")
    sheets = os.path.join(out_dir, "sheets")
    os.makedirs(sheets, exist_ok=True)
    sheet.save(os.path.join(sheets, name + ".jpg"), quality=85)
    summary = {k: stats.get(k) for k in ["regions", "colors", "valid", "labelsBelowLegibleSize", "labelRoomUnmet", "totalMs"]}
    summary["drawing"] = stats.get("drawing")
    art = stats.get("lineArt") or {}
    summary["lineArt"] = {k: art.get(k) for k in ["enclosedAreas", "interiorStrokes", "openEndsPer1000", "drawnLength"]}
    print(f"{name}: {summary['regions']} areas, {summary['colors']} paints, valid {summary['valid']}, "
          f"{summary['totalMs']:.0f} ms, rectified {summary['drawing']['rectified']}")
    return name, summary


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--out", required=True)
    p.add_argument("--width", type=int, default=900, help="each panel's width in the sheets")
    p.add_argument("drawings", nargs="*")
    args, rest = p.parse_known_args()
    options = [o for o in rest if o != "--"]
    drawings = args.drawings
    if not drawings:
        folder = os.path.join(ROOT, "Tests", "Drawings")
        drawings = sorted(f for f in glob.glob(os.path.join(folder, "*.*"))
                          if f.lower().endswith((".png", ".jpg")) and not f.endswith("-photo.jpg"))
        drawings = [d for pair in ((d, os.path.splitext(d)[0] + "-photo.jpg") for d in drawings) for d in pair if os.path.exists(d)]
    os.makedirs(args.out, exist_ok=True)
    summary = {}
    for d in drawings:
        name, s = convert(d, args.out, options, args.width)
        summary[name] = s
    with open(os.path.join(args.out, "summary.json"), "w") as f:
        json.dump(summary, f, indent=1, sort_keys=True)
    # The contact sheet: every painting, four to a row.
    paintings = [(n, os.path.join(args.out, "runs", n, "painted.png")) for n in summary if summary[n]]
    cell = 420
    cols = 4
    rows = (len(paintings) + cols - 1) // cols
    contact = Image.new("RGB", (cols * cell, rows * (cell + 20)), "white")
    draw = ImageDraw.Draw(contact)
    for i, (n, path) in enumerate(paintings):
        im = Image.open(path).convert("RGB")
        im.thumbnail((cell - 8, cell - 8))
        x, y = (i % cols) * cell, (i // cols) * (cell + 20)
        contact.paste(im, (x + 4, y + 4))
        draw.text((x + 4, y + cell), n, fill="black")
    contact.save(os.path.join(args.out, "contact.jpg"), quality=85)


if __name__ == "__main__":
    main()
