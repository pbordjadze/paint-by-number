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
- A soft shadow stays on the ground, smaller and paler while the pet is in the air; pets higher in the
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
SIDE = 0.42         # h: a pet stands this far to one side of its spot, and works toward it
STILL = 0.5         # h: a job this close is worked from where the pet stands, without a walk
MARGIN = 0.12       # share of the picture: no job, nor a line's start, this close to a side or the top
BANDS = 3           # upright bands the crew shares out, left to right, so it spreads over the picture
SPACE = 1.0         # h: how far apart pets' spots stay while both are there (see _clear)
TRACE = 1.5         # h per second while drawing a line by walking along it
TRACE_RAMP = (0.12, 0.16)
HOLD = 0.3          # s: everyone standing takes the reviewing pose as a step ends
EXIT = 1.8          # times walking pace, for the walk off the picture at the end
WAVE = 0.6          # s of waving goodbye
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


def trace_time(dist, h):
    """Seconds to draw a line `dist` px long, walking along it."""
    return dist / (TRACE * h) + 0.5 * (TRACE_RAMP[0] + TRACE_RAMP[1])


def trapezoid(tau, dist, v, acc, dec):
    """Distance covered `tau` s into a move of `dist` at top speed `v`, speeding up over `acc` s
    and slowing over `dec` s."""
    if dist <= 0:
        return 0.0
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


def travelled(tau, dist, h):
    """Distance walked `tau` s after the lean."""
    return trapezoid(tau, dist, WALK * h, ACCEL, DECEL)


def traced(tau, dist, h):
    """Distance drawn `tau` s into tracing a line."""
    return trapezoid(tau, dist, TRACE * h, *TRACE_RAMP)


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


class Planner:
    """Hands out the jobs. A pet stands beside its spot (SIDE), on the side it came from, so the
    change it makes is never hidden under it; spots of pets working at the same time stay SPACE
    apart; arrivals land on the step's quarter beats, rippling left to right, the first on the
    step's own downbeat when a pet can be there by then. Each pet has its band of the picture
    (BANDS, by where it pops in) and takes a job elsewhere only when its band has none it can
    reach in time."""

    def __init__(self, pets, size, h, rng, beat, origin):
        self.pets, self.h, self.rng = pets, h, rng
        self.W, self.H = size
        self.beat, self.origin = beat, origin
        self.taken = []                 # (from, to, x, y, pet)
        m = MARGIN
        self.box = (m * self.W, m * self.H + h, (1 - m) * self.W, self.H - 4)   # where feet may work
        n, self.bands = len(pets), max(1, min(BANDS, len(pets)))
        order = sorted(range(n), key=lambda i: pets[i].stops[0][2])
        self.band = {i: rank * self.bands // n for rank, i in enumerate(order)}

    def _in_band(self, i, x):
        x0, _, x1, _ = self.box
        w = (x1 - x0) / self.bands
        b = self.band[i]
        return x0 + b * w - 0.25 * self.h <= x <= x0 + (b + 1) * w + 0.25 * self.h

    def _inside(self, x, y):
        x0, y0, x1, y1 = self.box
        return x0 <= x <= x1 and y0 <= y <= y1

    def _end(self, stop):
        path = stop[5]
        return (float(path[-1][0]), float(path[-1][1])) if path is not None else (stop[2], stop[3])

    def _stand(self, jx, jy, fromx):
        h = self.h
        side = -1 if fromx < jx else 1
        x = jx + side * SIDE * h
        if not 0.05 * self.W <= x <= 0.95 * self.W:
            x = jx - side * SIDE * h
        return min(max(x, 0.05 * self.W), 0.95 * self.W), min(jy + 0.05 * h, self.H - 4)

    def _clear(self, x, y, t0, t1, me):
        # pets are taller than wide: clear means side by side with room, or a whole pet apart up and down
        h = self.h
        return all(o == me or b + 0.2 < t0 or t1 + 0.2 < a
                   or abs(x - ox) >= 0.85 * SPACE * h or abs(y - oy) >= 1.15 * SPACE * h
                   for a, b, ox, oy, o in self.taken)

    def _snap(self, t, x):
        k = math.ceil((t - self.origin) / self.beat - 1e-6)
        return self.origin + k * self.beat + 0.15 * x / self.W

    def _depart(self, i, depart):
        prev = self.pets[i].stops[-1]
        if depart > prev[1]:            # it kept at it there until it had to go
            self.pets[i].stops[-1] = prev[:1] + (depart,) + prev[2:]

    def step(self, t0, t_end, candidates, k, homes=None):
        """Jobs at `candidates` (spots) for step `k`; returns the seeds its change spreads from,
        (time, x, y), a short sweep beside each pet as it works. `homes`, if given, is where
        each pet must be by when afterwards ((x, y, t) per pet)."""
        h, pool, seeds = self.h, list(candidates), []
        free = [p.stops[-1][1] for p in self.pets]
        live = [True] * len(self.pets)
        while any(live) and pool:
            i = min((j for j in range(len(self.pets)) if live[j]), key=lambda j: free[j])
            x, y = self._end(self.pets[i].stops[-1])
            best = None
            for q, (jx, jy) in [(q, c) for own in (True, False) for q, c in enumerate(pool)
                                if self._in_band(i, c[0]) == own]:
                if best is not None and not self._in_band(i, jx):
                    break                       # a job in its own band always comes first
                sx, sy = self._stand(jx, jy, x)
                d = math.hypot(sx - x, sy - y)
                if d < STILL * h:       # near enough to reach from here: no little shuffle over
                    sx, sy, d = x, y, 0.0
                reach = max(free[i] + walk_time(d, h), t0)          # compared unsnapped: the beat's
                arrive = self._snap(reach, sx)                       # ripple must not pull anyone sideways
                last = t_end
                if homes:
                    hx, hy, by = homes[i]
                    last = min(last, by - walk_time(math.hypot(hx - sx, hy - sy), h) / EXIT)
                if arrive + WORK[0] > last or not self._clear(sx, sy, arrive, arrive + WORK[1], i):
                    continue
                if best is None or reach < best[6]:
                    best = (arrive, q, sx, sy, d, last, reach)
            if best is None:
                live[i] = False
                continue
            arrive, q, sx, sy, d, last, _ = best
            jx, jy = pool.pop(q)
            self._depart(i, arrive - walk_time(d, h))
            leave = min(arrive + self.rng.uniform(*WORK), last)
            self.pets[i].stops.append((arrive, leave, sx, sy, k, None))
            self.taken.append((arrive, leave, sx, sy, i))
            free[i] = leave
            toward = 1 if jx >= sx else -1
            for f, dx in ((0.1, -0.2), (0.35, 0.05), (0.6, 0.25)):
                seeds.append((arrive + f * (leave - arrive), jx + toward * dx * h, jy))
        return seeds

    def trace(self, t0, t_end, strokes, k, homes=None):
        """Step `k`'s lines: each free pet walks to the nearest line it can draw in time and draws
        it by walking along it. Returns (seeds, traces): traces are (stroke index, start time,
        duration, points in drawing order)."""
        h, seeds, traces = self.h, [], []
        pool = {n: s for n, s in enumerate(strokes)
                if float(np.hypot(*np.diff(s, axis=0).T).sum()) >= 0.9 * h}
        free = [p.stops[-1][1] for p in self.pets]
        live = [True] * len(self.pets)
        while any(live) and pool:
            i = min((j for j in range(len(self.pets)) if live[j]), key=lambda j: free[j])
            x, y = self._end(self.pets[i].stops[-1])
            best = None
            # a line starting in its own band always comes first
            starts = [(own, n, pts) for own in (True, False) for n, s in pool.items() for pts in (s, s[::-1])
                      if self._inside(pts[0][0], pts[0][1]) and self._in_band(i, pts[0][0]) == own]
            for own, n, pts in starts:
                if best is not None and not own:
                    break
                length = float(np.hypot(*np.diff(pts, axis=0).T).sum())
                d = math.hypot(pts[0][0] - x, pts[0][1] - y)
                reach = max(free[i] + walk_time(d, h), t0)
                arrive = self._snap(reach, pts[0][0])
                dur = trace_time(length, h)
                end_by = t_end
                if homes:
                    hx, hy, by = homes[i]
                    end_by = min(end_by, by - walk_time(math.hypot(hx - pts[-1][0], hy - pts[-1][1]), h))
                if arrive + dur > end_by or not self._clear(pts[0][0], pts[0][1], arrive, arrive + 0.4, i):
                    continue
                if best is None or reach < best[5]:
                    best = (arrive, n, dur, pts, d, reach)
            if best is None:
                live[i] = False
                continue
            arrive, n, dur, pts, d, _ = best
            del pool[n]
            self._depart(i, arrive - walk_time(d, h))
            self.pets[i].stops.append((arrive, arrive + dur, float(pts[0][0]), float(pts[0][1]), k, pts))
            self.taken.append((arrive, arrive + 0.4, float(pts[0][0]), float(pts[0][1]), i))
            free[i] = arrive + dur + 0.12
            traces.append((n, arrive, dur, pts))
            cum = np.concatenate(([0], np.cumsum(np.hypot(*np.diff(pts, axis=0).T))))
            for f in np.linspace(0, 1, 6):
                dist = f * cum[-1]
                tt = arrive + dur * f
                seeds.append((tt, float(np.interp(dist, cum, pts[:, 0])), float(np.interp(dist, cum, pts[:, 1]))))
        return seeds, traces

    def _crosses(self, a, b, o):
        """Whether walking from a to b passes over a pet standing at o (boxes as in _clear)."""
        (ax, ay), (bx, by), (ox, oy) = a, b, o
        L2 = (bx - ax) ** 2 + (by - ay) ** 2
        u = min(max(((ox - ax) * (bx - ax) + (oy - ay) * (by - ay)) / max(L2, 1e-9), 0), 1)
        px, py = ax + u * (bx - ax), ay + u * (by - ay)
        return abs(px - ox) < 0.85 * SPACE * self.h and abs(py - oy) < 1.15 * SPACE * self.h

    def farewell(self, wave_at, frame_h):
        """The goodbye: each pet waves where it stands at `wave_at[i]` for WAVE s, then walks
        briskly to the nearest edge whose way doesn't cross a pet still there, and steps out of
        the frame."""
        h = self.h
        spots = [self._end(p.stops[-1]) for p in self.pets]
        for i, p in enumerate(self.pets):
            prev = p.stops[-1]
            x, y = spots[i]
            if prev[5] is not None:
                done = prev[0] + trace_time(float(np.hypot(*np.diff(prev[5], axis=0).T).sum()), h)
            else:
                done = prev[1] if prev[4] >= 0 else prev[0]
            at = max(wave_at[i], done)
            self._depart(i, at)
            p.stops.append((at, at + WAVE, x, y, -2, None))
            exits = sorted([(-0.7 * h, y), (self.W + 0.7 * h, y), (x, -0.25 * h), (x, frame_h + 1.2 * h)],
                           key=lambda e: math.hypot(e[0] - x, e[1] - y))
            others = spots[:i] + spots[i + 1:]
            ex, ey = next((e for e in exits if not any(self._crosses((x, y), e, o) for o in others)), exits[0])
            need = walk_time(math.hypot(ex - x, ey - y), h) / EXIT
            p.stops.append((at + WAVE + need, float('inf'), ex, ey, -3, None))


class Pet:
    """One pet's way through the show. `stops` are (arrive, leave, x, y, step, path): a job
    (step 0-5) worked standing at (x, y), or drawn by walking `path`; the first stop is where it
    pops in at `appear` (step -1); at the end it waves where it stands (step -2), then walks out
    of the frame (step -3). `step_ends` are when steps end, for the shared hold."""

    def __init__(self, sprites, start, height, rng, appear, wave_at, step_ends):
        self.sp = sprites
        self.stops = [start]
        self.h = height
        self.appear = appear
        self.wave_at = wave_at
        self.step_ends = step_ends
        self.rng = rng
        self.facing = 'right'

    def finish(self):
        """Builds the walks between stops once every stop is planned."""
        self.segments = []
        for s0, s1 in zip(self.stops, self.stops[1:]):
            l0 = s0[1]
            x0, y0 = (float(s0[5][-1][0]), float(s0[5][-1][1])) if s0[5] is not None else (s0[2], s0[3])
            a1, x1, y1 = s1[0], s1[2], s1[3]
            dx, dy = x1 - x0, y1 - y0
            d = math.hypot(dx, dy)
            bend = self.rng.uniform(0.06, 0.16) * self.rng.choice([-1, 1])
            cx, cy = (x0 + x1) / 2 - dy * bend, (y0 + y1) / 2 + dx * bend
            ts = np.linspace(0, 1, 65)
            px = (1 - ts) ** 2 * x0 + 2 * (1 - ts) * ts * cx + ts ** 2 * x1
            py = (1 - ts) ** 2 * y0 + 2 * (1 - ts) * ts * cy + ts ** 2 * y1
            cum = np.concatenate(([0], np.cumsum(np.hypot(np.diff(px), np.diff(py)))))
            need = walk_time(float(cum[-1]), self.h) - LEAN
            hurry = max(1.0, need / max(a1 - l0 - LEAN, 0.05))
            self.segments.append({'leave': l0, 'arrive': a1, 'px': px, 'py': py, 'cum': cum,
                                  'len': float(cum[-1]), 'd': d, 'hurry': hurry})
        total = 0.0
        for seg in self.segments:       # distance walked before each walk, so the cycle never jumps
            seg['before'] = total
            total += seg['len']

    def _point(self, s, dist):
        u = np.interp(dist, s['cum'], np.linspace(0, 1, len(s['cum'])))
        i = min(int(u * (len(s['px']) - 1)), len(s['px']) - 2)
        f = u * (len(s['px']) - 1) - i
        x = s['px'][i] + (s['px'][i + 1] - s['px'][i]) * f
        y = s['py'][i] + (s['py'][i + 1] - s['py'][i]) * f
        return x, y, s['px'][i + 1] - s['px'][i]

    def _walking(self, x, y, tx, walked, speed, extra_lift=0.0):
        h = self.h
        if abs(tx) > 0.15:
            self.facing = 'right' if tx > 0 else 'left'
        frame = int(walked / (STRIDE * h) * 8)
        bob = 0.022 * h * abs(math.sin(math.pi * walked / (STRIDE * h / 2))) * min(speed, 1)
        tilt = TILT * min(speed, 1) * (-1 if self.facing == 'right' else 1)
        return x, y, bob + extra_lift, self.facing, frame, 1.0, 1.0, tilt, 1.0

    def state(self, t):
        """(x, y, lift, row, frame, sx, sy, tilt, alpha) at time t."""
        h = self.h
        start = self.stops[0]
        if t < self.appear:
            return start[2], start[3], 0.0, 'idle', 0, 1.0, 1.0, 0.0, 0.0
        for i, seg in enumerate(self.segments):
            if t < seg['leave']:
                break
            if t < seg['arrive']:
                if seg['len'] < 1e-6:                           # the next job is right here: it stays put
                    return self._at_stop(self.stops[i], t, seg['before'])
                dt = t - seg['leave']
                if dt < LEAN:                                   # the breath before setting off
                    w = math.sin(math.pi * dt / LEAN)
                    x, y = seg['px'][0], seg['py'][0]
                    lean_back = 2.5 * w * (1 if seg['px'][-1] >= seg['px'][0] else -1)
                    return x, y, 0.0, self.facing, 0, 1 + 0.05 * w, 1 - 0.06 * w, lean_back, 1.0
                k = seg['hurry']
                dist = travelled((dt - LEAN) * k, seg['len'], h)
                x, y, tx = self._point(seg, dist)
                speed = (travelled((dt - LEAN + 0.01) * k, seg['len'], h) - dist) / 0.01 / (WALK * h)
                to_go = seg['arrive'] - t
                hop = 0.0
                nxt = self.stops[i + 1]
                if seg['d'] >= HOP_MIN * h and to_go < HOP_TIME and nxt[5] is None:
                    hop = HOP * h * math.sin(math.pi * (1 - to_go / HOP_TIME))
                return self._walking(x, y, tx, seg['before'] + dist, speed, hop)
            nxt = self.stops[i + 1]
            if t <= nxt[1] or i + 1 == len(self.segments):
                return self._at_stop(nxt, t, seg['before'] + seg['len'])
        return self._at_stop(self.stops[0], t, 0.0)

    def _holding(self, t):
        return any(e - HOLD <= t < e for e in self.step_ends)

    def _at_stop(self, stop, t, walked):
        arrive, leave, x, y, k, path = stop
        h = self.h
        cum = np.concatenate(([0], np.cumsum(np.hypot(*np.diff(path, axis=0).T)))) if path is not None else None
        if path is not None and arrive <= t <= arrive + trace_time(float(cum[-1]), h):   # drawing a line
            dist = traced(t - arrive, float(cum[-1]), h)
            x = float(np.interp(dist, cum, path[:, 0]))
            y = float(np.interp(dist, cum, path[:, 1]))
            ahead = float(np.interp(min(dist + 2, cum[-1]), cum, path[:, 0])) - x
            speed = (traced(t - arrive + 0.01, float(cum[-1]), h) - dist) / 0.01 / (WALK * h)
            return self._walking(x, y, ahead, walked + dist, speed)
        if path is not None:                                    # the line drawn, it looks it over
            x, y = float(path[-1][0]), float(path[-1][1])
            arrive += trace_time(float(cum[-1]), h)
        land = t - arrive
        sy = 1 + spring(land, -0.10, 0.22, 0.08) if path is None else 1.0
        sx = 1 / math.sqrt(max(sy, 0.5))
        if k == -2:                                             # waving goodbye
            return x, y, 0.0, 'wave', int((t - arrive) * 7), 1.0, 1.0, 0.0, 1.0
        if k == -3:                                             # gone
            return x, y, 0.0, 'idle', 0, 1.0, 1.0, 0.0, 0.0
        if self._holding(t):
            return x, y, 0.0, 'review', int(t * 8), sx, sy, 0.0, 1.0
        if t <= leave and k >= 0:
            return x, y, 0.0, WORK_POSE[k], int(land * 8), sx, sy, 0.0, 1.0
        return x, y, 0.0, 'idle', int(t * 6), sx, sy, 0.0, 1.0

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
        depth = 0.9 + 0.16 * min(max(y / picture_h, 0), 1)   # below the picture: as near as it gets
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
        air = min(lift / max(self.h * HOP, 1), 1)
        sw = self.h * depth * 0.40 * (1 - 0.4 * air)
        sh = max(2, round(sw * 0.42))
        shadow = Image.new('RGBA', (max(2, round(2 * sw)), sh), (0, 0, 0, 0))
        ImageDraw.Draw(shadow).ellipse((0, 0, shadow.width - 1, sh - 1),
                                       fill=(52, 42, 48, int(44 * alpha * (1 - 0.6 * air))))
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
