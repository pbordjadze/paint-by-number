#!/usr/bin/env python3
"""Visual + quantitative evaluation harness for the template pipeline.

    tools/eval.py run IMAGE... --out DIR [--sheet-width 2400] [--importance-dir DIR] [-- pbn generate options]

For every image: converts to PPM, runs `pbn generate`, rasterizes the SVG outputs with
resvg, and writes a contact sheet `DIR/<name>/sheet.png` (source | painted | template)
plus `DIR/summary.json` and an overview grid `DIR/overview.png`. With --importance-dir,
`<name>.pgm` in that directory (if present) is passed to pbn as the importance map.

Requires a static release build of pbn:  tools/swift.sh build -c release --static-swift-stdlib
(or set PBN=/path/to/pbn, e.g. a saved baseline binary for before/after comparisons)
"""
import json
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PBN = os.environ.get("PBN", os.path.join(ROOT, ".build", "release", "pbn"))
SVG2PNG = os.path.join(ROOT, "tools", "svg2png.mjs")


def svg_to_png(svg, png, width=None):
    cmd = ["node", SVG2PNG, svg, png] + ([str(width)] if width else [])
    subprocess.run(cmd, check=True, cwd=os.path.join(ROOT, "tools"))


def process(image_path, out_root, pbn_args, sheet_width, importance_dir=None):
    name = os.path.splitext(os.path.basename(image_path))[0]
    out = os.path.join(out_root, name)
    os.makedirs(out, exist_ok=True)
    ppm = os.path.join(out, "input.ppm")
    Image.open(image_path).convert("RGB").save(ppm)
    extra = []
    if importance_dir and os.path.exists(os.path.join(importance_dir, name + ".pgm")):
        extra = ["--importance", os.path.join(importance_dir, name + ".pgm")]
    res = subprocess.run([PBN, "generate", ppm, out] + pbn_args + extra, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"[{name}] FAILED\n{res.stderr}", file=sys.stderr)
        return name, None
    stats = json.load(open(os.path.join(out, "stats.json")))
    working = Image.open(os.path.join(out, "working.ppm")).convert("RGB")
    w, h = working.size
    panel_w = sheet_width // 3
    for svg in ("painted", "template", "painted-outlined"):
        svg_to_png(os.path.join(out, f"{svg}.svg"), os.path.join(out, f"{svg}.png"), panel_w * 2)
    raster = Image.open(os.path.join(out, "raster.ppm")).convert("RGB")
    raster.save(os.path.join(out, "raster.png"))
    working.save(os.path.join(out, "working.png"))
    boundaries = None
    if os.path.exists(os.path.join(out, "boundaries.ppm")):
        boundaries = Image.open(os.path.join(out, "boundaries.ppm")).convert("RGB")
        boundaries.save(os.path.join(out, "boundaries.png"))

    panel_h = int(h * panel_w / w)
    sheet = Image.new("RGB", (panel_w * 3, 2 * panel_h + 28), "white")
    for i, img in enumerate([
        working,
        Image.open(os.path.join(out, "painted.png")).convert("RGB"),
        Image.open(os.path.join(out, "template.png")).convert("RGB"),
    ]):
        sheet.paste(img.resize((panel_w, panel_h), Image.LANCZOS), (i * panel_w, 28))
    # Second row: region raster | region boundaries | palette swatches.
    sheet.paste(raster.resize((panel_w, panel_h), Image.LANCZOS), (0, 28 + panel_h))
    if boundaries is not None:
        sheet.paste(boundaries.resize((panel_w, panel_h), Image.LANCZOS), (panel_w, 28 + panel_h))
    d = ImageDraw.Draw(sheet)
    palette = stats.get("palette", [])
    if palette:
        cols = 6
        rows = (len(palette) + cols - 1) // cols
        cw, ch = panel_w // cols, min(panel_h // max(rows, 1), 60)
        font = ImageFont.load_default(size=max(10, min(ch // 2, 18)))
        names = stats.get("colorNames", [])
        name_font = ImageFont.load_default(size=max(9, ch // 4))
        for i, hx in enumerate(palette):
            x0, y0 = 2 * panel_w + (i % cols) * cw, 28 + panel_h + (i // cols) * ch
            rgb = tuple(int(hx[k:k + 2], 16) for k in (0, 2, 4))
            d.rectangle([x0 + 2, y0 + 2, x0 + cw - 2, y0 + ch - 2], fill=rgb)
            lum = 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]
            ink = (0, 0, 0) if lum > 128 else (255, 255, 255)
            d.text((x0 + 8, y0 + 6), str(i + 1), fill=ink, font=font)
            if ch >= 36 and i < len(names):
                d.text((x0 + 8, y0 + ch - 6 - max(9, ch // 4)), names[i], fill=ink, font=name_font)
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
    importance_dir = None
    images = []
    it = iter(argv)
    for a in it:
        if a == "--out":
            out_root = next(it)
        elif a == "--sheet-width":
            sheet_width = int(next(it))
        elif a == "--importance-dir":
            importance_dir = next(it)
        else:
            images.append(a)
    os.makedirs(out_root, exist_ok=True)
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(lambda p: process(p, out_root, pbn_args, sheet_width, importance_dir), images))
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
