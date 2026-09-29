#!/usr/bin/env python3
"""Visual + quantitative evaluation harness for the template pipeline.

    tools/eval.py run IMAGE... --out DIR [--sheet-width 2400] [-- pbn generate options]

For every image: converts to PPM, runs `pbn generate`, rasterizes the SVG outputs with
resvg, and writes a contact sheet `DIR/<name>/sheet.png` (source | painted | template)
plus `DIR/summary.json` and an overview grid `DIR/overview.png`.

Requires a static release build of pbn:  tools/swift.sh build -c release --static-swift-stdlib
"""
import json
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PBN = os.path.join(ROOT, ".build", "release", "pbn")
SVG2PNG = os.path.join(ROOT, "tools", "svg2png.mjs")


def svg_to_png(svg, png, width=None):
    cmd = ["node", SVG2PNG, svg, png] + ([str(width)] if width else [])
    subprocess.run(cmd, check=True, cwd=os.path.join(ROOT, "tools"))


def process(image_path, out_root, pbn_args, sheet_width):
    name = os.path.splitext(os.path.basename(image_path))[0]
    out = os.path.join(out_root, name)
    os.makedirs(out, exist_ok=True)
    ppm = os.path.join(out, "input.ppm")
    Image.open(image_path).convert("RGB").save(ppm)
    res = subprocess.run([PBN, "generate", ppm, out] + pbn_args, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"[{name}] FAILED\n{res.stderr}", file=sys.stderr)
        return name, None
    stats = json.load(open(os.path.join(out, "stats.json")))
    working = Image.open(os.path.join(out, "working.ppm")).convert("RGB")
    w, h = working.size
    panel_w = sheet_width // 3
    for svg in ("painted", "template", "painted-outlined"):
        svg_to_png(os.path.join(out, f"{svg}.svg"), os.path.join(out, f"{svg}.png"), panel_w * 2)
    Image.open(os.path.join(out, "raster.ppm")).save(os.path.join(out, "raster.png"))
    working.save(os.path.join(out, "working.png"))

    panel_h = int(h * panel_w / w)
    sheet = Image.new("RGB", (panel_w * 3, panel_h + 28), "white")
    for i, img in enumerate([
        working,
        Image.open(os.path.join(out, "painted.png")).convert("RGB"),
        Image.open(os.path.join(out, "template.png")).convert("RGB"),
    ]):
        sheet.paste(img.resize((panel_w, panel_h), Image.LANCZOS), (i * panel_w, 28))
    d = ImageDraw.Draw(sheet)
    caption = (f"{name}  {stats['width']}x{stats['height']}  colors={stats['colors']}  regions={stats['regions']}  "
               f"dE={stats['meanDeltaE']:.4f}  r<2:{stats['regionsUnderRadius2']}  total={stats['totalMs']:.0f}ms")
    d.text((8, 6), caption, fill=(0, 0, 0), font=ImageFont.load_default(size=16))
    sheet.save(os.path.join(out, "sheet.png"))
    return name, stats


def main():
    argv = sys.argv[1:]
    if not argv or argv[0] != "run":
        print(__doc__)
        sys.exit(1)
    argv = argv[1:]
    pbn_args = []
    if "--" in argv:
        i = argv.index("--")
        argv, pbn_args = argv[:i], argv[i + 1:]
    out_root = "out"
    sheet_width = 2400
    images = []
    it = iter(argv)
    for a in it:
        if a == "--out":
            out_root = next(it)
        elif a == "--sheet-width":
            sheet_width = int(next(it))
        else:
            images.append(a)
    os.makedirs(out_root, exist_ok=True)
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(lambda p: process(p, out_root, pbn_args, sheet_width), images))
    summary = {name: stats for name, stats in results if stats}
    json.dump(summary, open(os.path.join(out_root, "summary.json"), "w"), indent=2)

    # Overview grid of painted previews (4 per row).
    thumbs = []
    for name, stats in results:
        if not stats:
            continue
        img = Image.open(os.path.join(out_root, name, "painted-outlined.png")).convert("RGB")
        img.thumbnail((600, 600))
        thumbs.append(img)
    if thumbs:
        cols = 4
        rows = (len(thumbs) + cols - 1) // cols
        cell = 600
        grid = Image.new("RGB", (cols * cell, rows * cell), "white")
        for i, t in enumerate(thumbs):
            grid.paste(t, ((i % cols) * cell, (i // cols) * cell))
        grid.save(os.path.join(out_root, "overview.png"))

    keys = ["regions", "meanDeltaE", "regionsUnderRadius2", "totalMs"]
    for name, stats in results:
        if stats:
            print(f"{name:16s} " + "  ".join(f"{k}={stats[k]:.4g}" if isinstance(stats[k], float) else f"{k}={stats[k]}" for k in keys))


if __name__ == "__main__":
    main()
