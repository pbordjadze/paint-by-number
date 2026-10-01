# W1 review — W1b tuning + W1c app (Opus 5.5)

Branch `wt/w1c-auto-app`, head `8e4312b`. No blocker. 147 tests in 11 suites pass; regression 24
cases; self-test 74 checks; strings ok (302).

## Major (open; each needs a re-tune)
1. Region model and bands were calibrated on pbn's fallback importance map, which rates busy texture
   important; the app's Vision maps give far fewer areas. CI simulator: lighthouse 159 areas in the
   app (28 colors) vs 410–546 in pbn at 28/0.4–0.6; parrots 139 (40, "Detailed") vs 279 at 40/0.7.
   With uniform 0.25/0.4 maps as a Vision stand-in, full templates have 0.64×/0.75× the areas Auto
   estimated (p10 0.42); with the fallback 1.05×; the fitted growth exponent drops from 0.46–0.63 to
   0.17–0.38. In the app the "~X min" lands below the target and more photos fall short of their
   band (0.4 map: Relaxed 8–45 min, Detailed 13–62).
2. The winner among neighbours is mostly noise: deterministic for the same pixels (taskset 0/0-1/0-3
   byte-identical; ±1 on one pixel flipped 0/36), but a JPEG q92 re-save changed the Relaxed winner on
   11/12 photos (dog 20→32 colors, cake 22→34, borsen 28→40). Candidate totals differ by 0.001–0.005,
   the size a re-encode moves them; the 0.001 tie window is below that. Suggestion: leave the center
   only when a neighbour wins by more than ~0.004.
3. Night-moon at Relaxed clearly worse than defaults: chromatic fraction 0.008 (dark photos have low
   absolute chroma) → monochrome cut → 16 colors (20 wins); lamp post and tree line vanish, orange glow
   shrinks; ΔE 0.0195 vs 0.0165; 6 min. Smoke-haze (18 colors) loses the cool sky. Suggestion: chroma
   relative to lightness, or skip the cut when the palette curve hasn't flattened.

## Minor
4. Fixed `31827c9`: Painting Length footers per choice (medians on 34 large photos: Quick 22, Relaxed
   37, Detailed 65 min; small photos 15/20/25): "Suggested settings aim for about 15 minutes of
   painting." / "…about half an hour of painting. Small or simple photos make shorter paintings." /
   "…about an hour of painting. Small or simple photos make shorter paintings."
5. Fixed `9ed9205`: CLAUDE.md W1 notes (Auto/ API, quantized features, decisions reproducible and
   never stored, bands + region model, `pbn suggest`, `generate --auto`, `auto_sheet.py`, the auto
   regime and `tools/baseline/auto.json`, the pbn-vs-Vision caveat).
6. Fixed `8e4312b`: doc comments ("starting values"; "same photo → same settings" → same pixels).
7. Left: `score(fullSize:)` defaults detail to 0.5 (only `choose` passes `fullSize`, with detail).
8. Left: if `choose` fails, the photo generates on whatever the sliders hold (may be the previous
   photo's suggestion); logged, chip hidden.

## Checked fine
Canvas formula (`GenerationSettings.workingSize`: 1100 + 1000 × detail, ≤ 1.5× source; decode at
2048; `sourceSize` passed); concurrency (`@concurrent`/nonisolated helpers, first-draft handler formed
nonisolated, load counter, cancellation flag); races (sliders blocked while choosing, `adopt` drops a
late draft, `makeDraft` waits, Reset no-op without a decision, share-sheet open builds a new flow);
saved data (tolerant decode, no bump, regeneration keeps fields; no `defaultColorCount` reads);
Settings picker; chip VoiceOver ("Settings, Suggested for this photo" / "Reset to Suggested, Custom");
keyboard layout fix sound.

## Acceptance (Relaxed, full size, 69 photos)
Spec criterion 14/69 (20 %); worse on both 2 (kodim12, kodim16, ~0.001); in band 41 (defaults 36).
At equal painting time (24 colors over detail 0.1–0.9 interpolated at Auto's region count): 57/69
(83 %) equal or better; median ΔE ratio 0.971 at 1.12× regions. By eye (15 photos): mostly
equivalent; hedgehog a real win (101 → 50 min, still readable); dog 53 vs 41 min for the same look;
kodim08 and smoke-haze slightly flatter; night-moon clearly worse. Verdict: judging at equal painting
time is acceptable, but the gain (~3 % ΔE) is within decision noise; Auto's real value is hitting a
length, which major 1 undercuts. "Never clearly worse" is not met (night-moon).
