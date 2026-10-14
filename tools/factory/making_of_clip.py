#!/usr/bin/env python3
"""A rough render of the making-of show, for judging its rhythm: the real layers
(making_of_layers.py), each step revealed where the crew works, the cards, and the crew as dots.

Usage:
  making_of_clip.py <generate-out> <snapshots> <out.mp4> [--width 1024] [--fps 60] [--crew 12]
                    [--step SECONDS] [--stop-every SECONDS] [--pets RESOURCES] [--stills DIR]

--pets draws the Lamp's pets (making_of_pets.py) from the app's Resources folder instead of dots.

Timeline: the photo alone for INTRO seconds, six steps of STEP seconds, then the template held
for OUTRO. In each step every worker makes VISITS stops (one per --stop-every seconds); the
step's change spreads from those stops, so it always grows from where somebody is working, at a
pace that fills the step:

  1 sketch             graphite drawn over the photo outward from each stop, strong edges first,
                       then the photo washes to paper behind it
  2 shading            a soft-edged bloom outward from each stop
  3 paints, 4 merged   whole regions (connected areas of one paint) pop in as the bloom reaches them
  5 ink                each of the template's strokes is drawn along its path from the stop nearest
                       its start, while the grey lifts halfway to the paper
  6 template           regions clear to paper as the bloom reaches them; each number appears with
                       its region

--stills DIR also writes a frame every quarter second, for contact sheets. Needs numpy, Pillow,
ffmpeg, the Charter Type 1 fonts (xfonts-scalable) and making_of_layers.py's node setup.
"""

import argparse
import math
import os
import re
import subprocess
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from making_of_layers import INK, PAPER, Sources, ink, sketch, wash  # noqa: E402
import making_of_pets  # noqa: E402

INTRO, OUTRO = 0.4, 1.6
STEP = 1.5      # --step
VISITS = 3      # one stop per half second of step
CARD_BAND = 232
FONT_DIR = '/usr/share/fonts/X11/Type1'
CHARTER = os.path.join(FONT_DIR, 'c0648bt_.pfb')
CHARTER_ITALIC = os.path.join(FONT_DIR, 'c0649bt_.pfb')

STEPS = [
    ('Sketch', [('Li Xu, Qiong Yan, Yang Xia and Jiaya Jia', '2012',
                 'Structure Extraction from Texture via Relative Total Variation')]),
    ('Shading', [('Eduardo Gastal and Manuel Oliveira', '2011',
                  'Domain Transform for Edge-Aware Image and Video Processing')]),
    ('Paints', [('David Arthur and Sergei Vassilvitskii', '2007',
                 'k-means++: The Advantages of Careful Seeding')]),
    ('Merged', [('Pedro Felzenszwalb and Daniel Huttenlocher', '2012',
                 'Distance Transforms of Sampled Functions')]),
    ('Ink', [('Saining Xie and Zhuowen Tu', '2015', 'Holistically-Nested Edge Detection'),
             ('Caroline Chan, Frédo Durand and Phillip Isola', '2022',
              'Learning to generate line drawings that convey geometry and semantics')]),
    ('Template', [('Peter Selinger', '2003', 'Potrace: a polygon-based tracing algorithm')]),
]
# The pets' colors, roughly: the dots stand in for them until the sprites go in.
CREW_COLORS = ['#C98A3B', '#2E9C8F', '#7FA7D9', '#8C5A3C', '#5B6B3A', '#C2553F', '#3F8FB8', '#9C3B5E',
               '#B23A3A', '#6C5A8E', '#D2A23A', '#4E7A4E', '#A0603A', '#3A6E8C', '#C77AA0', '#7A7A3A',
               '#5A5A7A', '#B86A4A', '#3A9A6A', '#8A6A9A']


def ink_line(pen, pts, value, width):
    """Draws a polyline at `value` onto `pen`, keeping whatever is darker there already."""
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    x0, y0 = max(int(min(xs)) - width, 0), max(int(min(ys)) - width, 0)
    x1, y1 = min(int(max(xs)) + width + 1, pen.width), min(int(max(ys)) + width + 1, pen.height)
    if x0 >= x1 or y0 >= y1:
        return
    tmp = Image.new('L', (x1 - x0, y1 - y0), 0)
    ImageDraw.Draw(tmp).line([(x - x0, y - y0) for x, y in pts], fill=value, width=width, joint='curve')
    pen.paste(ImageChops.lighter(pen.crop((x0, y0, x1, y1)), tmp), (x0, y0))


def smoothstep(x):
    x = np.clip(x, 0, 1)
    return x * x * (3 - 2 * x)


def ease(x):
    x = min(max(x, 0.0), 1.0)
    return x * x * (3 - 2 * x)


def label_regions(rgb):
    """Connected areas of one color (4-connected), by runs and union-find: (labels, count)."""
    q = (np.clip(rgb, 0, 1) * 255 + 0.5).astype(np.int64)
    key = (q[..., 0] << 16) | (q[..., 1] << 8) | q[..., 2]
    h, w = key.shape
    parent = []

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    rows = []
    for y in range(h):
        row = key[y]
        cuts = np.flatnonzero(row[1:] != row[:-1]) + 1
        starts = np.concatenate(([0], cuts))
        ends = np.concatenate((cuts, [w]))
        ids = list(range(len(parent), len(parent) + len(starts)))
        parent.extend(ids)
        rows.append((starts, ends, row[starts], ids))
        if y:
            ps, pe, pv, pid = rows[y - 1]
            i = j = 0
            while i < len(starts) and j < len(ps):
                if starts[i] < pe[j] and ps[j] < ends[i] and row[starts[i]] == pv[j]:
                    a, b = find(ids[i]), find(pid[j])
                    if a != b:
                        parent[max(a, b)] = min(a, b)
                if ends[i] < pe[j]:
                    i += 1
                else:
                    j += 1
    roots = {}
    labels = np.empty((h, w), dtype=np.int32)
    for y, (starts, ends, _, ids) in enumerate(rows):
        lab = [roots.setdefault(find(r), len(roots)) for r in ids]
        labels[y] = np.repeat(lab, ends - starts)
    return labels, len(roots)


def value_noise(shape, cells, rng):
    h, w = shape
    g = rng.random((cells[1] + 1, cells[0] + 1)).astype(np.float32)
    ys = np.linspace(0, cells[1], h, endpoint=False)
    xs = np.linspace(0, cells[0], w, endpoint=False)
    y0, x0 = ys.astype(int), xs.astype(int)
    fy, fx = smoothstep(ys - y0)[:, None], smoothstep(xs - x0)[None, :]
    a, b = g[y0][:, x0], g[y0][:, x0 + 1]
    c, d = g[y0 + 1][:, x0], g[y0 + 1][:, x0 + 1]
    return (a + (b - a) * fx) * (1 - fy) + (c + (d - c) * fx) * fy


def parse_template(svg, scale):
    """The template's strokes (polylines) and numbers (x, y, size, text), in picture pixels."""
    text = open(svg, encoding='utf-8').read()
    d = re.search(r'<g id="lines-drawing"[^>]*><path d="([^"]*)"', text).group(1)
    strokes = []
    for part in d.split('M')[1:]:
        nums = [float(v) for v in re.findall(r'-?[\d.]+', part)]
        pts = [(nums[i] * scale, nums[i + 1] * scale) for i in range(0, len(nums) - 1, 2)]
        if len(pts) >= 2:
            strokes.append(np.array(pts, dtype=np.float32))
    numbers = [(float(x) * scale, float(y) * scale, float(s) * scale, t)
               for x, y, s, t in re.findall(r'<text x="([\d.]+)" y="([\d.]+)" font-size="([\d.]+)">([^<]*)</text>', text)]
    return strokes, numbers


def sample_stops(weight, n, rng, spacing):
    """`n` stops drawn by `weight`, no two closer than `spacing` (relaxed if it can't be met)."""
    h, w = weight.shape
    p = weight.ravel().astype(np.float64)
    p = p / p.sum()
    picks = []
    for _ in range(40):
        cand = rng.choice(p.size, size=n * 30, p=p)
        picks = []
        for c in cand:
            y, x = divmod(int(c), w)
            if all((x - a) ** 2 + (y - b) ** 2 >= spacing ** 2 for a, b in picks):
                picks.append((x, y))
                if len(picks) == n:
                    return picks
        spacing *= 0.85
    return picks


class Crew:
    """Each worker's stops: (arrive, leave, x, y, step), in time order across the show; the first
    is where it starts, along the bottom of the picture (`inside`) or just below it."""

    def __init__(self, n, size, rng, inside=False):
        w, h = size
        y = h - 10 if inside else h + 40
        self.stops = [[(0.0, INTRO * 0.6, w * (i + 0.5) / n + rng.uniform(-20, 20), y, 0)] for i in range(n)]
        self.rng = rng

    def plan_step(self, t0, points, step=0):
        """Hands `points` out in VISITS rounds, each round to the nearest free worker; returns
        the visits as (time, x, y)."""
        n = len(self.stops)
        visits = []
        pool = list(points)
        for j in range(VISITS):
            order = self.rng.permutation(n)
            for i in order:
                if not pool:
                    break
                _, leave, x, y, _ = self.stops[i][-1]
                k = min(range(len(pool)), key=lambda q: (pool[q][0] - x) ** 2 + (pool[q][1] - y) ** 2)
                px, py = pool.pop(k)
                gap = (STEP - 0.3) / VISITS
                arrive = t0 + 0.10 + j * gap + self.rng.uniform(-0.12, 0.12) * gap
                arrive = max(arrive, leave + 0.18)
                self.stops[i].append((arrive, arrive + 0.55 * gap, px, py, step))
                visits.append((arrive, px, py))
        return visits

    def positions(self, t):
        out = []
        for s in self.stops:
            if t <= s[0][1]:
                out.append((s[0][2], s[0][3], 0.0))
                continue
            pos = None
            for (a0, l0, x0, y0, _), (a1, l1, x1, y1, _) in zip(s, s[1:]):
                if t < a1:
                    u = ease((t - l0) / max(a1 - l0, 1e-3)) if t > l0 else 0.0
                    pos = (x0 + (x1 - x0) * u, y0 + (y1 - y0) * u, 1.0 if l0 < t < a1 else 0.0)
                    break
                if t <= l1:
                    pos = (x1, y1, 0.0)
                    break
            out.append(pos or (s[-1][2], s[-1][3], 0.0))
        return out


def arrival(visits, shape, speed, t_end, noise):
    """When the change reaches each pixel: the earliest visit plus its distance over `speed`,
    roughened by `noise`, never after `t_end`."""
    h, w = shape
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    T = np.full(shape, np.inf, dtype=np.float32)
    for t, x, y in visits:
        np.minimum(T, t + np.hypot(xs - x, ys - y) / speed, out=T)
    T += noise
    t_start = min(v[0] for v in visits)
    hi = T.max()
    if hi > t_end:
        T = t_start + (T - t_start) * (t_end - t_start) / (hi - t_start)
    return T


def region_min(T, labels, count):
    m = np.full(count, np.inf, dtype=np.float32)
    np.minimum.at(m, labels.ravel(), T.ravel())
    return m[labels]


class Cards:
    def __init__(self, width):
        self.width = width
        self.cache = {}

    def image(self, k):
        if k in self.cache:
            return self.cache[k]
        w = self.width
        img = Image.new('L', (w, CARD_BAND), 0)
        d = ImageDraw.Draw(img)
        caps = ImageFont.truetype(CHARTER, 21)
        title = ImageFont.truetype(CHARTER_ITALIC, 30)
        y = 30
        for authors, year, ttl in STEPS[k][1]:
            line = f'{authors.upper()} · {year}'
            d.text(((w - d.textlength(line, font=caps)) / 2, y), line, font=caps, fill=255)
            y += 32
            words, lines, cur = ttl.split(), [], ''
            for word in words:
                trial = (cur + ' ' + word).strip()
                if d.textlength(trial, font=title) > w * 0.84 and cur:
                    lines.append(cur)
                    cur = word
                else:
                    cur = trial
            lines.append(cur)
            for ln in lines:
                d.text(((w - d.textlength(ln, font=title)) / 2, y), ln, font=title, fill=255)
                y += 38
            y += 18
        a = np.asarray(img, dtype=np.float32) / 255
        self.cache[k] = a
        return a


def motion_report(pets, total, size, h, out):
    """How the pets move, by numbers and by eye: per pet its fastest speed and hardest
    acceleration (in its heights per second), and a spacing chart, its feet every 1/30 s, darker
    later; even spacing is steady speed, bunching is slowing down."""
    os.makedirs(out, exist_ok=True)
    dt = 1 / 120
    lines = []
    for n, p in enumerate(pets):
        xs, ys, lifts = [], [], []
        for i in range(int(total / dt)):
            st = p.state(i * dt)
            xs.append(st[0])
            ys.append(st[1])
            lifts.append(st[2])
        xs, ys, lifts = np.array(xs), np.array(ys), np.array(lifts)
        v = np.hypot(np.diff(xs), np.diff(ys)) / dt / h
        acc = np.abs(np.diff(v)) / dt
        lift_v = np.abs(np.diff(lifts)) / dt / h
        jobs = len(p.stops) - 1
        moving = v > 0.2
        lines.append(f'{n:2d} jobs {jobs:2d}  ground: top {v.max():4.2f} h/s, mean moving {v[moving].mean() if moving.any() else 0:4.2f},'
                     f' moving {moving.mean() * 100:3.0f}% of the time, hardest accel {np.percentile(acc, 99.5):5.1f} h/s2'
                     f'  lift: top {lifts.max() / h:4.2f} h, fastest {lift_v.max():4.2f} h/s')
        ys = ys - lifts
        if n < 4:
            img = Image.new('RGB', size, (247, 244, 238))
            d = ImageDraw.Draw(img)
            for i in range(0, len(xs), 4):
                c = int(200 * (1 - i / len(xs)))
                d.ellipse((xs[i] - 2, ys[i] - 2, xs[i] + 2, ys[i] + 2), fill=(c, c, c))
            img.save(os.path.join(out, f'spacing-{n}.png'))
    for n, p in enumerate(pets[:2]):
        for sgm, stop in zip(p.segments, p.stops[1:]):
            lines.append(f'pet {n} walks {sgm["leave"]:.2f}-{sgm["arrive"]:.2f} s, {sgm["d"] / h:.1f} h, to ({stop[2]:.0f}, {stop[3]:.0f}), step {stop[4]}'
                         + (' and draws a line' if stop[5] is not None else ''))
    for k in range(6):
        xs = [st[2] for p in pets for st in p.stops if st[4] == k]
        if xs:
            third = [sum(1 for x in xs if j * size[0] / 3 <= x < (j + 1) * size[0] / 3) for j in range(3)]
            lines.append(f'step {k + 1}: {len(xs)} jobs, left/middle/right thirds {third[0]}/{third[1]}/{third[2]}')
    # crowding: how often two pets' boxes (0.7 h wide, h tall) overlap, standing or walking
    frames, touching, worst = 0, 0, 0
    for i in range(0, int(total * 30)):
        t = i / 30
        boxes = []
        for p in pets:
            st = p.state(t)
            if st[8] > 0.5:
                boxes.append((st[0] - 0.35 * h, st[1] - st[2] - h, st[0] + 0.35 * h, st[1] - st[2]))
        n = sum(1 for a_ in range(len(boxes)) for b_ in range(a_ + 1, len(boxes))
                if boxes[a_][0] < boxes[b_][2] and boxes[b_][0] < boxes[a_][2] and boxes[a_][1] < boxes[b_][3] and boxes[b_][1] < boxes[a_][3])
        frames += 1
        touching += n > 0
        worst = max(worst, n)
    lines.append(f'pets overlapping in {touching / frames * 100:.0f}% of frames, at most {worst} pairs at once')
    traces = sum(1 for p in pets for st in p.stops if st[5] is not None)
    lines.append(f'lines drawn by walking: {traces}; out of the frame by {min(p.stops[-1][0] for p in pets):.2f}-{max(p.stops[-1][0] for p in pets):.2f} s')
    open(os.path.join(out, 'motion.txt'), 'w').write('\n'.join(lines) + '\n')
    print('\n'.join(lines))


def main():
    global STEP, VISITS, INTRO, OUTRO
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('generated')
    ap.add_argument('snapshots')
    ap.add_argument('out')
    ap.add_argument('--width', type=int, default=1024)
    ap.add_argument('--fps', type=int, default=60)
    ap.add_argument('--crew', type=int, default=12)
    ap.add_argument('--seed', type=int, default=7)
    ap.add_argument('--stills')
    ap.add_argument('--step', type=float, default=STEP)
    ap.add_argument('--stop-every', type=float, default=0.5)
    ap.add_argument('--pets')
    ap.add_argument('--motion', help='write a motion report and spacing charts of the pets to this folder, and stop')
    a = ap.parse_args()
    STEP, VISITS = a.step, max(2, round(a.step / a.stop_every))
    if a.pets:
        INTRO = 0.6         # the pets pop in first
        OUTRO = 2.4         # wave, walk out, and leave the template a moment to itself
    pace = 1.5 / STEP          # the constants below were set for 1.5 s steps
    rng = np.random.default_rng(a.seed)

    src = Sources(a.generated, a.snapshots, a.width)
    W, H = src.size
    layers = src.layers()
    paper = src.paper
    starts = [INTRO + k * STEP for k in range(6)]
    total = INTRO + 6 * STEP + OUTRO

    # what each step's stops are drawn toward
    vb = float(re.search(r'viewBox="0 0 ([\d.]+)', open(src.svg).read()).group(1))
    strokes, numbers = parse_template(src.svg, W / vb)
    pal_labels, pal_n = label_regions(src.palette)
    sim_labels, sim_n = label_regions(src.simplified)
    area = lambda labels, n: np.bincount(labels.ravel(), minlength=n)[labels].astype(np.float32)
    stroke_w = np.zeros((H, W), dtype=np.float32)
    for s in strokes:
        x, y = int(min(max(s[0][0], 0), W - 1)), int(min(max(s[0][1], 0), H - 1))
        stroke_w[y, x] += float(np.hypot(*np.diff(s, axis=0).T).sum())
    num_w = np.zeros((H, W), dtype=np.float32)
    for x, y, _, _ in numbers:
        num_w[int(min(max(y, 0), H - 1)), int(min(max(x, 0), W - 1))] += 1
    weights = [
        src.structure + 0.35,           # edges first, but the whole picture gets visited
        np.ones((H, W), dtype=np.float32),
        np.sqrt(area(pal_labels, pal_n)) / area(pal_labels, pal_n),
        np.sqrt(area(sim_labels, sim_n)) / area(sim_labels, sim_n),
        stroke_w + 1e-6 * stroke_w.max(),
        num_w + 1e-6,
    ]
    crew = Crew(a.crew, (W, H), rng)
    pet_h = 0.12 * H
    if a.pets:
        # a pet's spot keeps all of it in the picture: half a pet from the sides, a pet from the top
        room = np.zeros((H, W), dtype=np.float32)
        room[int(pet_h) + 4:H - 8, int(0.05 * W):W - int(0.05 * W)] = 1
        weights = [w * room for w in weights]
    n_stops = a.crew * VISITS
    end = INTRO + 6 * STEP
    pets, traces, seeds_by_step = [], [], []
    if a.pets:
        ids = making_of_pets.ORDER[:a.crew]
        sprites = making_of_pets.load(a.pets, ids)
        pet_rng = np.random.default_rng(a.seed + 1)
        order = pet_rng.permutation(len(ids))
        wave = pet_rng.permutation(len(ids))
        # they pop in all over the picture, so the first step starts everywhere at once
        homes = sample_stops(weights[0], len(ids), rng, spacing=0.2 * W)
        for i, pid in enumerate(ids):
            x, y = homes[i % len(homes)]
            appear = 0.04 + 0.035 * order[i]
            start = (appear, appear + 0.05, x, y, -1, None)
            pets.append(making_of_pets.Pet(sprites[pid], start, pet_h, pet_rng, appear,
                                           end + 0.15 + 0.06 * wave[i], [s0 + STEP for s0 in starts]))
        planner = making_of_pets.Planner(pets, (W, H), pet_h, pet_rng, STEP / 4, INTRO)
    T = []
    for k in range(6):
        if pets:
            if k == 4:
                visits, traces = planner.trace(starts[k], starts[k] + STEP - 0.15, strokes, k)
            else:
                pts = sample_stops(weights[k], a.crew * 4, rng, spacing=0.1 * W)
                visits = planner.step(starts[k], starts[k] + STEP - 0.15, pts, k)
            if not visits:
                visits = [(starts[k] + 0.1, W / 2, H / 2)]
        else:
            pts = sample_stops(weights[k], n_stops, rng, spacing=0.09 * W)
            visits = crew.plan_step(starts[k], pts, k)
        seeds_by_step.append(visits)
        noise = 0.10 * value_noise((H, W), (18, 12), rng) + 0.06 * value_noise((H, W), (60, 40), rng)
        T.append(arrival(visits, (H, W), speed=0.55 * W * pace, t_end=starts[k] + STEP - 0.2, noise=noise))
    if pets:
        planner.farewell([end - 0.05 + 0.03 * w for w in wave], H + CARD_BAND)
    T_pal = region_min(T[2], pal_labels, pal_n)
    T_sim = region_min(T[3], sim_labels, sim_n)
    T_clear = region_min(T[5], sim_labels, sim_n)
    # steps 3 and 4 settle with a small overshoot, darker then back, where the picture changes
    settle = {k: np.clip(np.abs(layers[k + 1] - layers[k]).max(axis=2) * 12, 0, 1)[..., None] for k in (2, 3)}

    # step 5: the lines the pets walk are drawn under their feet; the rest follow from where they
    # are, at a calmer pace, each darkening from grey to ink as it goes down
    t5_end = starts[4] + STEP - 0.12
    traced_by = {n: (t0, dur, pts) for n, t0, dur, pts in traces}
    stroke_plan = []
    for n, s in enumerate(strokes):
        if n in traced_by:
            t0, dur, pts = traced_by[n]
            pts = np.asarray(pts, dtype=np.float32)
            cum = np.concatenate(([0], np.cumsum(np.hypot(*np.diff(pts, axis=0).T))))
            stroke_plan.append((t0, dur, pts, cum, True))
            continue
        x, y = int(min(max(s[0][0], 0), W - 1)), int(min(max(s[0][1], 0), H - 1))
        cum = np.concatenate(([0], np.cumsum(np.hypot(*np.diff(s, axis=0).T))))
        t0 = max(float(T[4][y, x]) + rng.uniform(0, 0.5), starts[4] + (0.3 if pets else 0.0))
        dur = min(max(cum[-1] / (0.45 * W * pace), 0.25), 0.9 / pace)
        if t0 + dur > t5_end:
            t0 = max(starts[4], t5_end - dur)
        stroke_plan.append((t0, dur, s, cum, False))
    pen = Image.new('L', (W * 2, H * 2), 0)
    INK_RAMP = 0.35                  # s for a stroke to darken from grey to ink
    lines_mult = ink(src.lines)
    lift_from, lift_to = wash(src.simplified, 0.45), wash(src.simplified, 0.22)
    # step 6: numbers, each with its region
    template = src.template
    numbers_mult = np.where(src.lines[..., None] > 0.85, template, 1.0)
    num_T = []
    for x, y, _, _ in numbers:
        clear_at = float(T_clear[int(min(max(y, 0), H - 1)), int(min(max(x, 0), W - 1))])
        near = [t for t, sx, sy in seeds_by_step[5] if math.hypot(sx - x, sy - y) < 1.6 * pet_h]
        # a number next to a working pet goes down a moment after it does; the rest come quietly later
        at = min(near) + 0.3 if pets and near else max(clear_at, starts[5] + (0.55 * STEP if pets else 0))
        num_T.append(min(max(at, clear_at + 0.05), end - 0.15))
    num_T = np.array(num_T)
    ys, xs = np.mgrid[0:H, 0:W].astype(np.float32)
    num_idx = np.full((H, W), -1, dtype=np.int32)
    for i, (x, y, sz, _) in enumerate(numbers):
        r = max(sz * 0.9, 4)
        x0, x1, y0, y1 = int(max(x - r, 0)), int(min(x + r + 1, W)), int(max(y - r, 0)), int(min(y + r + 1, H))
        if x0 >= x1 or y0 >= y1:
            continue
        box = (xs[y0:y1, x0:x1] - x) ** 2 + (ys[y0:y1, x0:x1] - y) ** 2 <= r * r
        num_idx[y0:y1, x0:x1][box] = i
    num_T_px = np.where(num_idx >= 0, num_T[np.maximum(num_idx, 0)], np.inf).astype(np.float32)

    for p in pets:
        p.finish()
    if a.motion:
        motion_report(pets, total, (W, H), pet_h, a.motion)
        return
    cards = Cards(W)
    frame_h = H + CARD_BAND
    frame_h += frame_h % 2
    ink_rgb = INK
    cmd = ['ffmpeg', '-y', '-loglevel', 'error', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{W}x{frame_h}',
           '-r', str(a.fps), '-i', '-', '-c:v', 'libx264', '-preset', 'medium', '-crf', '18', '-pix_fmt', 'yuv420p',
           '-movflags', '+faststart', a.out]
    enc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    if a.stills:
        os.makedirs(a.stills, exist_ok=True)
    frames = int(round(total * a.fps))
    for f in range(frames):
        t = f / a.fps
        k = int((t - INTRO) // STEP) if t >= INTRO else -1
        if k < 0:
            pic = layers[0]
        elif k == 0:
            drawn = smoothstep((t - (T[0] - 0.3 * src.structure)) / 0.14)[..., None]
            # the wash follows the graphite, but is done before the step ends
            washed = smoothstep((t - np.minimum(T[0] + 0.12, starts[0] + STEP - 0.35)) / 0.3)[..., None]
            graphite = sketch(src.structure, 1.0)
            pic = (layers[0] + (paper - layers[0]) * washed) * (1 - drawn * (1 - graphite))
        elif k <= 3:
            Tk = [T[0], T[1], T_pal, T_sim][k]
            soft = 0.16 if k < 2 else 0.09
            m = smoothstep((t - Tk) / soft)[..., None]
            pic = layers[k] + (layers[k + 1] - layers[k]) * m
            if k in settle:
                bump = np.sin(np.pi * np.clip((t - Tk) / 0.22, 0, 1))[..., None]
                pic = pic * (1 - 0.1 * bump * settle[k])
        elif k == 4:
            for t0, dur, s, cum, walked in stroke_plan:
                if t < t0 or t > t0 + dur + INK_RAMP + 1 / a.fps:
                    continue
                if walked:
                    a1 = making_of_pets.traced(t - t0, float(cum[-1]), pet_h)
                else:
                    a1 = ease((t - t0) / dur) * cum[-1]
                if a1 <= 0:
                    continue
                pts = [tuple(p) for p, c in zip(s, cum) if c < a1]
                pts.append(tuple(np.interp(a1, cum, s[:, c]) for c in (0, 1)))
                if len(pts) < 2:
                    continue
                value = int(255 * (0.45 + 0.55 * min(max((t - t0) / (dur + INK_RAMP), 0), 1)))
                ink_line(pen, [(x * 2, y * 2) for x, y in pts], value, 9)
            pm = np.asarray(pen.reduce(2), dtype=np.float32)[..., None] / 255
            lift = smoothstep((t - T[4]) / 0.16)[..., None]
            pic = paper * (lift_from + (lift_to - lift_from) * lift) * (1 - pm * (1 - lines_mult))
        else:
            if k == 5 and t < INTRO + 6 * STEP:
                clear = smoothstep((t - T_clear) / 0.12)[..., None]
                nm = smoothstep((t - num_T_px) / 0.1)[..., None]
                pic = paper * (lift_to + (1 - lift_to) * clear) * lines_mult * (1 - nm * (1 - numbers_mult))
            else:
                last = paper * lines_mult * numbers_mult
                u = smoothstep((t - INTRO - 6 * STEP) / 0.15)
                pic = last + (layers[6] - last) * u

        frame = np.empty((frame_h, W, 3), dtype=np.float32)
        frame[:H] = pic
        frame[H:] = PAPER
        if 0 <= k < 6:
            ls = t - starts[k]
            fade = 0.15 / pace ** 0.5
            alpha = float(smoothstep(np.array(ls / fade)) * (1 - smoothstep(np.array((ls - (STEP - fade)) / fade))))
            if alpha > 0:
                c = cards.image(k)[..., None] * (0.62 * alpha)
                frame[H:H + CARD_BAND] = frame[H:H + CARD_BAND] * (1 - c) + ink_rgb * c
        img = Image.fromarray((np.clip(frame, 0, 1) * 255 + 0.5).astype(np.uint8))
        draw = ImageDraw.Draw(img, 'RGBA')
        if pets:
            # they dim only as the painting screen arrives, never while waving
            fade = 1.0 if t < total - 0.3 else max(0.0, (total - t) / 0.3)
            if fade > 0:
                canvas = img.convert('RGBA')
                for pet in sorted(pets, key=lambda p: p.state(t)[1]):
                    pet.draw(canvas, t, fade, H)
                img = canvas.convert('RGB')
        elif t < INTRO + 6 * STEP + OUTRO - 0.3:
            fade = 1.0 if t < INTRO + 6 * STEP else max(0.0, 1 - (t - INTRO - 6 * STEP) / 0.5)
            for i, (x, y, moving) in enumerate(crew.positions(t)):
                if y > H + 12:
                    continue
                col = CREW_COLORS[i % len(CREW_COLORS)]
                r = 9 if moving else 10.5
                al = int(255 * fade)
                draw.ellipse((x - r * 1.1, y - r * 0.35 + r, x + r * 1.1, y + r * 0.35 + r), fill=(52, 42, 48, int(50 * fade)))
                draw.ellipse((x - r - 2.5, y - r - 2.5, x + r + 2.5, y + r + 2.5), fill=(255, 255, 255, al))
                cr, cg, cb = (int(col[i2:i2 + 2], 16) for i2 in (1, 3, 5))
                draw.ellipse((x - r, y - r, x + r, y + r), fill=(cr, cg, cb, al))
        enc.stdin.write(img.tobytes())
        if a.stills and f % max(1, a.fps // 4) == 0:
            img.save(os.path.join(a.stills, f'{t:05.2f}.jpg'), quality=85)
    enc.stdin.close()
    if enc.wait():
        sys.exit('ffmpeg failed')


if __name__ == '__main__':
    main()
