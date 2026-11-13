#!/usr/bin/env python3
"""Kit paint, before and after, on the evaluation set (painting-company rows 188 and 191).

    tools/kit_eval.py run --set SET --out DIR [--only id,id] [--jobs N] [--before "OPTS"] [--both "OPTS"]
        [-- <pbn options for after>]
    tools/kit_eval.py grid --out DIR [--width 1100]

`SET` is `Tests/EvalSet` of the branch `claude/over-constraint-spike` (row 188's photos, maps and
stand-in scenes; not on `main`): `git archive origin/claude/over-constraint-spike Tests/EvalSet |
tar -x -C X`, with `X/Tests/Corpus` and `X/App/PaintByNumber/Resources/Samples` linked to this
repository's, since its manifest names some photos there.

For every photo `run` makes the coloring book the app would (the set's edge maps, its stand-in
subject as the silhouette, its eyes (where the stand-in's `eyes.json` is empty, almonds at the
eye features the set marks by hand, `standin_eyes`), the app's importance map from the scene; 24 paints, detail
0.5) twice with the same pbn: `before` with the regions' paints, `after` with `--paint-mix kit`
(and any options after `--`: `-- --paint-mix lively` makes `after` lively paint, painting-company
row 326, and with `--before "--paint-mix kit"` compares it with kit paint); `--before` adds pbn options to `before` alone (a
round's baseline: `--before "--paint-mix kit"`), `--both` to both (`--auto` lets Auto choose
the colours and detail, from the scene's importance map, as the app does). It writes `DIR/<id>/{before,after}/` (pbn's output, `finished.png`:
the finished painting, paint with the drawing in ink over it, from `painted-outlined.svg`, 1280 px
wide) and `DIR/summary.md`. A painting already in `DIR` is measured again, not made again: give
each build its own `DIR`.

The measures are the finished painting's against the photo, never ΔE (a loop steered by ΔE drifts
back to the regions' means): `chroma` and `chroma90` are the painting's mean and top-decile OKLab
chroma over the photo's, `contrast` its lightness spread (5th to 95th percentile) over the photo's,
`skinC` and `skinL` the mean chroma and lightness on the scene's faces over the photo's there
(skin should stay near 1), `neon` the share of pixels with chroma above 0.25 (a kit has none).

`grid` writes `DIR/<id>/grid.jpg` (the photo, before, after, side by side at `--width` each) and
`DIR/grids.jpg` (every photo's row, smaller), to look at with the Read tool.

Requires the release pbn (tools/swift.sh build -c release --static-swift-stdlib, or PBN=...;
PBN_BEFORE=... runs `before` with another build, the last round's),
node (`cd tools && npm ci`), numpy and Pillow.
"""
import argparse
import json
import os
import re
import shlex
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PBN = os.environ.get("PBN", os.path.join(ROOT, ".build", "release", "pbn"))
# `before` from another build (the last round's), to compare rounds: PBN_BEFORE=…/pbn.
PBN_BEFORE = os.environ.get("PBN_BEFORE", PBN)
SVG2PNG = os.path.join(ROOT, "tools", "svg2png.mjs")


def read_pgm(path):
    with open(path, "rb") as f:
        data = f.read()
    m = re.match(rb"P5\s+(\d+)\s+(\d+)\s+(\d+)\s", data)
    w, h = int(m.group(1)), int(m.group(2))
    return np.frombuffer(data[m.end():m.end() + w * h], dtype=np.uint8).reshape(h, w).astype(np.float32) / 255


def save_pgm(path, values):
    h, w = values.shape
    with open(path, "wb") as f:
        f.write(f"P5\n{w} {h}\n255\n".encode())
        f.write(np.rint(np.clip(values, 0, 1) * 255).astype(np.uint8).tobytes())


def importance_from_scene(scene_dir):
    """The map `SubjectImportance.analysis` makes of the scene, as tools/scene_eval.py (row 188)
    derives it: 0.25 floor, saliency 0.2 + 0.4 s, the subject at 0.75, faces and animals raised
    toward 1 in an ellipse."""
    with open(os.path.join(scene_dir, "scene.json")) as f:
        scene = json.load(f)
    subject = read_pgm(os.path.join(scene_dir, scene["subject"]))
    saliency = read_pgm(os.path.join(scene_dir, scene["saliency"]))
    h, w = subject.shape
    m = np.maximum(np.full((h, w), 0.25, dtype=np.float32), 0.2 + 0.4 * saliency)
    m = np.maximum(m, 0.75 * subject)
    ys, xs = np.mgrid[0:h, 0:w]
    for (x, y, bw, bh) in scene.get("faces", []) + scene.get("animals", []):
        x0, y0, x1, y1 = x - bw * 0.25, y - bh * 0.3, x + bw * 1.25, y + bh * 1.3
        cx, cy = (x0 + x1) / 2 * w, (y0 + y1) / 2 * h
        rx, ry = max(1, (x1 - x0) * w / 2), max(1, (y1 - y0) * h / 2)
        d = ((xs + 0.5 - cx) / rx) ** 2 + ((ys + 0.5 - cy) / ry) ** 2
        m = np.maximum(m, np.where(d < 1.6, np.minimum(1, 1.25 - 0.5 * d), 0))
    return m, scene


def standin_eyes(scene, size):
    """Eye polygons for `pbn --eyes` from the scene's eye features, for a scene whose `eyes.json`
    is empty: an almond as wide as the eye (a feature's radius is 1.2 half-widths of the long
    side), 0.45 as tall, quantized as `EyeFinder` does. Eyes narrower than its minimum (1.2 % of
    the long side) are left out, as the app leaves them."""
    import math
    w, h = size
    long_side = max(w, h)
    polygons = []
    for f in scene.get("features", []):
        if f["kind"] != "eye":
            continue
        half = f["radius"] / 1.2 * long_side
        if 2 * half < 0.012 * long_side:
            continue
        cx, cy = f["x"] * w, f["y"] * h
        points = [(cx + half * math.cos(2 * math.pi * i / 16), cy + 0.45 * half * math.sin(2 * math.pi * i / 16))
                  for i in range(16)]
        polygons.append([[round(min(max(x / w, 0), 1) * 4096) / 4096, round(min(max(y / h, 0), 1) * 4096) / 4096]
                         for x, y in points])
    return polygons


def oklab(rgb):
    c = rgb.astype(np.float32) / 255
    lin = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    l = 0.4122214708 * lin[..., 0] + 0.5363325363 * lin[..., 1] + 0.0514459929 * lin[..., 2]
    m = 0.2119034982 * lin[..., 0] + 0.6806995451 * lin[..., 1] + 0.1073969566 * lin[..., 2]
    s = 0.0883024619 * lin[..., 0] + 0.2817188376 * lin[..., 1] + 0.6299787005 * lin[..., 2]
    l_, m_, s_ = np.cbrt(l), np.cbrt(m), np.cbrt(s)
    return np.stack([0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
                     1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
                     0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_], axis=-1)


def measures(photo_rgb, painted_rgb, faces):
    h, w = painted_rgb.shape[:2]
    photo = oklab(np.asarray(Image.fromarray(photo_rgb).resize((w, h), Image.LANCZOS)))
    paint = oklab(painted_rgb)

    def stats(lab, mask=None):
        L, C = lab[..., 0], np.hypot(lab[..., 1], lab[..., 2])
        if mask is not None:
            L, C = L[mask], C[mask]
        return C.mean(), np.percentile(C, 90), np.percentile(L, 95) - np.percentile(L, 5), L.mean(), (C > 0.25).mean()

    p, q = stats(photo), stats(paint)
    out = {"chroma": q[0] / p[0], "chroma90": q[1] / p[1], "contrast": q[2] / p[2], "neon": q[4], "photoNeon": p[4]}
    if faces:
        mask = np.zeros((h, w), bool)
        for (x, y, bw, bh) in faces:
            mask[int(y * h):int((y + bh) * h), int(x * w):int((x + bw) * w)] = True
        fp, fq = stats(photo, mask), stats(paint, mask)
        out["skinC"], out["skinL"] = fq[0] / fp[0], fq[3] / fp[3]
    return {k: float(v) for k, v in out.items()}


def process(photo, set_dir, out_root, after_opts, before_opts=(), both_opts=()):
    pid = photo["id"]
    out_dir = os.path.join(out_root, pid)
    os.makedirs(out_dir, exist_ok=True)
    ppm = os.path.join(out_dir, "input.ppm")
    source = Image.open(os.path.normpath(os.path.join(set_dir, photo["file"]))).convert("RGB")
    source.save(ppm)
    scene_dir = os.path.join(set_dir, "scenes", pid)
    importance, scene = importance_from_scene(scene_dir)
    save_pgm(os.path.join(out_dir, "importance.pgm"), importance)
    for name in ("contours", "drawing"):
        Image.open(os.path.join(set_dir, "maps", f"{pid}-{name}.png")).convert("L").save(os.path.join(out_dir, name + ".pgm"))
    common = ["--colors", "24", "--detail", "0.5", "--line-style", "coloringBook",
              "--edges", os.path.join(out_dir, "contours.pgm"), "--lines", os.path.join(out_dir, "drawing.pgm"),
              "--objects", os.path.join(scene_dir, "subject.pgm"), "--importance", os.path.join(out_dir, "importance.pgm")]
    eyes = os.path.join(scene_dir, "eyes.json")
    if os.path.exists(eyes) and os.path.getsize(eyes) > 2:
        common += ["--eyes", eyes]
    elif marked := standin_eyes(scene, source.size):
        # The stand-in's landmarker missed these faces, whose eyes the set marks by hand
        # (`overrides.json`) and Vision finds on the device: almonds at the marked eyes.
        eyes = os.path.join(out_dir, "eyes.json")
        with open(eyes, "w") as f:
            json.dump(marked, f)
        common += ["--eyes", eyes]
    results = {}
    common += list(both_opts)
    for variant, opts in (("before", list(before_opts)), ("after", ["--paint-mix", "kit"] + after_opts)):
        out = os.path.join(out_dir, variant)
        png = os.path.join(out, "finished.png")
        if os.path.exists(png):  # made by an earlier run into this DIR: a new build needs a new DIR
            results[variant] = measures(np.asarray(source), np.asarray(Image.open(png).convert("RGB")), scene.get("faces"))
            continue
        os.makedirs(out, exist_ok=True)
        pbn = PBN_BEFORE if variant == "before" else PBN
        r = subprocess.run([pbn, "generate", ppm, out] + common + opts, capture_output=True, text=True)
        if r.returncode != 0:
            print(f"{pid}/{variant}: pbn failed\n{r.stderr[-2000:]}", file=sys.stderr)
            return pid, None
        subprocess.run(["node", SVG2PNG, os.path.join(out, "painted-outlined.svg"), png, "1280"], check=True,
                       cwd=os.path.join(ROOT, "tools"))
        results[variant] = measures(np.asarray(source), np.asarray(Image.open(png).convert("RGB")), scene.get("faces"))
        with open(os.path.join(out, "stats.json")) as f:
            stats = json.load(f)
        results[variant].update(regions=stats["regions"], colors=stats["colors"],
                                tiny=stats.get("regionsUnderRadius3", 0))
        if "auto" in stats:
            results[variant]["detail"] = stats["auto"]["settings"]["detail"]
    with open(os.path.join(out_dir, "kit.json"), "w") as f:
        json.dump(results, f, indent=1)
    return pid, results


KEYS = ["chroma", "chroma90", "contrast", "skinC", "skinL", "neon", "regions", "colors", "detail"]


def run(args, after_opts):
    with open(os.path.join(args.set, "manifest.json")) as f:
        photos = json.load(f)["photos"]
    if args.only:
        wanted = set(args.only.split(","))
        photos = [p for p in photos if p["id"] in wanted]
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        results = [r for r in pool.map(lambda p: process(p, args.set, args.out, after_opts, shlex.split(args.before),
                                                   shlex.split(args.both)), photos) if r[1]]
    lines = ["| photo | variant | " + " | ".join(KEYS) + " |", "|" + "---|" * (len(KEYS) + 2)]
    for pid, r in results + [("mean", None)]:
        for v in ("before", "after"):
            rows = [r[v]] if r else [x[v] for _, x in results]
            cells = []
            for k in KEYS:
                vals = [row[k] for row in rows if k in row]
                cells.append(f"{np.mean(vals):.3f}" if vals else "")
            lines.append(f"| {pid} | {v} | " + " | ".join(cells) + " |")
    text = "\n".join(lines)
    with open(os.path.join(args.out, "summary.md"), "w") as f:
        f.write(f"Both: {args.both}  Before: {args.before}  After: --paint-mix kit {' '.join(after_opts)}\n\n{text}\n")
    print(text)


def grid(args):
    font = ImageFont.load_default(size=28)
    rows = []
    for pid in sorted(os.listdir(args.out)):
        d = os.path.join(args.out, pid)
        if not os.path.exists(os.path.join(d, "after", "finished.png")):
            continue
        tiles = []
        for label, path in (("photo", os.path.join(d, "input.ppm")), ("before", os.path.join(d, "before", "finished.png")),
                            ("after", os.path.join(d, "after", "finished.png"))):
            im = Image.open(path).convert("RGB")
            im = im.resize((args.width, round(im.height * args.width / im.width)), Image.LANCZOS)
            ImageDraw.Draw(im).text((12, 8), f"{pid} {label}", fill=(0, 0, 0), font=font, stroke_width=3,
                                    stroke_fill=(255, 255, 255))
            tiles.append(im)
        row = Image.new("RGB", (sum(t.width for t in tiles), max(t.height for t in tiles)), "white")
        x = 0
        for t in tiles:
            row.paste(t, (x, 0))
            x += t.width
        row.save(os.path.join(d, "grid.jpg"), quality=92)
        rows.append(row.resize((row.width // 3, row.height // 3), Image.LANCZOS))
    if rows:
        sheet = Image.new("RGB", (max(r.width for r in rows), sum(r.height for r in rows)), "white")
        y = 0
        for r in rows:
            sheet.paste(r, (0, y))
            y += r.height
        sheet.save(os.path.join(args.out, "grids.jpg"), quality=88)


def main():
    argv = sys.argv[1:]
    after_opts = []
    if "--" in argv:
        i = argv.index("--")
        argv, after_opts = argv[:i], argv[i + 1:]
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("run")
    r.add_argument("--set", required=True)
    r.add_argument("--out", required=True)
    r.add_argument("--only")
    r.add_argument("--jobs", type=int, default=2)
    r.add_argument("--before", default="")
    r.add_argument("--both", default="")
    g = sub.add_parser("grid")
    g.add_argument("--out", required=True)
    g.add_argument("--width", type=int, default=1100)
    args = ap.parse_args(argv)
    if args.cmd == "run":
        run(args, after_opts)
    else:
        grid(args)


if __name__ == "__main__":
    main()
