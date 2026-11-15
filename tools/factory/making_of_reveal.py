"""What the making-of show's parts share of their schedule, in float64: the template's lines as
stair steps that relax into their smooth curves (`staircase`, `relaxed_lines`), the earliest time in
each region (`region_min`), the disc of the picture each number owns (`number_discs`), and when the
cards, the seed rings and the real template come and go.

This is the reference for Sources/MakingOf (Outlines, Arrival.regionMinimum, Timeline), which ports
it line by line; making_of_fields.py builds the show on it. Geometry is float64 throughout and uses
only + - * / and sqrt, so Swift and Python agree bit for bit; lines are polylines with an ink value,
never pixels. The crew show's own schedule (its arrival fields and their noise, the paints' flow from
them, the lines it drew by walking, the numbers' times) left with its fixture (painting-company row
110).

The numbers every function shares are named below, in one block; Sources/MakingOf's
ScheduleStyle holds the same ones (in camelCase), and the tests check they agree (the numbers' discs
are making_of_clip.py's alone: the app draws each number itself).
"""

import math
import os
import sys
from collections import namedtuple

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import making_of_pets as pets  # noqa: E402

# --- the schedule's constants (ScheduleStyle in Swift) -------------------------------------------------

REFERENCE_STEP = 1.5      # s: the step the cards' fade was tuned at; pace = REFERENCE_STEP / step
STAIRCASE_SPACING = 1.5   # px between the samples of a line before they are snapped to the grid
INK_GREY = 0.45           # ink value a burning line starts at; it darkens to full ink over `inkRamp`
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
HANDOFF = 0.15            # s: the finished drawing hands over to the real template over this long

STEPS = 6
INK_STEP = 4              # the step whose lines are drawn
TEMPLATE_STEP = 5

Stroke = namedtuple('Stroke', 'index t0 dur jagged smooth relax')


def starts(intro, step):
    """When each step begins."""
    return [intro + k * step for k in range(STEPS)]


def smoothstep(x):
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3 - 2 * x)


# --- regions -------------------------------------------------------------------------------------------

def pixel_grid(shape):
    """Every pixel's x and y as float64, by the pixel's index (not its centre)."""
    h, w = shape
    ys, xs = np.mgrid[0:h, 0:w]
    return xs.astype(np.float64), ys.astype(np.float64)


def region_min(T, labels, count):
    """The earliest time in each of `count` regions (inf for an empty one)."""
    m = np.full(count, np.inf)
    np.minimum.at(m, labels.ravel(), T.ravel())
    return m


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


def relaxed_lines(plan, t, relax_time):
    """The template step's lines at time t: every point relaxed from its stair-stepped place
    toward the smooth curve as far as the ripple has reached it (each Stroke's `relax`), in full ink.
    t = inf is the finished template. [(stroke index, points, 1.0)]."""
    out = []
    for s in plan:
        m = smoothstep((t - s.relax) / relax_time)[:, None]
        out.append((s.index, s.jagged * (1 - m) + s.smooth * m, 1.0))      # exactly each end at 0 and 1
    return out


# --- numbers -------------------------------------------------------------------------------------------

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
# When the cards, the seed rings and the real template come and go (Sources/MakingOf's
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


def handoff(t, intro, step):
    """How far the real template has taken over from the finished drawing, 0...1."""
    return pets.ease((t - (intro + STEPS * step)) / HANDOFF)


# --- fingerprints --------------------------------------------------------------------------------------

FNV_OFFSET, FNV_PRIME = 0xCBF29CE484222325, 0x100000001B3


def fingerprint(values):
    """FNV-1a (64 bit) over the IEEE bytes of float64 `values`, as a hex string: the whole of a
    field in one comparison, where a lattice of samples says where it went wrong."""
    h = FNV_OFFSET
    for byte in np.ascontiguousarray(values, dtype='<f8').tobytes():
        h = ((h ^ byte) * FNV_PRIME) & 0xFFFFFFFFFFFFFFFF
    return f'{h:016x}'
