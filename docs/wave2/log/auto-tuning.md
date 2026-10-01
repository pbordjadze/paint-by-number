# Auto tuning log (W1b)

Tuning of Suggested settings ("Auto", `Sources/PaintCore/Auto/`) on the pipeline wave 2 ships
with (W3 landed the `bandRings` metric only, so the pipeline is wave 1's). Started from W1a's
untuned constants at `72a0ecc`. Corpus: 69 photos, listed with sources and licences in
`auto-corpus.md`: the six samples, Kodak 01–24, scikit-image astronaut, chelsea, coffee and
rocket, and 35 CC0 / public-domain photos at the app's 2048-px source size (portraits, pets,
animals, night, snow, food, architecture, haze). Hand-written hints (faces, cats, dogs) for
ten photos.

Tools (scratch, `/tmp/pbn-w1b/`): `pbn suggest` at Quick, Relaxed and Detailed with 5
candidates for every photo; a compact sheet per photo (photo | five candidates' painted
drafts, per length, winner framed, every score term) next to `tools/auto_sheet.py`'s;
`measure.py` (draft and full region counts over a settings grid); `accept.py` (full-size
`pbn generate --auto` against 24/0.5/0.5).

## What the app actually generates (the band problem)

- Photos are kept at ≤ 2048 px (`ArtworkStore.sourceMaxPixelSize`); the working canvas is
  `1100 + 1000 × detail` px on the long side, at most 1.5 × the source. A 12 MP photo is
  segmented at 1400 / 1600 / 1900 px for detail 0.3 / 0.5 / 0.8; a 768-px sample at 1152 px
  whatever the detail.
- Full-size region counts, 35 large photos (p10 / median / p90): 24 colours at detail 0.3
  81 / 359 / 359 … at 0.5 103 / 532 / 532, at 0.9 186 / 1028 / 1028; 40 colours 160 / 376 /
  784 (0.3), 232 / 714 / 1421 (0.5), 492 / 1482 / 3727 (0.9). The 34 photos ≤ 768 px: 40
  colours 87 / 217 / 397 at 0.1 up to 270 / 434 / 956 at 0.9.
- At 3 s per region (kept: no evidence against it) the spec's bands (Quick 10–45, Relaxed
  40–120, Detailed 100–300 min) need 800–2400 regions for Relaxed: only the busiest large
  photos reach that, and no 768-px photo. With the old bands every Relaxed/Detailed
  candidate sat below its band, so the band term pushed toward the most regions while only
  Quick's top ever bit.

**Bands now:** Quick 8–25 min, Relaxed 20–50, Detailed 40–120 (overlapping, so a photo
that cannot fill one lands near it). Detailed's detail center 0.7 → 0.8 (at 0.7 the median
large photo sat at the bottom of its band).

**Region model:** the draft → full region count grows as area^(0.29 + 0.42 × detail) instead
of area^0.6: least squares over 730 (photo, colours, detail) cases (16 and 40 colours,
12–72 for four photos; detail 0.1–0.9), rms error of the log count 0.22 against 0.29
(median exponent measured 0.31 at detail 0.1, 0.47 at 0.3, 0.55 at 0.5, 0.64 at 0.7, 0.73
at 0.9). Density terms did not help (0.21).

Final winners against their band (estimates at decision time):

| length | large photos (34): below / inside / above, median | ≤ 768 px (35) |
| --- | --- | --- |
| Quick 8–25 | 2 / 22 / 10, 21 min (range 5–35) | 5 / 27 / 3, 14 min |
| Relaxed 20–50 | 4 / 24 / 6, 36 min (10–55) | 20 / 15 / 0, 18 min |
| Detailed 40–120 | 6 / 26 / 2, 65 min (18–122) | 30 / 5 / 0, 22 min |

"Above" Quick are the busy photos (grass, tulips, papayas, river stones) whose shortest
candidate is already 27–35 minutes. Small photos cannot fill Relaxed/Detailed at any setting.

**Settings footer:** "Suggested settings aim for about an hour of painting." is no longer
true. Proposed (W1c owns the string): "Quick aims for about 15 minutes of painting, Relaxed
for about half an hour, Detailed for an hour or more. Small photos make shorter paintings."

## Rounds

One change per round was the aim; round 1 bundled the fixes the review had already
diagnosed (each tied to a recorded disagreement or finding), later rounds changed one or two
things and were judged against the previous round's sheets.

| round | change | why (evidence) |
| --- | --- | --- |
| 0 | W1a's constants | 28 disagreements recorded (table below) |
| 1 | bands and Detailed center (above); detail-dependent region exponent | Relaxed/Detailed unreachable; exponent 0.52…0.72 with detail (review 1, 2) |
| 1 | monochrome cut fades in (×0.6 at no chromatic pixels → ×1 at 0.15) instead of a step | regatta (0.108), kodim09/10, windsurfer (0.047), portrait-tunnel (0.110), cake (0.149), clouds, mountain-haze lost paints to the cliff; grey copies of six photos knee at 23–27 vs 27–37 for colour, so the cut itself is right |
| 1 | palette curve and noise kept at 4 decimals | at 3, one quantum between 8 and 12 paints was 0.00025 ΔE/paint against the 0.0004 threshold (review 8); 4 decimals is 1/200 JND, still far above cross-device float noise |
| 1 | importance entropy measured above the map's floor | the fallback map's 0.2 floor rated every photo 0.986–0.999 |
| 1 | below-band weight 0.05 → 0.01 (above stays separate) | kodim20 Detailed: 6 more regions outweighed 0.004 ΔE, 20 paints won over 26 |
| 1→2 | noise reference to σ (0.0033), reverted to 0.01 | the draft averages sensor noise away (σ 12/255 added reads 0.0017 at 2048 px, 0.0036 at 768); the σ scale only raised clean, textured photos' smoothness by 0.1–0.2 (review 7: the scale mismatch is real, but the term already behaves as intended at 0.01) |
| 2 | price per paint 0.0001 in `total` | past the knee a paint bought a median 0.00002; noise drifted Relaxed to its 40-paint ceiling |
| 3 | above-band weight 0.05 → 0.15; tie tolerance 0.002 → 0.001 | hedgehog Detailed chose 163 min over 107 that looked the same; portrait 53 min Relaxed; ties took 10 paints over 18 (guinea pig) and 28 over 38 (borsen) |
| 4 | ties go to the time nearest the band's middle, not fewer regions | the fewer-regions tie made pont-royal's Detailed (32 min) shorter than its Relaxed (41) |
| 4 | ramp rule dropped | without W3's allocation (review 6): on 32 decisions for photos with ramps, 1.3× the paints lowered ΔE by 0.0005 and raised the ring share by 0.8 points |
| 4 | importance entropy as the covered share (exp H / cells) | normalized entropy above the floor still spanned only 0.95–0.99; the share spans 0.72–0.96 (no rule reads it yet) |
| 5 | small-source rule (−0.1 detail under 900 px) dropped | on 105 small-photo decisions the score chose more detail than the center 77 times and less never, and those photos already fell short of the bands |

Detail above 0.5 barely moving the draft (W1a's note) is the pipeline's: at the draft size
the candidates' canvases differ by the generator's 1.5× cap, and region counts move with
detail mostly at full size, which the detail-dependent exponent now models. Detailed now
clearly sits above Relaxed (median 65 vs 36 min on large photos).

## Disagreements (photo, length, winner, preferred, why)

Round 0 (W1a constants), 28 of 207 pairs (13.5 %), from ~40 sheets viewed plus the time
columns of the rest:

| photo | length | winner | preferred | why |
| --- | --- | --- | --- | --- |
| borsen | Quick | #3 | #0 | 41 min is not Quick; 24c d0.3 (27 min) looks as good |
| cake | Relaxed | #0 | #2 | monochrome ×0.6 at 0.149: 26c keeps the cream/caramel layers |
| cake | Detailed | #4 | #2 | 20c too few for the layers |
| regatta | Relaxed | #0 | #2 | monochrome misfire: 24c separates sea and sails, 4 rings vs 10 |
| butternut | Quick | #3 | #2 | 50 min of grass crumbs; 24c d0.1 (19 min) keeps the squash |
| clouds | Quick | #4 | #2 | 34 min and monochrome cut on a blue sky |
| dog | Quick | #3 | #4 | 48 min of grass blades; 18c d0.25 (28 min) keeps the face |
| hedgehog | Quick | #0 | #2 | 57 min; 24c d0.1 (33 min) as readable |
| goose | Quick | #3 | #2 | 42 min; 24c d0.25 (17 min) keeps the goose |
| guineapig | Quick | #4 | #3 | 35 min; 14c d0.25 (16 min) |
| kodim05 | Quick | #3 | #4 | 37 min of spokes; 18c d0 (24 min) |
| kodim10 | Detailed | #0 | #1 | 12c (monochrome at the band floor) loses the tan sail |
| kodim08 | Quick | #3 | #2 | 31 min; 24c d0 (17 min) reads as well |
| kodim09 | Relaxed | #4 | #2 | monochrome misfire on the sails' stripes |
| kodim13 | Quick | #3 | #2 | 37 min of river stones; 24c d0 (19 min) |
| kodim20 | Detailed | #1 | #0 | below band, 6 regions outweighed 0.004 ΔE; 20c loses the plane's markings |
| papayas | Quick | #0 | #2 | 81 min; 24c d0.1 (48 min) is the least |
| windsurfer | Quick | #4 | #2 | monochrome ×0.6 (0.047) on a vivid sail |
| portrait-tunnel | Quick | #0 | #2 | monochrome ×0.6 (0.110) on a portrait: lips and shading lost |
| mountain-haze | Relaxed | #1 | #2 | 10 paints for Relaxed (monochrome at 0.084) |
| tulips | Quick | #1 | #2 | 60 min; 24c d0.1 (38 min) |
| tiger-snow | Quick | #3 | #0 | 43 min; 24c d0.3 (27 min) keeps the stripes |
| mongoose | Quick | #4 | #0 | 38 min; 14c d0.15 (24 min) |
| snowy-road | Quick | #0 | #3 | 61 min; 12c d0.1 (27 min) |
| paris-night-street | Quick | #0 | #4 | 39 min; 18c d0.1 (29 min) keeps the lights |
| snow-forest | Quick | #1 | #3 | 50 min; 14c d0.1 (26 min) |
| waterfall | Quick | #0 | #2 | 58 min; 24c d0.1 (34 min) |
| red-panda | Quick | #0 | #2 | 36 min; 24c d0.25 (23 min) |

Intermediate rounds: round 2 recorded borsen Detailed (tie → 28 paints), guineapig Relaxed
(tie → 10 paints), hedgehog Detailed (163 min), portrait-tunnel Quick (31 min) and Relaxed (53
min); round 3 snow-forest Quick, pont-royal Detailed (shorter than Relaxed), cake Relaxed,
portrait-tunnel Relaxed.

Final (rounds 4–5), 4 of 207 pairs (1.9 %), none clearly wrong:

| photo | length | winner | preferred | why |
| --- | --- | --- | --- | --- |
| snow-forest | Quick | #2 18c d0.3 (33 min) | #3 14c d0.1 (18 min) | a 0.001-apart call; the shorter one reads as well |
| cake | Relaxed | #1 22c d0.5 (20 min) | #4 30c d0.7 (30 min) | the plate's shading; Relaxed looks like Quick |
| portrait-tunnel | Relaxed | #4 24c d0.85 (53 min) | #0 24c d0.65 (32 min) | looks the same, 3 min over the band |
| frontenac-night | Detailed | #1 20c d0.8 | #0 26c d0.8 | 0.0006 apart; Detailed with fewer paints than Relaxed's 34 |

## Acceptance against fixed defaults (Relaxed, full-size templates)

`pbn generate --auto --length relaxed` against `--colors 24 --detail 0.5 --smooth 0.5` on all
69 photos (hints where written); fidelity is the stats' unweighted mean ΔE (Auto's own score
weights by importance), a tie is within 0.0005 ΔE and 2 % regions.

- Equal or better ΔE at equal or fewer regions: **14 / 69 (20 %)**. Not met.
- Never worse on both: **2 photos** worse on both (kodim12: 171 vs 152 regions, 0.0268 vs
  0.0256; kodim16: 292 vs 261, 0.0281 vs 0.0269; both small, below the band). Not met.
- Inside the Relaxed band on every photo: **41 / 69** (24/0.5/0.5: 36 / 69). Not met; the
  ≤ 768-px photos cannot reach 20 minutes at reasonable settings.
- What happens instead: Auto has lower ΔE on 52 of 69 photos and more regions on 44.
  The criterion is a dominance test against a fixed point, while the objective is the
  best fidelity inside a time band; where 24/0.5 falls below the band (most photos at the
  old defaults' 10–30 minutes) Auto buys fidelity with regions, as designed.
- Fair comparison at equal regions: the defaults' ΔE curve (24 colours at detail 0.3, 0.5,
  0.7, 0.9, log-interpolated at Auto's region count): Auto is on or below it on **56 / 69
  (81 %)**. The 13 above it are mostly low-chroma photos where Auto chose fewer than 24 paints
  (night-moon 20, smoke-haze 18, mountain-haze 18, kodim08 18, dog 20, kodim16 20), trading
  ≤ 0.003 ΔE for fewer paints, which region count does not measure.

The criterion as written needs a decision: either measure acceptance at equal painting time
(the curve comparison above), or the Relaxed band must be pinned to the defaults' region
count, which would drop the time-band objective.

## Determinism and budget

- Byte-identical `decision.json` for parrots (768 px), lynx and portrait-tunnel (2048 px) at
  Detailed with hints under `taskset -c 0`, `0-1` and `0-3`.
- `pbn suggest` (Relaxed, 5 candidates) on the shared, loaded 4-core box: samples 340–535 ms
  (first draft 134–198 ms), large photos 545–860 ms (hedgehog the slowest). CI's M1 is
  faster; budget 1.5 s.

## Fixture and baselines

- `Tests/PaintCoreTests/Fixtures/auto-parrots.json` regenerated (draft PPM unchanged): the
  analysis (4-decimal curve and noise, entropy 0.842) and the decision moved with the tuning
  (now 40c d0.7 s0.47).
- `tools/baseline/auto.json` regenerated with `tools/regression.py --update`; the 18 legacy
  cases stayed "same" (their baseline is not rewritten: only timings differed).

## Open

- Fog is untested (no free fog photo reachable); portraits and pets are few and small.
- `importanceEntropy` now spreads (0.72–0.96) but no rule reads it; on the device Vision's
  saliency and face maps will move `subjectCoverage` and the weights, which this tuning could
  only approximate with hints.
