# W3 — Gradient-aware palette allocation (Opus 5.5) — report

Branch `wt/w3-gradient`, head `7f4bde1`. **Acceptance not met**: the spec's ramp weight does not
reduce the parrots' bokeh rings, and nothing tried reached ≤ 3 rings within +3 % mean ΔE. Shipped:
the metric only; pipeline output byte-identical; `pipelineVersion` untouched.

## Landed
- `Segmentation/BandRings.swift` (pinned API): regions whose shared border is weak (mean photo
  step < `contrast` × paint difference, true OKLab) over ≥ `fraction` of its length; on
  `RegionAdjacency.boundarySteps` over the final regions (fixed 32-row chunks); image frame not
  counted; size mismatch / malformed segmentation → 0.
- stats.json `bandRings`; eval caption `rings=`.
- regression.py: `bandRings` in `BASELINE_KEYS`, "rings" column — **informational**, not the
  ×1.10 band: ±1 noise on the decoded JPEGs moved it a lot (barn c24 40→62, c150 29→45,
  lighthouse c24 22→11), and CI decodes with another Pillow. Self-test 50 checks.
- Baseline regenerated (only `bandRings` and `totalMs` changed; templates "same").
- CLAUDE.md: `bandRings` in the stats list; informational in the regression bullet.
- `BandRingsTests` (5): 8-ring radial ramp counts 8; same regions on a hard-edged photo count 0;
  thresholds decide; degenerate → 0; deterministic sky scene. No `PaletteAllocationTests`
  (no allocation change kept).
- Results: 106 tests in 9 suites passed; regression 18 cases pass.

## Measured (34 photos: samples, kodim01–24, astronaut/chelsea/coffee/rocket; hand-made soft
ellipse importance maps for astronaut, chelsea, coffee, parrots in /tmp/pbn-w3/importance/)
Baseline sums: c24 rings 1441 / regions 12697 / tiny 89, mean ΔE 0.0351, p95 0.0971; c12 rings
890 / 4726; c24i (n=4) rings 301 / 836. Parrots c24: 107 of 202 regions are rings.

Sweep (rings / mean ΔE vs baseline, c24 n=34):
- spec grid 3×3: rings +2.1…+4.9 %, ΔE −1.0…+0.3 % (c24i rings +0.3…+13.6 %)
- spec pick 0.012/0.3: rings +2.5 %, ΔE 0 % (c24i +6.6 %, +1.0 %)
- 6 ramp-weight variants: rings +0.8…+5.4 %, ΔE −0.1…+0.9 %
- ring fusion at band tolerance (importance²): rings −16.5 %, ΔE +6.2 % (c24i +7.3 %)
- same at 1.5×: rings −34 %, ΔE +12.6 % (c24i +17.6 %)
The parrots palette keeps the same grey ladder under every allocation variant.

## Why the spec's design can't meet the target
- The bokeh greys belong to the subject (white faces, black stripes, beaks use them); nearest-paint
  labelling cuts the bokeh at each.
- Fallback importance rates the bokeh 0.48–0.61, like the body (0.56): a ramp counts as coherent
  structure; local steps don't separate bokeh from subject either.
- k-means always spends all 24 paints; the spec's ramp+spots scene ends with 9 neutrals in baseline
  and variants alike, so its "≤ 4 ramp paints" test can't pass this way.

## Crops
Parrots bokeh: baseline ~5 rings, c24i ~4, every allocation variant 4–5, Q1 ~4, Q2 3 (light grey
turns khaki). kodim03: Q1 flattens the cap, Q2 caps and wall (rules fusion out). Lighthouse/regatta
skies unchanged. Experiments: /tmp/pbn-w3/experiments.diff.

## Decision requested
≤ 3 rings needs fusing tones ~0.15 apart in unimportant ramps: +6…13 % mean ΔE and flattened
subjects with today's fallback importance. Either relax the ΔE budget or fix the fallback importance
so ramps don't count as structure (pipeline-wide).
