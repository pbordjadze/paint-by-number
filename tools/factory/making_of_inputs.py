#!/usr/bin/env python3
"""What the making-of crew is planned from, chosen exactly: where each pet pops in, the spots every
step's jobs are done at, the k-means++ seeds step 3 drops, and the template's lines.

Usage:
  making_of_inputs.py <generate-out> <snapshots> [--spec JSON] [--seed 7] [--crew N]
                      [--pet-height SHARE] [--width PX] [--out FILE]

<generate-out> is `pbn generate`'s output directory (template.svg), <snapshots> its `--snapshots`
directory. Writes {"seed", "inputs", "seeds", "paints", "trace"} as JSON (stdout, or --out):
`inputs` is what `making_of_pets.plan` and Sources/MakingOf's `CrewInputs` take, at the precision
the plan file keeps; `seeds` are step 3's [time, x, y, paint]; `paints` the distinct colours of
palette.ppm as r << 16 | g << 8 | b, in order (a seed's paint is an index into it); `trace` the
numbers on the way, for finding where a port first differs.

Every random draw is SplitMix64's (`making_of_pets.stream`, one stream per purpose) and every
quantity a draw or a comparison turns on is an integer or a double made of `+ - * /` and `sqrt`
(making_of_exact.py), so Sources/MakingOf (`CrewInputs.make`) gets the same numbers bit for bit.
It works at the snapshots' size, as the app does; --width resamples the pictures first, as
making_of_layers.py does, for a clip at another size.

The weights the spots are drawn by (all multiplied by `room`, the picture without a margin where a
pet would stand in a corner):
  step 0 and homes  the structure plus 0.35: the edges first, but the whole picture is visited
  step 1            the same everywhere
  step 3            1 / sqrt(area) of the merged region a pixel is in, so small regions are visited
  step 5            where the numbers are, in the open: away from where lines run thick
Step 2's are the seeds' places, and step 4's lines are the strokes.
"""

import argparse
import json
import math
import os
import re
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import making_of_exact as exact  # noqa: E402
import making_of_pets  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SPEC = os.path.join(ROOT, 'App', 'PaintByNumber', 'Resources', 'making-of.json')

CARD_BAND = 232         # px below the picture, which the farewell walks off the bottom of
INK_STEP = 4            # drawn by walking along the strokes: no spots
PATIENCE = 40           # rounds of draws before `sample_stops` settles for fewer spots
RELAX = 0.85            # the spacing's share kept each round that came up short
# px past a line's half width at which a pixel still counts as inked, as resvg's rasterization of it
# does (a pixel at least a sixth covered): its pixel count on the parrots, 18814 against 18844
LINE_REACH = 0.33
# k-means++ chroma stretch, as in the segmentation grid.
CHROMA = np.array([1.0, 1.6, 1.6])


class Pictures:
    """The five stage pictures a show reads, as bytes at one size (W x H)."""

    NAMES = {'working': 'working-image.ppm', 'structure': 'structure.pgm', 'smoothed': 'smoothed.ppm',
             'palette': 'palette.ppm', 'simplified': 'simplified.ppm'}

    def __init__(self, snapshots, width=None):
        def load(name, mode, flat=False):
            with Image.open(os.path.join(snapshots, self.NAMES[name])) as file:
                im = file.convert(mode)
            if size != im.size:
                im = im.resize(size, Image.NEAREST if flat else Image.LANCZOS)
            return np.asarray(im, dtype=np.uint8)

        with Image.open(os.path.join(snapshots, self.NAMES['working'])) as first:
            w0, h0 = first.size
        size = (width or w0, round(h0 * (width or w0) / w0))
        self.size = size
        self.working = load('working', 'RGB')
        self.structure = load('structure', 'L')
        self.smoothed = load('smoothed', 'RGB')
        self.palette = load('palette', 'RGB', flat=True)
        self.simplified = load('simplified', 'RGB', flat=True)


class Template:
    """The template's drawn lines and numbers in picture pixels, as the SVG prints them (canvas
    units to 0.01) scaled to the picture: `strokes` (arrays of x, y, in drawing order), `numbers`
    ((x, y, size)), `line_width` (px)."""

    def __init__(self, svg, width):
        with open(svg, encoding='utf-8') as f:
            text = f.read()
        vb = float(re.search(r'viewBox="0 0 ([\d.]+) [\d.]+"', text).group(1))
        self.scale = width / vb
        m = (re.search(r'<g id="lines-drawing"[^>]*><path d="([^"]*)"[^>]*stroke-width="([\d.]+)"', text)
             or re.search(r'<path d="([^"]*)" fill="none" stroke="#9ea3aa" stroke-width="([\d.]+)"', text))
        self.strokes = []
        for part in m.group(1).split('M')[1:]:
            nums = [float(v) for v in re.findall(r'-?[\d.]+', part)]
            pts = [(nums[i] * self.scale, nums[i + 1] * self.scale) for i in range(0, len(nums) - 1, 2)]
            if len(pts) >= 2:
                self.strokes.append(np.array(pts, dtype=np.float64))
        self.line_width = float(m.group(2)) * self.scale
        self.numbers = [(float(x) * self.scale, float(y) * self.scale, float(s) * self.scale)
                        for x, y, s in re.findall(r'<text x="([\d.]+)" y="([\d.]+)" font-size="([\d.]+)">', text)]


def sample_stops(weights, width, n, rng, spacing):
    """`n` spots (x, y) in a plane `width` wide, drawn by `weights` (row-major, non-negative), no two
    closer than `spacing`. Each round draws `n * 30` numbers from `rng`, takes the spot whose running
    weight first passes `u * total`, and keeps those far enough from the ones kept; a round that
    comes up short starts over with the spacing relaxed (`RELAX`), and after `PATIENCE` rounds the
    last round's spots are what there is. A plane with no weight is drawn from as if every cell
    weighed the same."""
    if n <= 0:
        return []
    cdf = exact.cumulative(weights)
    total = float(cdf[-1])
    if not total > 0:
        cdf, total = np.arange(1.0, len(cdf) + 1.0), float(len(cdf))
    picks = []
    for _ in range(PATIENCE):
        u = np.array([rng.random() for _ in range(n * 30)])
        picks = []
        for c in exact.bisect_right(cdf, u * total):
            y, x = divmod(int(c), width)
            if all((x - a) ** 2 + (y - b) ** 2 >= spacing * spacing for a, b in picks):
                picks.append((x, y))
                if len(picks) == n:
                    return picks
        spacing *= RELAX
    return picks


def distance2(lab, point):
    """Squared distance from each row of `lab` to `point`, summed left to right."""
    d = lab - point
    return d[:, 0] * d[:, 0] + d[:, 1] * d[:, 1] + d[:, 2] * d[:, 2]


def kmeanspp(lab, k, rng):
    """k-means++ seeding (Arthur and Vassilvitskii 2007) over the rows of `lab`: the first seed at
    random, each next one drawn with probability proportional to its squared distance to the
    nearest seed so far, by one draw of `rng` each. Returns the chosen indices in order (at most one
    per row); once every row is a seed's twin, a seed is any row."""
    n = len(lab)
    if n == 0:
        return []
    first = rng.below(n)
    order = [first]
    d2 = distance2(lab, lab[first])
    for _ in range(min(k, n) - 1):
        cdf = exact.cumulative(d2)
        total = float(cdf[-1])
        c = int(exact.bisect_right(cdf, rng.random() * total)) if total > 0 else rng.below(n)
        order.append(c)
        d2 = np.minimum(d2, distance2(lab, lab[c]))
    return order


def paints_of(palette):
    """The distinct colours of the palette picture as keys, ascending, and for each pixel the index
    of its colour among them."""
    keys, index = np.unique(exact.color_keys(palette), return_inverse=True)
    return keys, index.reshape(palette.shape[:2])


def paint_rgb(keys):
    """Byte colours of `keys`."""
    return np.stack([(keys >> 16) & 255, (keys >> 8) & 255, keys & 255], axis=1)


def bands(width, margin, count):
    """Column edges that split the picture between its margins into `count` bands: the margin, then
    steps of an equal share, truncated (numpy's linspace written out)."""
    lo, hi = margin * width, (1 - margin) * width
    step = (hi - lo) / count
    return [int(lo + step * i) for i in range(count)] + [int(hi)]


class Built:
    """What `build` made: `inputs` (the plan's, as a dict), `seeds` [(time, x, y, paint)], `paint_keys`
    and `paint_of` (each pixel's index among them), `sim_labels` and `sim_n` (the merged regions),
    `strokes` and `numbers` (the template's, unquantized), `trace`."""


def build(pictures, template, spec, seed, ids, exit_band=CARD_BAND, pet_height=None):
    """The crew's inputs for `ids` (pets, in crew order) at the pictures' size, with the show's `seed`
    (the planner's too). `pet_height` overrides the spec's share of the shorter side."""
    W, H = pictures.size
    crew, timing = spec['crew'], spec['timing']
    intro, step = exact.quantize(float(timing['intro']), 4), exact.quantize(float(timing['step']), 4)
    starts = [intro + k * step for k in range(6)]
    pet_h = exact.quantize((pet_height or float(crew['height'])) * min(W, H), 2)
    margin = float(crew['margin'])
    n = len(ids)
    trace = {}

    # a pet's spot keeps all of it in the picture and off its edges, so nobody works in a corner
    room = np.zeros((H, W))
    x0 = int(margin * W)
    y0 = int(margin * H + pet_h)
    room[y0:max(H - 8, y0), x0:max(W - x0, x0)] = 1.0

    sim_labels, sim_n = exact.label_regions(exact.color_keys(pictures.simplified))
    area = np.bincount(sim_labels.ravel(), minlength=sim_n)[sim_labels].astype(np.float64)
    count = np.zeros((H, W))
    for x, y, _ in template.numbers:
        count[int(min(max(y, 0), H - 1)), int(min(max(x, 0), W - 1))] += 1
    # for the numbers a pet picks the open spots, where few lines run, so it doesn't stand tangled
    # in the finished drawing's ink
    ink = exact.line_mask(W, H, template.strokes, template.line_width / 2 + LINE_REACH)
    density = exact.box_sum(ink, max(1, int(0.35 * pet_h)))
    p95 = exact.percentile(density, 95)
    gap = 1 - np.minimum(density / (p95 + 1e-6), 1.0)
    weights = [
        (4.0 * pictures.structure + 357.0) * room,             # s / 255 + 0.35, in units of 1/1020
        room,
        None,
        np.sqrt(area) / area * room,
        None,
        (count + 1e-6) * (0.05 + gap * gap) * room,
    ]
    trace['labels'] = sim_n
    trace['inkPixels'] = int(ink.sum())
    trace['percentile95'] = p95
    trace['weightTotals'] = [None if w is None else float(exact.cumulative(w.ravel())[-1]) for w in weights]

    # they pop in one to a band, each at its first job, so the first step starts everywhere at once
    nb = max(1, min(int(crew['bands']), n))
    edges = bands(W, margin, nb)
    rng = making_of_pets.stream(seed, making_of_pets.STREAM_HOMES, 0)
    yy, xx = np.mgrid[0:H, 0:W]
    reach = 0.2 * W
    homes = []
    for b in range(nb):
        band = np.zeros((H, W))
        band[:, edges[b]:edges[b + 1]] = weights[0][:, edges[b]:edges[b + 1]]
        for hx, hy in homes:                    # apart across band edges too
            band[(xx - hx) ** 2 + (yy - hy) ** 2 < reach * reach] = 0
        homes += sample_stops(band.ravel(), W, sum(1 for j in range(n) if j * nb // n == b), rng, spacing=reach)
    trace['homes'] = [list(h) for h in homes]

    # step 3's seeds: real pixels of the smoothed picture, chosen by the method itself
    keys, paint_of = paints_of(pictures.palette)
    paint_lab = exact.oklab(paint_rgb(keys)) * CHROMA
    gy = range(int(0.12 * H) + 4, H - 8, 6)
    gx = range(int(0.05 * W), W - int(0.05 * W), 6)
    grid = [(x, y) for y in gy for x in gx]
    sample_lab = exact.oklab(np.array([pictures.smoothed[y, x] for x, y in grid]).reshape(-1, 3)) * CHROMA
    picks = kmeanspp(sample_lab, len(keys), making_of_pets.stream(seed, making_of_pets.STREAM_SEEDS, 0))
    drop = min(float(spec['seeds']['dropEvery']), 1.0 / len(picks)) if picks else 0.0
    seeds = []
    for j, c in enumerate(picks):
        d2 = distance2(paint_lab, sample_lab[c])
        seeds.append((starts[2] + 0.12 + j * drop, float(grid[c][0]), float(grid[c][1]), int(np.argmin(d2))))

    candidates = []
    for k in range(6):
        if k == 2:
            spots = [(x, y) for _, x, y, _ in seeds]
        elif k == INK_STEP:
            spots = []                          # its lines are the strokes
        else:
            spots = sample_stops(weights[k].ravel(), W, n * 4, making_of_pets.stream(seed, making_of_pets.STREAM_SPOTS, k),
                                 spacing=0.1 * W)
            if k == 0:
                spots = homes + spots           # each pet pops in at its first job
        candidates.append(spots)

    px = lambda v: exact.quantize(float(v), 2)
    spots = lambda pts: [[px(x), px(y)] for x, y in pts]
    out = Built()
    out.inputs = {
        'size': [px(W), px(H)], 'petHeight': pet_h, 'intro': intro, 'step': step, 'seed': int(seed),
        'pets': [{'id': pid, 'start': spots([homes[i % len(homes)]])[0]} for i, pid in enumerate(ids)],
        'candidates': [spots(c) for c in candidates], 'strokes': [spots(s) for s in template.strokes],
        'frameHeight': px(H + exit_band)}
    out.seeds, out.paint_keys, out.paint_of = seeds, keys, paint_of
    out.sim_labels, out.sim_n = sim_labels, sim_n
    out.strokes, out.numbers, out.trace = template.strokes, template.numbers, trace
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('generated')
    ap.add_argument('snapshots')
    ap.add_argument('--spec', default=SPEC)
    ap.add_argument('--seed', type=int, default=7)
    ap.add_argument('--crew', type=int, help="the first N pets of the crew's order (default the spec's crew)")
    ap.add_argument('--pet-height', type=float, help="a pet's height as a share of the picture's shorter side")
    ap.add_argument('--width', type=int, help="the pictures' width in px (default the snapshots')")
    ap.add_argument('--out', help='write the JSON here instead of to stdout')
    a = ap.parse_args()
    with open(a.spec, encoding='utf-8') as f:
        spec = json.load(f)
    making_of_pets.configure(spec)
    ids = making_of_pets.ORDER[:a.crew or len(spec['crew']['pets'])]
    pictures = Pictures(a.snapshots, a.width)
    template = Template(os.path.join(a.generated, 'template.svg'), pictures.size[0])
    built = build(pictures, template, spec, a.seed, ids, pet_height=a.pet_height)
    doc = {'seed': a.seed, 'inputs': built.inputs, 'seeds': [list(s) for s in built.seeds],
           'paints': [int(k) for k in built.paint_keys], 'trace': built.trace}
    text = json.dumps(doc, separators=(',', ':'))
    if a.out:
        with open(a.out, 'w', encoding='utf-8') as f:
            f.write(text + '\n')
    else:
        print(text)


if __name__ == '__main__':
    main()
