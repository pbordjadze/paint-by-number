#!/usr/bin/env python3
"""The short Making-of's graphite drawing, off the device (painting-company row 361).

    tools/graphite_sim.py <photo> <out.png> [--dark] [--at 0.2 0.45 0.7 1]

Lays out, side by side, the drawing as `GraphiteSketch.draw` (App/PaintByNumber/Features/Create/
FormingShow.swift) makes it with Core Image on the device and as the preview shows it at each
progress of `--at`: the photo at most 900 px across, in grey, a color-dodge pencil sketch of it
(the grey over a blur of its negative, `sigma` 4: dark where the photo changes, paper where it is
flat, raised to `gamma` after `gain`) in the sheet's ink, over the grey gone `paper` of the way to
the sheet's paper. The strokes race along the photo's shapes: each pixel's arrival is its distance
from the strongest stroke near the middle, a stroke cheap to travel along and bare paper dear
(Dijkstra on a quarter-size max of the strokes), and the drawing is `STAGES` images, each the
strokes arrived by then, cross-faded as the progress passes. Core Image's blurs and grey differ a
little from Pillow's: a guide to the look and the parameters' balance, not a pixel match.
`--dark` uses the dark sheet.
"""
import argparse
import heapq

import numpy as np
from PIL import Image, ImageFilter

# CanvasPalette's sheet paper and ink, sRGB (App/PaintByNumber/Canvas/CanvasTypes.swift).
LIGHT = (np.array([0.957, 0.937, 0.902]), np.array([0.118, 0.102, 0.133]))
DARK = (np.array([0.137, 0.118, 0.133]), np.array([0.812, 0.780, 0.827]))
# GraphiteSketch's constants.
LONG_SIDE, SIGMA, GAIN, GAMMA, PAPER, PENCIL, STAGES, COARSE = 900, 4.0, 2.5, 1.4, 0.88, 0.9, 8, 4


def strokes(grey):
    soft = np.asarray(Image.fromarray((grey * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8))) / 255
    negative = Image.fromarray(((1 - soft) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(SIGMA))
    dodge = np.clip(soft / np.maximum(1 - np.asarray(negative) / 255, 1e-3), 0, 1)
    return np.clip((1 - dodge) * GAIN, 0, 1) ** GAMMA


def arrivals(s):
    """Each pixel's arrival (0…1), as `GraphiteSketch.arrivals` works it out."""
    H, W = s.shape
    h, w = H // COARSE, W // COARSE
    coarse = s[: h * COARSE, : w * COARSE].reshape(h, COARSE, w, COARSE).max(axis=(1, 3))
    cost = 1 / (0.06 + coarse)
    yy, xx = np.mgrid[0:h, 0:w]
    score = coarse - 0.6 * np.hypot(yy - h * 0.45, xx - w * 0.5) / max(h, w)
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
    a = np.clip(dist / max(np.percentile(dist, 99), 1e-6), 0, 1)
    return np.asarray(Image.fromarray((a * 255).astype(np.uint8)).resize((W, H), Image.BILINEAR)) / 255


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("photo")
    parser.add_argument("out")
    parser.add_argument("--dark", action="store_true")
    parser.add_argument("--at", type=float, nargs="+", default=[0.2, 0.45, 0.7, 1.0])
    args = parser.parse_args()

    image = Image.open(args.photo).convert("RGB")
    s = min(1, LONG_SIDE / max(image.size))
    image = image.resize((int(image.width * s), int(image.height * s)), Image.LANCZOS)
    rgb = np.asarray(image) / 255
    grey = np.asarray(image.convert("L")) / 255
    paper, ink = DARK if args.dark else LIGHT
    stroke = strokes(grey)
    arrival = arrivals(stroke)
    base = grey[..., None] * (1 - PAPER) + paper * PAPER
    # Stage j holds every stroke arrived by (j + 1) / STAGES, and the next share's ramping in.
    stages = [stroke * np.clip(j + 2 - STAGES * arrival, 0, 1) * PENCIL for j in range(STAGES)]

    frames = []
    for p in args.at:
        # The photo drains to the base over the first 40%; stage floor(k) whole, the next fading in.
        k = p * STAGES
        i = int(min(k, STAGES))
        alpha = np.zeros_like(stroke)
        if i >= 1:
            alpha = stages[min(i, STAGES) - 1]
        if i < STAGES:
            nxt = stages[i] * (k - i)
            alpha = alpha + nxt * (1 - alpha)
        frame = base * min(1, p / 0.4) + rgb * (1 - min(1, p / 0.4))
        frames.append(ink * alpha[..., None] + frame * (1 - alpha[..., None]))
    sheet = np.concatenate(frames, axis=1)
    Image.fromarray((np.clip(sheet, 0, 1) * 255).astype(np.uint8)).save(args.out)


if __name__ == "__main__":
    main()
