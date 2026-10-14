#!/usr/bin/env python3
"""The making-of show's six layers, drawn from one generation's real stage pictures.

Each step of the show adds only what its stage contributes, in pencil and ink on the paper:

  1 sketch    the structure field (`structure.pgm`) as graphite
  2 shading   the smoothed image's lightness as a soft wash under the sketch
  3 paints    one flat tone per paint (`palette.ppm`), the sketch fading
  4 merged    the simplified regions' tones (`simplified.ppm`): small bits gone
  5 ink       the book's lines (`line-art.pgm`) over those tones
  6 template  the template itself (`template.svg`: lines and numbers), as the painter gets it

Usage:
  making_of_layers.py <generate-out> <snapshots> <layers-out> [--width W]

<generate-out> is `pbn generate`'s output directory (template.svg), <snapshots> its
`--snapshots` directory. Writes layer-0.png (the photo) to layer-6.png at W pixels wide
(default: the snapshots' width). Needs numpy, Pillow and node with @resvg/resvg-js for the
template: tools/node_modules (`cd tools && npm ci`), or the folder holding a node_modules in
$MAKING_OF_NODE_MODULES (a worktree can borrow the main checkout's).
"""

import argparse
import json
import os
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image

PAPER = np.array([247, 244, 238], dtype=np.float32) / 255
GRAPHITE = np.array([0.30, 0.29, 0.31], dtype=np.float32)
INK = np.array([0x34, 0x2A, 0x30], dtype=np.float32) / 255
TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load(path, size, mode):
    im = Image.open(path).convert(mode)
    if im.size != size:
        im = im.resize(size, Image.LANCZOS)
    return np.asarray(im, dtype=np.float32) / 255


def lightness(rgb):
    """OKLab L of encoded sRGB, 0...1."""
    lin = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
    l = 0.4122214708 * lin[..., 0] + 0.5363325363 * lin[..., 1] + 0.0514459929 * lin[..., 2]
    m = 0.2119034982 * lin[..., 0] + 0.6806995451 * lin[..., 1] + 0.1073969566 * lin[..., 2]
    s = 0.0883024619 * lin[..., 0] + 0.2817188376 * lin[..., 1] + 0.6299787005 * lin[..., 2]
    l, m, s = np.cbrt(l), np.cbrt(m), np.cbrt(s)
    return 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s


def sketch(structure, strength):
    """A multiply layer: graphite where the structure field is strong."""
    d = np.clip((structure - 0.05) / 0.45, 0, 1) ** 0.8 * 0.8 * strength
    return 1 - d[..., None] * (1 - GRAPHITE)


def wash(rgb, strength):
    """A multiply layer: the picture's lightness as grey, `strength` of the way to it."""
    L = lightness(rgb)
    return (1 - strength * (1 - L))[..., None]


def ink(lines, strength=1.0):
    """A multiply layer: dark lines (black on white) in the app's ink."""
    d = (1 - lines) * strength
    return 1 - d[..., None] * (1 - INK)


def rasterize(svg, width, out):
    """The template SVG at `width` pixels, through resvg."""
    base = os.environ.get('MAKING_OF_NODE_MODULES', TOOLS)
    script = (
        "import { createRequire } from 'node:module'; import { readFileSync, writeFileSync } from 'node:fs';"
        "const [base, svg, w, out] = process.argv.slice(1);"
        "const { Resvg } = createRequire(base + '/')('@resvg/resvg-js');"
        "const r = new Resvg(readFileSync(svg), { fitTo: { mode: 'width', value: Number(w) }, background: 'white' });"
        "writeFileSync(out, r.render().asPng());"
    )
    subprocess.run(['node', '--input-type=module', '-e', script, '--', base, svg, str(width), out], check=True)


def save(arr, path):
    Image.fromarray((np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8)).save(path)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('generated')
    ap.add_argument('snapshots')
    ap.add_argument('out')
    ap.add_argument('--width', type=int)
    a = ap.parse_args()
    snap = lambda n: os.path.join(a.snapshots, n)
    w0, h0 = Image.open(snap('working-image.ppm')).size
    width = a.width or w0
    size = (width, round(h0 * width / w0))
    os.makedirs(a.out, exist_ok=True)

    photo = load(snap('working-image.ppm'), size, 'RGB')
    structure = load(snap('structure.pgm'), size, 'L')
    smoothed = load(snap('smoothed.ppm'), size, 'RGB')
    palette = load(snap('palette.ppm'), size, 'RGB')
    simplified = load(snap('simplified.ppm'), size, 'RGB')
    if not os.path.exists(snap('line-art.pgm')):
        sys.exit('no line-art.pgm: generate a coloring book with --edges')
    lines = load(snap('line-art.pgm'), size, 'L')
    with tempfile.TemporaryDirectory() as tmp:
        png = os.path.join(tmp, 'template.png')
        rasterize(os.path.join(a.generated, 'template.svg'), width, png)
        template = load(png, size, 'RGB')

    paper = np.broadcast_to(PAPER, photo.shape)
    merged = paper * wash(simplified, 0.45)
    layers = [
        photo,
        paper * sketch(structure, 1.0),
        paper * wash(smoothed, 0.35) * sketch(structure, 0.8),
        paper * wash(palette, 0.45) * sketch(structure, 0.35),
        merged,
        merged * ink(lines),
        paper * template,
    ]
    for i, layer in enumerate(layers):
        save(layer, os.path.join(a.out, f'layer-{i}.png'))
    with open(os.path.join(a.out, 'layers.json'), 'w') as f:
        json.dump({'size': size, 'layers': [f'layer-{i}.png' for i in range(len(layers))]}, f)


if __name__ == '__main__':
    main()
