#!/usr/bin/env python3
"""Over-constraint spike (painting-company row 191): today's template beside cheap "loosenings".

    tools/loosen_eval.py run --out DIR [--only id,id] [--variants a,b] [--jobs N]
    tools/loosen_eval.py sheet --out DIR [--variants a,b]
    tools/loosen_eval.py grid --out DIR [--variants a,b]
    tools/loosen_eval.py blind --out DIR --variants a,b[,c] [--pairs id,id,...] OUT_HTML [--seed N]

Each variant is what can be tried without changing the app: pbn flags (`--colors`, `--detail`,
`--smooth`, `--tuning`), an importance map edited here (the app's map from the scene, as
`tools/scene_eval.py` derives it, with its background lowered), or the finished painting's paints
transformed after generation (`painted.svg`'s fills, in OKLab). `today` is the color method as
`tools/scene_eval.py`'s `old` runs it: a coloring book from the set's edge maps at 24 colours and
detail 0.5, the subject mask closed, the stand-in's eyes, the app's importance map.

`run` writes `DIR/<id>/<variant>/` (pbn's output, `painted.png` the finished painting (paint and ink) at 1280 px,
`template.png` the numbered template) and `DIR/summary.md` (per variant the means of regions,
paints, crumbs, ΔE and the painting-time estimate). `sheet` writes `DIR/sheet-<variant>.jpg`:
per photo the photo, today and the variant, finished and as templates; `grid` writes `DIR/<id>/grid.jpg`: the photo and every
variant's finished painting, labelled, to compare them all at once. `blind` writes one HTML
page: per photo the finished paintings of the variants given (today and one or two others),
lettered in a random order per photo, and `OUT_HTML.key.json` beside it, to be kept apart.

Requires the release pbn (tools/swift.sh build -c release --static-swift-stdlib, or PBN=...),
node (`cd tools && npm ci`), numpy, scipy and Pillow.
"""
import argparse
import base64
import html
import io
import json
import math
import os
import random
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import scene_eval as se  # noqa: E402

SET = se.DEFAULT_SET

# name: (pbn options, background importance (None: the app's map), palette transform or None[,
# the drawing's ink width as a factor on pbn's, 0 for none])
VARIANTS = {
    "today": ([], None, None),
    # The subject protected less: half the importance's pull on smoothing and the smallest area,
    # twice the smallest cell, texture flattened more (fur and foliage as a few shapes).
    "loosesubject": (["--tuning", "subjectEmphasis=0.5", "--tuning", "minimumCellSize=2", "--tuning", "textureFlattening=2.5",
                      "--tuning", "smoothing=1.5"], None, None),
    # The drawing in a bolder ink (2.5×: about the canvas's 1.5 pt line on a phone-sized painting).
    "inkbold": ([], None, None, 2.5),
    # A finished kit shows no lines: the paint covers them. The paint alone.
    "noink": ([], None, None, 0),
    # Fewer paints: kits for beginners use 10–20.
    "paints12": (["--colors", "12"], None, None),
    # A calm background: the background's importance at 0 instead of the app's 0.25 floor and
    # saliency, so its smallest area, band fusion and texture merging act as on the least
    # important pixels; the subject and faces keep the app's map.
    "calmback": ([], 0.0, None),
    # Bold shapes everywhere: three times the smallest cell, more smoothing and texture flattening.
    "bold": (["--tuning", "minimumCellSize=3", "--tuning", "smoothing=1.8", "--tuning", "textureFlattening=2"], None, None),
    # A kit's palette: the same regions, the paints made bolder (chroma up to 1.3×, lightness
    # spread 1.15× around its middle; `kit_color`), as kit paints are mixed brighter than a photo's.
    "kitpaint": ([], None, "kit"),
    # Flat shading: the smoothness setting high (Potts, outline passes) and texture flattened.
    "flat": (["--smooth", "0.9", "--tuning", "textureFlattening=2"], None, None),
    # The subject protected less and a kit's paints: the two that read best, together.
    "loosekit": (["--tuning", "subjectEmphasis=0.5", "--tuning", "minimumCellSize=2", "--tuning", "textureFlattening=2.5",
                  "--tuning", "smoothing=1.5"], None, "kit"),
    # Everything a beginner's kit does at once.
    "kit": (["--colors", "14", "--tuning", "minimumCellSize=2.5", "--tuning", "smoothing=1.5",
             "--tuning", "textureFlattening=2"], 0.0, "kit"),
}

# Picked for the blind page: faces, pets, animals, a landscape, a flower, a building.
BLIND_DEFAULT = "kodim04,german-shepherd,parrots,oxbow-bend,sailor-and-girl,barn,tabby-cat,lighthouse"


def oklab_to_srgb(lab):
    L, a, b = lab[..., 0], lab[..., 1], lab[..., 2]
    l_ = L + 0.3963377774 * a + 0.2158037573 * b
    m_ = L - 0.1055613458 * a - 0.0638541728 * b
    s_ = L - 0.0894841775 * a - 1.2914855480 * b
    l, m, s = l_ ** 3, m_ ** 3, s_ ** 3
    r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
    g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
    bl = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
    lin = np.stack([r, g, bl], axis=-1)
    c = np.where(lin <= 0.0031308, 12.92 * lin, 1.055 * np.abs(lin) ** (1 / 2.4) - 0.055)
    return c


def smoothstep(a, b, x):
    u = min(1.0, max(0.0, (x - a) / (b - a)))
    return u * u * (3 - 2 * u)


def kit_color(rgb):
    """One paint made bolder: chroma up to 1.3×, lightness spread 1.15× around 0.5, then pulled
    back into sRGB by reducing chroma only (hue and lightness kept). The chroma gain fades out
    on near-greys (below 0.015, where a hue is mostly noise: an off-white would turn pink) and
    on paints already vivid (above 0.12, which would clip: a macaw's red loses its shading)."""
    lab = se.oklab(np.array(rgb, dtype=np.uint8).reshape(1, 1, 3))[0, 0].astype(np.float64)
    L = min(0.98, max(0.08, 0.5 + (lab[0] - 0.5) * 1.15))
    chroma = math.hypot(lab[1], lab[2])
    gain = 1 + 0.3 * smoothstep(0.015, 0.04, chroma) * (1 - smoothstep(0.12, 0.2, chroma))
    for k in np.linspace(gain, 0, 30):
        c = oklab_to_srgb(np.array([L, lab[1] * k, lab[2] * k]))
        if np.all(c >= -0.002) and np.all(c <= 1.002):
            break
    return tuple(int(round(v)) for v in np.clip(c, 0, 1) * 255)


def transform_svg(path, kind):
    with open(path) as f:
        text = f.read()
    cache = {}

    def sub(m):
        hexv = m.group(2).lower()
        if hexv in ("ffffff", "2a2622", "000000"):
            return m.group(0)
        if hexv not in cache:
            rgb = tuple(int(hexv[i:i + 2], 16) for i in (0, 2, 4))
            cache[hexv] = "%02x%02x%02x" % kit_color(rgb)
        return f'{m.group(1)}#{cache[hexv]}'
    # Fills only: the drawing's ink is a stroke.
    text = re.sub(r'(fill=")#([0-9a-fA-F]{6})', sub, text)
    with open(path, "w") as f:
        f.write(text)


def process(photo, variants, out_root):
    pid = photo["id"]
    out_dir = os.path.join(out_root, pid)
    os.makedirs(out_dir, exist_ok=True)
    ppm = os.path.join(out_dir, "input.ppm")
    Image.open(photo["path"]).convert("RGB").save(ppm)
    scene_dir = os.path.join(SET, "scenes", pid)
    importance, subject = se.importance_from_scene(scene_dir)
    se.save_pgm(os.path.join(out_dir, "importance.pgm"), importance)
    common = ["--colors", "24", "--detail", "0.5"]
    for name in ("contours", "drawing"):
        Image.open(os.path.join(SET, "maps", f"{pid}-{name}.png")).convert("L").save(os.path.join(out_dir, name + ".pgm"))
    common += ["--line-style", "coloringBook", "--edges", os.path.join(out_dir, "contours.pgm"),
               "--lines", os.path.join(out_dir, "drawing.pgm"), "--objects", os.path.join(scene_dir, "subject.pgm")]
    eyes = os.path.join(scene_dir, "eyes.json")
    if os.path.exists(eyes) and os.path.getsize(eyes) > 2:
        common += ["--eyes", eyes]
    results = {}
    for v in variants:
        opts, back, palette = VARIANTS[v][:3]
        ink = VARIANTS[v][3] if len(VARIANTS[v]) > 3 else 1
        imp_path = os.path.join(out_dir, "importance.pgm")
        if back is not None:
            # The subject's and faces' importance as the app has it; the rest lowered to `back`.
            calm = np.where(subject >= 0.5, importance, np.minimum(importance, back))
            faces = importance >= 0.75
            calm = np.where(faces, importance, calm)
            imp_path = os.path.join(out_dir, f"importance-{v}.pgm")
            se.save_pgm(imp_path, calm)
        out = os.path.join(out_dir, v)
        os.makedirs(out, exist_ok=True)
        stats = se.generate(f"{pid}/{v}", ppm, out, common + ["--importance", imp_path] + opts)
        if stats is None:
            continue
        if palette:
            for svg in ("painted.svg", "template.svg", "painted-outlined.svg"):
                transform_svg(os.path.join(out, svg), palette)
        # The finished painting as the app shows it: the paint with the drawing in ink over it
        # (pbn's painted-outlined.svg; its region strokes are each region's own paint).
        finished = os.path.join(out, "painted-outlined.svg")
        if ink == 0:
            finished = os.path.join(out, "painted.svg")
        elif ink != 1:
            with open(finished) as f:
                text = f.read()
            i = text.find('<g id="lines-drawing"')
            text = text[:i] + re.sub(r'stroke-width="([0-9.]+)"', lambda m: f'stroke-width="{float(m.group(1)) * ink:.2f}"', text[i:])
            finished = os.path.join(out, "finished.svg")
            with open(finished, "w") as f:
                f.write(text)
        se.svg_to_png(finished, os.path.join(out, "painted.png"), 1280)
        se.svg_to_png(os.path.join(out, "template.svg"), os.path.join(out, "template.png"), 1280)
        m = se.measures(out, stats, subject)
        results[v] = m
    with open(os.path.join(out_dir, "loosen.json"), "w") as f:
        json.dump(results, f, indent=1)
    return pid, results


KEYS = [("regions", "{:.0f}"), ("colors", "{:.1f}"), ("tiny", "{:.0f}"), ("backRegionsPerKpx", "{:.2f}"),
        ("dE", "{:.4f}"), ("dEsubject", "{:.4f}"), ("detailKept", "{:.2f}"), ("smoothness", "{:.1f}"),
        ("belowLegible", "{:.0f}")]


def run(args):
    photos = se.load_manifest(SET, args.only)
    variants = args.variants.split(",")
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        results = list(pool.map(lambda p: process(p, variants, args.out), photos))
    lines = ["| variant | " + " | ".join(k for k, _ in KEYS) + " |", "|" + "---|" * (len(KEYS) + 1)]
    for v in variants:
        rows = [r[v] for _, r in results if v in r]
        if rows:
            lines.append(f"| {v} | " + " | ".join(fmt.format(np.nanmean([row[k] for row in rows])) for k, fmt in KEYS) + " |")
    text = "\n".join(lines)
    with open(os.path.join(args.out, "summary.md"), "w") as f:
        f.write(f"Means over {len(results)} photos\n\n{text}\n")
    print(text)


FONT = ImageFont.load_default(size=22)


def sheet(args):
    for v in args.variants.split(","):
        if v == "today":
            continue
        rows = []
        for pid in sorted(os.listdir(args.out)):
            d = os.path.join(args.out, pid)
            if not os.path.exists(os.path.join(d, v, "painted.png")):
                continue
            cell = 520
            photo = Image.open(os.path.join(d, "input.ppm")).convert("RGB")
            ph = int(cell * photo.height / photo.width)
            row = Image.new("RGB", (cell * 5 + 32, ph + 34), "white")
            dr = ImageDraw.Draw(row)
            row.paste(photo.resize((cell, ph), Image.LANCZOS), (0, 34))
            dr.text((4, 4), pid, fill=(0, 0, 0), font=FONT)
            panels = [("today", "painted"), (v, "painted"), ("today", "template"), (v, "template")]
            for i, (m, kind) in enumerate(panels):
                x = (i + 1) * (cell + 8)
                row.paste(Image.open(os.path.join(d, m, kind + ".png")).convert("RGB").resize((cell, ph), Image.LANCZOS), (x, 34))
                dr.text((x + 4, 4), f"{m} {kind}", fill=(0, 0, 0), font=FONT)
            rows.append(row)
        if not rows:
            continue
        width = rows[0].width
        out = Image.new("RGB", (width, sum(r.height for r in rows)), "white")
        y = 0
        for r in rows:
            out.paste(r.resize((width, int(r.height * width / r.width))), (0, y))
            y += r.height
        out.save(os.path.join(args.out, f"sheet-{v}.jpg"), quality=82)
        print(os.path.join(args.out, f"sheet-{v}.jpg"))


def grid(args):
    variants = args.variants.split(",")
    for pid in sorted(os.listdir(args.out)):
        d = os.path.join(args.out, pid)
        if not os.path.isdir(d):
            continue
        photo = Image.open(os.path.join(d, "input.ppm")).convert("RGB")
        panels = [("photo", photo)] + [(v, Image.open(os.path.join(d, v, "painted.png")).convert("RGB"))
                                       for v in variants if os.path.exists(os.path.join(d, v, "painted.png"))]
        cell = 600
        ph = int(cell * photo.height / photo.width)
        cols = 4
        rows = (len(panels) + cols - 1) // cols
        out = Image.new("RGB", (cols * (cell + 6), rows * (ph + 30)), "white")
        dr = ImageDraw.Draw(out)
        for i, (name, im) in enumerate(panels):
            x, y = (i % cols) * (cell + 6), (i // cols) * (ph + 30)
            out.paste(im.resize((cell, ph), Image.LANCZOS), (x, y + 30))
            dr.text((x + 4, y + 4), name, fill=(0, 0, 0), font=FONT)
        out.save(os.path.join(d, "grid.jpg"), quality=85)


PAGE = """<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Which would you paint?</title>
<style>
:root { --paper: #f7f4ee; --ink: #23201b; --muted: #6d665b; --line: #d9d2c5; --mark: #5a4a8a;
  --display: "New York", "Iowan Old Style", Georgia, serif; --body: -apple-system, "SF Pro Text", "Helvetica Neue", Arial, sans-serif; }
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { --paper: #1b1917; --ink: #ece7dd; --muted: #a39b8d; --line: #3a3530; --mark: #b9aee6; color-scheme: dark } }
:root[data-theme="dark"] { --paper: #1b1917; --ink: #ece7dd; --muted: #a39b8d; --line: #3a3530; --mark: #b9aee6; color-scheme: dark }
body { background: var(--paper); color: var(--ink); font-family: var(--body); line-height: 1.5; margin: 0; padding: 24px 16px 48px; }
main { max-width: 1500px; margin: 0 auto; display: grid; gap: 44px; }
h1 { font-family: var(--display); font-weight: 500; font-size: 1.9rem; margin: 0; }
p.lead { color: var(--muted); max-width: 62ch; margin: 6px 0 0; }
section { display: grid; gap: 10px; }
h2 { font-family: var(--display); font-weight: 500; font-size: 1.2rem; margin: 0; }
.row { display: grid; grid-template-columns: 1fr 2fr 2fr; gap: 10px; align-items: start; }
.row.r3 { grid-template-columns: repeat(2, minmax(0, 1fr)); }
@media (max-width: 760px) { .row, .row.r3 { grid-template-columns: 1fr; } .row figure.photo { max-width: 55%; } }
figure { margin: 0; min-width: 0; display: grid; gap: 6px; }
img { width: 100%; height: auto; display: block; border: 1px solid var(--line); }
figcaption { font-size: 0.85rem; letter-spacing: 0.04em; text-transform: uppercase; color: var(--muted); }
figcaption b { color: var(--mark); font-size: 1rem; }
footer { color: var(--muted); font-size: 0.9rem; border-top: 1px solid var(--line); padding-top: 16px; }
</style>
<main><header><h1>Which would you paint?</h1><p class="lead">__LEAD__</p></header>
__SECTIONS__
<footer>Paint by Moonlight, the over-constraint spike (painting-company row 191). Each picture is the finished painting, as the app shows it once every area is filled.</footer></main>
"""


def jpeg_uri(image, width):
    if image.width > width:
        image = image.resize((width, int(image.height * width / image.width)), Image.LANCZOS)
    buf = io.BytesIO()
    image.convert("RGB").save(buf, format="JPEG", quality=84, optimize=True)
    return "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode()


def blind(args):
    rng = random.Random(args.seed)
    variants = args.variants.split(",")
    letters = "ABC"[:len(variants)]
    sections, key = [], []
    for n, pid in enumerate(args.pairs.split(","), start=1):
        d = os.path.join(args.out, pid)
        order = variants[:]
        rng.shuffle(order)
        photo = Image.open(os.path.join(d, "input.ppm"))
        figs = [f'<figure class="photo"><img src="{jpeg_uri(photo, 480)}" alt="photo {n}"><figcaption>the photo</figcaption></figure>']
        for letter, v in zip(letters, order):
            im = Image.open(os.path.join(d, v, "painted.png"))
            figs.append(f'<figure><img src="{jpeg_uri(im, 900)}" alt="photo {n}, painting {letter}"><figcaption><b>{letter}</b></figcaption></figure>')
        sections.append(f'<section><h2>{n}</h2><div class="row r{len(variants)}">{"".join(figs)}</div></section>')
        key.append({"photo": n, "id": pid, **dict(zip(letters, order))})
    ways = {2: "two", 3: "three"}[len(variants)]
    lead = (f"{len(key)} photos, each made into a paint-by-number {ways} ways and shown finished. The letters change "
            f"places from photo to photo. For each: which would you rather have painted ({', '.join(letters)}), and a few words why. "
            "The key is kept apart.")
    with open(args.html, "w") as f:
        f.write(PAGE.replace("__LEAD__", html.escape(lead)).replace("__SECTIONS__", "\n".join(sections)))
    with open(args.html + ".key.json", "w") as f:
        json.dump(key, f, indent=1)
    print(f"{args.html}: {len(key)} photos, {os.path.getsize(args.html) / 1e6:.1f} MB; key {args.html}.key.json")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="command", required=True)
    r = sub.add_parser("run")
    r.add_argument("--out", required=True)
    r.add_argument("--only")
    r.add_argument("--variants", default=",".join(VARIANTS))
    r.add_argument("--jobs", type=int, default=4)
    s = sub.add_parser("sheet")
    s.add_argument("--out", required=True)
    s.add_argument("--variants", default=",".join(VARIANTS))
    g = sub.add_parser("grid")
    g.add_argument("--out", required=True)
    g.add_argument("--variants", default=",".join(VARIANTS))
    b = sub.add_parser("blind")
    b.add_argument("--out", required=True)
    b.add_argument("--variants", default="today,kitpaint,loosekit")
    b.add_argument("--pairs", default=BLIND_DEFAULT)
    b.add_argument("--seed", type=int, default=191)
    b.add_argument("html")
    args = ap.parse_args()
    {"run": run, "sheet": sheet, "grid": grid, "blind": blind}[args.command](args)


if __name__ == "__main__":
    main()
