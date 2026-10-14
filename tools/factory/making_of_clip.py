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
import os
import re
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

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


def main():
    global STEP, VISITS
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
    a = ap.parse_args()
    STEP, VISITS = a.step, max(2, round(a.step / a.stop_every))
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
        src.structure + 0.08,
        np.ones((H, W), dtype=np.float32),
        np.sqrt(area(pal_labels, pal_n)) / area(pal_labels, pal_n),
        np.sqrt(area(sim_labels, sim_n)) / area(sim_labels, sim_n),
        stroke_w + 1e-6 * stroke_w.max(),
        num_w + 1e-6,
    ]
    crew = Crew(a.crew, (W, H), rng, inside=bool(a.pets))
    pet_h = 0.12 * H
    if a.pets:
        # a pet's spot keeps all of it in the picture: half a pet from the sides, a pet from the top
        room = np.zeros((H, W), dtype=np.float32)
        room[int(pet_h) + 4:H - 8, int(0.05 * W):W - int(0.05 * W)] = 1
        weights = [w * room for w in weights]
    n_stops = a.crew * VISITS
    T = []
    for k in range(6):
        pts = sample_stops(weights[k], n_stops, rng, spacing=(0.11 if a.pets else 0.09) * W)
        visits = crew.plan_step(starts[k], pts, k)
        noise = 0.10 * value_noise((H, W), (18, 12), rng) + 0.06 * value_noise((H, W), (60, 40), rng)
        T.append(arrival(visits, (H, W), speed=0.55 * W * pace, t_end=starts[k] + STEP - 0.2, noise=noise))
    T_pal = region_min(T[2], pal_labels, pal_n)
    T_sim = region_min(T[3], sim_labels, sim_n)
    T_clear = region_min(T[5], sim_labels, sim_n)

    # step 5: each stroke drawn from its start, at a pen's pace, finished before the step ends
    t5_end = starts[4] + STEP - 0.12
    stroke_plan = []
    for s in strokes:
        x, y = int(min(max(s[0][0], 0), W - 1)), int(min(max(s[0][1], 0), H - 1))
        seg = np.hypot(*np.diff(s, axis=0).T)
        cum = np.concatenate(([0], np.cumsum(seg)))
        t0 = float(T[4][y, x])
        dur = min(max(cum[-1] / (0.9 * W * pace), 0.12), 0.6 / pace)
        if t0 + dur > t5_end:
            t0 = max(starts[4], t5_end - dur)
        stroke_plan.append((t0, dur, s, cum))
    pen = Image.new('L', (W * 2, H * 2), 0)
    pen_draw = ImageDraw.Draw(pen)
    pen_done = [0.0] * len(strokes)
    lines_mult = ink(src.lines)
    lift_from, lift_to = wash(src.simplified, 0.45), wash(src.simplified, 0.22)
    # step 6: numbers, each with its region
    template = src.template
    numbers_mult = np.where(src.lines[..., None] > 0.85, template, 1.0)
    num_T = np.array([T_clear[int(min(max(y, 0), H - 1)), int(min(max(x, 0), W - 1))] for x, y, _, _ in numbers])
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

    pets = []
    if a.pets:
        ids = making_of_pets.ORDER[:a.crew]
        sprites = making_of_pets.load(a.pets, ids)
        pet_rng = np.random.default_rng(a.seed + 1)
        for i, pid in enumerate(ids):
            pets.append(making_of_pets.Pet(sprites[pid], crew.stops[i], pet_h, pet_rng, INTRO + 6 * STEP))
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
            washed = smoothstep((t - T[0] - 0.12) / 0.3)[..., None]
            graphite = sketch(src.structure, 1.0)
            pic = (layers[0] + (paper - layers[0]) * washed) * (1 - drawn * (1 - graphite))
        elif k <= 3:
            Tk = [T[0], T[1], T_pal, T_sim][k]
            soft = 0.16 if k < 2 else 0.09
            m = smoothstep((t - Tk) / soft)[..., None]
            pic = layers[k] + (layers[k + 1] - layers[k]) * m
        elif k == 4:
            for i, (t0, dur, s, cum) in enumerate(stroke_plan):
                u = min(max((t - t0) / dur, 0.0), 1.0)
                if u <= pen_done[i]:
                    continue
                a0, a1 = pen_done[i] * cum[-1], ease(u) * cum[-1] if u < 1 else cum[-1]
                if a1 <= a0:
                    continue
                pts = [tuple(np.interp(a0, cum, s[:, c]) for c in (0, 1))]
                pts += [tuple(p) for p, c in zip(s, cum) if a0 < c < a1]
                pts.append(tuple(np.interp(a1, cum, s[:, c]) for c in (0, 1)))
                pen_draw.line([(x * 2, y * 2) for x, y in pts], fill=255, width=9, joint='curve')
                pen_done[i] = a1 / cum[-1] if cum[-1] else 1.0
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
            end = INTRO + 6 * STEP
            fade = 1.0 if t < end + OUTRO - 0.45 else max(0.0, 1 - (t - (end + OUTRO - 0.45)) / 0.35)
            if fade > 0:
                canvas = img.crop((0, 0, W, H)).convert('RGBA')
                for pet in sorted(pets, key=lambda p: p.state(t)[1]):
                    pet.draw(canvas, t, fade, H)
                img.paste(canvas.convert('RGB'), (0, 0))
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
