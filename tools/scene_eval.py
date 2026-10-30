#!/usr/bin/env python3
"""The evaluation of the scene method against the color method on `Tests/EvalSet` (painting-company row 188).

    tools/scene_eval.py run --out DIR [--set Tests/EvalSet] [--only id,id] [--colors 24] [--detail 0.5]
        [--book | --classic] [--old OPTIONS] [--new OPTIONS] [--jobs N]
    tools/scene_eval.py blind --out DIR --pairs id,id,... [--seed N]

For every photo of the set's `manifest.json`, `run` generates two templates with the release pbn:
`old`, the color method as the app runs it today (the importance map the app would derive from the
scene's Vision findings, `--importance`), and `new`, the scene method (`--method scene --scene`),
both with the stand-in scene of `<set>/scenes/<id>/scene.json` (`tools/scene_standin.py`) and, as
coloring books (the default; --classic for classic lines), the edge maps of `<set>/maps/`, the
subject mask as the silhouette to close (`--objects`) and the stand-in's eye outlines
(`--eyes`), as the app passes Vision's. It
writes `DIR/<id>/{old,new}/` (pbn's output, each view rasterized), `DIR/<id>/pair.png` (the photo,
old and new side by side: the finished painting, then the template, with the measures under each)
and `DIR/summary.json` and `DIR/summary.md` (the measures of every photo and their means),
and prints the table.

Measures (per photo and method; from pbn's stats.json unless said otherwise, the rest computed
here from pbn's rasters and the scene's subject mask at the working size):

  dE, p95 dE        mean and 95th-percentile OKLab distance of the finished painting to the photo
  dE subject/back   the same split by the subject mask (pixels where the mask is above half)
  detail kept       of the photo's strong edges on the subject (the top decile of the gradient
                    magnitude of the working image inside the mask, a pixel-wide ridge), the share
                    within 2 px of a region boundary: how much of the subject's detail the regions
                    keep (an eye's rim, a whisker's edge)
  back regions/kpx  regions per 1000 px² of background: how calm the background is
  regions, colors   counts (the app's limits: colors ≤ the setting; regions are what they are)
  tiny (r<3)        regions whose inscribed radius is under 3 units (unpaintable crumbs)
  smoothness        mean absolute turning angle per unit length along the template's edges
                    (degrees per unit, from template.svg's polylines; lower is calmer)
  numbers           the smallest label room (single-digit equivalent) and the count below legible
  ms                pbn's total pipeline time on this machine (device times come from CI's bench)

`blind` lays out A/B pairs for a reader who must not know which is which: `DIR/blind/<n>.png` with
the two paintings labelled A and B in a per-pair random order, and `DIR/blind/key.json` the key,
to be kept apart from the pictures.

Requires the release pbn (tools/swift.sh build -c release --static-swift-stdlib, or PBN=...), node
(`cd tools && npm ci`), numpy and Pillow.
"""
import argparse
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

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PBN = os.environ.get("PBN", os.path.join(ROOT, ".build", "release", "pbn"))
SVG2PNG = os.path.join(ROOT, "tools", "svg2png.mjs")
DEFAULT_SET = os.path.join(ROOT, "Tests", "EvalSet")
METHODS = ["old", "new"]


def svg_to_png(svg, png, width=None):
    cmd = ["node", SVG2PNG, svg, png] + ([str(width)] if width else [])
    subprocess.run(cmd, check=True, cwd=os.path.join(ROOT, "tools"))


def load_manifest(set_dir, only):
    with open(os.path.join(set_dir, "manifest.json")) as f:
        photos = json.load(f)["photos"]
    if only:
        wanted = set(only.split(","))
        photos = [p for p in photos if p["id"] in wanted]
    out = []
    for p in photos:
        path = os.path.normpath(os.path.join(set_dir, p["file"]))
        if not os.path.exists(path):
            print(f"{p['id']}: {path} is missing, skipped", file=sys.stderr)
            continue
        out.append({**p, "path": path})
    return out


# MARK: - The app's importance map from a scene (SubjectImportance.analysis, in numpy)

def read_pgm(path):
    with open(path, "rb") as f:
        data = f.read()
    m = re.match(rb"P5\s+(\d+)\s+(\d+)\s+(\d+)\s", data)
    w, h = int(m.group(1)), int(m.group(2))
    return np.frombuffer(data[m.end():m.end() + w * h], dtype=np.uint8).reshape(h, w).astype(np.float32) / 255


def importance_from_scene(scene_dir):
    """The importance map `SubjectImportance.analysis` would make of these findings: 0.25 floor,
    saliency 0.2 + 0.4 s, the subject at 0.75, faces and animals raised toward 1 in an ellipse."""
    with open(os.path.join(scene_dir, "scene.json")) as f:
        scene = json.load(f)
    subject = read_pgm(os.path.join(scene_dir, scene["subject"]))
    saliency = read_pgm(os.path.join(scene_dir, scene["saliency"]))
    h, w = subject.shape
    m = np.full((h, w), 0.25, dtype=np.float32)
    m = np.maximum(m, 0.2 + 0.4 * saliency)
    m = np.maximum(m, 0.75 * subject)
    ys, xs = np.mgrid[0:h, 0:w]
    for (x, y, bw, bh) in scene.get("faces", []) + scene.get("animals", []):
        x0, y0, x1, y1 = x - bw * 0.25, y - bh * 0.3, x + bw * 1.25, y + bh * 1.3
        cx, cy = (x0 + x1) / 2 * w, (y0 + y1) / 2 * h
        rx, ry = max(1, (x1 - x0) * w / 2), max(1, (y1 - y0) * h / 2)
        d = ((xs + 0.5 - cx) / rx) ** 2 + ((ys + 0.5 - cy) / ry) ** 2
        v = np.where(d < 1.6, np.minimum(1, 1.25 - 0.5 * d), 0)
        m = np.maximum(m, v)
    return m, subject


def save_pgm(path, values):
    h, w = values.shape
    with open(path, "wb") as f:
        f.write(f"P5\n{w} {h}\n255\n".encode())
        f.write(np.rint(np.clip(values, 0, 1) * 255).astype(np.uint8).tobytes())


# MARK: - Measures computed here

def oklab(rgb):
    """sRGB bytes (h, w, 3) → OKLab, like ColorScience (Björn Ottosson's matrices)."""
    c = rgb.astype(np.float32) / 255
    lin = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    l = 0.4122214708 * lin[..., 0] + 0.5363325363 * lin[..., 1] + 0.0514459929 * lin[..., 2]
    m = 0.2119034982 * lin[..., 0] + 0.6806995451 * lin[..., 1] + 0.1073969566 * lin[..., 2]
    s = 0.0883024619 * lin[..., 0] + 0.2817188376 * lin[..., 1] + 0.6299787005 * lin[..., 2]
    l_, m_, s_ = np.cbrt(l), np.cbrt(m), np.cbrt(s)
    L = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_
    a = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_
    b = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
    return np.stack([L, a, b], axis=-1)


def boundary_mask(raster):
    """Pixels where the painted raster changes to a neighbour (a region boundary, 1 px)."""
    r = raster
    b = np.zeros(r.shape[:2], dtype=bool)
    diff_x = np.any(r[:, 1:] != r[:, :-1], axis=-1)
    diff_y = np.any(r[1:, :] != r[:-1, :], axis=-1)
    b[:, 1:] |= diff_x
    b[:, :-1] |= diff_x
    b[1:, :] |= diff_y
    b[:-1, :] |= diff_y
    return b


def dilate(mask, radius):
    out = mask.copy()
    for dy in range(-radius, radius + 1):
        for dx in range(-radius, radius + 1):
            if dx * dx + dy * dy > radius * radius or (dx == 0 and dy == 0):
                continue
            shifted = np.zeros_like(mask)
            ys = slice(max(0, dy), mask.shape[0] + min(0, dy))
            yd = slice(max(0, -dy), mask.shape[0] + min(0, -dy))
            xs = slice(max(0, dx), mask.shape[1] + min(0, dx))
            xd = slice(max(0, -dx), mask.shape[1] + min(0, -dx))
            shifted[yd, xd] = mask[ys, xs]
            out |= shifted
    return out


def gradient_magnitude(lab):
    L = lab[..., 0]
    gx = np.zeros_like(L)
    gy = np.zeros_like(L)
    gx[:, 1:-1] = (L[:, 2:] - L[:, :-2]) / 2
    gy[1:-1, :] = (L[2:, :] - L[:-2, :]) / 2
    return np.hypot(gx, gy)


def ridge(mag):
    """Pixels that are a local maximum of `mag` across either axis (a pixel-wide edge)."""
    r = np.zeros_like(mag, dtype=bool)
    r[:, 1:-1] |= (mag[:, 1:-1] >= mag[:, :-2]) & (mag[:, 1:-1] >= mag[:, 2:])
    r[1:-1, :] |= (mag[1:-1, :] >= mag[:-2, :]) & (mag[1:-1, :] >= mag[2:, :])
    return r


def edge_turning(svg_path):
    """Mean absolute turning angle per unit of length along the template's boundary polylines,
    in degrees per unit: pbn's template.svg holds each edge as a `<path d="M x y L x y ...">`."""
    with open(svg_path) as f:
        text = f.read()
    total_angle = 0.0
    total_length = 0.0
    for d in re.findall(r' d="([^"]+)"', text):
        nums = re.findall(r"-?\d+(?:\.\d+)?(?:e-?\d+)?", d)
        if len(nums) < 6:
            continue
        pts = np.array(nums, dtype=np.float64).reshape(-1, 2)
        v = np.diff(pts, axis=0)
        lengths = np.hypot(v[:, 0], v[:, 1])
        keep = lengths > 1e-6
        v, lengths = v[keep], lengths[keep]
        if len(v) < 2:
            continue
        angles = np.arctan2(v[:, 1], v[:, 0])
        turn = np.abs((np.diff(angles) + np.pi) % (2 * np.pi) - np.pi)
        total_angle += np.degrees(turn).sum()
        total_length += lengths.sum()
    return total_angle / total_length if total_length > 0 else 0.0


def measures(out_dir, stats, subject_small):
    """The measures of one generation, from pbn's output in `out_dir` and the subject mask."""
    working = np.asarray(Image.open(os.path.join(out_dir, "working.ppm")).convert("RGB"))
    raster = np.asarray(Image.open(os.path.join(out_dir, "raster.ppm")).convert("RGB"))
    h, w = working.shape[:2]
    subject = np.asarray(Image.fromarray((subject_small * 255).astype(np.uint8)).resize((w, h), Image.BILINEAR)) >= 128
    lab_photo = oklab(working)
    lab_paint = oklab(raster)
    de = np.sqrt(((lab_photo - lab_paint) ** 2).sum(axis=-1))
    background = ~subject
    boundaries = boundary_mask(raster)
    near = dilate(boundaries, 2)
    mag = gradient_magnitude(lab_photo)
    strong = np.zeros_like(subject)
    if subject.any():
        threshold = np.quantile(mag[subject], 0.9)
        strong = subject & ridge(mag) & (mag >= threshold) & (mag > 0.01)
    detail_kept = float(near[strong].mean()) if strong.any() else float("nan")
    # Regions per 1000 px² of background: regions whose pixels are mostly background.
    region_map = None
    back_regions = float("nan")
    try:
        # pbn writes no region id raster; count distinct painted colours' connected areas crudely
        # from the boundaries instead: the number of 4-connected components of ~boundaries that
        # lie mostly in the background.
        from scipy import ndimage
        labels, n = ndimage.label(~boundaries)
        if n > 0:
            frac = ndimage.mean(background.astype(np.float32), labels, index=np.arange(1, n + 1))
            back_regions = float((np.asarray(frac) > 0.5).sum()) / max(1.0, background.sum() / 1000)
    except ImportError:
        pass
    return {
        "dE": float(de.mean()), "p95dE": float(np.quantile(de, 0.95)),
        "dEsubject": float(de[subject].mean()) if subject.any() else float("nan"),
        "dEbackground": float(de[background].mean()) if background.any() else float("nan"),
        "detailKept": detail_kept,
        "subjectShare": float(subject.mean()),
        "backRegionsPerKpx": back_regions,
        "regions": stats["regions"], "colors": stats["colors"],
        "tiny": stats["regionsUnderRadius3"],
        "smoothness": edge_turning(os.path.join(out_dir, "template.svg")),
        "minLabelRoom": stats["minLabelRoom"], "belowLegible": stats["labelsBelowLegibleSize"],
        "valid": stats["valid"], "ms": stats["totalMs"], "bytes": stats["encodedBytes"],
    }


# MARK: - Generation and sheets

def generate(label, ppm, out, args):
    res = subprocess.run([PBN, "generate", ppm, out] + args, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"[{label}] FAILED\n{res.stderr}", file=sys.stderr)
        return None
    with open(os.path.join(out, "stats.json")) as f:
        return json.load(f)


FONT = ImageFont.load_default(size=15)


def caption_lines(m):
    return [
        f"dE {m['dE']:.4f} (subject {m['dEsubject']:.4f}, back {m['dEbackground']:.4f})  p95 {m['p95dE']:.3f}",
        f"regions {m['regions']}  colors {m['colors']}  tiny {m['tiny']}  back {m['backRegionsPerKpx']:.2f}/kpx",
        f"detail kept {100 * m['detailKept']:.0f}%  smoothness {m['smoothness']:.1f}°/u  "
        f"numbers ≥ {m['minLabelRoom']:.2f} ({m['belowLegible']} illegible)  {m['ms']:.0f} ms",
    ]


def pair_sheet(photo_dir, photo_path, results, cell=640):
    """`pair.png`: the photo and, per method, the finished painting over the template, measures under."""
    photo = Image.open(photo_path).convert("RGB")
    w, h = photo.size
    ph = int(cell * h / w)
    text_h = 20 * 3 + 10
    sheet = Image.new("RGB", (cell * 3 + 16, 2 * ph + text_h + 36 + 8), "white")
    d = ImageDraw.Draw(sheet)
    sheet.paste(photo.resize((cell, ph), Image.LANCZOS), (0, 36))
    d.text((6, 8), os.path.basename(photo_dir), fill=(0, 0, 0), font=ImageFont.load_default(size=20))
    for i, method in enumerate(METHODS):
        x = (i + 1) * (cell + 8)
        label = {"old": "color method (today)", "new": "scene method (new)"}[method]
        d.text((x + 6, 8), label, fill=(0, 0, 0), font=ImageFont.load_default(size=20))
        out = os.path.join(photo_dir, method)
        if method not in results:
            d.text((x + 6, 48), "failed", fill=(200, 0, 0), font=FONT)
            continue
        for row, name in enumerate(["painted", "template"]):
            png = os.path.join(out, name + ".png")
            if not os.path.exists(png):
                svg_to_png(os.path.join(out, name + ".svg"), png, cell)
            sheet.paste(Image.open(png).convert("RGB").resize((cell, ph), Image.LANCZOS), (x, 36 + row * ph))
        for k, line in enumerate(caption_lines(results[method])):
            d.text((x + 6, 36 + 2 * ph + 6 + 20 * k), line, fill=(0, 0, 0), font=FONT)
    sheet.save(os.path.join(photo_dir, "pair.png"))


def process(photo, args, out_root):
    pid = photo["id"]
    out_dir = os.path.join(out_root, pid)
    os.makedirs(out_dir, exist_ok=True)
    ppm = os.path.join(out_dir, "input.ppm")
    Image.open(photo["path"]).convert("RGB").save(ppm)
    scene_dir = os.path.join(args.set, "scenes", pid)
    scene_json = os.path.join(scene_dir, "scene.json")
    has_scene = os.path.exists(scene_json)
    if has_scene:
        importance, subject = importance_from_scene(scene_dir)
        save_pgm(os.path.join(out_dir, "importance.pgm"), importance)
    else:
        print(f"{pid}: no scene in {scene_dir}; both methods run without one", file=sys.stderr)
        subject = np.ones((16, 16), dtype=np.float32)
    common = ["--colors", str(args.colors), "--detail", str(args.detail)]
    if not args.classic:
        contours = os.path.join(args.set, "maps", pid + "-contours.png")
        drawing = os.path.join(args.set, "maps", pid + "-drawing.png")
        if os.path.exists(contours) and os.path.exists(drawing):
            # pbn reads PGM; the set keeps the maps as PNG.
            for png, name in ((contours, "contours"), (drawing, "drawing")):
                Image.open(png).convert("L").save(os.path.join(out_dir, name + ".pgm"))
            common += ["--line-style", "coloringBook", "--edges", os.path.join(out_dir, "contours.pgm"),
                       "--lines", os.path.join(out_dir, "drawing.pgm")]
            if has_scene:
                common += ["--objects", os.path.join(scene_dir, "subject.pgm")]
                eyes = os.path.join(scene_dir, "eyes.json")
                if os.path.exists(eyes) and os.path.getsize(eyes) > 2:
                    common += ["--eyes", eyes]
        else:
            print(f"{pid}: no edge maps in {os.path.dirname(contours)}; classic lines", file=sys.stderr)
    per_method = {
        "old": (["--importance", os.path.join(out_dir, "importance.pgm")] if has_scene else []) + args.old,
        "new": ["--method", "scene"] + (["--scene", scene_json] if has_scene else []) + args.new,
    }
    results = {}
    for method in METHODS:
        out = os.path.join(out_dir, method)
        os.makedirs(out, exist_ok=True)
        stats = generate(f"{pid}/{method}", ppm, out, common + per_method[method])
        if stats is None:
            continue
        for name in ("painted", "template"):
            svg_to_png(os.path.join(out, name + ".svg"), os.path.join(out, name + ".png"), 1280)
        results[method] = measures(out, stats, subject)
    pair_sheet(out_dir, photo["path"], results)
    return pid, results


COLUMNS = [("dE", "{:.4f}"), ("dEsubject", "{:.4f}"), ("dEbackground", "{:.4f}"), ("detailKept", "{:.2f}"),
           ("regions", "{:.0f}"), ("backRegionsPerKpx", "{:.2f}"), ("tiny", "{:.0f}"), ("colors", "{:.0f}"),
           ("smoothness", "{:.1f}"), ("minLabelRoom", "{:.2f}"), ("belowLegible", "{:.0f}"), ("ms", "{:.0f}")]


def summarize(all_results, out_root):
    rows = []
    for pid, results in all_results:
        for method in METHODS:
            if method in results:
                rows.append({"id": pid, "method": method, **results[method]})
    means = {}
    for method in METHODS:
        sel = [r for r in rows if r["method"] == method]
        means[method] = {k: float(np.nanmean([r[k] for r in sel])) for k, _ in COLUMNS} if sel else {}
    with open(os.path.join(out_root, "summary.json"), "w") as f:
        json.dump({"rows": rows, "means": means}, f, indent=1)
    lines = ["| photo | method | " + " | ".join(k for k, _ in COLUMNS) + " |", "|" + "---|" * (len(COLUMNS) + 2)]
    for r in rows:
        lines.append(f"| {r['id']} | {r['method']} | " + " | ".join(fmt.format(r[k]) for k, fmt in COLUMNS) + " |")
    for method in METHODS:
        if means[method]:
            lines.append(f"| **mean** | {method} | " + " | ".join(fmt.format(means[method][k]) for k, fmt in COLUMNS) + " |")
    text = "\n".join(lines)
    with open(os.path.join(out_root, "summary.md"), "w") as f:
        f.write(text + "\n")
    print(text)


def run(args):
    photos = load_manifest(args.set, args.only)
    os.makedirs(args.out, exist_ok=True)
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        all_results = list(pool.map(lambda p: process(p, args, args.out), photos))
    summarize(all_results, args.out)
    # One overview of every pair, for a quick scroll.
    pairs = [os.path.join(args.out, pid, "pair.png") for pid, _ in all_results if os.path.exists(os.path.join(args.out, pid, "pair.png"))]
    if pairs:
        ims = [Image.open(p).convert("RGB") for p in pairs]
        width = max(im.width for im in ims)
        scale = 1200 / width
        thumbs = [im.resize((int(im.width * scale), int(im.height * scale)), Image.LANCZOS) for im in ims]
        sheet = Image.new("RGB", (1200, sum(t.height for t in thumbs)), "white")
        y = 0
        for t in thumbs:
            sheet.paste(t, (0, y))
            y += t.height
        sheet.save(os.path.join(args.out, "overview.jpg"), quality=85)


def blind(args):
    """A/B pairs in random order, with the key kept apart."""
    rng = random.Random(args.seed)
    out = os.path.join(args.out, "blind")
    os.makedirs(out, exist_ok=True)
    key = []
    for n, pid in enumerate(args.pairs.split(","), start=1):
        order = METHODS[:] if rng.random() < 0.5 else METHODS[::-1]
        photo = Image.open(os.path.join(args.out, pid, "input.ppm")).convert("RGB")
        cell = 720
        ph = int(cell * photo.height / photo.width)
        sheet = Image.new("RGB", (cell * 3 + 16, ph + 40), "white")
        d = ImageDraw.Draw(sheet)
        sheet.paste(photo.resize((cell, ph), Image.LANCZOS), (0, 40))
        d.text((6, 8), f"pair {n}: the photo", fill=(0, 0, 0), font=ImageFont.load_default(size=22))
        for i, (letter, method) in enumerate(zip("AB", order)):
            x = (i + 1) * (cell + 8)
            png = os.path.join(args.out, pid, method, "painted.png")
            sheet.paste(Image.open(png).convert("RGB").resize((cell, ph), Image.LANCZOS), (x, 40))
            d.text((x + 6, 8), letter, fill=(0, 0, 0), font=ImageFont.load_default(size=22))
        sheet.save(os.path.join(out, f"{n}.png"))
        key.append({"pair": n, "photo": pid, "A": order[0], "B": order[1]})
    with open(os.path.join(out, "key.json"), "w") as f:
        json.dump(key, f, indent=1)
    print(f"{len(key)} pairs in {out}; the key is key.json")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="command", required=True)
    r = sub.add_parser("run")
    r.add_argument("--out", required=True)
    r.add_argument("--set", default=DEFAULT_SET)
    r.add_argument("--only")
    r.add_argument("--colors", type=int, default=24)
    r.add_argument("--detail", type=float, default=0.5)
    r.add_argument("--classic", action="store_true")
    r.add_argument("--book", action="store_true")
    r.add_argument("--old", default="", help="extra pbn options for the color method")
    r.add_argument("--new", default="", help="extra pbn options for the scene method")
    r.add_argument("--jobs", type=int, default=2)
    b = sub.add_parser("blind")
    b.add_argument("--out", required=True)
    b.add_argument("--pairs", required=True)
    b.add_argument("--seed", type=int, default=188)
    args = ap.parse_args()
    if args.command == "run":
        args.old = args.old.split() if args.old else []
        args.new = args.new.split() if args.new else []
        run(args)
    else:
        blind(args)


if __name__ == "__main__":
    main()
