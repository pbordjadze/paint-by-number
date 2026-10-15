#!/usr/bin/env python3
"""The picture of the making-of show at a moment: what each step does to the layers
(making_of_layers.py), as pure functions of arrays, with no drawing in them.

At time t the show is in a step (`stage_of`) and shows one of

  photo        before the first step
  sketch       step 1: where the reveal's time T has passed, the photo's texture smears away and the
               color drains, graphite goes down on what survives, strongest structure first, and the
               photo fades to paper behind it
  blend        steps 2 to 4: layer k becomes layer k + 1 as T passes, with a soft edge; steps 3
               and 4 dip a little darker where much changes, as the paint settles
  ink          step 5: the grey of each merged region lifts as its time passes (the lines the crew
               draws are the renderer's: it passes their coverage in as `ink`)
  template     step 6: regions clear to paper under the smoothed lines
  hold         the finished drawing

`ink` is a coverage plane, 0...1 where the lines (pen strokes in step 5, outlines in step 6 and
after) darken the paper; the numbers are the renderer's too (`numbers` of template_picture is what
making_of_clip.py still draws with). Sources/MakingOf's `Compositor` is the port, the same
formulas on the same names, compared by Tests/MakingOfTests with the numbers that
tools/tests/test_making_of_layers.py writes. The numbers in the formulas are `RevealStyle`'s.
"""

import numpy as np

from making_of_layers import INK, PAPER, STYLE, sketch


def smoothstep(x):
    x = np.clip(x, 0, 1)
    return x * x * (3 - 2 * x)


def stage_of(t, intro, step):
    """-1 before the first step, 0...5 in a step, 6 once the six are over."""
    if t < intro:
        return -1
    if t >= intro + 6 * step:
        return 6
    return min(int((t - intro) // step), 5)


def settle_plane(lower, upper, style=STYLE):
    """How much the picture changes where layer `lower` becomes `upper`, 0...1: a change that
    covers much dips darker as it settles."""
    return np.clip(np.abs(upper - lower).max(axis=2) * style.settle_gain, 0, 1)[..., None]


def sketch_picture(t, photo, detextured, survivors, graphite, T, end, paper=PAPER, style=STYLE):
    """Step 1 at time t. `T`: when the change reaches each pixel; `end`: when the step ends;
    `graphite`: the multiply layer of the survivors at full strength."""
    luma = np.array(style.luma, dtype=np.float32)
    smear = smoothstep((t - T) / style.smear_ramp)[..., None]
    base = photo + (detextured - photo) * smear
    drain = smoothstep((t - T - style.drain_delay) / style.drain_ramp)[..., None]
    base = base + ((base @ luma)[..., None] - base) * drain
    drawn_at = np.minimum(T + style.graphite_delay - style.graphite_by_structure * survivors, end - style.graphite_margin)
    drawn = smoothstep((t - drawn_at) / style.graphite_ramp)[..., None]
    washed = smoothstep((t - np.minimum(T + style.wash_delay, end - style.wash_margin)) / style.wash_ramp)[..., None]
    return (base + (paper - base) * washed) * (1 - drawn * (1 - graphite))


def blend_picture(k, t, lower, upper, T, settle=None, style=STYLE):
    """Steps 2 to 4 (k = 1...3) at time t: `lower` becomes `upper` where `T` has passed. `settle`
    (steps 3 and 4) is `settle_plane`."""
    soft = style.soft_early if k < 2 else style.soft_late
    m = smoothstep((t - T) / soft)[..., None]
    pic = lower + (upper - lower) * m
    if settle is not None:
        bump = np.sin(np.pi * np.clip((t - T) / style.settle_ramp, 0, 1))[..., None]
        pic = pic * (1 - style.settle_depth * bump * settle)
    return pic


def ink_picture(t, paper, toned, lifted, T_lift, ink=None, style=STYLE):
    """Step 5 at time t: the merged regions' greys (`toned`) lift toward `lifted` as `T_lift`
    passes; `ink` is the pen's coverage."""
    lift = smoothstep((t - T_lift) / style.lift_ramp)[..., None]
    pic = paper * (toned + (lifted - toned) * lift)
    return pic if ink is None else pic * (1 - ink * (1 - INK))


def template_picture(t, paper, lifted, T_clear, ink=None, numbers=None, style=STYLE):
    """Step 6 at time t: regions clear from `lifted` to paper as `T_clear` passes. `ink` is the
    outlines' coverage; `numbers` (the clip tool's) is (how far each number has come in, the
    multiply layer of the numbers)."""
    clear = smoothstep((t - T_clear) / style.clear_ramp)[..., None]
    pic = paper * (lifted + (1 - lifted) * clear)
    if ink is not None:
        pic = pic * (1 - ink * (1 - INK))
    if numbers is not None:
        shown, multiply = numbers
        pic = pic * (1 - shown * (1 - multiply))
    return pic


def hold_picture(paper, ink=None, numbers=None, template=None, handoff=0.0):
    """The finished drawing: paper under the smooth outlines' `ink` and the numbers' multiply
    layer, `handoff` of the way (0...1) to the `template` as the SVG renders it."""
    last = paper if ink is None else paper * (1 - ink * (1 - INK))
    if numbers is not None:
        last = last * numbers
    return last if template is None else last + (template - last) * handoff


class Compositor:
    """Every picture of the show as a function of the time. `layers`: the first five of
    making_of_layers.paper_layers; `src`: anything with the `detextured`, `survivors`, `toned` and
    `lifted` of making_of_layers.derive (Sources, or a namespace of its result); `times`: when the
    change of each step reaches each pixel, (H, W) each, under `sketch`, `shading`, `paints`,
    `merged` (steps 1 to 4), `lift` (step 5) and `clear` (step 6); `intro` and `step`: the show's
    timing."""

    def __init__(self, layers, src, times, intro, step, style=STYLE):
        self.layers, self.src, self.times, self.intro, self.step, self.style = layers, src, times, intro, step, style
        self.paper = np.broadcast_to(PAPER, layers[0].shape)
        self.graphite = sketch(src.survivors, style.sketch_strengths[0], style)
        self.settle = {k: settle_plane(layers[k], layers[k + 1], style) for k in (2, 3)}

    def picture(self, t, ink=None):
        """The picture at time t; `ink`: the lines' coverage, (H, W) or (H, W, 1), where the step
        draws them."""
        k = stage_of(t, self.intro, self.step)
        T, style, layers, src = self.times, self.style, self.layers, self.src
        if ink is not None and ink.ndim == 2:
            ink = ink[..., None]
        if k < 0:
            return layers[0]
        if k == 0:
            return sketch_picture(t, layers[0], src.detextured, src.survivors, self.graphite, T['sketch'],
                                  self.intro + self.step, self.paper, style)
        if k <= 3:
            field = [T['sketch'], T['shading'], T['paints'], T['merged']][k]
            return blend_picture(k, t, layers[k], layers[k + 1], field, self.settle.get(k), style)
        if k == 4:
            return ink_picture(t, self.paper, src.toned, src.lifted, T['lift'], ink, style)
        if k == 5:
            return template_picture(t, self.paper, src.lifted, T['clear'], ink, None, style)
        return hold_picture(self.paper, ink)
