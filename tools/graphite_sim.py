#!/usr/bin/env python3
"""A rough look, off the device, at the short Making-of's graphite drawing (painting-company row 361).

    tools/graphite_sim.py <photo> <out.png> [--intensity 3] [--paper 0.72] [--dark]

`GraphiteSketch.draw` (App/PaintByNumber/Features/Create/FormingShow.swift) makes it with Core
Image on the device; this stands in for that pass with numpy and Pillow: the photo at most 900 px
across, without its color (contrast 1.1), gone `--paper` of the way to the sheet's paper, its
edges (a Gaussian blur of 1.2, then a central-difference gradient for CIEdges, times
`--intensity`, clamped) laid over in the sheet's ink at 80%. CIEdges' own kernel differs, so it
is a guide to the parameters' balance, not a pixel match. `--dark` uses the dark sheet.
"""
import argparse

import numpy as np
from PIL import Image, ImageFilter

# CanvasPalette's sheet paper and ink, sRGB (approximate; the app reads them from CanvasPalette).
LIGHT = (np.array([0.97, 0.955, 0.925]), np.array([0.16, 0.15, 0.17]))
DARK = (np.array([0.11, 0.11, 0.13]), np.array([0.86, 0.85, 0.82]))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("photo")
    parser.add_argument("out")
    parser.add_argument("--intensity", type=float, default=3.0)
    parser.add_argument("--paper", type=float, default=0.72)
    parser.add_argument("--dark", action="store_true")
    args = parser.parse_args()

    image = Image.open(args.photo).convert("RGB")
    s = min(1, 900 / max(image.size))
    image = image.resize((int(image.width * s), int(image.height * s)), Image.LANCZOS)
    rgb = np.asarray(image).astype(np.float32) / 255
    mono = np.clip((rgb @ np.array([0.2126, 0.7152, 0.0722], np.float32) - 0.5) * 1.1 + 0.5, 0, 1)
    blurred = Image.fromarray((mono * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2))
    soft = np.asarray(blurred).astype(np.float32) / 255
    gx, gy = np.zeros_like(soft), np.zeros_like(soft)
    gx[:, 1:-1] = soft[:, 2:] - soft[:, :-2]
    gy[1:-1, :] = soft[2:, :] - soft[:-2, :]
    edges = np.clip(np.hypot(gx, gy) * args.intensity, 0, 1)[..., None]
    paper, ink = DARK if args.dark else LIGHT
    lead = ink * 0.8 + paper * 0.2
    washed = mono[..., None] * (1 - args.paper) + paper * args.paper
    drawing = lead * edges + washed * (1 - edges)
    Image.fromarray((np.clip(drawing, 0, 1) * 255).astype(np.uint8)).save(args.out)


if __name__ == "__main__":
    main()
