#!/usr/bin/env python3
"""The short Making-of's graphite drawing, off the device (painting-company row 361).

    tools/graphite_sim.py <name>… --out <sheet.png> [--dark] [--at 0.15 0.38 0.7 1] [--height 360]

`<name>` is a photo of `Tests/Corpus` whose line maps are committed in `tools/baseline/lines/`
(barn, espresso, hibiscus, lighthouse, parrots, regatta), or a path `<photo>:<drawing.png>:<contours.png>`.
Draws each as the preview shows it at each progress of `--at` (one row per photo), as
`GraphiteSketch` (App/PaintByNumber/Features/Create/FormingShow.swift) and its shader
(`FormingGraphite.metal`) make it on the device, step for step:

- the strokes: the painting's own line drawing, recovered from `LineArtInput.edges` where it
  beat the contours (0.85 × the contour map), ramped between `DRAWING`, and the contours' cores
  ramped between `CONTOUR` at `CONTOUR_SHARE`, so outlines the drawing misses are drawn thin; the
  pencil's pressure wavers by `PRESSURE` (`wavering`), and pieces smaller than `SHORTEST` pixels
  (the photo's texture) are left out (`without_specks`). No filter of the photo;
- the halo: the strokes box-blurred twice over `HALO_RADIUS`, times `HALO_GAIN`: where the photo's
  color drains;
- the race: each pixel's arrival is its shortest way from the strongest stroke near the middle,
  strokes cheap and bare paper dear (Dijkstra on a `COARSE`-times coarser max of the strokes),
  equalized so the ink arrives evenly, bilinear between cells;
- each frame: a pixel reached comes in over `EDGE`, its stroke in the ink at `PENCIL` and fresh
  (within `FRESH` of the front) darker and warmer, the point; near a stroke the photo goes `WASH`
  of the way to the paper. Everything else is the photo, untouched.

`--at` is the race's progress, which on the device runs `FormingShow.graphiteProgress`: about two
thirds by the time an iPad Air has made the template, never done until it is. The demos hold
0.38 (`create-forming-graphite`) and 0.7 (`create-forming`). `--dark` uses the dark sheet.

Needs numpy and Pillow.
"""
import argparse
import heapq
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
# CanvasPalette's sheet paper and ink, sRGB (App/PaintByNumber/Canvas/CanvasTypes.swift).
LIGHT = (np.array([0.957, 0.937, 0.902]), np.array([0.118, 0.102, 0.133]))
DARK = (np.array([0.137, 0.118, 0.133]), np.array([0.812, 0.780, 0.827]))
WARM = np.array([0.95, 0.60, 0.25])
# GraphiteSketch's constants.
CONTOUR_WEIGHT = 0.85
DRAWING, CONTOUR, CONTOUR_SHARE, PRESSURE = (0.3, 0.7), (0.62, 0.92), 0.8, 0.2
COARSE, HALO_RADIUS, HALO_GAIN = 3, 2, 2.0
SHORTEST, STROKE_FLOOR = 24, 0.1
PENCIL, EDGE, FRESH, WASH, POINT = 0.95, 0.012, 0.06, 0.25, 0.8
INK_RIDGE, POINT_RIDGE = (0.35, 0.6), (0.12, 0.4)
CENTRE = (0.5, 0.45)


def ramp(v, a, b):
    t = np.clip((v - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def wavering(w, h):
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    u, v = xx * 0.043, yy * 0.037
    return 0.5 + 0.25 * np.sin(u + 1.7 * np.sin(v * 0.8)) + 0.25 * np.sin(v * 1.3 - 0.9 * np.sin(u * 0.7))


def strokes(drawing, contours):
    """`GraphiteSketch.strokes`: the maps (uint8, the contours at the drawing's size)."""
    scaled = np.floor(contours.astype(np.float32) * CONTOUR_WEIGHT + 0.5).astype(np.int32)
    edges = np.maximum(drawing.astype(np.int32), scaled)
    drawn = np.where(edges > scaled, edges, 0) / 255
    outline = ramp(contours / 255, *CONTOUR) * CONTOUR_SHARE
    s = np.maximum(ramp(drawn, *DRAWING), outline)
    h, w = drawing.shape
    return without_specks(s * (1 - PRESSURE + PRESSURE * wavering(w, h)))


def without_specks(s):
    """`GraphiteSketch.withoutSpecks`: pieces of stroke (above `STROKE_FLOOR`, 8-connected) of
    fewer than `SHORTEST` pixels are texture, not drawing, and are left out."""
    h, w = s.shape
    on = s > STROKE_FLOOR
    seen = np.zeros_like(on)
    out = s.copy()
    for y0, x0 in zip(*np.nonzero(on)):
        if seen[y0, x0]:
            continue
        seen[y0, x0] = True
        stack, piece = [(y0, x0)], []
        while stack:
            y, x = stack.pop()
            piece.append((y, x))
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    ny, nx = y + dy, x + dx
                    if 0 <= ny < h and 0 <= nx < w and on[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        stack.append((ny, nx))
        if len(piece) < SHORTEST:
            ys, xs = zip(*piece)
            out[list(ys), list(xs)] = 0
    return out


def box_blur(a, r):
    """A box blur over 2r + 1, edges clamped, rows then columns."""
    for axis in (1, 0):
        padded = np.pad(a, [(r, r) if k == axis else (0, 0) for k in range(2)], mode="edge")
        c = np.cumsum(padded, axis=axis, dtype=np.float64)
        c = np.concatenate([np.zeros_like(c.take([0], axis=axis)), c], axis=axis)
        n = a.shape[axis]
        a = (c.take(range(2 * r + 1, n + 2 * r + 1), axis=axis) - c.take(range(0, n), axis=axis)) / (2 * r + 1)
    return a


def halo(s):
    return np.minimum(box_blur(box_blur(s, HALO_RADIUS), HALO_RADIUS) * HALO_GAIN, 1)


def coarse_arrivals(s):
    """`GraphiteSketch.arrivals(_:width:height:)` on a grid of strokes."""
    h, w = s.shape
    cost = 1 / (0.08 + s)
    yy, xx = np.mgrid[0:h, 0:w]
    score = s - 0.6 * np.hypot(yy - h * CENTRE[1], xx - w * CENTRE[0]) / max(h, w)
    seed = np.unravel_index(np.argmax(score), score.shape)
    dist = np.full((h, w), np.inf)
    dist[seed] = 0
    queue = [(0.0, seed[0], seed[1])]
    steps = [(0, -1, 1), (0, 1, 1), (-1, 0, 1), (1, 0, 1), (-1, -1, 1.414), (-1, 1, 1.414), (1, -1, 1.414), (1, 1, 1.414)]
    while queue:
        d, y, x = heapq.heappop(queue)
        if d > dist[y, x]:
            continue
        for dy, dx, step in steps:
            Y, X = y + dy, x + dx
            if 0 <= Y < h and 0 <= X < w:
                nd = d + step * 0.5 * (cost[y, x] + cost[Y, X])
                if nd < dist[Y, X]:
                    dist[Y, X] = nd
                    heapq.heappush(queue, (nd, Y, X))
    order = np.argsort(dist, axis=None, kind="stable")
    weight = (s + 0.02).ravel()[order]
    arrival = np.empty(h * w)
    arrival[order] = np.minimum(np.cumsum(weight) / weight.sum(), 1)
    arrival[np.ravel_multi_index(seed, (h, w))] = 0
    return arrival.reshape(h, w)


def arrivals(s):
    """`GraphiteSketch.arrivals(of:width:height:)`: per cell, bilinear between cells."""
    H, W = s.shape
    h, w = H // COARSE, W // COARSE
    cells = s[: h * COARSE, : w * COARSE].reshape(h, COARSE, w, COARSE).max(axis=(1, 3))
    a = coarse_arrivals(cells)
    fy = np.clip((np.arange(H) + 0.5) / COARSE - 0.5, 0, h - 1)
    fx = np.clip((np.arange(W) + 0.5) / COARSE - 0.5, 0, w - 1)
    y0 = np.minimum(fy.astype(int), h - 2)
    x0 = np.minimum(fx.astype(int), w - 2)
    ty, tx = (fy - y0)[:, None], (fx - x0)[None, :]
    top = a[y0][:, x0] * (1 - tx) + a[y0][:, x0 + 1] * tx
    bottom = a[y0 + 1][:, x0] * (1 - tx) + a[y0 + 1][:, x0 + 1] * tx
    return top * (1 - ty) + bottom * ty


def quantized(a):
    """As the device's map stores it: 8 bits."""
    return np.round(np.clip(a, 0, 1) * 255) / 255


def inputs(name):
    if ":" in name:
        photo, drawing, contours = name.split(":")
    else:
        photo = ROOT / "Tests" / "Corpus" / f"{name}.jpg"
        drawing = ROOT / "tools" / "baseline" / "lines" / f"{name}-drawing.png"
        contours = ROOT / "tools" / "baseline" / "lines" / f"{name}-contours.png"
    d = Image.open(drawing).convert("L")
    c = Image.open(contours).convert("L")
    if c.size != d.size:
        c = c.resize(d.size, Image.BOX)
    rgb = Image.open(photo).convert("RGB").resize(d.size, Image.LANCZOS)
    return np.asarray(rgb) / 255, np.asarray(d), np.asarray(c)


def frames(name, dark, at):
    rgb, d, c = inputs(name)
    paper, ink = DARK if dark else LIGHT
    point = ink * (1 - POINT) + WARM * POINT
    s = strokes(d, c)
    near, arrival = quantized(halo(s)), quantized(arrivals(s))
    s = quantized(s)
    shown = []
    for p in at:
        # `GraphiteSketch.shade`, and the shader's colors over the photo.
        behind = p - arrival
        reached = np.clip(behind / EDGE, 0, 1)
        tip = np.where((behind >= 0) & (behind < FRESH), 1 - behind / FRESH, 0)
        pt = ramp(s, *POINT_RIDGE) * reached * tip
        a = np.maximum(ramp(s, *INK_RIDGE) * reached * (PENCIL + (1 - PENCIL) * tip), pt)
        wash = WASH * near * reached * (1 - a)
        lead = ink + (point - ink) * np.where(a > 0, pt / np.maximum(a, 1e-9), 0)[..., None]
        frame = lead * a[..., None] + paper * wash[..., None] + rgb * (1 - a - wash)[..., None]
        shown.append(frame)
    return np.concatenate(shown, axis=1)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("names", nargs="+")
    parser.add_argument("--out", required=True)
    parser.add_argument("--dark", action="store_true")
    parser.add_argument("--at", type=float, nargs="+", default=[0.15, 0.38, 0.7, 1.0])
    parser.add_argument("--height", type=int, default=360, help="each row's height in the sheet")
    args = parser.parse_args()
    rows = [frames(name, args.dark, args.at) for name in args.names]
    height = args.height
    rows = [Image.fromarray((np.clip(r, 0, 1) * 255).astype(np.uint8)) for r in rows]
    rows = [r.resize((r.width * height // r.height, height), Image.LANCZOS) for r in rows]
    sheet = Image.new("RGB", (max(r.width for r in rows), height * len(rows)), "white")
    for i, r in enumerate(rows):
        sheet.paste(r, (0, i * height))
    sheet.save(args.out)


if __name__ == "__main__":
    main()
