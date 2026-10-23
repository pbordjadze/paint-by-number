"""The making-of show's crew planner, the show's SplitMix64 and its random streams, and the easing the
shared modules use. The crew show it planned, and the sprites it drew, left this repository with the
Marginarium. Paul's decision (October 23): the Marginarium is private for now; it leaves every build
and this repository. Its archive is in the private painting-company repository. The planner stays:
the field show's inputs are still drawn for the spec's crew, and its plan's visits and walked lines
are in the fixtures Sources/MakingOf replays (making_of_reveal.py --fixture). Every number below is
in a guardian's own height (h) or in seconds:

- A guardian walks at WALK h/s. It takes the nearest job it can reach and finish within the step, so
  it does as many as fit and never darts; a guardian with nothing in reach keeps working where it is.
- Setting off takes LEAN s, then it speeds up over ACCEL s; it slows over DECEL s before the spot.
- A guardian sets off for its next job as soon as it finishes the last, so nobody moves in step with
  anybody else; it arrives no sooner than the step it works for has begun.
- They pop in one after another at the start and wave one after another at the end.

`plan(inputs)` is the whole crew's planning as one pure function of plain data (the picture, the
candidate spots of each step, the template's strokes, a seed), drawing every random number from
SplitMix64. Its Swift port was retired on October 23, 2026 (the app plays the show with no crew).
"""

import math
from collections import namedtuple

import numpy as np

ORDER = []          # the crew, in order: the spec's (`configure`)

WALK = 2.4          # h per second
LEAN = 0.14         # s, the breath before setting off
ACCEL, DECEL = 0.22, 0.28
WORK = (0.6, 0.95)  # s at a job
SIDE = 0.42         # h: a guardian stands this far to one side of its spot, and works toward it
STILL = 0.5         # h: a job this close is worked from where the guardian stands, without a walk
MARGIN = 0.12       # share of the picture: no job, nor a line's start, this close to a side or the top
BANDS = 3           # upright bands the crew shares out, left to right, so it spreads over the picture
SPACE = 1.0         # h: how far apart guardians' spots stay while both are there (see _clear)
TRACE = 1.5         # h per second while drawing a line by walking along it
TRACE_RAMP = (0.12, 0.16)
EXIT = 1.8          # times walking pace, for the walk off the picture at the end
WAVE = 0.6          # s of waving goodbye
LOOK = 0.4          # s of a last look at the finished picture, before the wave
EDGE_WAVE = 0.5     # s the last one out waves again, just inside the edge
BEAT = 0.25         # share of a step between the beats arrivals land on
INK_STEP = 4        # the step whose lines are drawn by walking along them


def configure(spec):
    """Sets the crew's constants from the show's spec (making-of.json, already loaded)."""
    global ORDER, WORK, BANDS, TRACE_RAMP
    crew = spec['crew']
    ORDER = list(crew['pets'])
    for key, name in (('walk', 'WALK'), ('lean', 'LEAN'), ('accel', 'ACCEL'), ('decel', 'DECEL'),
                      ('side', 'SIDE'), ('space', 'SPACE'), ('trace', 'TRACE'), ('exit', 'EXIT'),
                      ('wave', 'WAVE'), ('still', 'STILL'), ('margin', 'MARGIN'), ('beat', 'BEAT'),
                      ('look', 'LOOK'), ('edgeWave', 'EDGE_WAVE')):
        globals()[name] = float(crew[key])
    WORK = tuple(float(v) for v in crew['work'])
    BANDS = int(crew['bands'])
    TRACE_RAMP = tuple(float(v) for v in crew['traceRamp'])


class SplitMix64:
    """PaintCore's SplitMix64 (Sources/PaintCore/Foundation/SplitMix64.swift) in 64-bit wrapping
    arithmetic, with the draws the show needs. Sources/MakingOf has the same ones; keep them equal
    (both test suites pin the first doubles of seed 1)."""

    MASK = (1 << 64) - 1

    def __init__(self, seed):
        self.state = seed & self.MASK

    def next(self):
        self.state = (self.state + 0x9E3779B97F4A7C15) & self.MASK
        z = self.state
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & self.MASK
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & self.MASK
        return z ^ (z >> 31)

    def random(self):
        """A double in [0, 1)."""
        return (self.next() >> 11) * 2.0 ** -53

    def uniform(self, a, b):
        return a + (b - a) * self.random()

    def below(self, n):
        """An integer in [0, n)."""
        return self.next() % n

    def permutation(self, n):
        """0..<n shuffled (Fisher-Yates, from the back)."""
        out = list(range(n))
        for i in range(n - 1, 0, -1):
            j = self.below(i + 1)
            out[i], out[j] = out[j], out[i]
        return out

    def choice(self, items):
        return items[self.below(len(items))]


# The show's random draws, one stream per purpose, so a draw count in one (sample_stops retries)
# can never shift another. Sources/MakingOf/Streams.swift has the same; both suites pin them.
STREAM_HOMES, STREAM_SPOTS, STREAM_NOISE, STREAM_SEEDS, STREAM_STROKES = 1, 2, 3, 4, 5


def stream(seed, purpose, index):
    """The SplitMix64 for one purpose (STREAM_*) and index (a step, a stroke, a noise grid) of
    the show's seed: a generator seeded from the first draw of `seed ^ (purpose << 32 | index)`."""
    assert 0 <= index < 1 << 32
    return SplitMix64(SplitMix64(seed ^ (purpose << 32 | index)).next())

def ease(x):
    x = min(max(x, 0.0), 1.0)
    return x * x * (3 - 2 * x)


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


def norm(dx, dy):
    """The length of (dx, dy). Plain arithmetic and a square root, not math.hypot or np.hypot:
    those round differently from one C library to the next, and a port must agree to the last bit
    wherever a comparison could turn on it."""
    return math.sqrt(dx * dx + dy * dy)


def cumulative(pts):
    """Distance along a polyline up to each of its points."""
    d = np.diff(pts, axis=0)
    return np.concatenate(([0.0], np.cumsum(np.sqrt(d[:, 0] * d[:, 0] + d[:, 1] * d[:, 1]))))


def traced(tau, dist, h):
    """Distance drawn `tau` s into tracing a line."""
    return trapezoid(tau, dist, TRACE * h, *TRACE_RAMP)


class Planner:
    """Hands out the jobs. A guardian stands beside its spot (SIDE), on the side it came from, so the
    change it makes is never hidden under it; spots of guardians working at the same time stay SPACE
    apart; arrivals land on the step's quarter beats, rippling left to right, the first on the
    step's own downbeat when a guardian can be there by then. Each guardian has its band of the picture
    (BANDS, by where it pops in) and takes a job elsewhere only when its band has none it can
    reach in time."""

    def __init__(self, pets, size, h, rng, beat, origin):
        self.pets, self.h, self.rng = pets, h, rng
        self.W, self.H = size
        self.beat, self.origin = beat, origin
        self.taken = []                 # (from, to, x, y, guardian)
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

    def _in_view(self, pts):
        """Whether a guardian walking along `pts` stays whole in the picture: its sides (0.7 h apart) and
        its head (h up) inside. Its feet are, on any of the template's lines."""
        h = self.h
        x, y = pts[:, 0], pts[:, 1]
        return bool((0.35 * h <= x).all() and (x <= self.W - 0.35 * h).all() and (h <= y).all())

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
        # guardians are taller than wide: clear means side by side with room, or a whole guardian apart up and down
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

    def step(self, t0, t_end, candidates, k):
        """Jobs at `candidates` (spots) for step `k`; returns the seeds its change spreads from,
        (time, x, y), a short sweep beside each guardian as it works."""
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
                d = norm(sx - x, sy - y)
                if d < STILL * h:       # near enough to reach from here: no little shuffle over
                    sx, sy, d = x, y, 0.0
                reach = max(free[i] + walk_time(d, h), t0)          # compared unsnapped: the beat's
                arrive = self._snap(reach, sx)                       # ripple must not pull anyone sideways
                if arrive + WORK[0] > t_end or not self._clear(sx, sy, arrive, arrive + WORK[1], i):
                    continue
                if best is None or reach < best[5]:
                    best = (arrive, q, sx, sy, d, reach)
            if best is None:
                live[i] = False
                continue
            arrive, q, sx, sy, d, _ = best
            jx, jy = pool.pop(q)
            self._depart(i, arrive - walk_time(d, h))
            leave = min(arrive + self.rng.uniform(*WORK), t_end)
            self.pets[i].stops.append((arrive, leave, sx, sy, k, None))
            self.taken.append((arrive, leave, sx, sy, i))
            free[i] = leave
            toward = 1 if jx >= sx else -1
            for f, dx in ((0.1, -0.2), (0.35, 0.05), (0.6, 0.25)):
                seeds.append((arrive + f * (leave - arrive), jx + toward * dx * h, jy))
        return seeds

    def trace(self, t0, t_end, strokes, k):
        """Step `k`'s lines: each free guardian walks to the nearest line it can draw in time and draws
        it by walking along it, never one that would take it out of the picture. Returns (seeds,
        traces): traces are (stroke index, start time, duration, points in drawing order)."""
        h, seeds, traces = self.h, [], []
        pool = {n: s for n, s in enumerate(strokes) if cumulative(s)[-1] >= 0.9 * h and self._in_view(s)}
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
                length = cumulative(pts)[-1]
                d = norm(pts[0][0] - x, pts[0][1] - y)
                reach = max(free[i] + walk_time(d, h), t0)
                arrive = self._snap(reach, pts[0][0])
                dur = trace_time(length, h)
                if arrive + dur > t_end or not self._clear(pts[0][0], pts[0][1], arrive, arrive + 0.4, i):
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
            cum = cumulative(pts)
            for f in (j / 5 for j in range(6)):
                dist = f * cum[-1]
                tt = arrive + dur * f
                seeds.append((tt, float(np.interp(dist, cum, pts[:, 0])), float(np.interp(dist, cum, pts[:, 1]))))
        return seeds, traces

    def _crosses(self, a, b, o):
        """Whether walking from a to b passes over a guardian standing at o (boxes as in _clear)."""
        (ax, ay), (bx, by), (ox, oy) = a, b, o
        L2 = (bx - ax) * (bx - ax) + (by - ay) * (by - ay)
        u = min(max(((ox - ax) * (bx - ax) + (oy - ay) * (by - ay)) / max(L2, 1e-9), 0), 1)
        px, py = ax + u * (bx - ax), ay + u * (by - ay)
        return abs(px - ox) < 0.85 * SPACE * self.h and abs(py - oy) < 1.15 * SPACE * self.h

    def farewell(self, wave_at, frame_h):
        """The goodbye: each guardian takes a last look at the finished picture (LOOK s, reviewing),
        waves where it stands from `wave_at[i]` for WAVE s, then walks briskly to the nearest edge
        whose way doesn't cross a guardian still there, and steps out of the frame. The last one out
        stops just inside that edge, turns to you and waves once more (EDGE_WAVE s) first."""
        h = self.h
        spots = [self._end(p.stops[-1]) for p in self.pets]
        leaving = []
        for i, p in enumerate(self.pets):
            prev = p.stops[-1]
            x, y = spots[i]
            if prev[5] is not None:
                done = prev[0] + trace_time(cumulative(prev[5])[-1], h)
            else:
                done = prev[1] if prev[4] >= 0 else prev[0]
            at = max(wave_at[i], done)
            self._depart(i, at)
            p.stops.append((at, at + LOOK, x, y, -4, None))
            p.stops.append((at + LOOK, at + LOOK + WAVE, x, y, -2, None))
            exits = sorted([(-0.7 * h, y), (self.W + 0.7 * h, y), (x, -0.25 * h), (x, frame_h + 1.2 * h)],
                           key=lambda e: norm(e[0] - x, e[1] - y))
            others = spots[:i] + spots[i + 1:]
            ex, ey = next((e for e in exits if not any(self._crosses((x, y), e, o) for o in others)), exits[0])
            off = at + LOOK + WAVE + walk_time(norm(ex - x, ey - y), h) / EXIT
            leaving.append((off, i, ex, ey))
        last = max(leaving)[1]
        for off, i, ex, ey in leaving:
            p = self.pets[i]
            if i == last:
                # it stops where it can still be seen whole, and waves to you before it goes
                x, y = spots[i]
                gone = p.stops[-1][1]
                if ex < 0 or ex > self.W:
                    sx, sy = (0.5 * h if ex < 0 else self.W - 0.5 * h), y
                else:
                    sx, sy = x, (1.05 * h if ey < 0 else self.H - 4)
                at = gone + walk_time(norm(sx - x, sy - y), h) / EXIT
                p.stops.append((at, at + EDGE_WAVE, sx, sy, -2, None))
                off = at + EDGE_WAVE + walk_time(norm(ex - sx, ey - sy), h) / EXIT
            p.stops.append((off, float('inf'), ex, ey, -3, None))


class Pet:
    """One guardian's way through the show. `stops` are (arrive, leave, x, y, step, path): a job
    (step 0-5) worked standing at (x, y), or drawn by walking `path`; the first stop is where it
    pops in at `appear` (step -1); at the end it takes a last look at the picture (step -4), waves
    where it stands (step -2), then walks out of the frame (step -3), the last one out waving once
    more just inside the edge (another step -2)."""

    def __init__(self, pid, start):
        self.id = pid
        self.stops = [start]


Plan = namedtuple('Plan', 'pets visits traces')


def plan(inputs):
    """The crew's whole show, planned: a pure function of plain data. Every random draw is
    SplitMix64's, in a fixed order (the guardians' appear order, their wave order, each job's work
    time as the steps are planned), so the same inputs plan the same show.

    inputs: size [W, H] and petHeight in px; intro and step in s; seed; guardians [{id, start: [x, y]}]
    in crew order; candidates, per step the spots [x, y] its jobs are done at (the ink step's are
    ignored); strokes, the template's lines [[x, y], ...], drawn by walking in the ink step;
    frameHeight, the video frame's, which the farewell walks off the bottom of.

    Returns Plan(guardians, visits, traces): the guardians with their stops; per step the
    points its change spreads from, (time, x, y); the lines drawn by walking, (stroke index,
    start, duration, points in drawing order)."""
    W, H = inputs['size']
    h, intro, step = inputs['petHeight'], inputs['intro'], inputs['step']
    starts = [intro + k * step for k in range(6)]
    end = intro + 6 * step
    rng = SplitMix64(inputs['seed'])
    crew = inputs['pets']
    order = rng.permutation(len(crew))
    wave = rng.permutation(len(crew))
    pets = []
    for i, member in enumerate(crew):
        appear = 0.04 + 0.035 * order[i]
        x, y = member['start']
        pets.append(Pet(member['id'], (appear, appear + 0.05, x, y, -1, None)))
    planner = Planner(pets, (W, H), h, rng, step * BEAT, intro)
    strokes = [np.array(s, dtype=np.float64) for s in inputs['strokes']]
    visits, traces = [], []
    for k in range(6):
        if k == INK_STEP:
            seeds, traces = planner.trace(starts[k], starts[k] + step - 0.15, strokes, k)
        else:
            seeds = planner.step(starts[k], starts[k] + step - 0.15, inputs['candidates'][k], k)
        visits.append(seeds or [(starts[k] + 0.1, W / 2, H / 2)])
    planner.farewell([end - 0.05 + 0.03 * w for w in wave], inputs['frameHeight'])
    return Plan(pets, visits, traces)


def quantized(inputs):
    """`inputs` at the precision the plan file keeps them: sizes and spots to 0.01 px, times to
    0.0001 s. Plan on these, so the file replays to the same show."""
    px = lambda v: round(float(v), 2)
    spots = lambda pts: [[px(x), px(y)] for x, y in pts]
    return {'size': [px(v) for v in inputs['size']], 'petHeight': px(inputs['petHeight']),
            'intro': round(float(inputs['intro']), 4), 'step': round(float(inputs['step']), 4),
            'seed': int(inputs['seed']),
            'pets': [{'id': m['id'], 'start': spots([m['start']])[0]} for m in inputs['pets']],
            'candidates': [spots(c) for c in inputs['candidates']],
            'strokes': [spots(s) for s in inputs['strokes']],
            'frameHeight': px(inputs['frameHeight'])}
