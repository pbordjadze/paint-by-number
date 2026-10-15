#!/usr/bin/env python3
"""A rough render of the making-of show, for judging its rhythm: the real layers
(making_of_layers.py), each step revealed where the crew works, the cards, and the Lamp's pets
(making_of_pets.py) as the crew.

Usage:
  making_of_clip.py <generate-out> <snapshots> <out.mp4> [--width PX] [--fps 60] [--crew N]
                    [--step SECONDS] [--pets RESOURCES] [--spec JSON] [--seed 7]
                    [--stills DIR] [--pet-height SHARE] [--motion DIR] [--plan-json PATH]

--pets is the folder of the pets' sheets, by default the app's Resources. The show's spec (--spec,
default App/PaintByNumber/Resources/making-of.json) sets the timing, each step's card (its caption,
with its methods' credit lines from ACKNOWLEDGEMENTS.md as a footnote, printed letter for letter)
and the crew's motion; --step, --crew (the first N pets of its order) and --pet-height override it.
Where the crew works, where it pops in and the seeds step 3 drops are chosen by making_of_inputs.py
from --seed, exactly as Sources/MakingOf does it; the noise that roughens each step's reveal and
the stroke start jitters still draw from numpy's generator, seeded by --seed.
--motion DIR writes a motion report of the pets and stops. --plan-json PATH writes the crew's plan
and stops: {"spec", "inputs", "plan", "states"}, the inputs rounded to 0.01 px and 0.0001 s before
the plan is made from them, and every pet's state at 30 per second. That file is
Sources/MakingOf's test fixture (Tests/MakingOfTests/Fixtures/plan-parrots.json); regenerate it,
after changing making_of_pets.py, making_of_inputs.py or the spec, with the generated parrots as in
the header of Sources/MakingOf/MakingOf.swift.

Timeline: the photo alone for INTRO seconds, six steps of STEP seconds, then the template held
for OUTRO. In each step the crew's stops are where its change spreads from, so it always grows from
where somebody is working, at a pace that fills the step:

  1 sketch             relative total variation: around each stop the photo's texture smears away
                       first, then graphite goes down on the structure that survives, strongest
                       first, and the photo washes to paper behind it
  2 shading            a soft-edged bloom outward from each stop
  3 paints             k-means++: real seeds (pixels drawn by their squared distance to the seeds so
                       far) drop one by one as dots, and each paint's areas flow out from its seed
  4 merged             whole regions (connected areas of one paint) pop in as the bloom reaches them
  5 ink                the template's lines as stair-stepped pixel outlines, the way Potrace starts,
                       drawn along their paths (pets walk some), while the grey lifts halfway
  6 template           Potrace's fit: the outlines relax into the template's smooth curves, rippling
                       out from the stops; areas clear to paper, and numbers come last

--stills DIR also writes a frame every quarter second, for contact sheets. Needs numpy, Pillow,
ffmpeg, the Charter Type 1 fonts (xfonts-scalable) and making_of_layers.py's node setup.
"""

import argparse
import json
import math
import os
import re
import subprocess
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from making_of_layers import INK, PAPER, Sources, sketch  # noqa: E402
import making_of_exact  # noqa: E402
import making_of_inputs  # noqa: E402
import making_of_pets  # noqa: E402

INTRO, OUTRO = 0.4, 1.6
STEP = 1.5      # --step
CARD_BAND = making_of_inputs.CARD_BAND
FONT_DIR = '/usr/share/fonts/X11/Type1'
CHARTER = os.path.join(FONT_DIR, 'c0648bt_.pfb')
CHARTER_ITALIC = os.path.join(FONT_DIR, 'c0649bt_.pfb')

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RESOURCES = os.path.join(ROOT, 'App', 'PaintByNumber', 'Resources')
SPEC = os.path.join(RESOURCES, 'making-of.json')
STEPS = []          # (id, caption, [(authors, year, title)]) per step, from the spec and Acknowledgements


def credits(names):
    """Each method's credit line as ACKNOWLEDGEMENTS.md prints it: (authors, year, title). A
    card prints exactly this, so a name that isn't credited there stops the render."""
    text = open(os.path.join(ROOT, 'ACKNOWLEDGEMENTS.md'), encoding='utf-8').read()
    out = []
    for name in names:
        # the exact heading (the models have one of their own, "Informative Drawings"), and the
        # credit line inside that section, never past the next heading
        m = re.search(r'^### ' + re.escape(name) + r'\n(?:(?!### ).*\n)*?(.+), "(.+)", (\d{4})$', text, re.M)
        if not m:
            sys.exit(f'{name}: no credit in ACKNOWLEDGEMENTS.md')
        out.append((m.group(1), m.group(3), m.group(2)))
    return out


def load_spec(path):
    """Reads the show's spec and applies it: timing, steps and cards, the crew's motion."""
    global INTRO, OUTRO, STEP, STEPS, GRID
    spec = json.load(open(path, encoding='utf-8'))
    if spec.get('version') != 1 or len(spec['steps']) != 6:
        sys.exit(f'{path}: expected version 1 with six steps')
    INTRO, STEP, OUTRO = (float(spec['timing'][k]) for k in ('intro', 'step', 'outro'))
    STEPS = [(st['id'], st['caption'], credits(st['methods'])) for st in spec['steps']]
    GRID = float(spec['outlines']['grid'])
    making_of_pets.configure(spec)
    return spec


LUMA = np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)


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


GRID = 5    # px: the step of the pixel outlines (coarse enough to see on a phone); the spec's


def staircase(pts, grid):
    """A smooth polyline as the stair-stepped pixel outline it was fitted to, paired point by
    point with the smooth line, so one can relax into the other: (jagged, smooth) arrays."""
    cum = np.concatenate(([0], np.cumsum(np.hypot(*np.diff(pts, axis=0).T))))
    d = np.linspace(0, cum[-1], max(2, int(cum[-1] / 1.5) + 1))
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
    return np.array(J, dtype=np.float32), np.array(S, dtype=np.float32)


def smoothstep(x):
    x = np.clip(x, 0, 1)
    return x * x * (3 - 2 * x)


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
    """Each step's card, after Caroline: what the step does in a few plain words, and under it,
    smaller and fainter like a footnote, the credit line of each paper it stands on."""

    def __init__(self, width, footnote):
        self.width = width
        self.footnote = footnote
        self.cache = {}

    def image(self, k):
        if k in self.cache:
            return self.cache[k]
        w = self.width
        img = Image.new('L', (w, CARD_BAND), 0)
        d = ImageDraw.Draw(img)
        caption = ImageFont.truetype(CHARTER, 31)
        small = ImageFont.truetype(CHARTER, 16)
        small_italic = ImageFont.truetype(CHARTER_ITALIC, 16)
        _, text, cites = STEPS[k]
        marks = ','.join('¹²³'[i] for i in range(len(cites)))
        d.text(((w - d.textlength(text + marks, font=caption)) / 2, 54), text + marks, font=caption, fill=255)
        y = 116
        faint = int(255 * self.footnote)
        for i, (authors, year, title) in enumerate(cites):
            # the credit line letter for letter, the title in italics, wrapped to the card
            runs = [(f'{"¹²³"[i]} {authors} · {year} · ', small)] + [(word + ' ', small_italic) for word in title.split()]
            lines, cur, width_now = [], [], 0.0
            for run, font in runs:
                size = d.textlength(run, font=font)
                if cur and width_now + size > w * 0.9:
                    lines.append(cur)
                    cur, width_now = [], 0.0
                cur.append((run, font))
                width_now += size
            lines.append(cur)
            for line in lines:
                x = (w - sum(d.textlength(r, font=f) for r, f in line)) / 2
                for run, font in line:
                    d.text((x, y), run, font=font, fill=faint)
                    x += d.textlength(run, font=font)
                y += 22
            y += 6
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
        work = slice(0, int(min(st[0] for st in p.stops if st[4] == -4) / dt))   # before the goodbye
        lines.append(f'{n:2d} jobs {jobs:2d}  ground: top {v.max():4.2f} h/s, mean moving {v[moving].mean() if moving.any() else 0:4.2f},'
                     f' moving {moving.mean() * 100:3.0f}% of the time, hardest accel {np.percentile(acc, 99.5):5.1f} h/s2'
                     f'  lift: top {lifts.max() / h:4.2f} h, fastest {lift_v.max():4.2f} h/s'
                     f'  before the goodbye: top {v[work].max():4.2f} h/s, hardest accel {np.percentile(acc[work], 99.5):5.1f} h/s2')
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


def write_plan(path, spec, inputs, planned, total):
    """The plan file: the spec and the inputs the plan was made from, the plan, and every pet's
    state 30 times a second to the show's end."""
    doc = {'spec': spec, 'inputs': inputs, 'plan': making_of_pets.plan_data(planned),
           'states': making_of_pets.states_data(planned.pets, total)}
    with open(path, 'w', encoding='utf-8') as f:     # one line per part
        f.write('{\n' + ',\n'.join(f'"{k}":' + json.dumps(v, separators=(',', ':')) for k, v in doc.items()) + '\n}\n')


def main():
    global STEP, INTRO, OUTRO
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('generated')
    ap.add_argument('snapshots')
    ap.add_argument('out')
    ap.add_argument('--width', type=int, help="the picture's width in px (default the snapshots', whose long side "
                    'the pipeline keeps to 1024: never upscaled)')
    ap.add_argument('--fps', type=int, default=60)
    ap.add_argument('--crew', type=int)
    ap.add_argument('--seed', type=int, default=7)
    ap.add_argument('--stills')
    ap.add_argument('--step', type=float)
    ap.add_argument('--spec', default=SPEC)
    ap.add_argument('--pets', default=RESOURCES)
    ap.add_argument('--pet-height', type=float, help="a pet's height as a share of the picture's shorter side (the spec's crew height)")
    ap.add_argument('--motion', help='write a motion report and spacing charts of the pets to this folder, and stop')
    ap.add_argument('--plan-json', help="write the crew's plan (inputs, plan, states) to this file, and stop")
    a = ap.parse_args()
    spec = load_spec(a.spec)
    if a.step:
        STEP = a.step
        spec['timing']['step'] = a.step
    ids = making_of_pets.ORDER[:a.crew or len(spec['crew']['pets'])]
    pace = 1.5 / STEP          # the constants below were set for 1.5 s steps
    rng = np.random.default_rng(a.seed)

    src = Sources(a.generated, a.snapshots, a.width, spec['sketch'], spec['tones'])
    W, H = src.size
    layers = src.layers()
    paper = src.paper
    starts = [INTRO + k * STEP for k in range(6)]
    total = INTRO + 6 * STEP + OUTRO
    end = INTRO + 6 * STEP

    # where the crew pops in and works, and the seeds step 3 drops, chosen exactly (making_of_inputs.py)
    pictures = making_of_inputs.Pictures(a.snapshots, a.width)
    assert pictures.size == src.size
    drawing = making_of_inputs.Template(src.svg, W)
    built = making_of_inputs.build(pictures, drawing, spec, a.seed, ids, pet_height=a.pet_height)
    strokes, numbers, seeds = built.strokes, built.numbers, built.seeds
    paint_keys, paint_of = built.paint_keys, built.paint_of
    sim_labels, sim_n = built.sim_labels, built.sim_n
    pal_labels, pal_n = making_of_exact.label_regions(making_of_exact.color_keys(pictures.palette))
    pet_h = built.inputs['petHeight']
    planned = making_of_pets.plan(built.inputs)
    if a.plan_json:
        write_plan(a.plan_json, spec, built.inputs, planned, total)
        return
    pets, seeds_by_step, traces = planned.pets, planned.visits, planned.traces
    # the noise each step's change is roughened by, drawn in step order from the picture's random numbers
    noises = [0.10 * value_noise((H, W), (18, 12), rng) + 0.06 * value_noise((H, W), (60, 40), rng) for _ in range(6)]
    T = [arrival(visits, (H, W), speed=0.55 * W * pace, t_end=starts[k] + STEP - 0.2, noise=noise)
         for k, (visits, noise) in enumerate(zip(seeds_by_step, noises))]
    # each paint's areas flow out from its seed; a paint no seed landed on follows the crew
    ys_, xs_ = np.mgrid[0:H, 0:W].astype(np.float32)
    T_seed = np.full((H, W), np.inf, dtype=np.float32)
    for st, sx, sy, paint in seeds:
        mine = paint_of == paint
        T_seed[mine] = np.minimum(T_seed[mine], st + 0.25 + np.hypot(xs_ - sx, ys_ - sy)[mine] / (W / 1.3))
    T_seed = np.where(np.isinf(T_seed), T[2] + 0.3, T_seed)
    lo, hi, cap = starts[2] + 0.2, float(T_seed.max()), starts[2] + STEP - 0.2
    if hi > cap:
        T_seed = lo + (T_seed - lo) * (cap - lo) / (hi - lo)
    T_pal = region_min(T_seed, pal_labels, pal_n)
    flat = paint_of.ravel()
    spread = np.full(len(paint_keys), -np.inf)
    np.maximum.at(spread, flat, T_pal.ravel())
    T_sim = region_min(T[3], sim_labels, sim_n)
    T_clear = region_min(T[5], sim_labels, sim_n)
    T_lift = region_min(T[4], sim_labels, sim_n)
    # steps 3 and 4 settle with a small overshoot, darker then back, where the picture changes
    settle = {k: np.clip(np.abs(layers[k + 1] - layers[k]).max(axis=2) * 12, 0, 1)[..., None] for k in (2, 3)}

    # step 5: the lines the pets walk are drawn under their feet; the rest follow from where they
    # are, at a calmer pace, each darkening from grey to ink as it goes down
    t5_end = starts[4] + STEP - 0.12
    traced_by = {n: (t0, dur, pts) for n, t0, dur, pts in traces}
    stroke_plan = []
    for n, s in enumerate(strokes):
        walked = n in traced_by
        if walked:
            t0, dur, pts = traced_by[n]
            pts = np.asarray(pts, dtype=np.float32)
        else:
            pts = s
        J, S = staircase(pts, GRID)
        cum = np.concatenate(([0], np.cumsum(np.hypot(*np.diff(S, axis=0).T))))
        if not walked:
            x, y = int(min(max(pts[0][0], 0), W - 1)), int(min(max(pts[0][1], 0), H - 1))
            t0 = max(float(T[4][y, x]) + rng.uniform(0, 0.5), starts[4] + 0.3)
            dur = min(max(cum[-1] / (0.45 * W * pace), 0.25), 0.9 / pace)
            if t0 + dur > t5_end:
                t0 = max(starts[4], t5_end - dur)
        # step 6 relaxes each point when the ripple from the crew reaches it
        ix = np.clip(S[:, 0].astype(int), 0, W - 1)
        iy = np.clip(S[:, 1].astype(int), 0, H - 1)
        relax = T[5][iy, ix][:, None]
        stroke_plan.append((t0, dur, J, S, cum, walked, relax))
    pen = Image.new('L', (W * 2, H * 2), 0)
    relax_time = float(spec['outlines']['relax'])
    graphite = sketch(src.survivors, 1.0)
    end0 = starts[0] + STEP

    def outlines(t):
        """Line coverage (0...1) with each point relaxed from its stair-stepped outline toward
        the smooth curve as far as the ripple has reached it at time t."""
        canvas = Image.new('L', (W * 2, H * 2), 0)
        d = ImageDraw.Draw(canvas)
        for _, _, J, S, _, _, relax in stroke_plan:
            m = smoothstep((t - relax) / relax_time)
            P = (J + (S - J) * m) * 2
            d.line([tuple(p) for p in P], fill=255, width=3)
        return np.asarray(canvas.reduce(2), dtype=np.float32)[..., None] / 255

    smooth_cov = outlines(float('inf'))
    INK_RAMP = float(spec['outlines']['inkRamp'])     # s for a stroke to darken from grey to ink
    lift_from, lift_to = src.toned, src.lifted
    # step 6: numbers, each with its region
    template = src.template
    numbers_mult = np.where(src.lines[..., None] > 0.85, template, 1.0)
    num_T = []
    for x, y, _ in numbers:
        clear_at = float(T_clear[int(min(max(y, 0), H - 1)), int(min(max(x, 0), W - 1))])
        near = [t for t, sx, sy in seeds_by_step[5] if math.hypot(sx - x, sy - y) < 1.6 * pet_h]
        # a number next to a working pet goes down a moment after it does; the rest come quietly later
        at = min(near) + 0.3 if near else max(clear_at, starts[5] + 0.55 * STEP)
        smoothed_at = float(T[5][int(min(max(y, 0), H - 1)), int(min(max(x, 0), W - 1))]) + 0.45
        num_T.append(min(max(at, clear_at + 0.05, smoothed_at), end - 0.15))
    num_T = np.array(num_T)
    ys, xs = np.mgrid[0:H, 0:W].astype(np.float32)
    num_idx = np.full((H, W), -1, dtype=np.int32)
    for i, (x, y, sz) in enumerate(numbers):
        r = max(sz * 0.9, 4)
        x0, x1, y0, y1 = int(max(x - r, 0)), int(min(x + r + 1, W)), int(max(y - r, 0)), int(min(y + r + 1, H))
        if x0 >= x1 or y0 >= y1:
            continue
        disc = (xs[y0:y1, x0:x1] - x) ** 2 + (ys[y0:y1, x0:x1] - y) ** 2 <= r * r
        num_idx[y0:y1, x0:x1][disc] = i
    num_T_px = np.where(num_idx >= 0, num_T[np.maximum(num_idx, 0)], np.inf).astype(np.float32)

    for p in pets:
        p.finish()
    if a.motion:
        motion_report(pets, total, (W, H), pet_h, a.motion)
        return
    sprites = making_of_pets.load(a.pets, ids)
    cards = Cards(W, float(spec['cards']['footnote']))
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
            # texture smears away first and the color drains, graphite goes down on what survives,
            # then the photo fades to paper behind it: grey to paper, never color punched to white
            smear = smoothstep((t - T[0]) / 0.3)[..., None]
            base = layers[0] + (src.detextured - layers[0]) * smear
            drain = smoothstep((t - T[0] - 0.1) / 0.5)[..., None]
            base = base + ((base @ LUMA)[..., None] - base) * drain
            drawn = smoothstep((t - np.minimum(T[0] + 0.35 - 0.25 * src.survivors, end0 - 0.4)) / 0.16)[..., None]
            washed = smoothstep((t - np.minimum(T[0] + 0.45, end0 - 0.8)) / 0.7)[..., None]
            pic = (base + (paper - base) * washed) * (1 - drawn * (1 - graphite))
        elif k <= 3:
            Tk = [T[0], T[1], T_pal, T_sim][k]
            soft = 0.16 if k < 2 else 0.09
            m = smoothstep((t - Tk) / soft)[..., None]
            pic = layers[k] + (layers[k + 1] - layers[k]) * m
            if k in settle:
                bump = np.sin(np.pi * np.clip((t - Tk) / 0.22, 0, 1))[..., None]
                pic = pic * (1 - 0.1 * bump * settle[k])
        elif k == 4:
            for t0, dur, J, S, cum, walked, _ in stroke_plan:
                if t < t0 or t > t0 + dur + INK_RAMP + 1 / a.fps:
                    continue
                if walked:
                    a1 = making_of_pets.traced(t - t0, float(cum[-1]), pet_h)
                else:
                    a1 = making_of_pets.ease((t - t0) / dur) * cum[-1]
                n_pts = int(np.searchsorted(cum, a1, side='right'))
                if n_pts < 2:
                    continue
                value = 255 if walked else int(255 * (0.45 + 0.55 * min(max((t - t0) / (dur + INK_RAMP), 0), 1)))
                ink_line(pen, [(x * 2, y * 2) for x, y in J[:n_pts]], value, 3)
            pm = np.asarray(pen.reduce(2), dtype=np.float32)[..., None] / 255
            lift = smoothstep((t - T_lift) / 0.12)[..., None]
            pic = paper * (lift_from + (lift_to - lift_from) * lift) * (1 - pm * (1 - INK))
        else:
            if k == 5 and t < INTRO + 6 * STEP:
                clear = smoothstep((t - T_clear) / 0.12)[..., None]
                nm = smoothstep((t - num_T_px) / 0.1)[..., None]
                cov = outlines(t)
                pic = paper * (lift_to + (1 - lift_to) * clear) * (1 - cov * (1 - INK)) * (1 - nm * (1 - numbers_mult))
            else:
                last = paper * (1 - smooth_cov * (1 - INK)) * numbers_mult
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
                c = cards.image(k)[..., None] * (float(spec['cards']['opacity']) * alpha)
                frame[H:H + CARD_BAND] = frame[H:H + CARD_BAND] * (1 - c) + ink_rgb * c
        img = Image.fromarray((np.clip(frame, 0, 1) * 255 + 0.5).astype(np.uint8))
        draw = ImageDraw.Draw(img, 'RGBA')
        if k == 2:
            # the k-means++ seeds: a ring where each landed, popping in, gone once its paint has spread
            gone = 1 - smoothstep(np.array((t - (starts[2] + STEP - 0.4)) / 0.35))
            ink_rgb8 = tuple(int(v * 255) for v in INK)
            for st, sx, sy, paint in seeds:
                if t < st:
                    continue
                u = min((t - st) / 0.22, 1.0)
                r = float(spec['seeds']['dot']) * (1 + 0.35 * math.sin(math.pi * u) * (1 - u))
                # once its paint has spread, the ring has done its job
                done = 1 - smoothstep(np.array((t - spread[paint] - 0.1) / float(spec['seeds']['fade'])))
                al = int(255 * float(gone) * float(done) * min(u * 3, 1))
                if al <= 0:
                    continue
                draw.ellipse((sx - r - 2.5, sy - r - 2.5, sx + r + 2.5, sy + r + 2.5), fill=(247, 244, 238, al))
                draw.ellipse((sx - r, sy - r, sx + r, sy + r), outline=ink_rgb8 + (al,), width=3)
                draw.ellipse((sx - 2.6, sy - 2.6, sx + 2.6, sy + 2.6), fill=ink_rgb8 + (al,))
        # they dim only as the painting screen arrives, never while waving
        fade = 1.0 if t < total - 0.3 else max(0.0, (total - t) / 0.3)
        if fade > 0:
            canvas = img.convert('RGBA')
            for pet in sorted(pets, key=lambda p: p.state(t)[1]):
                pet.draw(sprites[pet.id], canvas, t, fade, H)
            img = canvas.convert('RGB')
        enc.stdin.write(img.tobytes())
        if a.stills and f % max(1, a.fps // 4) == 0:
            img.save(os.path.join(a.stills, f'{t:05.2f}.jpg'), quality=85)
    enc.stdin.close()
    if enc.wait():
        sys.exit('ffmpeg failed')


if __name__ == '__main__':
    main()
