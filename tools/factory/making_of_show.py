#!/usr/bin/env python3
"""The making-of show, built once and then a pure function of the time: the factory's twin of
Sources/MakingOf's `Show`, which it is the reference of. The clip tool (making_of_clip.py) plays it
with Pillow; the app's view plays Sources/MakingOf's with Core Graphics and Metal.

    show = Show(snapshots, svg, spec, seed=7)
    frame = show.frame(t)             # what to draw at t, as plain data
    picture = show.composite(frame)   # the picture of that frame, float32 (H, W, 3)

Building runs the whole pipeline of the show once, from the folder `pbn generate --snapshots` writes
and the template's svg: the crew's inputs (making_of_inputs.py), the crew's plan (making_of_pets.py),
the layers and the compositor (making_of_layers.py, making_of_compose.py), the fields of when each
step's change reaches each pixel and the schedules of the lines and numbers (making_of_reveal.py).

`frame(t)` is {time, step, picture: {stage, time, handoff}, ink: [{stroke, points, value}],
numbers: [alpha], seed_rings: [{x, y, radius, alpha}], sprites: [sprite_draw, back to front],
card: {step, caption, methods, opacity, footnote_opacity} or None}, all places in pixels of the
snapshots' picture; Sources/MakingOf's `ShowFrame` has the same, and its doc comment says what a view
draws from it. The tests write a few of these for the small show fixture (`frames-small.json`) for
the Swift port to be compared with.

Changing the show means changing the two together: the cards' and rings' timing is
making_of_reveal.py's, the guardians' look making_of_pets.py's, the layers' look
making_of_layers.py's.
"""

import math
import sys
import os

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import making_of_compose as compose  # noqa: E402
import making_of_exact as exact  # noqa: E402
import making_of_inputs as inputs  # noqa: E402
import making_of_layers as layers  # noqa: E402
import making_of_pets as pets  # noqa: E402
import making_of_reveal as reveal  # noqa: E402

CARD_BAND = inputs.CARD_BAND


def crew_inputs(snapshots, svg, spec, seed, ids=None, pet_height=None, exit_band=CARD_BAND):
    """The pictures, the template and what the crew is planned from (`making_of_inputs.build`), for the
    first `ids` of the spec's crew (default all of it). Configures making_of_pets from the spec."""
    pets.configure(spec)
    ids = ids or pets.ORDER[:len(spec['crew']['pets'])]
    pictures = inputs.Pictures(snapshots)
    template = inputs.Template(svg, pictures.size[0])
    built = inputs.build(pictures, template, spec, seed, ids, exit_band=exit_band, pet_height=pet_height)
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


class Show:
    """The show, built from `snapshots` (the folder `pbn generate --snapshots` writes) and `svg` (its
    template.svg) for the spec (a dict, making-of.json) and `seed`. `ids` and `pet_height` override the
    crew and the guardians' height as in making_of_inputs.build; `metrics` maps a guardian's id to its
    sheet's (top, foot, cx) in cell pixels (pet-metrics.json, or Sprites(...).metrics).

    Attributes the frame tools read: `size` (W, H), `duration`, `spec`, `built` (making_of_inputs.Built),
    `planned` (the crew's plan), `times` (when each step's change reaches each pixel, float32, under
    the Compositor's names), `compositor`, `strokes` (making_of_reveal.stroke_schedule),
    `number_times`, `seeds`, `spread`, `line_width`."""

    def __init__(self, snapshots, svg, spec, seed=7, ids=None, pet_height=None, metrics=None, exit_band=CARD_BAND):
        pictures, template, built = crew_inputs(snapshots, svg, spec, seed, ids, pet_height, exit_band)
        self.spec, self.seed, self.built, self.metrics = spec, seed, built, metrics or {}
        for member in built.inputs['pets']:
            if member['id'] not in self.metrics:
                raise KeyError(f"no sprite metrics for {member['id']}")
        self.size = (W, H) = pictures.size
        self.line_width = template.line_width
        intro, step = float(spec['timing']['intro']), float(spec['timing']['step'])
        self.intro, self.step = intro, step
        self.duration = intro + reveal.STEPS * step + float(spec['timing']['outro'])
        self.pet_height = built.inputs['petHeight']
        self.planned = planned = pets.plan(built.inputs)
        self.seeds = built.seeds

        shape = (H, W)
        T = [reveal.step_arrival(k, planned.visits[k], shape, intro, step, seed) for k in range(reveal.STEPS)]
        palette_labels, palette_count = exact.label_regions(exact.color_keys(pictures.palette))
        labels, count = built.sim_labels, built.sim_n
        paint_times, self.spread = reveal.paint_flow(
            built.seeds, built.paint_of, len(built.paint_keys), T[2], palette_labels, palette_count, intro, step)
        per_pixel = lambda per_region, regions: per_region[regions].astype(np.float32)
        clear = reveal.region_min(T[5], labels, count)
        self.times = {'sketch': T[0].astype(np.float32), 'shading': T[1].astype(np.float32),
                      'paints': per_pixel(paint_times, palette_labels),
                      'merged': per_pixel(reveal.region_min(T[3], labels, count), labels),
                      'lift': per_pixel(reveal.region_min(T[4], labels, count), labels),
                      'clear': per_pixel(clear, labels)}
        stages = layers.Stages.read(snapshots, None, spec['sketch'], spec['tones'])
        self.compositor = compose.Compositor(stages.layers(), stages, self.times, intro, step)

        strokes = [np.array(s) for s in built.inputs['strokes']]
        self.strokes = reveal.stroke_schedule(
            strokes, planned.traces, T[reveal.INK_STEP], T[reveal.TEMPLATE_STEP], intro, step,
            float(spec['outlines']['grid']), seed)
        self.number_times = reveal.number_times(
            built.numbers, clear, labels, T[reveal.TEMPLATE_STEP], planned.visits[reveal.TEMPLATE_STEP],
            intro, step, self.pet_height)

    def frame(self, t):
        """What to draw at time `t`: see the module's docstring."""
        spec, intro, step = self.spec, self.intro, self.step
        stage = compose.stage_of(t, intro, step)
        k = stage if 0 <= stage < reveal.STEPS else None
        ink = [{'stroke': i, 'points': points, 'value': value} for i, points, value in
               reveal.lines_at(self.strokes, t, intro, step, float(spec['outlines']['inkRamp']),
                               float(spec['outlines']['relax']), self.pet_height)]
        numbers = [pets.ease((t - at) / reveal.NUMBER_FADE) for at in self.number_times] \
            if stage >= reveal.TEMPLATE_STEP else []
        rings = []
        if stage == 2:
            for seed in self.seeds:
                ring = reveal.seed_ring(seed, self.spread[seed[3]], t, intro, step,
                                        float(spec['seeds']['dot']), float(spec['seeds']['fade']))
                if ring:
                    rings.append(ring)
        fade = reveal.crew_fade(t, self.duration)
        drawn = []
        if fade > 0:
            for pet in self.planned.pets:
                state = pet.state(t)
                d = pets.sprite_draw(pet.id, state, t - pet.appear, fade, self.pet_height, self.size[1],
                                     self.metrics[pet.id])
                if d:
                    drawn.append((state[1], d))
        drawn.sort(key=lambda pair: pair[0])           # farther ones first; a stable sort keeps the crew's order
        card = None
        if k is not None:
            fade_in = reveal.card_fade(k, t, intro, step)
            if fade_in > 0:
                opacity = float(spec['cards']['opacity']) * fade_in
                card = {'step': k, 'caption': spec['steps'][k]['caption'], 'methods': spec['steps'][k]['methods'],
                        'opacity': opacity, 'footnote_opacity': opacity * float(spec['cards']['footnote'])}
        return {'time': t, 'step': k, 'picture': {'stage': stage, 'time': t, 'handoff': reveal.handoff(t, intro, step)},
                'ink': ink, 'numbers': numbers, 'seed_rings': rings, 'sprites': [d for _, d in drawn], 'card': card}

    def composite(self, frame):
        """The picture of `frame`, float32 (H, W, 3): the layers blended as its recipe says, with its lines
        rasterized by `ink_coverage` at the template's line width. The numbers, the hand-off, the rings,
        the guardians and the card are the renderer's, as in Sources/MakingOf's `Show.composite`."""
        W, H = self.size
        ink = ink_coverage(frame['ink'], W, H, self.line_width) if frame['ink'] else None
        return self.compositor.picture(frame['picture']['time'], ink)
