#!/usr/bin/env python3
"""When each part of the making-of picture changes: the show's reveal schedule, in float64.

This is the reference for Sources/MakingOf (ValueNoise, Arrival, Outlines, NumberSchedule, Timeline),
which ports it line by line; change the two together and regenerate the fixture:

  python3 tools/factory/making_of_reveal.py --fixture Tests/MakingOfTests/Fixtures/show-small \\
      Tests/MakingOfTests/Fixtures/reveal-small.json

(the fixture's inputs are made here from the small show fixture, by hand and by the crew's planner,
so the schedule is judged apart from the code that picks a real show's spots and paints.)

A step's change spreads from where the crew works (`arrival`), roughened by noise, and each region
of the picture changes when the change first reaches it (`region_min`). The paints flow out from
the k-means++ seeds instead (`paint_flow`); the template's lines are drawn stair-stepped, then
relax into their smooth curves (`stroke_schedule`, `staircase`), and each number comes in near the
last guardian to work by it (`number_times`). Everything is a pure function of its inputs and the
show's seed, from SplitMix64 streams (making_of_pets.stream): noise and the strokes' start
jitter. Geometry is float64 throughout and uses only + - * / and sqrt, so Swift and Python agree
bit for bit; lines are polylines with an ink value, never pixels.

The numbers every function shares are named below, in one block; Sources/MakingOf's
ScheduleStyle holds the same ones (in camelCase), and the tests check they agree.
"""

import argparse
import json
import math
import os
import re
import sys
from collections import namedtuple

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import making_of_pets as pets  # noqa: E402

# --- the schedule's constants (ScheduleStyle in Swift) -------------------------------------------------

REFERENCE_STEP = 1.5      # s: the step the speeds below were tuned at; pace = REFERENCE_STEP / step
ARRIVAL_SPEED = 0.55      # picture widths per second (times pace) a step's change spreads at
STEP_MARGIN = 0.2         # s: every pixel of a step has changed this long before the step ends
COARSE_NOISE = 0.10       # s of roughness: broad swells ...
COARSE_CELLS = (18, 12)   # ... from this many cells across and down
FINE_NOISE = 0.06         # ... and fine grain ...
FINE_CELLS = (60, 40)     # ... from this many
SEED_DELAY = 0.25         # s from a seed dropping to its paint starting to flow out of it
SEED_SPEED_DIVISOR = 1.3  # a paint flows out at one picture width per this many seconds
PAINT_FLOOR = 0.2         # s into the paints step before which no paint flows
UNSEEDED_DELAY = 0.3      # s a paint no seed landed on lags the crew's own change
STAIRCASE_SPACING = 1.5   # px between the samples of a line before they are snapped to the grid
STROKE_JITTER = 0.5       # s at most a line the crew doesn't walk waits after the crew reaches it
STROKE_EARLIEST = 0.3     # s into the ink step before any line the crew doesn't walk begins
STROKE_SPEED = 0.45       # picture widths per second (times pace) such a line is drawn at
STROKE_MIN_TIME = 0.25    # s: the quickest such a line is drawn
STROKE_MAX_TIME = 0.9     # s (over pace): the slowest
INK_END_MARGIN = 0.12     # s: such a line is drawn this long before the ink step ends
INK_GREY = 0.45           # ink value a line starts at; it darkens to full ink over `inkRamp`
NUMBER_NEAR = 1.6         # guardian heights: a number this near a working guardian goes down just after it
NUMBER_AFTER_PET = 0.3    # s after that guardian's visit
NUMBER_LATE = 0.55        # steps into the template step the other numbers wait for, at the earliest
NUMBER_AFTER_CLEAR = 0.05  # s after its area has cleared to paper, at the earliest
NUMBER_AFTER_RELAX = 0.45  # s after the outlines have relaxed at it
NUMBER_END_MARGIN = 0.15  # s: every number is down this long before the show's steps end
NUMBER_FADE = 0.1         # s a number takes to come in
NUMBER_DISC = 0.9         # of a number's size: the radius of the disc it owns (at least NUMBER_DISC_MINIMUM)
NUMBER_DISC_MINIMUM = 4.0  # px
CARD_FADE = 0.15          # s: a card fades in and out over this long at the reference step (over sqrt of the pace)
RING_POP = 0.22           # s: a seed ring pops in over this long ...
RING_SWELL = 0.35         # ... swelling by this share of its radius on the way ...
RING_RISE = 3.0           # ... and is opaque once a third of that has passed
RING_GONE_BEFORE = 0.4    # s: every ring is gone this long before the paints step ends, over ...
RING_GONE_FADE = 0.35     # ... this long
RING_AFTER_SPREAD = 0.1   # s: a ring fades this long after its paint has spread everywhere
CREW_FADE_OUT = 0.3       # s: every guardian fades out over the last of this long of the show
HANDOFF = 0.15            # s: the finished drawing hands over to the real template over this long
WHOLE_WITHIN = 1e-9       # px: a line walked to the end can fall a rounding short of its length; it is whole

STEPS = 6
INK_STEP = pets.INK_STEP
TEMPLATE_STEP = 5

Stroke = namedtuple('Stroke', 'index walked t0 dur jagged smooth cum relax')


def starts(intro, step):
    """When each step begins."""
    return [intro + k * step for k in range(STEPS)]


def smoothstep(x):
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3 - 2 * x)


# --- noise ---------------------------------------------------------------------------------------------

def noise_lattice(cells, rng):
    """The random values of a lattice of `cells` (across, down): (down + 1) rows of (across + 1),
    row-major, one draw each."""
    cx, cy = cells
    return np.array([rng.random() for _ in range((cy + 1) * (cx + 1))], dtype=np.float64).reshape(cy + 1, cx + 1)


def value_noise(shape, cells, lattice):
    """A smooth field over `shape` (h, w) from a lattice: bilinear between its values, eased with
    smoothstep, the picture spanning exactly `cells` cells."""
    h, w = shape
    ys = np.arange(h) * (cells[1] / h)      # numpy's linspace(0, cells, n, endpoint=False)
    xs = np.arange(w) * (cells[0] / w)
    y0, x0 = ys.astype(int), xs.astype(int)
    fy, fx = smoothstep(ys - y0)[:, None], smoothstep(xs - x0)[None, :]
    a, b = lattice[y0][:, x0], lattice[y0][:, x0 + 1]
    c, d = lattice[y0 + 1][:, x0], lattice[y0 + 1][:, x0 + 1]
    return (a + (b - a) * fx) * (1 - fy) + (c + (d - c) * fx) * fy


def step_lattices(seed, k):
    """Step k's two lattices, drawn from the noise streams 2k and 2k + 1."""
    return (noise_lattice(COARSE_CELLS, pets.stream(seed, pets.STREAM_NOISE, 2 * k)),
            noise_lattice(FINE_CELLS, pets.stream(seed, pets.STREAM_NOISE, 2 * k + 1)))


def step_noise(shape, seed, k):
    """The roughness of step k's change, in seconds."""
    coarse, fine = step_lattices(seed, k)
    return COARSE_NOISE * value_noise(shape, COARSE_CELLS, coarse) \
        + FINE_NOISE * value_noise(shape, FINE_CELLS, fine)


# --- arrival -------------------------------------------------------------------------------------------

def pixel_grid(shape):
    """Every pixel's x and y as float64, by the pixel's index (not its centre)."""
    h, w = shape
    ys, xs = np.mgrid[0:h, 0:w]
    return xs.astype(np.float64), ys.astype(np.float64)


def arrival(visits, shape, speed, t_end, noise):
    """When the change reaches each pixel: the earliest visit (time, x, y) plus its distance over
    `speed`, roughened by `noise`, and squeezed to be done by `t_end`."""
    xs, ys = pixel_grid(shape)
    T = np.full(shape, np.inf)
    for t, x, y in visits:
        dx, dy = xs - x, ys - y
        np.minimum(T, t + np.sqrt(dx * dx + dy * dy) / speed, out=T)
    T += noise
    t_start = min(v[0] for v in visits)
    hi = T.max()
    if hi > t_end and hi > t_start:
        T = t_start + (T - t_start) * (t_end - t_start) / (hi - t_start)
    return T


def step_arrival(k, visits, shape, intro, step, seed):
    """Step k's `arrival`, at the show's pace."""
    pace = REFERENCE_STEP / step
    return arrival(visits, shape, ARRIVAL_SPEED * shape[1] * pace, starts(intro, step)[k] + step - STEP_MARGIN,
                   step_noise(shape, seed, k))


def region_min(T, labels, count):
    """The earliest time in each of `count` regions (inf for an empty one)."""
    m = np.full(count, np.inf)
    np.minimum.at(m, labels.ravel(), T.ravel())
    return m


def paint_flow(seeds, paint_of, n_paints, T2, labels, n_labels, intro, step):
    """Each paint's areas flow out from its seeds (time, x, y, paint) across the paints step; a
    paint no seed landed on follows the crew's own change `T2`. Returns the time per region of
    `labels` (a region changes as one) and per paint the time its last region has changed."""
    w = paint_of.shape[1]
    s2 = starts(intro, step)[2]
    xs, ys = pixel_grid(paint_of.shape)
    T = np.full(paint_of.shape, np.inf)
    for st, sx, sy, paint in seeds:
        mine = paint_of == paint
        dx, dy = xs - sx, ys - sy
        T[mine] = np.minimum(T[mine], st + SEED_DELAY + np.sqrt(dx * dx + dy * dy)[mine] / (w / SEED_SPEED_DIVISOR))
    T = np.where(np.isinf(T), T2 + UNSEEDED_DELAY, T)
    lo, hi, cap = s2 + PAINT_FLOOR, T.max(), s2 + step - STEP_MARGIN
    if hi > cap and hi > lo:
        T = lo + (T - lo) * (cap - lo) / (hi - lo)
    region = region_min(T, labels, n_labels)
    spread = np.full(n_paints, -np.inf)
    np.maximum.at(spread, paint_of.ravel(), region[labels].ravel())
    return region, spread


# --- outlines ------------------------------------------------------------------------------------------

def linspace(stop, n):
    """numpy's linspace(0, stop, n) for n >= 2, written out."""
    out = np.arange(n) * (stop / (n - 1))
    out[-1] = stop
    return out


def staircase(pts, grid):
    """A smooth polyline as the stair-stepped pixel outline it was fitted to, paired point by
    point with the smooth line, so one can relax into the other: (jagged, smooth) arrays."""
    pts = np.asarray(pts, dtype=np.float64)
    cum = pets.cumulative(pts)
    d = linspace(cum[-1], max(2, int(cum[-1] / STAIRCASE_SPACING) + 1))
    smooth = np.stack([np.interp(d, cum, pts[:, 0]), np.interp(d, cum, pts[:, 1])], axis=1)
    snapped = np.round(smooth / grid) * grid
    J, S = [snapped[0]], [smooth[0]]
    for b, sm in zip(snapped[1:], smooth[1:]):
        a = J[-1]
        if (b == a).all():
            continue
        if a[0] != b[0] and a[1] != b[1]:          # a stair: across, then down
            J.append(np.array([b[0], a[1]]))
            S.append(sm)
        J.append(b)
        S.append(sm)
    if len(J) < 2:
        J.append(snapped[-1])
        S.append(smooth[-1])
    return np.array(J), np.array(S)


def clamped_index(v, n):
    """A coordinate as the index of the pixel it falls in, kept inside 0..<n."""
    return int(min(max(v, 0), n - 1))


def stroke_schedule(strokes, traces, T_ink, T_relax, intro, step, grid, seed):
    """When and how each line of the template is drawn. `traces` are the lines the crew walks,
    (stroke index, start, duration, points in drawing order); the rest begin where the crew's
    ink-step change reaches their first point (`T_ink`), a moment later by a draw from their own
    stream, and are drawn at a calmer pace. Each line is a Stroke: start, duration, the stair-stepped
    and the smooth points, the distance along the smooth ones, and when step 6's ripple (`T_relax`)
    reaches each. Every stroke is in the order it was given."""
    h, w = T_ink.shape
    pace = REFERENCE_STEP / step
    s4 = starts(intro, step)[INK_STEP]
    t_end = s4 + step - INK_END_MARGIN
    walked_by = {n: (t0, dur, pts) for n, t0, dur, pts in traces}
    out = []
    for n, s in enumerate(strokes):
        walked = n in walked_by
        if walked:
            t0, dur, pts = walked_by[n]
        else:
            pts = s
        J, S = staircase(pts, grid)
        cum = pets.cumulative(S)
        if not walked:
            x, y = clamped_index(pts[0][0], w), clamped_index(pts[0][1], h)
            jitter = pets.stream(seed, pets.STREAM_STROKES, n).uniform(0, STROKE_JITTER)
            t0 = max(float(T_ink[y, x]) + jitter, s4 + STROKE_EARLIEST)
            dur = min(max(cum[-1] / (STROKE_SPEED * w * pace), STROKE_MIN_TIME), STROKE_MAX_TIME / pace)
            if t0 + dur > t_end:
                t0 = max(s4, t_end - dur)
        ix = np.clip(S[:, 0].astype(int), 0, w - 1)
        iy = np.clip(S[:, 1].astype(int), 0, h - 1)
        out.append(Stroke(n, walked, t0, dur, J, S, cum, T_relax[iy, ix]))
    return out


def inked_lines(plan, t, ink_ramp, pet_h):
    """The ink step's lines at time t: each line begun, as far as it has been drawn along its
    stair-stepped outline, at its ink value (0...1): walked lines are in full ink, the others darken from
    INK_GREY. [(stroke index, points, value)]; a pure function of t."""
    out = []
    for s in plan:
        if t < s.t0:
            continue
        if s.walked:
            drawn = pets.traced(t - s.t0, float(s.cum[-1]), pet_h)
        else:
            drawn = pets.ease((t - s.t0) / s.dur) * s.cum[-1]
        if s.cum[-1] - drawn < WHOLE_WITHIN:
            drawn = s.cum[-1]
        n_pts = int(np.searchsorted(s.cum, drawn, side='right'))
        if n_pts < 2:
            continue
        u = min(max((t - s.t0) / (s.dur + ink_ramp), 0.0), 1.0)
        value = 1.0 if s.walked else INK_GREY * (1 - u) + u
        out.append((s.index, s.jagged[:n_pts], value))
    return out


def relaxed_lines(plan, t, relax_time):
    """The template step's lines at time t: every point relaxed from its stair-stepped place
    toward the smooth curve as far as the ripple from the crew has reached it, in full ink.
    t = inf is the finished template. [(stroke index, points, 1.0)]."""
    out = []
    for s in plan:
        m = smoothstep((t - s.relax) / relax_time)[:, None]
        out.append((s.index, s.jagged * (1 - m) + s.smooth * m, 1.0))      # exactly each end at 0 and 1
    return out


def lines_at(plan, t, intro, step, ink_ramp, relax_time, pet_h):
    """The lines drawn at time t of the whole show: none before the ink step, the ink step's, then
    the relaxing template's, and the smooth ones from the show's end on."""
    s = starts(intro, step)
    if t < s[INK_STEP]:
        return []
    if t < s[INK_STEP + 1]:
        return inked_lines(plan, t, ink_ramp, pet_h)
    return relaxed_lines(plan, t if t < intro + STEPS * step else math.inf, relax_time)


# --- numbers -------------------------------------------------------------------------------------------

def number_times(numbers, clear, simplified, T_relax, visits, intro, step, pet_h):
    """When each number (x, y, size) comes in: just after the last visit of a guardian working near it
    (`visits` are the template step's, (time, x, y)), else late in the step; never before its area
    has cleared (`clear`, per region of `simplified`) nor before the outlines have relaxed at it."""
    h, w = T_relax.shape
    s5 = starts(intro, step)[TEMPLATE_STEP]
    end = intro + STEPS * step
    out = []
    for x, y, _ in numbers:
        ix, iy = clamped_index(x, w), clamped_index(y, h)
        clear_at = float(clear[simplified[iy, ix]])
        near = [t for t, vx, vy in visits if pets.norm(vx - x, vy - y) < NUMBER_NEAR * pet_h]
        at = min(near) + NUMBER_AFTER_PET if near else max(clear_at, s5 + NUMBER_LATE * step)
        relaxed_at = float(T_relax[iy, ix]) + NUMBER_AFTER_RELAX
        out.append(min(max(at, clear_at + NUMBER_AFTER_CLEAR, relaxed_at), end - NUMBER_END_MARGIN))
    return out


def number_discs(numbers, shape):
    """Which number owns each pixel (the later of overlapping discs), -1 for none: a disc about
    the number's place, as big as the number and at least NUMBER_DISC_MINIMUM px."""
    h, w = shape
    xs, ys = pixel_grid(shape)
    owner = np.full(shape, -1, dtype=np.int32)
    for i, (x, y, size) in enumerate(numbers):
        r = max(size * NUMBER_DISC, NUMBER_DISC_MINIMUM)
        x0, x1 = int(max(x - r, 0)), int(min(x + r + 1, w))
        y0, y1 = int(max(y - r, 0)), int(min(y + r + 1, h))
        if x0 >= x1 or y0 >= y1:
            continue
        dx, dy = xs[y0:y1, x0:x1] - x, ys[y0:y1, x0:x1] - y
        owner[y0:y1, x0:x1][dx * dx + dy * dy <= r * r] = i
    return owner


# --- overlays ------------------------------------------------------------------------------------------
# When the cards, the seed rings, the crew and the real template come and go (Sources/MakingOf's
# Timeline): pure functions of the time, like everything above.

def card_fade(k, t, intro, step):
    """How far card `k` has faded in or out at `t`, 0...1: in over the first CARD_FADE of its step and out
    over the last, a brisker show fading faster."""
    fade = CARD_FADE / math.sqrt(REFERENCE_STEP / step)
    local = t - starts(intro, step)[k]
    return pets.ease(local / fade) * (1 - pets.ease((local - (step - fade)) / fade))


def seed_ring(seed, spread, t, intro, step, dot, fade):
    """The ring of a seed (time, x, y, paint) at `t` as {x, y, radius, alpha}, or None while it doesn't
    show. `spread`: when its paint's last region has changed; `dot`, `fade`: the spec's seeds."""
    st, sx, sy, _ = seed
    if t < st:
        return None
    gone = 1 - pets.ease((t - (starts(intro, step)[2] + step - RING_GONE_BEFORE)) / RING_GONE_FADE)
    u = min((t - st) / RING_POP, 1.0)
    done = 1 - pets.ease((t - spread - RING_AFTER_SPREAD) / fade)
    alpha = gone * done * min(u * RING_RISE, 1)
    if not alpha > 0:
        return None
    return {'x': sx, 'y': sy, 'radius': dot * (1 + RING_SWELL * math.sin(math.pi * u) * (1 - u)), 'alpha': alpha}


def crew_fade(t, duration):
    """How much of the crew shows at `t`: all of it until the last CREW_FADE_OUT of the show."""
    return min(max((duration - t) / CREW_FADE_OUT, 0.0), 1.0)


def handoff(t, intro, step):
    """How far the real template has taken over from the finished drawing, 0...1."""
    return pets.ease((t - (intro + STEPS * step)) / HANDOFF)


# --- the fixture ---------------------------------------------------------------------------------------
# Tests/MakingOfTests/Fixtures/reveal-small.json: the inputs (visits, traces, strokes, numbers, seeds and
# label planes, injected so the schedule is judged apart from the code that picks them) and what this
# module computes from them, for Sources/MakingOf to equal bit for bit.

FNV_OFFSET, FNV_PRIME = 0xCBF29CE484222325, 0x100000001B3


def fingerprint(values):
    """FNV-1a (64 bit) over the IEEE bytes of float64 `values`, as a hex string: the whole of a
    field in one comparison, where a lattice of samples says where it went wrong."""
    h = FNV_OFFSET
    for byte in np.ascontiguousarray(values, dtype='<f8').tobytes():
        h = ((h ^ byte) * FNV_PRIME) & 0xFFFFFFFFFFFFFFFF
    return f'{h:016x}'


def label_regions(key):
    """Connected areas of one value (4-connected) in a 2-D integer array: (labels, count)."""
    h, w = key.shape
    labels = np.full((h, w), -1, dtype=np.int32)
    count = 0
    for y0 in range(h):
        for x0 in range(w):
            if labels[y0, x0] >= 0:
                continue
            labels[y0, x0] = count
            todo = [(x0, y0)]
            while todo:
                x, y = todo.pop()
                for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if 0 <= nx < w and 0 <= ny < h and labels[ny, nx] < 0 and key[ny, nx] == key[y, x]:
                        labels[ny, nx] = count
                        todo.append((nx, ny))
            count += 1
    return labels, count


def runs(plane):
    """A 2-D integer array as [value, length] runs, row-major."""
    flat = plane.ravel().tolist()
    out, i = [], 0
    while i < len(flat):
        j = i
        while j < len(flat) and flat[j] == flat[i]:
            j += 1
        out.append([flat[i], j - i])
        i = j
    return out


def read_ppm(path):
    with open(path, 'rb') as f:
        data = f.read()
    m = re.match(rb'P6\s+(\d+)\s+(\d+)\s+255\s', data)
    w, h = int(m.group(1)), int(m.group(2))
    return np.frombuffer(data[m.end():], dtype=np.uint8).reshape(h, w, 3)


def parse_template(svg):
    """The template's lines (point lists) and numbers (x, y, size) at the svg's own scale."""
    text = open(svg, encoding='utf-8').read()
    d = re.search(r'<g id="lines-drawing"[^>]*><path d="([^"]*)"', text).group(1)
    strokes = []
    for part in d.split('M')[1:]:
        nums = [float(v) for v in re.findall(r'-?[\d.]+', part)]
        pts = [[nums[i], nums[i + 1]] for i in range(0, len(nums) - 1, 2)]
        if len(pts) >= 2:
            strokes.append(pts)
    numbers = [[float(x), float(y), float(s)]
               for x, y, s, _ in re.findall(r'<text x="([\d.]+)" y="([\d.]+)" font-size="([\d.]+)">([^<]*)</text>', text)]
    return strokes, numbers


def lattice_samples(plane, every):
    """A plane's values at every `every`th pixel, row by row, for a readable comparison."""
    return plane[::every, ::every].ravel().tolist()


def make_inputs(folder, spec):
    """The schedule's inputs for the small show fixture: its template's lines and numbers, its
    pictures' regions, spots of the crew's, paint seeds, and the visits and walked lines that the crew's
    planner makes of them. JSON-ready; `replay` computes everything from it."""
    pets.configure(spec)
    intro, step = float(spec['timing']['intro']), float(spec['timing']['step'])
    seed = 7
    palette = read_ppm(os.path.join(folder, 'palette.ppm'))
    simplified = read_ppm(os.path.join(folder, 'simplified.ppm'))
    h, w, _ = palette.shape
    shape = (h, w)
    pet_h = round(float(spec['crew']['height']) * min(w, h), 2)
    strokes, numbers = parse_template(os.path.join(folder, 'template.svg'))
    strokes = [[[round(x, 2), round(y, 2)] for x, y in s] for s in strokes]

    def key_of(rgb):
        q = rgb.astype(np.int64)
        return (q[..., 0] << 16) | (q[..., 1] << 8) | q[..., 2]

    paint_keys, paint_flat = np.unique(key_of(palette), return_inverse=True)
    paint_of = paint_flat.reshape(shape).astype(np.int32)
    n_paints = len(paint_keys)
    pal_labels, n_pal = label_regions(key_of(palette))
    paint_of_region = [0] * n_pal                  # a region has one colour, so one paint
    for r, p in zip(pal_labels.ravel().tolist(), paint_of.ravel().tolist()):
        paint_of_region[r] = p
    sim_labels, n_sim = label_regions(key_of(simplified))

    # the crew: three guardians, spots of its own for each step, planned as the show plans them
    s = starts(intro, step)
    m = float(spec['crew']['margin'])

    def spots(k, n, purpose=pets.STREAM_SPOTS):
        rng = pets.stream(seed, purpose, k)
        return [[round(m * w + rng.random() * (1 - 2 * m) * w, 2),
                 round(m * h + pet_h + rng.random() * (h - 8 - m * h - pet_h), 2)] for _ in range(n)]

    # k-means++ is not under test: a seed for most paints, at a random pixel of the paint, dropped in turn
    rng = pets.stream(seed, pets.STREAM_SEEDS, 0)
    seeds = []
    for j, paint in enumerate(rng.permutation(n_paints)):
        if j % 5 == 4:
            continue                                 # these paints get no seed, and follow the crew
        ys_, xs_ = np.nonzero(paint_of == paint)
        c = rng.below(len(xs_))
        seeds.append([round(s[2] + 0.12 + j * min(float(spec['seeds']['dropEvery']), 1.0 / n_paints), 4),
                      float(xs_[c]), float(ys_[c]), int(paint)])
    candidates = [spots(0, 12), spots(1, 12), [[x, y] for _, x, y, _ in seeds], spots(3, 12), [], spots(5, 12)]
    homes = spots(0, 3, pets.STREAM_HOMES)
    planned = pets.plan(pets.quantized({
        'size': [w, h], 'petHeight': pet_h, 'intro': intro, 'step': step, 'seed': seed,
        'pets': [{'id': pid, 'start': homes[i]} for i, pid in enumerate(spec['crew']['pets'])],
        'candidates': candidates, 'strokes': strokes, 'frameHeight': h + 232}))
    return {
        'size': [w, h], 'petHeight': pet_h, 'seed': seed, 'sampling': 18,
        'visits': [[[t, x, y] for t, x, y in v] for v in planned.visits],
        'traces': [{'stroke': n, 'start': t0, 'duration': dur, 'points': [[x, y] for x, y in pts]}
                   for n, t0, dur, pts in planned.traces],
        'strokes': strokes, 'numbers': numbers, 'seeds': seeds, 'paints': n_paints, 'paintOfRegion': paint_of_region,
        'paletteLabels': {'count': n_pal, 'runs': runs(pal_labels)},
        'simplifiedLabels': {'count': n_sim, 'runs': runs(sim_labels)},
    }


def from_runs(rs, shape):
    """`runs` undone."""
    return np.repeat([r[0] for r in rs], [r[1] for r in rs]).astype(np.int32).reshape(shape)


def replay(inputs, spec):
    """Everything this module computes from `make_inputs`' inputs, JSON-ready: what
    Sources/MakingOf must equal exactly."""
    pets.configure(spec)
    intro, step = float(spec['timing']['intro']), float(spec['timing']['step'])
    grid, relax_time, ink_ramp = (float(spec['outlines'][k]) for k in ('grid', 'relax', 'inkRamp'))
    w, h = inputs['size']
    shape = (h, w)
    seed, pet_h, sampling = inputs['seed'], inputs['petHeight'], inputs['sampling']
    visits, strokes, numbers, seeds = inputs['visits'], inputs['strokes'], inputs['numbers'], inputs['seeds']
    pal_labels = from_runs(inputs['paletteLabels']['runs'], shape)
    sim_labels = from_runs(inputs['simplifiedLabels']['runs'], shape)
    n_pal, n_sim = inputs['paletteLabels']['count'], inputs['simplifiedLabels']['count']
    paint_of = np.array(inputs['paintOfRegion'], dtype=np.int32)[pal_labels]
    s = starts(intro, step)

    lattices = [step_lattices(seed, k) for k in range(STEPS)]
    noise = [step_noise(shape, seed, k) for k in range(STEPS)]
    T = [step_arrival(k, visits[k], shape, intro, step, seed) for k in range(STEPS)]
    expected = {
        'lattices': [{'coarse': {'first': c.ravel()[:3].tolist(), 'fingerprint': fingerprint(c)},
                      'fine': {'first': f.ravel()[:3].tolist(), 'fingerprint': fingerprint(f)}} for c, f in lattices],
        'noise': [{'samples': lattice_samples(n, sampling), 'fingerprint': fingerprint(n)} for n in noise],
        'arrival': [{'samples': lattice_samples(t, sampling), 'max': float(t.max()), 'min': float(t.min()),
                     'fingerprint': fingerprint(t)} for t in T],
    }
    paint_times, spread = paint_flow(seeds, paint_of, inputs['paints'], T[2], pal_labels, n_pal, intro, step)
    expected['paints'] = {'first': paint_times[:16].tolist(), 'fingerprint': fingerprint(paint_times),
                          'spread': spread.tolist()}
    expected['merged'] = region_min(T[3], sim_labels, n_sim).tolist()
    expected['lift'] = region_min(T[4], sim_labels, n_sim).tolist()
    clear = region_min(T[5], sim_labels, n_sim)
    expected['clear'] = clear.tolist()

    traces = [(t['stroke'], t['start'], t['duration'], t['points']) for t in inputs['traces']]
    plan = stroke_schedule(strokes, traces, T[INK_STEP], T[TEMPLATE_STEP], intro, step, grid, seed)
    expected['strokes'] = [{
        'walked': p.walked, 't0': p.t0, 'dur': p.dur, 'jagged': len(p.jagged), 'smooth': len(p.smooth),
        'length': float(p.cum[-1]), 'jaggedFingerprint': fingerprint(p.jagged), 'smoothFingerprint': fingerprint(p.smooth),
        'relaxFingerprint': fingerprint(p.relax), 'relaxMin': float(p.relax.min()), 'relaxMax': float(p.relax.max()),
    } for p in plan]
    expected['order'] = sorted(range(len(plan)), key=lambda i: (plan[i].t0, i))
    detail = [next(p.index for p in plan if p.walked), next(p.index for p in plan if not p.walked),
              min(range(len(plan)), key=lambda i: len(plan[i].jagged))]
    expected['strokeDetail'] = [{'index': i, 'jagged': plan[i].jagged.tolist(), 'smooth': plan[i].smooth.tolist(),
                                 'cumulative': plan[i].cum.tolist(), 'relax': plan[i].relax.tolist()} for i in detail]

    def drawn(lines):
        fp = fingerprint(np.concatenate([pts.ravel() for _, pts, _ in lines])) if lines else fingerprint([])
        return [{'stroke': i, 'points': len(pts), 'value': v} for i, pts, v in lines], fp

    times = [s[INK_STEP] - 0.1, s[INK_STEP] + 0.2, s[INK_STEP] + 0.5, s[INK_STEP] + 0.9, s[INK_STEP] + 1.4,
             s[INK_STEP] + 1.75, s[INK_STEP] + 2.2, s[TEMPLATE_STEP] + 0.05, s[TEMPLATE_STEP] + 0.5,
             s[TEMPLATE_STEP] + 1.1, s[TEMPLATE_STEP] + 1.7, s[TEMPLATE_STEP] + 2.45, intro + STEPS * step + 0.5]
    expected['lines'] = []
    for t in times:
        lines, fp = drawn(lines_at(plan, t, intro, step, ink_ramp, relax_time, pet_h))
        expected['lines'].append({'time': t, 'lines': lines, 'fingerprint': fp})
    expected['bounds'] = {'jaggedFingerprint': drawn(relaxed_lines(plan, -math.inf, relax_time))[1],
                          'smoothFingerprint': drawn(relaxed_lines(plan, math.inf, relax_time))[1]}

    nums = [tuple(n) for n in numbers]
    expected['numbers'] = number_times(nums, clear, sim_labels, T[TEMPLATE_STEP],
                                       [tuple(v) for v in visits[TEMPLATE_STEP]], intro, step, pet_h)
    expected['discs'] = {'runs': runs(number_discs(nums, shape))}
    return expected


def fixture(folder, spec_path):
    spec = json.load(open(spec_path, encoding='utf-8'))
    inputs = make_inputs(folder, spec)
    return {
        'about': 'The reveal schedule on the small show fixture: inputs, then what making_of_reveal.py computes '
                 'from them. Regenerate with `making_of_reveal.py --fixture` (see its docstring).',
        'spec': spec, 'inputs': inputs, 'expected': replay(inputs, spec),
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--fixture', metavar='SHOW_SMALL', required=True,
                    help="the small show fixture's folder (palette.ppm, simplified.ppm, template.svg)")
    ap.add_argument('out')
    ap.add_argument('--spec', default=os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'App',
                                                   'PaintByNumber', 'Resources', 'making-of.json'))
    a = ap.parse_args()
    doc = fixture(a.fixture, a.spec)
    with open(a.out, 'w', encoding='utf-8') as f:     # one line per part
        f.write('{\n' + ',\n'.join(f'"{k}":' + json.dumps(v, separators=(',', ':')) for k, v in doc.items()) + '\n}\n')


if __name__ == '__main__':
    main()
