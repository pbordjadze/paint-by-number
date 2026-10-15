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

Sources/MakingOf's `ShowLayers` is this module's port (derive, ToneCurve, RevealStyle), compared
by Tests/MakingOfTests with the numbers `tools/tests/test_making_of_layers.py --write-goldens`
writes. Everything continuous is computed in float64: the tone curve from the simplified picture's
paints and their pixel counts (the picture is flat), the boxes by prefix sums of doubles.

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
import math
import os
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass, fields

import numpy as np
from PIL import Image


@dataclass(frozen=True)
class RevealStyle:
    """The look of the show's pictures: every number the layers and the compositor
    (making_of_compose.py) used to carry inline. Sources/MakingOf's `RevealStyle` mirrors it field
    for field, the names in camelCase (`style_dict`), and Tests/MakingOfTests compares the two.
    What the show's spec (making-of.json) sets, the tones and the sketch, is not here."""

    # paper, pencil and ink: `paper` and `ink` as 8-bit colors, `graphite` as 0...1
    paper: tuple = (247, 244, 238)
    graphite: tuple = (0.30, 0.29, 0.31)
    ink: tuple = (0x34, 0x2A, 0x30)
    luma: tuple = (0.2126, 0.7152, 0.0722)      # how bright a color looks, for draining it to grey

    # relative total variation, as the pipeline's StructureMap measures it
    rtv_window: float = 4.0                     # the window's radius in px of a 1024 px wide picture
    rtv_chroma: float = 1.6                     # chroma stretched as the segmentation grid is
    rtv_epsilon: float = 1e-4                   # keeps the ratio finite where nothing varies
    structure_exponent: float = 3.0             # the pipeline's: coherence ** 3 is how structured
    survivor_percentile: float = 99.5           # the survivors are rescaled to the structure's
    variation_percentile: float = 90.0          # the variation that counts as busy
    percentile_epsilon: float = 1e-6
    texture_gain: float = 1.4

    # the greys of the tone curve
    tone_percentiles: tuple = (1.0, 99.0)       # of lightness: black and white of the picture
    tone_span_floor: float = 1e-6               # a flat picture still has a span
    tone_gamma_range: tuple = (0.05, 20.0)      # what the bisection brackets; t ** g averages less as g grows
    tone_bisections: int = 40

    # the multiply layers
    graphite_floor: float = 0.05                # structure below this leaves no mark
    graphite_span: float = 0.45
    graphite_exponent: float = 0.8
    graphite_density: float = 0.8               # the darkest graphite, before a layer's strength
    sketch_strengths: tuple = (1.0, 0.8, 0.35)  # of the layers 1 to 3
    wash_strength: float = 0.35                 # how far layer 2 goes to the smoothed picture's lightness
    lift_share: float = 0.5                     # how much of the greys the ink step lifts

    # the compositor: seconds are the ramps a change takes to come in
    smear_ramp: float = 0.3                     # step 1: texture smears away
    drain_delay: float = 0.1                    # then the color drains
    drain_ramp: float = 0.5
    graphite_delay: float = 0.35                # graphite goes down, strongest structure first
    graphite_by_structure: float = 0.25
    graphite_margin: float = 0.4                # and is down this long before the step ends
    graphite_ramp: float = 0.16
    wash_delay: float = 0.45                    # the photo fades to paper behind it
    wash_margin: float = 0.8
    wash_ramp: float = 0.7
    soft_early: float = 0.16                    # step 2's edge, soft
    soft_late: float = 0.09                     # steps 3 and 4: crisper
    settle_gain: float = 12.0                   # how much a layer changes, to how dark it dips
    settle_ramp: float = 0.22
    settle_depth: float = 0.1
    lift_ramp: float = 0.12                     # step 5: a region's grey lifts
    clear_ramp: float = 0.12                    # step 6: it clears to paper


STYLE = RevealStyle()


def style_dict(style=STYLE):
    """The style as JSON, its names in camelCase as the Swift struct spells them."""
    camel = lambda name: re.sub(r'_(\w)', lambda m: m.group(1).upper(), name)
    return {camel(f.name): list(getattr(style, f.name)) if isinstance(getattr(style, f.name), tuple)
            else getattr(style, f.name) for f in fields(style)}


PAPER = np.array(STYLE.paper, dtype=np.float32) / 255
GRAPHITE = np.array(STYLE.graphite, dtype=np.float32)
INK = np.array(STYLE.ink, dtype=np.float32) / 255
TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_SKETCH = {'coherenceFrom': 0.2, 'coherenceSpan': 0.45, 'coherenceExponent': 1.2, 'smearRadius': 4}
DEFAULT_TONES = {'low': 0.62, 'high': 0.92, 'mean': 0.85}


def load(path, size, mode, flat=False):
    """A picture at `size`, 0...1 floats; a `flat` one (one color per area) keeps its colors."""
    im = Image.open(path).convert(mode)
    if im.size != size:
        im = im.resize(size, Image.NEAREST if flat else Image.LANCZOS)
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


def relative_total_variation(rgb, radius, style=STYLE):
    """What StructureMap measures (Xu et al. 2012), on a picture: per pixel, how coherent the
    color steps are over a window (1 = they all point one way, a contour; 0 = they cancel,
    texture), and how much variation there is in all. Same window as the pipeline (a box of
    `radius`, twice), chroma stretched as the segmentation grid is. In float64."""
    stretch = np.array([1, style.rtv_chroma, style.rtv_chroma])
    lab = oklab(np.asarray(rgb, dtype=np.float64)) * stretch
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
    return np.clip(coherent / (total + style.rtv_epsilon), 0, 1), total


def sketch(structure, strength, style=STYLE):
    """A multiply layer: graphite where the structure field is strong."""
    d = (np.clip((structure - style.graphite_floor) / style.graphite_span, 0, 1) ** style.graphite_exponent
         * style.graphite_density * strength)
    return 1 - d[..., None] * (1 - GRAPHITE)


def wash(rgb, strength):
    """A multiply layer: the picture's lightness as grey, `strength` of the way to it."""
    L = lightness(rgb)
    return (1 - strength * (1 - L))[..., None]


def paint_keys(rgb):
    """Each pixel's color of a picture (0...1 floats, read as 8-bit) as one integer, 0xRRGGBB."""
    q = (np.clip(rgb, 0, 1) * 255 + 0.5).astype(np.int64)
    return (q[..., 0] << 16) | (q[..., 1] << 8) | q[..., 2]


def key_colors(keys):
    """0xRRGGBB integers as 0...1 float64 colors, (n, 3)."""
    return np.stack([(keys >> 16) & 255, (keys >> 8) & 255, keys & 255], axis=-1) / 255.0


def paint_counts(rgb):
    """The distinct colors of a flat picture and the pixels each covers: (colors as 0...1
    float64, counts), in order of lightness."""
    keys, counts = np.unique(paint_keys(rgb), return_counts=True)
    colors = key_colors(keys)
    order = np.argsort(lightness(colors), kind='stable')
    return colors[order], counts[order]


def counted_percentile(values, counts, q):
    """numpy.percentile(numpy.repeat(values, counts), q) (linear, its lerp) without repeating:
    `values` ascending, each seen `counts` times."""
    cum = np.cumsum(counts)
    n = int(cum[-1])
    virtual = q / 100 * (n - 1)
    index = int(np.floor(virtual))
    gamma = virtual - index
    stat = lambda rank: float(values[np.searchsorted(cum, rank, side='right')])
    a, b = stat(index), stat(min(index + 1, n - 1))
    diff = b - a
    return b - diff * (1 - gamma) if gamma >= 0.5 else a + diff * gamma


class ToneCurve:
    """Maps lightness onto greys from `low` to `high`, bent so that a picture averages `mean`:
    the Snow Queen's lighter, clearer greys. Made from the picture's paints and their pixel
    counts (it is flat: one lightness per paint), so it is exact and takes a few dozen powers,
    not forty per pixel; every stage after it gets the same curve and changes only where the
    picture does. Calling it maps a flat picture to greys, (H, W, 1)."""

    def __init__(self, rgb, low, high, mean, style=STYLE):
        colors, counts = paint_counts(rgb)
        L = lightness(colors)
        p_lo, p_hi = style.tone_percentiles
        self.lo = lo = counted_percentile(L, counts, p_lo)
        hi = counted_percentile(L, counts, p_hi)
        self.span = span = max(hi - lo, style.tone_span_floor)
        self.low, self.high = low, high
        t = np.clip((L - lo) / span, 0, 1)
        want = (mean - low) / (high - low)
        total = float(counts.sum())

        def average(g):                 # summed in order, like the Swift port
            return float(np.cumsum(counts * t ** g)[-1]) / total

        a, b = style.tone_gamma_range
        for _ in range(style.tone_bisections):
            g = math.sqrt(a * b)
            a, b = (g, b) if average(g) > want else (a, g)
        self.gamma = math.sqrt(a * b)

    def grey(self, L):
        return self.low + (self.high - self.low) * np.clip((L - self.lo) / self.span, 0, 1) ** self.gamma

    def __call__(self, rgb):
        keys, inverse = np.unique(paint_keys(rgb), return_inverse=True)
        return self.grey(lightness(key_colors(keys)))[inverse.reshape(rgb.shape[:2])][..., None]


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


def derive(photo, structure, smoothed, palette, simplified, sketch_spec=None, tones=None, style=STYLE):
    """What the pipeline's stages say about one generation's pictures (0...1 floats of one
    size, `structure` one channel), in float64: the relative total variation (`coherence`,
    `variation`), the `survivors` of it on the structure, the `texture` and the `detextured`
    photo, and the tone curve of the paints (`tone`, `toned`, `lifted`). `smoothed` and `palette`
    are not read here; the layers use them."""
    photo = np.asarray(photo, dtype=np.float64)
    structure = np.asarray(structure, dtype=np.float64)
    radius = max(1, round(style.rtv_window * photo.shape[1] / 1024))     # the pipeline's window, scaled
    coherence, variation = relative_total_variation(photo, radius, style)
    ratio = coherence ** style.structure_exponent
    # graphite only on what survives: structure where the steps agree, as strong as before
    k = sketch_spec or DEFAULT_SKETCH
    keep = np.clip((coherence - k['coherenceFrom']) / k['coherenceSpan'], 0, 1) ** k['coherenceExponent']
    kept = structure * keep
    survivors = np.clip(kept * np.percentile(structure, style.survivor_percentile)
                        / (np.percentile(kept, style.survivor_percentile) + style.percentile_epsilon), 0, 1)
    # the photo with its texture smeared away: where steps cancel and there is much of them
    busy = np.clip(variation / (np.percentile(variation, style.variation_percentile) + style.percentile_epsilon), 0, 1)
    texture = np.clip((1 - ratio) * busy * style.texture_gain, 0, 1)
    smear = int(k['smearRadius'])
    detextured = photo + (box(box(photo, smear), smear) - photo) * texture[..., None]
    t = tones or DEFAULT_TONES
    tone = ToneCurve(simplified, t['low'], t['high'], t['mean'], style)
    toned = tone(simplified)
    return {'coherence': coherence, 'variation': variation, 'survivors': survivors, 'texture': texture,
            'detextured': detextured, 'tone': tone, 'toned': toned,
            'lifted': 1 - style.lift_share * (1 - toned)}      # the ink step lifts the grey part of the way


def paper_layers(photo, smoothed, palette, survivors, tone, toned, style=STYLE):
    """The first five layers of the show, as 0...1 pictures: the photo, then the paper under
    graphite, under graphite and a wash of the smoothed picture, under the paints' greys and
    fading graphite, under the merged regions' greys. (The sixth, the ink, and the seventh,
    the template, need its rasterized lines.)"""
    paper = np.broadcast_to(PAPER, photo.shape)
    strengths = style.sketch_strengths
    return [
        photo,
        paper * sketch(survivors, strengths[0], style),
        paper * wash(smoothed, style.wash_strength) * sketch(survivors, strengths[1], style),
        paper * tone(palette) * sketch(survivors, strengths[2], style),
        paper * toned,
    ]


class Stages:
    """One generation's stage pictures (0...1 float32 arrays of one size) with what `derive` makes
    of them, as the show reads them, and the first five layers."""

    def __init__(self, photo, structure, smoothed, palette, simplified, sketch_spec=None, tones=None):
        self.photo, self.structure, self.smoothed = photo, structure, smoothed
        self.palette, self.simplified = palette, simplified
        self.paper = np.broadcast_to(PAPER, photo.shape)
        d = derive(photo, structure, smoothed, palette, simplified, sketch_spec, tones)
        f32 = lambda name: d[name].astype(np.float32)
        self.coherence, self.survivors, self.texture, self.detextured = (
            f32('coherence'), f32('survivors'), f32('texture'), f32('detextured'))
        self.toned, self.lifted = f32('toned'), f32('lifted')
        self.tone = lambda img: d['tone'](img).astype(np.float32)

    def layers(self):
        return paper_layers(self.photo, self.smoothed, self.palette, self.survivors, self.tone, self.toned)

    @classmethod
    def read(cls, snapshots, size=None, sketch_spec=None, tones=None):
        """The stages of `pbn generate --snapshots`'s folder, at `size` (default the photo's)."""
        snap = lambda n: os.path.join(snapshots, n)
        if size is None:
            with Image.open(snap('working-image.ppm')) as photo:
                size = photo.size
        return cls(load(snap('working-image.ppm'), size, 'RGB'), load(snap('structure.pgm'), size, 'L'),
                   load(snap('smoothed.ppm'), size, 'RGB'), load(snap('palette.ppm'), size, 'RGB', flat=True),
                   load(snap('simplified.ppm'), size, 'RGB', flat=True), sketch_spec, tones)


class Sources(Stages):
    """One generation's stage pictures at `width` pixels wide, 0...1 floats, plus the
    multiply layers the six steps are made of."""

    def __init__(self, generated, snapshots, width=None, sketch_spec=None, tones=None):
        snap = lambda n: os.path.join(snapshots, n)
        w0, h0 = Image.open(snap('working-image.ppm')).size
        width = width or w0
        self.size = size = (width, round(h0 * width / w0))
        self.svg = os.path.join(generated, 'template.svg')
        with tempfile.TemporaryDirectory() as tmp:
            rasterize(self.svg, width, os.path.join(tmp, 'template.png'))
            rasterize(self.svg, width, os.path.join(tmp, 'lines.png'), numbers=False)
            self.template = load(os.path.join(tmp, 'template.png'), size, 'RGB')
            self.lines = load(os.path.join(tmp, 'lines.png'), size, 'L')
        super().__init__(load(snap('working-image.ppm'), size, 'RGB'), load(snap('structure.pgm'), size, 'L'),
                         load(snap('smoothed.ppm'), size, 'RGB'), load(snap('palette.ppm'), size, 'RGB', flat=True),
                         load(snap('simplified.ppm'), size, 'RGB', flat=True), sketch_spec, tones)

    def layers(self):
        return super().layers() + [self.paper * self.lifted * ink(self.lines), self.paper * self.template]


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
