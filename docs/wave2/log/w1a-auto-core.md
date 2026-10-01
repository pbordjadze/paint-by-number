# W1a — Suggested settings, core (Opus 5.5) — report

Branch `wt/w1a-auto-core`, head `baf9e86`. Release build, full tests (122 in 9 suites) and the
regression gate (24 cases, the 18 existing byte-identical; self-test 73 checks) pass. Constants are
the spec's untuned starting values.

## API deviations (source-compatible)
1. `analyze`/`choose` take `sourceSize: (width: Int, height: Int)? = nil` after the image (nil =
   the image is the photo). The app must pass the photo's own size when it hands `choose` the
   draft, or "source under 900 px" always fires. Both reduce larger inputs to the draft size.
2. `score` takes `fullSize: … = nil` (the full template's canvas) so time is estimated at full
   size; region counts grow ~area^0.6 on the samples (`regionAreaExponent`), not by area.
3. `AutoScore.bandPenalty` added (decision JSON explains its total).
4. Public additions: `PaintingLength.colorBand/detailCenter/detailBand/timeBand` (colors 6–24 /
   8–40 / 12–72; detail center ± 0.35), `AutoSettings.smoothnessBand` (0.25–0.8), `draftLongSide`,
   `draftImage(from:)` (mirrors `CreateModel.prepare`), `importance(for:map:)`, `scoreFormula`.
5. `structureDensity` = share of busy pixels with coherent gradients (the spec's "mean coherent /
   own p90" rated a 2-px checkerboard high and a sharp rectangle low); ramps use a blurred slope
   that must agree at two scales (the spec's 0.002 threshold rejected real skies).

## Contents
- `Sources/PaintCore/Auto/`: every spec type and function; features quantized to 3 decimals;
  fixed-chunk ordered sums; seeded. `choose`: center → `firstDraft` before scoring → rest in
  parallel (≤ one per core); a shared latch stops other threads' candidates once one sees
  cancellation. "Top third" thresholds measured on 28 corpus photos: chroma spread ≥ 0.03,
  structure ≥ 0.083.
- `Segmentation/BandRings.swift` (the pinned signature; border excluded from the perimeter) —
  W3's version is canonical.
- `PaintingTime.estimate` in PaintCore; the app's `Artwork.swift` delegates;
  `RenderingTests.swift` qualifies `PaintByNumber.PaintingTime`.
- `pbn suggest` (table + `decision.json`; `--out` also writes draft/working/candidate previews),
  `generate --auto [--length] [--hints] [--candidates]` (`auto`, `analysis` in stats.json),
  `bench` "suggest" line.
- `tools/auto_sheet.py`, eval.py caption, regression `auto-relaxed` regime (hard: inside bands;
  informational vs `tools/baseline/auto.json`; `--update` writes both). No workflow change needed.
- `AutoSettingsTests` (21); fixtures `auto-parrots.json` + `auto-parrots-draft.ppm` (no JPEG
  decoder on Linux); settings/winner/analysis exact, scores to 1e-4.

## Budget
`pbn suggest` (5 candidates, Relaxed) 370–710 ms per sample on the loaded 4-core box (M1 budget
1.5 s). Lighthouse ~420 ms: prepare 18, analysis 22 (curve 5), center 101, scoring 11 each,
remaining 4 in parallel 267. Pipeline runs dominate; no optimization.

## Looks off (for W1b)
- Time bands vs small photos: 768-px sources give ≤ ~800 regions even at 150/1.0, so every
  Relaxed/Detailed candidate is below band and the penalty pushes to the most regions.
- Detail barely moves the draft above 0.5: Detailed sometimes picks fewer colors than Relaxed.
- Monochrome rule misfires on regatta (10.8 % chromatic, vivid sails → ×0.6 → 18 colors).
- Draft `bandRings` high (50–55 % of parrots' regions); W3's version replaces it.
- `importanceEntropy` ≈ 0.994 everywhere with the fallback map (never below 0.2); no rule reads it.
