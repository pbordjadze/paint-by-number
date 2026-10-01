# W1b — Suggested settings, tuning (Opus 5.5) — report

Branch `wt/w1b-auto-tuning`, head `6efa8eb`. Full log: `auto-tuning.md`; corpus: `auto-corpus.md`.
126 tests pass; regression 24 cases all "same" (legacy baseline not rewritten, only timings
differed); self-test 73 checks.

## Changes (`48e6bb9`, every constant commented with what it was tuned on)
- Time bands recalibrated to what the app generates (photos kept ≤ 2048 px; canvas 1100 + 1000 ×
  detail px; 35 large photos: median ~380 regions / 19 min at detail 0.3, 680 at 0.5, 1350 at 0.9):
  Quick 8–25 min, Relaxed 20–50, Detailed 40–120 (overlapping); Detailed center detail 0.7 → 0.8;
  3 s/region kept. The spec's Relaxed band needed 800–2400 regions, which almost no photo reaches.
- Draft → full region growth area^(0.29 + 0.42 × detail) instead of area^0.6 (fitted on 730
  cases; rms log error 0.29 → 0.22).
- Scoring: overshooting the band costs more (0.05 → 0.15), undershooting less (0.01); a small price
  per paint (0.0001; noise otherwise pushed Relaxed to 40 paints); tighter ties (0.001) broken by
  time nearest the band's middle (fewer-regions tie-break made a Detailed painting shorter than
  Relaxed).
- Monochrome cut ×0.6 fades in below 15 % chromatic pixels (regatta misfire fixed).
- Dropped with evidence: the ramp rule (ΔE −0.0005, more rings); "−0.1 detail under 900 px"
  (scores moved detail up in 77/105 decisions, never down).
- Palette curve and noise kept at 4 decimals (fixes the coarse color knee); importance entropy
  measured above the map's 0.2 floor (now 0.72–0.96; no rule reads it); noise reference 0.01 kept
  (draft downscale averages noise; rescaling over-smoothed textured photos).
- API: `AutoSettings.score` gains a defaulted `detail:`. `auto-parrots.json` and
  `tools/baseline/auto.json` regenerated.

## Disagreements by eye
28/207 (13.5 %) → 4/207 (1.9 %), none clearly wrong (snow-forest Quick, cake Relaxed,
portrait-tunnel Relaxed, frontenac-night Detailed). ~40 sheets per round, five rounds.

## Acceptance at Relaxed (full size, 69 photos) — not met as written
- Equal-or-better ΔE at equal-or-fewer regions vs 24/0.5/0.5: 14/69 (20 %).
- Worse on both: 2 (kodim12, kodim16; small photos; ~0.001 ΔE).
- Inside the time band: 41/69 (defaults: 36).
The criterion tests dominance over a fixed point, but the objective is best fidelity inside a time
band: where 24/0.5 is below the band, Auto adds regions on purpose. Against 24 colors at Auto's own
region count (detail interpolated), Auto is equal or better on 56/69 (81 %); most exceptions are
low-color photos where Auto chose fewer paints. Photos ≤ 768 px can't reach 20 min at sane settings.
**Owner decision:** judge acceptance at equal painting time (81 %), or tie Relaxed's band to the
defaults' region count (giving up the time goal).

## Footer
"about an hour" is no longer true. Proposed: "Quick aims for about 15 minutes of painting, Relaxed
for about half an hour, Detailed for an hour or more. Small photos make shorter paintings." Median
estimates on large photos: Quick 21 min, Relaxed 36, Detailed 65.

## Corpus
35 CC0/public-domain photos from GitHub repos (pinned commits). No fog photo reachable (haze, smoke,
overcast stand in); few portraits (3) and pets (dog, guinea pig, chelsea). Hints for ten photos in
/tmp/pbn-w1b/hints (not committed).

## Checks
decision.json byte-identical under taskset 0 / 0-1 / 0-3. `pbn suggest` 5 candidates: 340–535 ms on
samples, 545–860 ms on 2048-px photos (loaded 4-core box); first draft 134–278 ms.
