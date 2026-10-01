# W3 — Gradient-aware palette allocation

Model: Opus 5.5. Reviewer: Opus 5.5 (adversarial, with its own baseline build, as in wave 1).

## Goal

Smooth gradients (sky, bokeh, a shaded wall) stop eating paints they cannot use well. At
the default 24 colors the parrots' bokeh highlight still posterizes into 4–5 nested rings
because five neutral paints are spent on a structureless background (wave 1 research,
`handoff/research.md` on `claude/resume-notes`, review item 3). After W3 a ramp earns the
2–3 tones it needs and the freed paints go to the subject, while subject gradients (a
cheek, a petal) keep their modelling.

## Today (wave 1)

- `PaletteBuilder.histogram` weights each sample by `(0.1 + importance²) × (1 + saliency ×
  contrast)` into a 64³ OKLab histogram, then compresses bin weights with `histogramGamma =
  0.6`. Nothing in the weight knows whether a pixel sits inside a ramp.
- `BandMerging` fuses a ramp's bands after labelling when the boundary is weak and the paints
  are close; `PaletteRefiner` re-spends paints freed by fusing. That fixes 150-color banding
  but not the 24-color case: the ring paints there are 3–7 JND apart, so fusing them would
  be visibly wrong, and the problem is allocation.
- Raising `paletteSaliency` to 2 or 3 did not change the neutral count (research notes).
- `RegionAdjacency.boundarySteps` gives the mean image step along each boundary; the research
  measured ring boundaries at 5–15 % of the paint difference versus 30–60 % at real
  contours.

## Design

### Ramp weight in the histogram

Add a per-sample factor to `PaletteBuilder.histogram`:

```
ramp(i)   = clamp(step(i) / rampStep, rampFloor, 1)       // step: blurred local color step
weight(i) = (0.1 + imp²) × (1 + saliency × contrast) × lerp(ramp(i), 1, imp)
```

- `step(i)`: the summed step magnitude `w` from `StructureMap` (already computed, box-blurred
  twice over `structureRadius`), i.e. how much color changes around the pixel. Inside a
  gentle ramp it is small; at contours and in texture it is large.
- `rampStep`: the step at which a sample counts fully; start at `0.012` OKLab per pixel at
  the working size (ramps measured in the research are well below this; edges well above).
- `rampFloor`: the least a ramp sample can weigh; start at `0.3`. Ramps still get paints,
  just fewer, and large ramps still dominate tiny ones.
- Importance restores the weight (`lerp(…, 1, imp)`): a shaded cheek or a petal keeps its
  tones; a background sky gives some up.

Both constants go into `SegmentationParameters` with doc comments; neither depends on the
user's settings at first (if tuning shows bold templates want a lower floor, tie it to
`detail` and say why).

### Spend the freed paints where they count

With fewer paints in ramps, the swap search already moves them to where the penalized error
is largest. Verify on the sheets that they land on the subject (the red parrot's face, the
cat's eye) and not on more background tones; if they do not, raise the penalty knee's
sensitivity for high-importance samples (one constant), and report what happened either way.

### The metric: `bandRings`

Add to the pipeline's reported stats (`pbn generate` → `stats.json`, also exposed as a
PaintCore function so W1 can reuse it):

```swift
/// Regions whose boundary is weak (mean image step below `contrast` × the paint difference)
/// over at least `fraction` of their perimeter: the rings a ramp posterizes into.
public static func bandRings(_ segmentation: Segmentation, working: RGBAImage,
                             contrast: Float = 0.25, fraction: Float = 0.7) -> Int
```

Computed from `RegionAdjacency.boundarySteps` on the final regions (deterministic, fixed
chunk sums). Add it to `BASELINE_KEYS` in `tools/regression.py` with a tolerance band
(`≤ baseline × 1.10`), and to the eval sheet caption.

## Procedure

1. Build the baseline `pbn` from the branch head before any change and keep it
   (`/tmp/pbn-w3/pbn-baseline`); run `tools/eval.py` at 24/0.5 and 150/1.0 on the six samples,
   the Kodak suite and astronaut/chelsea/coffee/rocket (with hand-made importance maps for the
   three subjects, as the research did). Record `bandRings`, regions, tiny regions, mean and
   p95 ΔE, palette size.
2. Implement the ramp weight; sweep `rampStep ∈ {0.008, 0.012, 0.018}` × `rampFloor ∈ {0.2,
   0.3, 0.45}`; pick by: parrots 24-color bokeh ring count (target ≤ 3, measured by eye on
   the crop and by `bandRings`), astronaut cheek modelling preserved (p95 ΔE on the face
   region within +5 % of baseline), regatta and lighthouse skies ≤ 3 tones with no visible
   step in the painted preview, overall mean ΔE within +3 % of baseline at 24 colors.
3. Bench (`pbn bench`, interleaved A-B-A-B, 3 runs): within +3 % total in every regime; the
   factor is one multiply per sample.
4. Regenerate the regression baseline with `--update --sheets`, look at every sheet, commit
   the baseline with the change. Do not touch `pipelineVersion`.
5. Report with before/after tables and crops, as the wave-1 research report did.

## Tests (`Tests/PaintCoreTests/PaletteAllocationTests.swift`)

- Synthetic: a gentle vertical grey ramp over two thirds of the frame plus eight distinct
  small colored spots on the rest, importance flat: at 24 colors the ramp receives ≤ 4 paints
  (count paints whose refit color lies on the ramp's line) and every spot keeps a paint
  within ΔE 0.05 of its color. The same scene with importance 1 on the ramp receives ≥ 6
  ramp paints (subject gradients keep tones).
- `bandRings` on a synthetic ramp sliced into bands counts them; on a hard-edged target of
  concentric rings with the same paints it counts 0.
- Determinism and monotonicity tests in `SegmentationTests` still pass; `regression.py
  --self-test` covers the new band.

## CLAUDE.md

Add the ramp weight (why it exists, what tunes it) to the segmentation notes, `bandRings` to
the stats list ("add fields, never rename them"), and the regression band.

## Acceptance

- Parrots at 24/0.5 (no importance map and with it): bokeh ≤ 3 rings; the red parrot's face
  gains at least one paint; eye rings intact.
- No sample loses visible subject modelling (reviewer checks astronaut, chelsea, hibiscus).
- Regression gate green with the new baseline; bench within budget; tests pass.

## Risks

- Down-weighting ramps could starve a photo that is mostly gradient (a sunset). The floor
  and the importance term bound this; the sunset case (Kodak 03, 16) is in the sweep.
- W1's tuning depends on this landing first; keep the change small and land it early.
