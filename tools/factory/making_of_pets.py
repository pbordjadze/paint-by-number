"""The Lamp's pets as the making-of show's crew: their sprites, their jobs, and how they move.

Sprites come from the app's own sheets (`App/PaintByNumber/Resources/pet-<id>.webp`, the
create-pet v2 contract in `SpriteAtlas.swift`): idle, walking right and left, waving, busy and
reviewing. The motion is procedural, on top of those frames, and every number below is in the
pet's own height (h) or in seconds:

- A pet walks at WALK h/s. It takes the nearest job it can reach and finish within the step, so
  it does as many as fit and never darts; a pet with nothing in reach keeps working where it is.
- Setting off: it leans back and squashes a little for LEAN s, then speeds up over ACCEL s,
  leaning forward as it goes; it slows over DECEL s before the spot.
- Its walk cycle advances with the distance it covers (8 frames per STRIDE h), so the feet keep
  pace, and its body bobs twice a cycle.
- A longer walk ends in a low hop onto the spot (HOP h over its last HOP_TIME s); landing
  squashes and springs back.
- A pet sets off for its next job as soon as it finishes the last, so nobody moves in step with
  anybody else; it arrives no sooner than the step it works for has begun.
- At work it shows its busy pose for the hands-on steps (sketch, shading, ink) and its reviewing
  pose for the others (paints, merged, template).
- A soft shadow stays on the ground, smaller while the pet is in the air; pets higher in the
  picture are a little smaller, and nearer ones are drawn over farther ones.
- They pop in one after another at the start and wave one after another at the end.
- Positions are drawn to a fraction of a pixel, so slow movement doesn't shimmer.
"""

import math
import os

import numpy as np
from PIL import Image, ImageDraw

CELL = (192, 208)
PAD = 4             # transparent margin added around each frame, for sampling between pixels
ROWS = {'idle': (0, 6), 'right': (1, 8), 'left': (2, 8), 'wave': (3, 4), 'busy': (7, 6), 'review': (8, 6)}
# Who comes first when fewer than all of them work: a mix of shapes and colors.
ORDER = ['enchanted-workshop', 'dinotopia', 'snow-queen', 'scholar', 'baba-yaga', 'painter', 'glassblower',
         'medea', 'nutcracker', 'emily-dickinson', 'pirosmani', 'robber-girl', 'hedge-witch', 'storybook',
         'balanchine', 'originality', 'bulat-okudzhava', 'child-at-bedtime', 'open-source-enthusiast',
         'bible-school-teacher']
WORK_POSE = ['busy', 'busy', 'review', 'review', 'busy', 'review']

WALK = 2.4          # h per second
LEAN = 0.14         # s, the breath before setting off
ACCEL, DECEL = 0.22, 0.28
STRIDE = 1.5        # h per walk cycle (8 frames)
HOP, HOP_TIME, HOP_MIN = 0.06, 0.32, 1.6    # h, s, and the shortest walk (h) that ends in one
WORK = (0.6, 0.95)  # s at a job
POP = 0.42          # s for the pop at the start
TILT = 4.0          # degrees of forward lean at full walking speed


def ease(x):
    x = min(max(x, 0.0), 1.0)
    return x * x * (3 - 2 * x)


def spring(t, amount, period=0.2, decay=0.07):
    """A damped spring's offset `t` s after a kick of `amount`."""
    if t < 0:
        return 0.0
    return amount * math.exp(-t / decay) * math.cos(2 * math.pi * t / period)


def walk_time(dist, h):
    """Seconds from setting off to arriving `dist` px away."""
    return LEAN + dist / (WALK * h) + 0.5 * (ACCEL + DECEL)


def travelled(tau, dist, h):
    """Distance covered `tau` s after the lean, on a trapezoid of speed."""
    v = WALK * h
    acc, dec = ACCEL, DECEL
    cruise = dist / v - 0.5 * (acc + dec)
    if cruise < 0:                      # too short to reach full speed: scale the ramps
        k = math.sqrt(dist / v / (0.5 * (acc + dec)))
        acc, dec, v, cruise = acc * k, dec * k, v * k, 0.0
    total = acc + cruise + dec
    tau = min(max(tau, 0.0), total)
    if tau < acc:
        return 0.5 * v * tau * tau / acc
    d = 0.5 * v * acc
    if tau < acc + cruise:
        return d + v * (tau - acc)
    d += v * cruise
    r = tau - acc - cruise
    return min(dist, d + v * r - 0.5 * v * r * r / dec)


class Sprites:
    """One pet's frames by row, plus where its feet are in the cell."""

    def __init__(self, path):
        sheet = Image.open(path).convert('RGBA')
        if sheet.size != (CELL[0] * 8, CELL[1] * 11):
            raise ValueError(f'{path}: not a create-pet v2 sheet')
        self.rows = {}
        self.size = (CELL[0] + 2 * PAD, CELL[1] + 2 * PAD)
        for name, (r, n) in ROWS.items():
            frames = []
            for c in range(n):
                im = Image.new('RGBA', self.size, (0, 0, 0, 0))
                im.paste(sheet.crop((c * CELL[0], r * CELL[1], (c + 1) * CELL[0], (r + 1) * CELL[1])), (PAD, PAD))
                frames.append(im)
            self.rows[name] = frames
        alpha = np.zeros(self.size[::-1], dtype=np.uint8)
        for im in self.rows['idle']:
            alpha = np.maximum(alpha, np.asarray(im)[..., 3])
        ys, xs = np.nonzero(alpha > 24)
        self.top, self.foot = int(ys.min()), int(ys.max())
        self.cx = float(xs.mean())


def plan_step(pets, t0, t_end, candidates, step, h, rng):
    """Hands out the step's jobs: whoever is free first takes the nearest untaken spot it can
    walk to and finish by `t_end`. Appends (arrive, leave, x, y, step) to each pet's stops and
    returns the visits (time, x, y) the step's change spreads from."""
    pool = list(candidates)
    free = [p.stops[-1][1] for p in pets]
    visits = []
    busy = [True] * len(pets)
    while any(busy) and pool:
        i = min((j for j in range(len(pets)) if busy[j]), key=lambda j: free[j])
        _, _, x, y, _ = pets[i].stops[-1]
        best, best_arrive = None, None
        for q, (px, py) in enumerate(pool):
            arrive = free[i] + walk_time(math.hypot(px - x, py - y), h)
            if arrive < t0 + 0.08:                  # wait, so the walk ends as the step begins
                arrive = t0 + 0.08 + rng.uniform(0, 0.25)
            if arrive + WORK[0] <= t_end and (best is None or arrive < best_arrive):
                best, best_arrive = q, arrive
        if best is None:
            busy[i] = False
            continue
        px, py = pool.pop(best)
        prev = pets[i].stops[-1]
        depart = best_arrive - walk_time(math.hypot(px - x, py - y), h)
        if depart > prev[1]:                     # it kept working there until it had to go
            pets[i].stops[-1] = (prev[0], depart, prev[2], prev[3], prev[4])
        leave = best_arrive + rng.uniform(*WORK)
        pets[i].stops.append((best_arrive, min(leave, t_end), px, py, step))
        free[i] = min(leave, t_end)
        visits.append((best_arrive, px, py))
    return visits


class Pet:
    """One pet's way through the show; `stops` are (arrive, leave, x, y, step), the first its
    starting place (step -1: idle there), where it pops in at `appear`."""

    def __init__(self, sprites, start, height, rng, appear, end_time, wave_at):
        self.sp = sprites
        self.stops = [start]
        self.h = height
        self.appear = appear
        self.end = end_time
        self.wave_at = wave_at
        self.rng = rng
        self.facing = 'right'

    def finish(self):
        """Builds the paths once all stops are planned."""
        self.segments = []
        for (a0, l0, x0, y0, _), (a1, _, x1, y1, _) in zip(self.stops, self.stops[1:]):
            dx, dy = x1 - x0, y1 - y0
            d = math.hypot(dx, dy)
            bend = self.rng.uniform(0.06, 0.16) * self.rng.choice([-1, 1])
            cx, cy = (x0 + x1) / 2 - dy * bend, (y0 + y1) / 2 + dx * bend
            ts = np.linspace(0, 1, 65)
            px = (1 - ts) ** 2 * x0 + 2 * (1 - ts) * ts * cx + ts ** 2 * x1
            py = (1 - ts) ** 2 * y0 + 2 * (1 - ts) * ts * cy + ts ** 2 * y1
            cum = np.concatenate(([0], np.cumsum(np.hypot(np.diff(px), np.diff(py)))))
            self.segments.append({'leave': l0, 'arrive': a1, 'px': px, 'py': py, 'cum': cum,
                                  'len': float(cum[-1]), 'd': d})
        # distance walked before each segment, for a walk cycle that never jumps
        total = 0.0
        for s in self.segments:
            s['before'] = total
            total += s['len']

    def _point(self, s, dist):
        u = np.interp(dist, s['cum'], np.linspace(0, 1, len(s['cum'])))
        i = min(int(u * (len(s['px']) - 1)), len(s['px']) - 2)
        f = u * (len(s['px']) - 1) - i
        x = s['px'][i] + (s['px'][i + 1] - s['px'][i]) * f
        y = s['py'][i] + (s['py'][i + 1] - s['py'][i]) * f
        return x, y, s['px'][i + 1] - s['px'][i]

    def state(self, t):
        """(x, y, lift, row, frame, sx, sy, tilt, alpha) at time t."""
        h = self.h
        since = t - self.appear
        start = self.stops[0]
        if since < 0:
            return start[2], start[3], 0.0, 'idle', 0, 1.0, 1.0, 0.0, 0.0
        for i, s in enumerate(self.segments):
            if t < s['leave']:
                break
            if t < s['arrive']:
                dt = t - s['leave']
                if dt < LEAN:                                   # the breath before setting off
                    w = math.sin(math.pi * dt / LEAN)
                    x, y = self.stops[i][2], self.stops[i][3]
                    back = -1 if self._dir(s) == 'right' else 1
                    return x, y, 0.0, self.facing, 0, 1 + 0.05 * w, 1 - 0.06 * w, 2.5 * w * -back, 1.0
                dist = travelled(dt - LEAN, s['len'], h)
                x, y, tx = self._point(s, dist)
                if abs(tx) > 0.15:
                    self.facing = 'right' if tx > 0 else 'left'
                walked = s['before'] + dist
                frame = int(walked / (STRIDE * h) * 8)
                speed = (travelled(dt - LEAN + 0.01, s['len'], h) - dist) / 0.01 / (WALK * h)
                bob = 0.022 * h * abs(math.sin(math.pi * walked / (STRIDE * h / 2))) * min(speed, 1)
                lift = bob
                to_go = s['arrive'] - t
                if s['d'] >= HOP_MIN * h and to_go < HOP_TIME:
                    lift += HOP * h * math.sin(math.pi * (1 - to_go / HOP_TIME))
                tilt = TILT * min(speed, 1) * (-1 if self.facing == 'right' else 1)
                return x, y, lift, self.facing, frame, 1.0, 1.0, tilt, 1.0
            nxt = self.stops[i + 1]
            if t <= nxt[1] or i + 1 == len(self.segments):
                return self._at_stop(nxt, t)
        return self._at_stop(self.stops[0] if not self.segments or t < self.segments[0]['leave'] else self.stops[-1], t)

    def _dir(self, s):
        return 'right' if s['px'][-1] >= s['px'][0] else 'left'

    def _at_stop(self, stop, t):
        arrive, leave, x, y, k = stop
        land = t - arrive
        sy = 1 + spring(land, -0.10, 0.22, 0.08)
        sx = 1 / math.sqrt(max(sy, 0.5))
        if t <= leave and k >= 0:
            return x, y, 0.0, WORK_POSE[k], int(land * 8), sx, sy, 0.0, 1.0
        if t < self.wave_at:
            return x, y, 0.0, 'idle', int(t * 6), sx, sy, 0.0, 1.0
        return x, y, 0.0, 'wave', int((t - self.wave_at) * 7), 1.0, 1.0, 0.0, 1.0

    def draw(self, canvas, t, fade, picture_h):
        x, y, lift, row, frame, sx, sy, tilt, alpha = self.state(t)
        since = t - self.appear
        if 0 <= since < POP:
            u = since / POP
            pop = 1 + 0.18 * math.sin(math.pi * u) * (1 - u)
            sx, sy = sx * pop, sy * pop
        alpha = min(alpha, ease(since / 0.18)) * fade
        if alpha <= 0.01:
            return
        frames = self.sp.rows[row]
        im = frames[frame % len(frames)]
        if abs(tilt) > 0.05:
            im = im.rotate(tilt, resample=Image.BICUBIC, center=(self.sp.cx, self.sp.foot))
        depth = 0.9 + 0.16 * min(max(y / picture_h, 0), 1)
        scale = self.h * depth / (self.sp.foot - self.sp.top)
        sxs, sys_ = 1 / (scale * sx), 1 / (scale * sy)      # source pixels per screen pixel
        ox = x - self.sp.cx * scale * sx                       # where the frame's corner lands, unrounded
        oy = y - lift - self.sp.foot * scale * sy
        # start on the first whole pixel inside the frame and sample from the fraction past its
        # corner, so the pet sits between pixels when it should (the frame's margin is clear)
        ix, iy = math.ceil(ox), math.ceil(oy)
        bx, by = (ix - ox) * sxs, (iy - oy) * sys_
        w = max(1, math.floor((self.sp.size[0] - bx) / sxs))
        hh = max(1, math.floor((self.sp.size[1] - by) / sys_))
        sprite = im.resize((w, hh), Image.LANCZOS, box=(bx, by, bx + w * sxs, by + hh * sys_))
        if alpha < 0.999:
            sprite.putalpha(sprite.getchannel('A').point(lambda v: int(v * alpha)))
        sw = self.h * depth * 0.40 * (1 - 0.3 * min(lift / max(self.h * HOP, 1), 1))
        sh = max(2, round(sw * 0.42))
        shadow = Image.new('RGBA', (max(2, round(2 * sw)), sh), (0, 0, 0, 0))
        ImageDraw.Draw(shadow).ellipse((0, 0, shadow.width - 1, sh - 1), fill=(52, 42, 48, int(44 * alpha)))
        put(canvas, shadow, round(x - sw), round(y - sh / 2))
        put(canvas, sprite, ix, iy)


def put(canvas, im, left, top):
    """Composites `im` at (left, top), clipped to the canvas."""
    x0, y0 = max(left, 0), max(top, 0)
    x1, y1 = min(left + im.width, canvas.width), min(top + im.height, canvas.height)
    if x0 >= x1 or y0 >= y1:
        return
    canvas.alpha_composite(im.crop((x0 - left, y0 - top, x1 - left, y1 - top)), dest=(x0, y0))


def load(resources, ids):
    return {i: Sprites(os.path.join(resources, f'pet-{i}.webp')) for i in ids}
