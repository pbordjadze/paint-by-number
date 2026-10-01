# W3, round two — second opinion and root-cause attempts (Opus 5.5)

Branch `wt/w3b-ramps`: no commits (nothing shipped). Pipeline, tests, baseline untouched.

## Round one verified (agree)
- Baseline reproduced byte-identically (parrots c24: 107 rings / 202 regions, mean ΔE 0.0352,
  p95 0.0767).
- The ramp factor was applied where the spec says (`PaletteBuilder.histogram`, before binning),
  but the bokeh's step (0.0091; grain ~half, coherent slope 0.005) gives factor 0.76, importance
  0.54 restores it to 0.89, bin gamma 0.6 to 0.93: almost no effect — and the bokeh greys are the
  subject's greys anyway.
- `bandRings` is computed correctly (working size, no draft/working mismatch) but too coarse to be
  the acceptance count (the red body and large background regions count too); rings were counted
  by eye on crops.
- Addition: fallback importance in the bokeh comes mostly from the centre bias (0.4 × centre
  0.5–0.82 vs 0.4 × busy 0.35), not from ramps-as-structure; ignoring ramps only moves bokeh
  importance 0.54 → 0.50.

## Approaches (34 photos, vs baseline; parrots bokeh rings by eye)
| Variant | bokeh rings | c24 rings | c24 mean ΔE | c24i mean ΔE | parrots mean ΔE |
|---|---|---|---|---|---|
| baseline | 5 | 1441 | 0.0351 | 0.0376 | 0.0352 |
| V1 defocus-gated importance | 5 | −3.7 % | +0.5 % | – | 0.0374 |
| V2 V1 + palette ramp weight 0.1 | 5 | −7.8 % | +0.9 % | +1.3 % | 0.0364 |
| V3 ramp band fusion ×1.0 | 4, white core lost | −10.8 % | +5.5 % | +4.9 % | 0.0390 |
| V4 fusion ×1.3 | 4, white core lost | −13.9 % | +10.0 % | +7.1 % | 0.0411 |
| fusion ×1.6 (parrots) | 2, background green | – | – | – | 0.0499 |
| L12 coarse-ladder labelling (0.12) | 3, white core kept | −3.5 % | +6.7 % | +4.2 % | 0.0407 |
| L12 without the new importance | 5 | −0.2 % | +2.6 % | – | 0.0372 |
L12 costs 7–30 % on astronaut, coffee, espresso, rocket, kodim06/12/16/19/20 and greys kodim16's
blue sky; gated to stay within budget it no longer fires on parrots. No variant gave the red
parrot's face a paint (15 paints in the face box at baseline, 12–14 in variants).

## Decision: not shipped — trade-off for the owner
A ramp cut into tones Δ apart has mean error ≈ Δ/4; halving the bokeh's tones roughly doubles the
error over every ramp, and the only paints freed are greys the subject also uses. ≤ 3 rings costs
~+16 % mean ΔE on parrots and +4–7 % corpus-wide once skies are gated in. If a ~+7 % budget is
acceptable, build on L12 (ladder per color family so skies keep their hue; blended gate edge).
Otherwise it needs a better importance signal than the fallback: the on-device Vision subject mask.
Experiments: /tmp/pbn-w3b/experiments.diff (env-switched), crops under /tmp/pbn-w3b.
