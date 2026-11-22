#!/usr/bin/env python3
"""The short Making-of's graphite drawing, off the device (painting-company row 361).

    tools/graphite_sim.py <photo>… --out <sheet.png> [--dark] [--at 0.15 0.38 0.7 1] [--height 360]

Draws each photo as the preview shows it at each progress of `--at` (one row per photo), as
`GraphiteSketch` (App/PaintByNumber/Features/Create/FormingShow.swift) makes it with Core Image on
the device, step for step:

- the photo at most 900 px across, in grey, through a 3 × 3 median (specks out);
- its lines: the grey's difference of Gaussians (`FINE`, `BROAD`), dark where the photo is darker
  than around it, times `GAIN` less `THRESHOLD`, so only real edges draw and flat paper and sky
  stay bare, then opened (a minimum, then a maximum, over 3 × 3) so no isolated speck is left;
- light hatching for the shadows: 45° stripes (`HATCH_WIDTH`) times how dark the blurred grey is
  below `SHADOW`, at most `HATCH`; the strokes are the lines screened with the hatching;
- the drawing: the strokes in the sheet's ink over the grey gone `PAPER` of the way to its paper;
- the race: each pixel's arrival is its shortest way from the strongest line near the middle,
  lines cheap and bare paper dear (Dijkstra on a quarter-size max of the lines), equalized so
  that the ink arrives evenly over the race;
- `STAGES` images, each the drawing wherever the race has reached by its end (the photo keeps its
  color everywhere else), cross-faded as the progress passes; and at the leading tip, the
  freshest strokes under a warm glint (`GLINT`, half size on the device).

`--at` is the race's progress, which on the device runs `FormingShow.graphiteProgress`: about two
thirds by the time an iPad Air has made the template, never done until it is.

Core Image's blurs, median and stripes differ a little from Pillow's: a guide to the look and the
parameters' balance, not a pixel match. `--dark` uses the dark sheet.
"""
import argparse
import heapq

import numpy as np
from PIL import Image, ImageFilter

# CanvasPalette's sheet paper and ink, sRGB (App/PaintByNumber/Canvas/CanvasTypes.swift).
LIGHT = (np.array([0.957, 0.937, 0.902]), np.array([0.118, 0.102, 0.133]))
DARK = (np.array([0.137, 0.118, 0.133]), np.array([0.812, 0.780, 0.827]))
WARM = np.array([0.75, 0.52, 0.30])
# GraphiteSketch's constants.
LONG_SIDE, FINE, BROAD, GAIN, THRESHOLD = 900, 1.8, 4.5, 14.0, 0.2
SHADOW, HATCH, HATCH_WIDTH, PENCIL, PAPER = 0.4, 0.16, 3.5, 0.9, 0.9
STAGES, COARSE, GLINT = 8, 4, 0.9


def blur(a, sigma):
    return np.asarray(Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(sigma))) / 255


def race(lines):
    """Each pixel's arrival (0…1), as `GraphiteSketch.arrivals` works it out."""
    H, W = lines.shape
    h, w = H // COARSE, W // COARSE
    s = lines[: h * COARSE, : w * COARSE].reshape(h, COARSE, w, COARSE).max(axis=(1, 3))
    cost = 1 / (0.2 + s)
    yy, xx = np.mgrid[0:h, 0:w]
    score = s - 0.6 * np.hypot(yy - h * 0.45, xx - w * 0.5) / max(h, w)
    seed = np.unravel_index(np.argmax(score), score.shape)
    dist = np.full((h, w), np.inf)
    dist[seed] = 0
    queue = [(0.0, seed[0], seed[1])]
    steps = [(-1, 0, 1), (1, 0, 1), (0, -1, 1), (0, 1, 1), (-1, -1, 1.414), (-1, 1, 1.414), (1, -1, 1.414), (1, 1, 1.414)]
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
    # Equalized: a cell's arrival is the share of the ink (and a little of the paper) reached first.
    order = np.argsort(dist, axis=None, kind="stable")
    weight = (s + 0.15).ravel()[order]
    arrival = np.empty(h * w)
    arrival[order] = np.cumsum(weight) / weight.sum()
    arrival = arrival.reshape(h, w)
    return np.asarray(Image.fromarray((arrival * 255).astype(np.uint8)).resize((W, H), Image.BILINEAR)) / 255


def frames(photo, dark, at):
    image = Image.open(photo).convert("RGB")
    s = min(1, LONG_SIDE / max(image.size))
    image = image.resize((int(image.width * s), int(image.height * s)), Image.LANCZOS)
    rgb = np.asarray(image) / 255
    grey = np.asarray(image.convert("L").filter(ImageFilter.MedianFilter(3))) / 255
    paper, ink = DARK if dark else LIGHT
    glint = ink * 0.5 + WARM * 0.5

    lines = np.clip((blur(grey, BROAD) - blur(grey, FINE)) * GAIN - THRESHOLD, 0, 1)
    opened = Image.fromarray((lines * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MaxFilter(3))
    lines = np.asarray(opened) / 255
    tone = np.clip((SHADOW - blur(grey, 3)) * (1.5 / SHADOW), 0, 1)
    H, W = grey.shape
    yy, xx = np.mgrid[0:H, 0:W]
    phase = ((xx + yy) / np.sqrt(2) % (2 * HATCH_WIDTH)) / (2 * HATCH_WIDTH)
    stripe = np.clip((np.abs(phase - 0.5) - 0.25) * 4 + 0.5, 0, 1)
    hatch = tone * stripe * HATCH
    strokes = 1 - (1 - lines * PENCIL) * (1 - hatch)
    base = grey[..., None] * (1 - PAPER) + paper * PAPER
    drawing = ink * strokes[..., None] + base * (1 - strokes[..., None])

    arrival = race(lines)
    reach = [np.clip(2 * (j + 1.5 - STAGES * arrival), 0, 1) for j in range(STAGES)]
    # A stage's fresh strokes: reached by it and not by the one before.
    glints = [blur(lines * reach[j] * (1 - (reach[j - 1] if j else 0)), 2) * 2.5 for j in range(STAGES)]

    shown = []
    for p in at:
        k = p * STAGES
        done = int(min(k, STAGES))
        frame = rgb.copy()
        # As FormingShowLayers draws them: the stage passed, the stage coming in, and the glint
        # passing from the one's fresh strokes to the other's.
        layers = []
        if done >= 1:
            layers.append((reach[done - 1], drawing, 1.0))
        if done < STAGES:
            layers.append((reach[done], drawing, k - done))
            if done >= 1:
                layers.append((np.clip(glints[done - 1], 0, 1) * GLINT, glint, 1 - (k - done)))
            layers.append((np.clip(glints[done], 0, 1) * GLINT, glint, k - done))
        for alpha, color, opacity in layers:
            a = (alpha * opacity)[..., None]
            frame = color * a + frame * (1 - a)
        shown.append(frame)
    return np.concatenate(shown, axis=1)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("photos", nargs="+")
    parser.add_argument("--out", required=True)
    parser.add_argument("--dark", action="store_true")
    parser.add_argument("--at", type=float, nargs="+", default=[0.15, 0.38, 0.7, 1.0])
    parser.add_argument("--height", type=int, default=360, help="each row's height in the sheet")
    args = parser.parse_args()
    rows = [frames(photo, args.dark, args.at) for photo in args.photos]
    height = args.height
    rows = [Image.fromarray((np.clip(r, 0, 1) * 255).astype(np.uint8)) for r in rows]
    rows = [r.resize((r.width * height // r.height, height), Image.LANCZOS) for r in rows]
    sheet = Image.new("RGB", (max(r.width for r in rows), height * len(rows)), "white")
    for i, r in enumerate(rows):
        sheet.paste(r, (0, i * height))
    sheet.save(args.out)


if __name__ == "__main__":
    main()
