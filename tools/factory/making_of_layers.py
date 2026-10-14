#!/usr/bin/env python3
"""The making-of show's six layers, drawn from one generation's real stage pictures.

Each step of the show adds only what its stage contributes, in pencil and ink on the paper:

  1 sketch    the structure that survives relative total variation, as graphite: the structure
              field (`structure.pgm`) weighted by how coherent the steps around each pixel are,
              so texture (feathers, leaves) drops out and contours stay
  2 shading   the smoothed image's lightness as a soft wash under the sketch
  3 paints    one flat tone per paint (`palette.ppm`), the sketch fading
  4 merged    the simplified regions' tones (`simplified.ppm`): small bits gone
  5 ink       the template's own lines over those tones, lifting toward the paper
  6 template  the template itself (`template.svg`: lines and numbers), as the painter gets it

Steps 5 and 6 share the template's lines, so the last step only lifts the tones and sets the
numbers.

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
import re
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


def box(a, r):
    """Box blur of radius r along both axes (2-D float array, edges clamped)."""
    for axis in (0, 1):
        pad = [(0, 0), (0, 0)]
        pad[axis] = (r + 1, r)
        c = np.cumsum(np.pad(a, pad + [(0, 0)] * (a.ndim - 2), mode='edge'), axis=axis)
        hi = np.take(c, np.arange(2 * r + 1, c.shape[axis]), axis=axis)
        lo = np.take(c, np.arange(0, c.shape[axis] - 2 * r - 1), axis=axis)
        a = (hi - lo) / (2 * r + 1)
    return a


def oklab(rgb):
    lin = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
    l = np.cbrt(0.4122214708 * lin[..., 0] + 0.5363325363 * lin[..., 1] + 0.0514459929 * lin[..., 2])
    m = np.cbrt(0.2119034982 * lin[..., 0] + 0.6806995451 * lin[..., 1] + 0.1073969566 * lin[..., 2])
    s = np.cbrt(0.0883024619 * lin[..., 0] + 0.2817188376 * lin[..., 1] + 0.6299787005 * lin[..., 2])
    return np.stack([0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                     1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                     0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s], axis=-1)


def relative_total_variation(rgb, radius):
    """What StructureMap measures (Xu et al. 2012), on a picture: per pixel, how coherent the
    color steps are over a window (1 = they all point one way, a contour; 0 = they cancel,
    texture), and how much variation there is in all. Same window as the pipeline (a box of
    `radius`, twice), chroma stretched by 1.6 as the segmentation grid is."""
    lab = oklab(rgb) * np.array([1, 1.6, 1.6], dtype=np.float32)
    dx = np.zeros_like(lab)
    dy = np.zeros_like(lab)
    dx[:, 1:] = lab[:, 1:] - lab[:, :-1]
    dy[1:] = lab[1:] - lab[:-1]
    coherent, total = 0, 0
    for d in (dx, dy):
        mag = np.sqrt((d * d).sum(axis=-1))
        vec = box(box(d, radius), radius)
        coherent = coherent + np.sqrt((vec * vec).sum(axis=-1))
        total = total + box(box(mag[..., None], radius), radius)[..., 0]
    return np.clip(coherent / (total + 1e-4), 0, 1), total


def sketch(structure, strength):
    """A multiply layer: graphite where the structure field is strong."""
    d = np.clip((structure - 0.05) / 0.45, 0, 1) ** 0.8 * 0.8 * strength
    return 1 - d[..., None] * (1 - GRAPHITE)


def wash(rgb, strength):
    """A multiply layer: the picture's lightness as grey, `strength` of the way to it."""
    L = lightness(rgb)
    return (1 - strength * (1 - L))[..., None]


def tone_curve(rgb, low, high, mean):
    """Maps lightness onto greys from `low` to `high`, bent so that `rgb` averages `mean`: the
    Snow Queen's lighter, clearer greys. Returns the map, so every stage after `rgb` gets the
    same one and changes only where the picture does."""
    L = lightness(rgb)
    lo, hi = np.percentile(L, (1, 99))
    span = max(float(hi - lo), 1e-6)
    t = np.clip((L - lo) / span, 0, 1)
    want = (mean - low) / (high - low)
    a, b = 0.05, 20.0                   # t ** g averages less as g grows
    for _ in range(40):
        g = (a * b) ** 0.5
        a, b = (g, b) if (t ** g).mean() > want else (a, g)
    g = (a * b) ** 0.5
    return lambda img: (low + (high - low) * np.clip((lightness(img) - lo) / span, 0, 1) ** g)[..., None]


def ink(lines, strength=1.0):
    """A multiply layer: dark lines (black on white) in the app's ink."""
    d = (1 - lines) * strength
    return 1 - d[..., None] * (1 - INK)


def rasterize(svg, width, out, numbers=True):
    """The template SVG at `width` pixels, through resvg; without its numbers if asked."""
    if not numbers:
        with open(svg, encoding='utf-8') as f:
            text = re.sub(r'<text\b[^>]*>.*?</text>', '', f.read(), flags=re.S)
        svg = out + '.svg'
        with open(svg, 'w', encoding='utf-8') as f:
            f.write(text)
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


class Sources:
    """One generation's stage pictures at `width` pixels wide, 0...1 floats, plus the
    multiply layers the six steps are made of."""

    def __init__(self, generated, snapshots, width=None, sketch_spec=None, tones=None):
        snap = lambda n: os.path.join(snapshots, n)
        w0, h0 = Image.open(snap('working-image.ppm')).size
        width = width or w0
        self.size = size = (width, round(h0 * width / w0))
        self.svg = os.path.join(generated, 'template.svg')
        self.photo = load(snap('working-image.ppm'), size, 'RGB')
        self.structure = load(snap('structure.pgm'), size, 'L')
        self.smoothed = load(snap('smoothed.ppm'), size, 'RGB')
        self.palette = load(snap('palette.ppm'), size, 'RGB')
        self.simplified = load(snap('simplified.ppm'), size, 'RGB')
        with tempfile.TemporaryDirectory() as tmp:
            rasterize(self.svg, width, os.path.join(tmp, 'template.png'))
            rasterize(self.svg, width, os.path.join(tmp, 'lines.png'), numbers=False)
            self.template = load(os.path.join(tmp, 'template.png'), size, 'RGB')
            self.lines = load(os.path.join(tmp, 'lines.png'), size, 'L')
        self.paper = np.broadcast_to(PAPER, self.photo.shape)
        # relative total variation, at the pipeline's window scaled to this picture
        radius = max(1, round(0.0025 * 1600 * width / 1024))
        self.coherence, variation = relative_total_variation(self.photo, radius)
        ratio = self.coherence ** 3          # the pipeline's structureExponent
        # graphite only on what survives: structure where the steps agree, as strong as before
        k = sketch_spec or {'coherenceFrom': 0.2, 'coherenceSpan': 0.45, 'coherenceExponent': 1.2, 'smearRadius': 4}
        keep = np.clip((self.coherence - k['coherenceFrom']) / k['coherenceSpan'], 0, 1) ** k['coherenceExponent']
        survivors = self.structure * keep
        self.survivors = np.clip(survivors * np.percentile(self.structure, 99.5)
                                 / (np.percentile(survivors, 99.5) + 1e-6), 0, 1)
        # the photo with its texture smeared away: where steps cancel and there is much of them
        busy = np.clip(variation / (np.percentile(variation, 90) + 1e-6), 0, 1)
        self.texture = np.clip((1 - ratio) * busy * 1.4, 0, 1)
        blurred = box(box(self.photo, int(k['smearRadius'])), int(k['smearRadius']))
        self.detextured = self.photo + (blurred - self.photo) * self.texture[..., None]
        t = tones or {'low': 0.62, 'high': 0.92, 'mean': 0.85}
        self.tone = tone_curve(self.simplified, t['low'], t['high'], t['mean'])
        self.toned = self.tone(self.simplified)
        self.lifted = 1 - 0.5 * (1 - self.toned)        # the ink step lifts the grey halfway

    def layers(self):
        paper = self.paper
        return [
            self.photo,
            paper * sketch(self.survivors, 1.0),
            paper * wash(self.smoothed, 0.35) * sketch(self.survivors, 0.8),
            paper * self.tone(self.palette) * sketch(self.survivors, 0.35),
            paper * self.toned,
            paper * self.lifted * ink(self.lines),
            paper * self.template,
        ]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('generated')
    ap.add_argument('snapshots')
    ap.add_argument('out')
    ap.add_argument('--width', type=int)
    a = ap.parse_args()
    src = Sources(a.generated, a.snapshots, a.width)
    os.makedirs(a.out, exist_ok=True)
    layers = src.layers()
    for i, layer in enumerate(layers):
        save(layer, os.path.join(a.out, f'layer-{i}.png'))
    with open(os.path.join(a.out, 'layers.json'), 'w') as f:
        json.dump({'size': src.size, 'layers': [f'layer-{i}.png' for i in range(len(layers))]}, f)


if __name__ == '__main__':
    main()
