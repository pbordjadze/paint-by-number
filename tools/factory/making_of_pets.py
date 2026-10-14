"""The Lamp's pets as the making-of show's crew: their sprites, and how they move between the
stops making_of_clip.py plans for them.

Sprites come from the app's own sheets (`App/PaintByNumber/Resources/pet-<id>.webp`, the
create-pet v2 contract in `SpriteAtlas.swift`): idle, walking right and left, waving, busy and
reviewing. The motion is procedural, on top of those frames:

- paths curve a little, and a pet leans back for a moment before it sets off;
- it hops onto its next spot and squashes as it lands;
- its walk cycle runs with its speed, between 8 and 16 frames a second;
- it works in its busy pose on the hands-on steps (sketch, shading, ink) and its reviewing pose
  on the others (paints, merged, template);
- a soft contact shadow stays on the ground, smaller while it is in the air;
- pets higher in the picture are drawn a little smaller, and nearer ones over farther ones;
- they come in with a small pop, and wave together at the end.
"""

import math
import os

import numpy as np
from PIL import Image, ImageDraw

CELL = (192, 208)
ROWS = {'idle': (0, 6), 'right': (1, 8), 'left': (2, 8), 'wave': (3, 4), 'busy': (7, 6), 'review': (8, 6)}
# Who comes first when fewer than all of them work: a mix of shapes and colors.
ORDER = ['enchanted-workshop', 'dinotopia', 'snow-queen', 'scholar', 'baba-yaga', 'painter', 'glassblower',
         'medea', 'nutcracker', 'emily-dickinson', 'pirosmani', 'robber-girl', 'hedge-witch', 'storybook',
         'balanchine', 'originality', 'bulat-okudzhava', 'child-at-bedtime', 'open-source-enthusiast',
         'bible-school-teacher']
WORK_POSE = ['busy', 'busy', 'review', 'review', 'busy', 'review']


def ease(x):
    x = min(max(x, 0.0), 1.0)
    return x * x * (3 - 2 * x)


class Sprites:
    """One pet's frames by row, plus where its feet are in the cell."""

    def __init__(self, path):
        sheet = Image.open(path).convert('RGBA')
        if sheet.size != (CELL[0] * 8, CELL[1] * 11):
            raise ValueError(f'{path}: not a create-pet v2 sheet')
        self.rows = {}
        for name, (r, n) in ROWS.items():
            self.rows[name] = [sheet.crop((c * CELL[0], r * CELL[1], (c + 1) * CELL[0], (r + 1) * CELL[1]))
                               for c in range(n)]
        alpha = np.zeros(CELL[::-1], dtype=np.uint8)
        for im in self.rows['idle']:
            alpha = np.maximum(alpha, np.asarray(im)[..., 3])
        ys, xs = np.nonzero(alpha > 24)
        self.top, self.foot = int(ys.min()), int(ys.max())
        self.cx = float(xs.mean())


class Pet:
    """One pet's way through the show: `stops` are (arrive, leave, x, y, step), the first its
    starting place."""

    def __init__(self, sprites, stops, height, rng, end_time):
        self.sp = sprites
        self.stops = stops
        self.height = height            # the pet's own height on screen, feet to top
        self.end = end_time             # when the steps are over: idle, then a wave
        self.segments = []
        for (a0, l0, x0, y0, _), (a1, l1, x1, y1, k1) in zip(stops, stops[1:]):
            dx, dy = x1 - x0, y1 - y0
            d = math.hypot(dx, dy)
            bend = rng.uniform(0.10, 0.22) * rng.choice([-1, 1])
            cx, cy = (x0 + x1) / 2 - dy * bend, (y0 + y1) / 2 + dx * bend
            ts = np.linspace(0, 1, 17)
            px = (1 - ts) ** 2 * x0 + 2 * (1 - ts) * ts * cx + ts ** 2 * x1
            py = (1 - ts) ** 2 * y0 + 2 * (1 - ts) * ts * cy + ts ** 2 * y1
            length = float(np.hypot(np.diff(px), np.diff(py)).sum())
            self.segments.append((l0, a1, (x0, y0), (cx, cy), (x1, y1), max(length, d)))
        self.facing = 'right'

    def _at(self, seg, u):
        _, _, (x0, y0), (cx, cy), (x1, y1), _ = seg
        x = (1 - u) ** 2 * x0 + 2 * (1 - u) * u * cx + u * u * x1
        y = (1 - u) ** 2 * y0 + 2 * (1 - u) * u * cy + u * u * y1
        tx = 2 * (1 - u) * (cx - x0) + 2 * u * (x1 - cx)
        return x, y, tx

    def state(self, t):
        """(x, y, lift, row, frame, sx, sy, alpha) at time t."""
        h = self.height
        alpha = ease(t / 0.35)
        pop = 1 + 0.12 * math.sin(math.pi * min(t / 0.35, 1.0))
        first = self.stops[0]
        if t < first[1]:
            return first[2], first[3], 0.0, 'idle', int(t * 6), pop, pop, alpha
        for i, seg in enumerate(self.segments):
            leave, arrive = seg[0], seg[1]
            a_next, l_next = self.stops[i + 1][0], self.stops[i + 1][1]
            if t < leave:
                break
            if t < arrive:
                span = arrive - leave
                lean = min(0.09, 0.22 * span)
                dt = t - leave
                if dt < lean:                                   # a breath before it sets off
                    w = math.sin(math.pi * dt / lean)
                    x, y = seg[2]
                    return x, y, 0.0, self.facing, 0, 1 + 0.06 * w, 1 - 0.07 * w, alpha
                u = ease((dt - lean) / (span - lean))
                x, y, tx = self._at(seg, u)
                if abs(tx) > 1:
                    self.facing = 'right' if tx > 0 else 'left'
                speed = seg[5] / max(span - lean, 0.05)
                rate = min(max(speed / h * 8, 8), 16)          # a cycle of 8 frames per body height
                frame = int((dt - lean) * rate)
                lift = h * 0.16 * math.sin(math.pi * min(max((u - 0.62) / 0.38, 0), 1))
                return x, y, lift, self.facing, frame, 1.0, 1.0, alpha
            if t <= l_next or i + 1 == len(self.segments):
                x, y, k = self.stops[i + 1][2], self.stops[i + 1][3], self.stops[i + 1][4]
                land = t - a_next
                sx = sy = 1.0
                if land < 0.12:                                 # the landing
                    w = math.sin(math.pi * land / 0.12)
                    sx, sy = 1 + 0.08 * w, 1 - 0.1 * w
                if t <= l_next:
                    return x, y, 0.0, WORK_POSE[k], int(land * 10), sx, sy, alpha
                if t < self.end + 0.15:
                    return x, y, 0.0, 'idle', int(t * 6), sx, sy, alpha
                return x, y, 0.0, 'wave', int((t - self.end) * 7), 1.0, 1.0, alpha
        last = self.stops[-1]
        return last[2], last[3], 0.0, 'idle', int(t * 6), 1.0, 1.0, alpha

    def draw(self, canvas, t, fade, picture_h):
        x, y, lift, row, frame, sx, sy, alpha = self.state(t)
        alpha *= fade
        if alpha <= 0.01:
            return
        frames = self.sp.rows[row]
        im = frames[frame % len(frames)]
        depth = 0.9 + 0.16 * min(max(y / picture_h, 0), 1)
        scale = self.height * depth / (self.sp.foot - self.sp.top)
        w = max(1, round(CELL[0] * scale * sx))
        hh = max(1, round(CELL[1] * scale * sy))
        sprite = im.resize((w, hh), Image.LANCZOS)
        if alpha < 0.999:
            a = sprite.getchannel('A').point(lambda v: int(v * alpha))
            sprite.putalpha(a)
        foot = self.sp.foot * scale * sy
        left = round(x - self.sp.cx * scale * sx)
        top = round(y - lift - foot)
        sw = self.height * depth * 0.42 * (1 - 0.35 * lift / max(self.height * 0.16, 1))
        sh = max(2, round(sw * 0.44))
        shadow = Image.new('RGBA', (max(2, round(2 * sw)), sh), (0, 0, 0, 0))
        ImageDraw.Draw(shadow).ellipse((0, 0, shadow.width - 1, sh - 1), fill=(52, 42, 48, int(46 * alpha)))
        put(canvas, shadow, round(x - sw), round(y - sh / 2))
        put(canvas, sprite, left, top)


def put(canvas, im, left, top):
    """Composites `im` at (left, top), clipped to the canvas."""
    x0, y0 = max(left, 0), max(top, 0)
    x1, y1 = min(left + im.width, canvas.width), min(top + im.height, canvas.height)
    if x0 >= x1 or y0 >= y1:
        return
    canvas.alpha_composite(im.crop((x0 - left, y0 - top, x1 - left, y1 - top)), dest=(x0, y0))


def load(resources, ids):
    return {i: Sprites(os.path.join(resources, f'pet-{i}.webp')) for i in ids}
