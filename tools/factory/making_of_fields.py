#!/usr/bin/env python3
"""The making-of show with no crew: each step's change grows from seeds over the picture itself, in
a pattern of its own that follows what the step does.

  1 sketch     graphite races along the structure like frost along cracks; the color drains and
               the paper washes in behind it, outward from the lines
  2 shading    watercolor blooms open from drops born at random moments, slow to a stop at edges
               and seep past them, each with a darker tide line at its rim
  3 paints     the real k-means++ seeds drop as rings, and each paint runs through its own areas
               like dye, jumping slowly between them
  4 merged     the tiny bits melt into their neighbors from the outside in, smallest first
  5 ink        the lines burn along the drawing like a fuse, branching at every junction, a spark
               at every burning tip, grey at first and darkening to ink
  6 template   a second fuse relaxes the outlines into curves; the areas clear in drifts; the
               numbers come out like stars, each with a faint ring

    show = FieldShow(snapshots, svg, spec, seed=7)
    frame = show.frame(t)             # what to draw at t, as plain data (`frame`)
    picture = show.composite(frame)

It is built from the shared modules (the k-means++ seeds, the paints, the merged regions, the
template's lines and numbers: making_of_inputs.py; the layers: making_of_layers.py; the pictures'
formulas: making_of_compose.py; the cards, the rings and the lines' stair steps:
making_of_reveal.py), and plays in making_of_clip.py. What
differs is when each part changes: an arrival time from each step's seeds through a cost field
(`geodesic`), roughened by domain-warped noise (`Noise`), then paced by rank (`paced`), so the
change covers the picture evenly whatever the field's outliers. The fields are computed at half the
picture's size and grown back bilinearly.

Every random draw is SplitMix64's (making_of_pets.stream, the purposes from STREAM_FIELDS on) and
every pick is made from integer weights (making_of_inputs.sample_stops), so a port picks the same
seeds; the fields are smooth float64 for a port to match within a tolerance, as the layers do.
Sources/MakingOf's `FieldShow` is the port: Tests/MakingOfTests compares it with the numbers that
tools/tests/test_making_of_fields.py --write-goldens writes (fields-small.json), which also pins the
picks `FieldShow.picks` records here.
"""

import dataclasses
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import making_of_compose as compose  # noqa: E402
import making_of_exact as exact  # noqa: E402
import making_of_inputs as inputs  # noqa: E402
import making_of_layers as layers  # noqa: E402
import making_of_pets as pets  # noqa: E402
import making_of_reveal as reveal  # noqa: E402

OUTRO = 1.6               # s the finished drawing holds: there is no goodbye to wait for
SCALE = 2                 # the fields are computed at 1 / SCALE of the picture's size
SWEEPS = 3                # rounds of geodesic's four sweeps
PACE_MIX = 0.8            # how much of a field's pace is its rank (the rest its plain stretch)
PACE_KNOTS = 2048         # ranks the pacing interpolates between
LATTICE = 129             # noise lattice points across (it wraps)
STREAM_FIELDS = 16        # making_of_pets.stream purposes from here on: the six steps, the noise

SKETCH_SEEDS, SKETCH_SPACING, SKETCH_BIRTHS = 9, 0.12, 0.5      # count, of the width, s
SKETCH_FLAT, SKETCH_GAIN, SKETCH_POWER = 0.05, 2.5, 0.7         # speed off and on the survivors
SKETCH_ROUGH = (70, 0.35)                                       # noise scale (px), strength
SKETCH_END = 1.05         # s before the step ends: the last pixel's graphite and wash still fit
BLOOM_SEEDS, BLOOM_SPACING, BLOOM_BIRTHS = 15, 0.11, 1.0
BLOOM_EDGE = 60.0         # how hard an edge stops a bloom: speed / (1 + this * structure^2)
BLOOM_ROUGH = (55, 0.55)
BLOOM_END = 0.3
DYE_OUTSIDE = 14.0        # how much slower a paint runs outside its own areas
DYE_BIRTH = 40.0          # px of the field per s of the seeds' drop times
DYE_ROUGH = (40, 0.4)
DYE_UNSEEDED = 60.0       # px later a paint no seed landed on starts, from the nearest seed
DYE_START, DYE_END = 0.2, 0.3
MELT_SPAN = 0.55          # of the step: the bits melt over this much of it, smallest first
MELT_JITTER = 0.8         # of the mean size: how much chance shuffles that order
MELT_RATE = 0.06          # s per px from a bit's border to its middle
MELT_REACH = 40.0         # px: no bit takes longer to melt than this far in
MELT_DRIFT = (90, 0.1, 0.6)   # the rest (the sketch fading): noise scale, then of the step
MELT_END = 0.25
FUSE_SEEDS, FUSE_BIRTHS = 7, 30.0     # px of the field: the fuses are lit at moments this far apart
FUSE_OFF_LINE = 30.0      # how much slower a fuse jumps a gap than it burns along a line
FUSE_END = 0.55           # s before the ink step ends: the last segment still darkens to ink
SPARK = 0.06              # s a spark shows at a burning tip
SPARKS_PER_LINE = 2       # at most, per line at once
RELAX_SEEDS, RELAX_BIRTHS, RELAX_SPAN = 5, 20.0, 0.55
CLEAR_DRIFT = (90, 0.25, 0.7)     # noise scale, then of the step: when the areas clear
NUMBER_AFTER, NUMBER_SPREAD, NUMBER_END = 0.1, 0.55, 0.2    # s
STAR = 0.35               # s a number's ring opens and fades
STAR_RADIUS = (0.6, 0.9, 3.0)     # of the number's size: from, growing by; at least px
STAR_ALPHA = 0.35
TIDE_DEPTH = (0.09, 0.12, 0.06)   # steps 2 to 4: how much darker a front's rim is
TIDE_WIDTH = 0.07         # s
LIFT_AFTER, LIFT_END = 0.15, 0.3

# the compositor's numbers for this show: graphite goes down as the front passes, not after it
STYLE = dataclasses.replace(
    layers.STYLE, graphite_delay=0.05, graphite_by_structure=0.15, graphite_ramp=0.14, drain_ramp=0.45,
    wash_delay=0.4, wash_margin=0.75, wash_ramp=0.6, soft_early=0.14, settle_depth=0.0, lift_ramp=0.25,
    clear_ramp=0.18)


# --- fields --------------------------------------------------------------------------------------------

def _sweep(T, cost):
    """One sweep down the rows of T, in place: from the row above (straight and diagonal), then
    along each row both ways in closed form, a running minimum of T minus the cumulative cost."""
    diagonal = math.sqrt(2)
    for y in range(1, T.shape[0]):
        above, c = T[y - 1], cost[y]
        reach = above + c
        reach[1:] = np.minimum(reach[1:], above[:-1] + diagonal * c[1:])
        reach[:-1] = np.minimum(reach[:-1], above[1:] + diagonal * c[:-1])
        row = np.minimum(T[y], reach)
        run = np.cumsum(c)
        row = run + np.minimum.accumulate(row - run)
        back = np.cumsum(c[::-1])
        T[y] = (back + np.minimum.accumulate(row[::-1] - back))[::-1]


def geodesic(cost, seeds=(), start=None, sweeps=SWEEPS):
    """When a front from `seeds` [(t, x, y)] (or from `start`, a field that is inf where nothing
    starts) reaches each cell, through `cost` (time to cross a cell; a diagonal step costs sqrt 2 of
    it): the fast-sweeping solution of the eikonal equation on the eight-neighbor grid, four sweeps
    (down, right, up, left) a round."""
    T = np.full(cost.shape, np.inf) if start is None else np.array(start, dtype=np.float64)
    for t, x, y in seeds:
        yi, xi = min(max(int(y), 0), cost.shape[0] - 1), min(max(int(x), 0), cost.shape[1] - 1)
        T[yi, xi] = min(T[yi, xi], t)
    for _ in range(sweeps):
        for flip in (False, True):
            for across in (False, True):
                A, C = (T.T, cost.T) if across else (T, cost)
                if flip:
                    A, C = A[::-1], C[::-1]
                A, C = np.ascontiguousarray(A), np.ascontiguousarray(C)
                _sweep(A, C)
                if flip:
                    A = A[::-1]
                T = np.ascontiguousarray(A.T if across else A)
    return T


def paced(T, lo, hi, over=None, mix=PACE_MIX):
    """`T` mapped into lo...hi mostly by its rank among the cells `over` (a mask; all finite cells
    if None), so the change covers them at an even pace however the field bunches; `mix` keeps the
    rest of its plain stretch, so a fast front still looks fast. Cells of one time share their mean
    rank; the earliest maps to lo, the latest and inf to hi."""
    ok = np.isfinite(T)
    ref = np.sort(T[ok & over] if over is not None else T[ok])
    knots, which = np.unique(ref[np.arange(PACE_KNOTS + 1) * (len(ref) - 1) // PACE_KNOTS], return_inverse=True)
    ranks = np.bincount(which, weights=np.arange(PACE_KNOTS + 1) / PACE_KNOTS) / np.bincount(which)
    ranks[0], ranks[-1] = 0.0, 1.0
    Tc = np.where(ok, T, knots[-1])
    rank = np.interp(Tc, knots, ranks) if len(knots) > 1 else np.ones_like(Tc)
    plain = np.clip((Tc - knots[0]) / max(knots[-1] - knots[0], 1e-9), 0, 1)
    return lo + (mix * rank + (1 - mix) * plain) * (hi - lo)


class Noise:
    """Value noise on wrapping lattices drawn from the show's stream, its octaves summed (fbm) and
    domain-warped (`warped`), on a plane of cells."""

    def __init__(self, seed):
        rng = pets.stream(seed, STREAM_FIELDS + 6, 0)
        self.grids = [np.array([rng.random() for _ in range(LATTICE * LATTICE)]).reshape(LATTICE, LATTICE)
                      for _ in range(6)]

    def _value(self, g, x, y):
        x0, y0 = np.floor(x), np.floor(y)
        fx, fy = compose.smoothstep(x - x0), compose.smoothstep(y - y0)
        n = LATTICE - 1
        xi, yi = x0.astype(np.int64) % n, y0.astype(np.int64) % n
        top = g[yi, xi] + (g[yi, xi + 1] - g[yi, xi]) * fx
        bottom = g[yi + 1, xi] + (g[yi + 1, xi + 1] - g[yi + 1, xi]) * fx
        return top + (bottom - top) * fy

    def fbm(self, x, y, octaves=5, first=0):
        out, amp, f, total = 0.0, 1.0, 1.0, 0.0
        for o in range(octaves):
            out = out + amp * self._value(self.grids[(first + o) % 6], x * f + 17.3 * o, y * f + 9.1 * o)
            total += amp
            amp, f = amp / 2, f * 2.03
        return out / total

    def warped(self, shape, scale, strength=3.0):
        ys, xs = np.mgrid[0:shape[0], 0:shape[1]].astype(np.float64) / scale
        return self.fbm(xs + strength * self.fbm(xs, ys, 4, 1), ys + strength * self.fbm(xs + 5.2, ys + 1.3, 4, 2), 5, 3)

    def rough(self, shape, scale, strength):
        """A speed factor, exp(strength * the warped noise, standardized): swells and fingers."""
        n = self.warped(shape, scale)
        return np.exp(strength * (n - n.mean()) / (n.std() + 1e-9))


def shrink(plane):
    """`plane` at 1 / SCALE of its size, each cell the mean of its block (the last odd row or
    column dropped)."""
    h, w = plane.shape[0] // SCALE * SCALE, plane.shape[1] // SCALE * SCALE
    p = np.asarray(plane[:h, :w], dtype=np.float64)
    return p.reshape(h // SCALE, SCALE, w // SCALE, SCALE).mean(axis=(1, 3))


def grow(field, size):
    """A field at the picture's `size` (W, H), bilinear between the centres of its cells."""
    W, H = size
    h, w = field.shape
    fy = np.clip((np.arange(H) + 0.5) / SCALE - 0.5, 0, h - 1)
    fx = np.clip((np.arange(W) + 0.5) / SCALE - 0.5, 0, w - 1)
    y0, x0 = np.minimum(fy.astype(np.int64), h - 2), np.minimum(fx.astype(np.int64), w - 2)
    ty, tx = (fy - y0)[:, None], (fx - x0)[None, :]
    a, b = field[y0][:, x0], field[y0][:, x0 + 1]
    c, d = field[y0 + 1][:, x0], field[y0 + 1][:, x0 + 1]
    top, bottom = a + (b - a) * tx, c + (d - c) * tx
    return top + (bottom - top) * ty


def born(seed, step, weights, width, n, spacing, t0, t1):
    """`n` seeds of step `step` [(t, x, y)] in a plane `width` cells wide, drawn by integer `weights`
    `spacing` cells apart, lit at moments of a Poisson process squeezed into t0...t1, in a shuffled
    order."""
    rng = pets.stream(seed, STREAM_FIELDS + step, 0)
    spots = inputs.sample_stops(weights, width, n, rng, spacing)
    gaps = [-math.log(1 - rng.random()) for _ in range(len(spots) + 1)]
    run = exact.cumulative(gaps)
    order = rng.permutation(len(spots))
    return [(t0 + (t1 - t0) * float(run[i]) / float(run[-1]), float(spots[j][0]), float(spots[j][1]))
            for i, j in enumerate(order)]


class TideCompositor(compose.Compositor):
    """The compositor, with a watercolor's tide line on the fronts of steps 2 to 4: a thin darker
    rim just behind where the change is arriving."""

    def picture(self, t, ink=None, numbers=None, template=None, handoff=0.0):
        pic = super().picture(t, ink, numbers, template, handoff)
        k = compose.stage_of(t, self.intro, self.step)
        if 1 <= k <= 3:
            u = (t - self.times[('shading', 'paints', 'merged')[k - 1]]) / TIDE_WIDTH
            pic = pic * (1 - TIDE_DEPTH[k - 1] * np.exp(-3 * (u - 0.6) ** 2) * (u > 0))[..., None]
        return pic


def show_inputs(snapshots, svg, spec, seed):
    """The pictures, the template and what the show is built from (`making_of_inputs.build`). The show
    draws no guardian, but its spots and seeds are still drawn for the spec's crew, as they were when
    it had one: the fixtures pin them. Configures making_of_pets from the spec."""
    pets.configure(spec)
    pictures = inputs.Pictures(snapshots)
    template = inputs.Template(svg, pictures.size[0])
    built = inputs.build(pictures, template, spec, seed, pets.ORDER[:len(spec['crew']['pets'])])
    return pictures, template, built


def ink_coverage(lines, width, height, line_width):
    """How much ink `lines` ([{points, value}]) put on each pixel, float32 (height, width): a pixel is
    covered by a line as far as its centre is within half `line_width` of it, softened over one pixel
    (full half a pixel inside the edge, none half a pixel outside) and times the line's value; where
    lines meet the darker wins. Round joins and ends. Sources/MakingOf's `InkCoverage`, bit for bit:
    only + - * and sqrt in float64, in a fixed order."""
    coverage = np.zeros((height, width))
    reach = line_width / 2 + 0.5
    for line in lines:
        pts, value = line['points'], line['value']
        for (ax, ay), (bx, by) in zip(pts[:-1], pts[1:]):
            x0 = max(int(math.floor(min(ax, bx) - reach)), 0)
            x1 = min(int(math.floor(max(ax, bx) + reach)) + 1, width)
            y0 = max(int(math.floor(min(ay, by) - reach)), 0)
            y1 = min(int(math.floor(max(ay, by) + reach)) + 1, height)
            if x0 >= x1 or y0 >= y1:
                continue
            px = np.arange(x0, x1, dtype=np.float64)[None, :] + 0.5
            py = np.arange(y0, y1, dtype=np.float64)[:, None] + 0.5
            vx, vy = bx - ax, by - ay
            length_squared = vx * vx + vy * vy
            along = np.clip(((px - ax) * vx + (py - ay) * vy) / length_squared, 0, 1) if length_squared > 0 else 0.0
            dx, dy = px - (ax + along * vx), py - (ay + along * vy)
            covered = np.clip(reach - np.sqrt(dx * dx + dy * dy), 0, 1) * value
            np.maximum(coverage[y0:y1, x0:x1], covered, out=coverage[y0:y1, x0:x1])
    return coverage.astype(np.float32)


class FieldShow:
    """The show with no crew, built from `snapshots` (the folder `pbn generate --snapshots` writes),
    `svg` (its template.svg), the spec (a dict, making-of.json) and `seed`."""

    def __init__(self, snapshots, svg, spec, seed=7):
        pictures, template, built = show_inputs(snapshots, svg, spec, seed)
        self.spec, self.seed, self.built = spec, seed, built
        self.size = (W, H) = pictures.size
        self.line_width = template.line_width
        intro, step = float(spec['timing']['intro']), float(spec['timing']['step'])
        self.intro, self.step = intro, step
        self.duration = intro + reveal.STEPS * step + OUTRO
        self.seeds = built.seeds
        s = reveal.starts(intro, step)
        stages = layers.Stages.read(snapshots, None, spec['sketch'], spec['tones'])
        noise = Noise(seed)
        h, w = H // SCALE, W // SCALE
        fine = noise.fbm(*(np.mgrid[0:h, 0:w][::-1].astype(np.float64) / 6.0), 4, 5)
        structure = pictures.structure.astype(np.int64)      # 0...255, exact, for the picks
        per_pixel = lambda per_region, regions: per_region[regions].astype(np.float32)
        labels, count = built.sim_labels, built.sim_n

        self.picks = {}                     # what chance decided, for the golden to pin
        # 1: fast along what survives relative total variation, slow across the flats
        survivors = np.clip(shrink(stages.survivors), 0, 1)
        speed = (SKETCH_FLAT + SKETCH_GAIN * survivors ** SKETCH_POWER) * noise.rough((h, w), *SKETCH_ROUGH)
        lit = born(seed, 0, shrink(structure ** 2).astype(np.int64).ravel(), w, SKETCH_SEEDS,
                   SKETCH_SPACING * w, 0.0, SKETCH_BIRTHS)
        sketch = paced(grow(geodesic(1 / speed, lit), self.size), s[0] + 0.05, s[0] + step - SKETCH_END)
        self.picks['sketch'] = lit

        # 2: blooms that stall at edges, with ragged fronts
        edges = np.clip(shrink(structure) / max(exact.percentile(structure, 98), 1), 0, 1)
        speed = noise.rough((h, w), *BLOOM_ROUGH) * (0.6 + 0.8 * fine) / (1 + BLOOM_EDGE * edges ** 2)
        drops = born(seed, 1, np.ones(h * w, dtype=np.int64), w, BLOOM_SEEDS, BLOOM_SPACING * w, 0.0, BLOOM_BIRTHS)
        shading = paced(grow(geodesic(1 / speed, drops), self.size), s[1] + 0.05, s[1] + step - BLOOM_END)
        self.picks['shading'] = drops

        # 3: each paint from its own seeds through its own areas; between them, slowly
        paint_of = built.paint_of[::SCALE, ::SCALE][:h, :w]
        rough = noise.rough((h, w), *DYE_ROUGH)
        flow = np.full((h, w), np.inf)
        everyone = []
        for p in range(len(built.paint_keys)):
            mine = [(t * DYE_BIRTH, x / SCALE, y / SCALE) for t, x, y, q in built.seeds if q == p]
            if mine:
                everyone += mine
                own = paint_of == p
                flow = np.where(own, np.minimum(flow, geodesic(np.where(own, 1.0, DYE_OUTSIDE) / rough, mine, sweeps=2)),
                                flow)
        missing = np.isinf(flow)
        if missing.any():
            flow[missing] = (geodesic(1 / rough, everyone) + DYE_UNSEEDED)[missing]
        paints = paced(grow(flow, self.size), s[2] + DYE_START, s[2] + step - DYE_END)
        self.spread = np.full(len(built.paint_keys), -np.inf)
        np.maximum.at(self.spread, built.paint_of.ravel(), paints.ravel())

        # 4: the bits merged away melt from their border in, the smallest first; the rest drifts. A
        # bit is an area of one paint that isn't the largest of the merged region it ended up in.
        bit_labels, bit_count = exact.label_regions(exact.color_keys(pictures.palette))
        pair = labels.astype(np.int64) * bit_count + bit_labels
        keys, counts = np.unique(pair, return_counts=True)
        region, area = keys // bit_count, keys % bit_count
        order = np.lexsort((area, -counts, region))           # per region: the largest area first
        first = np.ones(len(order), dtype=bool)
        first[1:] = region[order][1:] != region[order][:-1]
        largest = np.empty(count, dtype=np.int64)
        largest[region[order][first]] = area[order][first]
        bits = bit_labels != largest[labels]
        sizes = np.bincount(bit_labels.ravel(), minlength=bit_count).astype(np.float64)
        melting = np.unique(bit_labels[bits])
        rng = pets.stream(seed, STREAM_FIELDS + 3, 0)
        typical = sizes[melting].mean() if len(melting) else 0.0
        shuffled = sizes[melting] + np.array([rng.random() for _ in melting]) * typical * MELT_JITTER
        rank = np.zeros(bit_count)
        rank[melting[np.argsort(shuffled, kind='stable')]] = np.arange(len(melting)) / max(len(melting) - 1, 1)
        inward = grow(geodesic(np.ones((h, w)), start=np.where(shrink(bits) > 0.5, np.inf, 0.0), sweeps=2), self.size)
        melt = s[3] + 0.1 + rank[bit_labels] * MELT_SPAN * step + np.minimum(inward, MELT_REACH) * MELT_RATE
        drift = paced(grow(noise.warped((h, w), MELT_DRIFT[0], 4.0), self.size),
                      s[3] + MELT_DRIFT[1] * step, s[3] + MELT_DRIFT[2] * step)
        merged = np.minimum(np.where(bits, melt, drift), s[3] + step - MELT_END)
        self.picks['melting'] = {'bits': int(bits.sum()), 'areas': melting.tolist(), 'rank': rank[melting].tolist()}

        # 5: fuses along the lines
        strokes = [np.array(st) for st in built.inputs['strokes']]
        on_line = exact.line_mask(w, h, [st / SCALE for st in strokes], 1.0)
        cells = np.flatnonzero(on_line.ravel())
        rng = pets.stream(seed, STREAM_FIELDS + 4, 0)
        fuse_cost = np.where(on_line, 1.0, FUSE_OFF_LINE) * (0.75 + 0.5 * fine)
        lines_full = exact.line_mask(W, H, strokes, 1.0)

        self.picks['fuses'] = lit_fuses = []

        def fuses(n, births):
            picked = [int(cells[rng.below(len(cells))]) for _ in range(n)]
            lit = [(rng.uniform(0, births), c % w, c // w) for c in picked]
            lit_fuses.append(lit)
            return geodesic(fuse_cost, lit)

        fuse = paced(grow(fuses(FUSE_SEEDS, FUSE_BIRTHS), self.size), s[4] + 0.05, s[4] + step - FUSE_END,
                     over=lines_full)
        lift = reveal.region_min(np.minimum(fuse + LIFT_AFTER, s[4] + step - LIFT_END), labels, count)

        # 6: a second fuse relaxes the outlines; the areas clear in drifts; the numbers come out
        relax = paced(grow(fuses(RELAX_SEEDS, RELAX_BIRTHS), self.size), s[5] + 0.05, s[5] + RELAX_SPAN * step,
                      over=lines_full)
        drift = paced(grow(noise.warped((h, w), CLEAR_DRIFT[0], 4.0), self.size),
                      s[5] + CLEAR_DRIFT[1] * step, s[5] + CLEAR_DRIFT[2] * step)
        clear = reveal.region_min(drift, labels, count)

        self.times = {'sketch': sketch.astype(np.float32), 'shading': shading.astype(np.float32),
                      'paints': paints.astype(np.float32), 'merged': merged.astype(np.float32),
                      'lift': per_pixel(lift, labels), 'clear': per_pixel(clear, labels)}
        self.compositor = TideCompositor(stages.layers(), stages, self.times, intro, step, STYLE)

        grid = float(spec['outlines']['grid'])
        self.strokes, self.fuses = [], []
        for n, st in enumerate(strokes):
            J, S = reveal.staircase(st, grid)
            ix = np.clip(S[:, 0].astype(int), 0, W - 1)
            iy = np.clip(S[:, 1].astype(int), 0, H - 1)
            at = fuse[iy, ix]
            self.fuses.append(at)
            self.strokes.append(reveal.Stroke(n, False, float(at.min()), float(at.max() - at.min()), J, S,
                                              pets.cumulative(S), relax[iy, ix]))
        rng = pets.stream(seed, STREAM_FIELDS + 5, 0)
        self.number_times = []
        for x, y, _ in built.numbers:
            at = float(clear[labels[reveal.clamped_index(y, H), reveal.clamped_index(x, W)]])
            self.number_times.append(min(at + NUMBER_AFTER + rng.uniform(0, NUMBER_SPREAD),
                                         s[5] + step - NUMBER_END))

    def burning(self, t):
        """The ink step's lines at time t: every segment the fuse has reached at both ends, grey at
        first and darkening to ink in eighths, as runs of one value; and the sparks at the burning
        tips, (x, y, heat 0...1)."""
        ramp = float(self.spec['outlines']['inkRamp'])
        lines, sparks = [], []
        for stroke, at in zip(self.strokes, self.fuses):
            seg = np.maximum(at[:-1], at[1:])
            lit = seg <= t
            if not lit.any():
                continue
            u = np.clip((t - seg) / ramp, 0, 1)
            value = np.minimum(np.floor((reveal.INK_GREY * (1 - u) + u) * 8) / 8 + 1 / 16, 1.0)
            i, n = 0, len(seg)
            while i < n:
                if not lit[i]:
                    i += 1
                    continue
                j = i
                while j + 1 < n and lit[j + 1] and value[j + 1] == value[i]:
                    j += 1
                lines.append({'stroke': stroke.index, 'points': stroke.jagged[i:j + 2], 'value': float(value[i])})
                i = j + 1
            hot = np.flatnonzero((at <= t) & (at > t - SPARK))
            for k in hot[::max(1, len(hot) // SPARKS_PER_LINE)]:
                sparks.append({'x': float(stroke.jagged[k][0]), 'y': float(stroke.jagged[k][1]),
                               'heat': 1 - (t - float(at[k])) / SPARK})
        return lines, sparks

    def frame(self, t):
        """What to draw at time `t`: {time, step, picture: {stage, time, handoff}, ink: [{stroke,
        points, value}], numbers: [alpha], seed_rings: [{x, y, radius, alpha}], sprites (always empty),
        card: {step, caption, methods, opacity, footnote_opacity} or None, sparks: [{x, y, heat}] in
        the ink step, stars: [{x, y, radius, alpha}] as the numbers come out}, all places in pixels
        of the snapshots' picture. Sources/MakingOf's `ShowFrame` has the same but `sprites`, and its
        doc comment says what a view draws from it."""
        spec, intro, step = self.spec, self.intro, self.step
        stage = compose.stage_of(t, intro, step)
        k = stage if 0 <= stage < reveal.STEPS else None
        ink, sparks, stars = [], [], []
        if stage == reveal.INK_STEP:
            ink, sparks = self.burning(t)
        elif stage >= reveal.TEMPLATE_STEP:
            ink = [{'stroke': i, 'points': points, 'value': value} for i, points, value in
                   reveal.relaxed_lines(self.strokes, t if t < intro + reveal.STEPS * step else math.inf,
                                        float(spec['outlines']['relax']))]
        numbers = []
        if stage >= reveal.TEMPLATE_STEP:
            numbers = [pets.ease((t - at) / reveal.NUMBER_FADE) for at in self.number_times]
            r0, grow_by, least = STAR_RADIUS
            for (x, y, size), at in zip(self.built.numbers, self.number_times):
                u = (t - at) / STAR
                if 0 < u < 1:
                    stars.append({'x': x, 'y': y, 'radius': max(size * r0, least) + size * grow_by * u,
                                  'alpha': STAR_ALPHA * (1 - u)})
        rings = []
        if stage == 2:
            for seed in self.seeds:
                ring = reveal.seed_ring(seed, self.spread[seed[3]], t, intro, step,
                                        float(spec['seeds']['dot']), float(spec['seeds']['fade']))
                if ring:
                    rings.append(ring)
        card = None
        if k is not None:
            fade_in = reveal.card_fade(k, t, intro, step)
            if fade_in > 0:
                opacity = float(spec['cards']['opacity']) * fade_in
                card = {'step': k, 'caption': spec['steps'][k]['caption'], 'methods': spec['steps'][k]['methods'],
                        'opacity': opacity, 'footnote_opacity': opacity * float(spec['cards']['footnote'])}
        return {'time': t, 'step': k, 'picture': {'stage': stage, 'time': t, 'handoff': reveal.handoff(t, intro, step)},
                'ink': ink, 'numbers': numbers, 'seed_rings': rings, 'sprites': [], 'card': card,
                'sparks': sparks, 'stars': stars}

    def composite(self, frame):
        """The picture of `frame`, float32 (H, W, 3): the layers blended as its recipe says, with its
        lines rasterized by `ink_coverage` at the template's line width. The numbers, the hand-off,
        the rings, the sparks, the stars and the card are the renderer's, as in Sources/MakingOf's
        `FieldShow.composite`."""
        W, H = self.size
        ink = ink_coverage(frame['ink'], W, H, self.line_width) if frame['ink'] else None
        return self.compositor.picture(frame['picture']['time'], ink)
