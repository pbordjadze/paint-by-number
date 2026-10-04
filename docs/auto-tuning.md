# Suggested settings: design and tuning log

## Design

- Auto decides `colorCount`, `detail` and `smoothness`; the region count follows from them, so
  Auto scores it rather than setting it.
- It lives in PaintCore (`AutoSettings`): the pipeline runs on the CPU and the decision is a
  small search over pipeline runs, so it stays portable, deterministic and testable on Linux
  (`pbn suggest`, `pbn generate --auto`). The app supplies only Vision's importance map and hints.
- The objective is the best importance-weighted fidelity inside the Painting Length's time
  band, every score term measured against this photo (colour error against its pixels, weighted
  by its own importance; rings where the photo itself shows no edge).
- A learned aesthetic score (Core ML) may only ever break ties between candidates whose
  measured scores are close: its output differs between chips and it is hard to test.
- Decisions are reproducible from the same pixels, importance, hints, length, line art and
  tuning on every device, and never stored: a saved painting keeps its recorded settings.

## Tuning

Tuning of Suggested settings ("Auto", `Sources/PaintCore/Auto/`) on pipeline version 2 (the
clean-room curve fitter of version 3 left Auto's pinned decision unchanged, and a
gradient-aware palette allocation was tried and not shipped, see
[`gradient-rings.md`](gradient-rings.md), so only the `bandRings` metric came with it).
Started from the first, untuned constants at `72a0ecc`. Corpus: 69 photos, listed with sources
and licences in [`auto-corpus.md`](auto-corpus.md): the six
corpus photos (`Tests/Corpus`), Kodak 01–24, scikit-image astronaut, chelsea, coffee and
rocket, and 35 CC0 / public-domain photos at the app's 2048-px source size (portraits, pets,
animals, night, snow, food, architecture, haze). Hand-written hints (faces, cats, dogs) for
ten photos.

"Review N" below is item N of the adversarial review of the first constants (`w1a-review.md`,
commit 2aa8e7e); round two answers the review of round one (`w1-review.md`, commit 2a1ff87).

Tools (scratch, not committed: `/tmp/pbn-w1b/`): `pbn suggest` at Quick, Relaxed and Detailed
with 5 candidates for every photo; a compact sheet per photo (photo | five candidates' painted
drafts, per length, winner framed, every score term) next to `tools/auto_sheet.py`'s;
`measure.py` (draft and full region counts over a settings grid); `accept.py` (full-size
`pbn generate --auto` against 24/0.5/0.5).

### What the app actually generates (the band problem)

- Photos are kept at ≤ 2048 px (`ArtworkStore.sourceMaxPixelSize`); the working canvas is
  `1100 + 1000 × detail` px on the long side, at most 1.5 × the source. A 12 MP photo is
  segmented at 1400 / 1600 / 1900 px for detail 0.3 / 0.5 / 0.8; a 768-px sample at 1152 px
  whatever the detail.
- Full-size region counts, 35 large photos (p10 / median / p90): 24 colours at detail 0.3
  81 / 359 / 359 … at 0.5 103 / 532 / 532, at 0.9 186 / 1028 / 1028; 40 colours 160 / 376 /
  784 (0.3), 232 / 714 / 1421 (0.5), 492 / 1482 / 3727 (0.9). The 34 photos ≤ 768 px: 40
  colours 87 / 217 / 397 at 0.1 up to 270 / 434 / 956 at 0.9.
- At 3 s per region (kept: no evidence against it) the first design's bands (Quick 10–45,
  Relaxed 40–120, Detailed 100–300 min) need 800–2400 regions for Relaxed: only the busiest
  large photos reach that, and no 768-px photo. With the old bands every Relaxed/Detailed
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

### Rounds

One change per round was the aim; round 1 bundled the fixes the review had already
diagnosed (each tied to a recorded disagreement or finding), later rounds changed one or two
things and were judged against the previous round's sheets.

| round | change | why (evidence) |
| --- | --- | --- |
| 0 | the first, untuned constants | 28 disagreements recorded (table below) |
| 1 | bands and Detailed center (above); detail-dependent region exponent | Relaxed/Detailed unreachable; exponent 0.52…0.72 with detail (review 1, 2) |
| 1 | monochrome cut fades in (×0.6 at no chromatic pixels → ×1 at 0.15) instead of a step | regatta (0.108), kodim09/10, windsurfer (0.047), portrait-tunnel (0.110), cake (0.149), clouds, mountain-haze lost paints to the cliff; grey copies of six photos knee at 23–27 vs 27–37 for colour, so the cut itself is right |
| 1 | palette curve and noise kept at 4 decimals | at 3, one quantum between 8 and 12 paints was 0.00025 ΔE/paint against the 0.0004 threshold (review 8); 4 decimals is 1/200 JND, still far above cross-device float noise |
| 1 | importance entropy measured above the map's floor | the fallback map's 0.2 floor rated every photo 0.986–0.999 |
| 1 | below-band weight 0.05 → 0.01 (above stays separate) | kodim20 Detailed: 6 more regions outweighed 0.004 ΔE, 20 paints won over 26 |
| 1→2 | noise reference to σ (0.0033), reverted to 0.01 | the draft averages sensor noise away (σ 12/255 added reads 0.0017 at 2048 px, 0.0036 at 768); the σ scale only raised clean, textured photos' smoothness by 0.1–0.2 (review 7: the scale mismatch is real, but the term already behaves as intended at 0.01) |
| 2 | price per paint 0.0001 in `total` | past the knee a paint bought a median 0.00002; noise drifted Relaxed to its 40-paint ceiling |
| 3 | above-band weight 0.05 → 0.15; tie tolerance 0.002 → 0.001 | hedgehog Detailed chose 163 min over 107 that looked the same; portrait 53 min Relaxed; ties took 10 paints over 18 (guinea pig) and 28 over 38 (borsen) |
| 4 | ties go to the time nearest the band's middle, not fewer regions | the fewer-regions tie made pont-royal's Detailed (32 min) shorter than its Relaxed (41) |
| 4 | ramp rule dropped | without a gradient-aware allocation, which was tried and not shipped ([`gradient-rings.md`](gradient-rings.md); review 6): on 32 decisions for photos with ramps, 1.3× the paints lowered ΔE by 0.0005 and raised the ring share by 0.8 points |
| 4 | importance entropy as the covered share (exp H / cells) | normalized entropy above the floor still spanned only 0.95–0.99; the share spans 0.72–0.96 (no rule reads it yet) |
| 5 | small-source rule (−0.1 detail under 900 px) dropped | on 105 small-photo decisions the score chose more detail than the center 77 times and less never, and those photos already fell short of the bands |

Detail above 0.5 barely moving the draft (noted with the first constants) is the pipeline's:
at the draft size the candidates' canvases differ by the generator's 1.5× cap, and region
counts move with detail mostly at full size, which the detail-dependent exponent now models.
Detailed now clearly sits above Relaxed (median 65 vs 36 min on large photos).

### Disagreements (photo, length, winner, preferred, why)

Round 0 (the first constants), 28 of 207 pairs (13.5 %), from ~40 sheets viewed plus the time
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

### Acceptance against fixed defaults (Relaxed, full-size templates)

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

Owner decision (2026-10-01): acceptance is judged at equal painting time (the curve comparison
above), not by the dominance criterion.

### Determinism and budget

- Byte-identical `decision.json` for parrots (768 px), lynx and portrait-tunnel (2048 px) at
  Detailed with hints under `taskset -c 0`, `0-1` and `0-3`.
- `pbn suggest` (Relaxed, 5 candidates) on the shared, loaded 4-core box: samples 340–535 ms
  (first draft 134–198 ms), large photos 545–860 ms (hedgehog the slowest). CI's M1 is
  faster; budget 1.5 s.

### Fixture and baselines

- `Tests/PaintCoreTests/Fixtures/auto-parrots.json` regenerated (draft PPM unchanged): the
  analysis (4-decimal curve and noise, entropy 0.842) and the decision moved with the tuning
  (then 40c d0.7 s0.47; round two below moved it again).
- `tools/baseline/auto.json` regenerated with `tools/regression.py --update`; the 18 legacy
  cases stayed "same" (their baseline is not rewritten: only timings differed).

### Open

- Fog is untested (no free fog photo reachable); portraits and pets are few and small.
- `importanceEntropy` now spreads (0.72–0.96) but no rule reads it; on the device Vision's
  saliency and face maps will move `subjectCoverage` and the weights, which this tuning could
  only approximate with hints.
- Whether one Painting Length is enough, or whether "more colours" and "less detail" are
  distinct wishes that need controls of their own, is the first design's open question.

## Round two (after the review)

The review of round one found three majors; each was fixed. Scratch, not committed:
`/tmp/pbn-w1b/` (`maps/`, `m2/`, `noise/`, `simD/`, `accept/`).

### 1. Region model and detail under Vision-like maps

The round-one model and bands came from pbn's fallback importance map (mean 0.56–0.64), which
rates busy texture important; the app passes Vision maps (0.25 base, attention 0.2–0.6, a
0.75 foreground mask, faces/animals near 1), which protect far less of the frame. Stand-ins
(`/tmp/pbn-w1b/mkmaps.py`): uniform 0.25 and 0.4, and a "vis" map per photo built like
`SubjectImportance` (hand-placed subject ellipses for 36 photos, an attention blob for the rest,
the hand-made maps of the gradient-ring experiments for astronaut, chelsea, coffee/espresso,
parrots/kodim23; means 0.36–0.63). CI's simulator counts (lighthouse 159 areas at 28 colours)
sit at the uniform-0.25 end.

- New feature `PhotoAnalysis.meanImportance` (mean importance weight; fallback 0.56–0.64, vis
  0.36–0.63, uniform maps their value).
- Growth refit on 1104 draft/full pairs (69 photos × 4 maps × detail 0.1/0.4/0.7/1 at 28
  colours): exponent −0.18 + 0.42 × detail + 0.77 × mean importance (clamped 0…1). rms of the
  log count 0.22 with per-map bias within ±0.04; the round-one model had rms 0.35 and biases
  −0.36 (u25), −0.26 (u40), −0.18 (vis). Check at full size, `pbn generate --auto` Relaxed,
  actual / estimated regions: vis median 0.99 (p10 0.75, p90 1.22), u25 1.01 (0.74, 1.22);
  the review measured 0.64× / 0.75× for the old model.
- Reachability (full templates, 28 colours, large photos, median minutes at detail 0.1/0.4/
  0.7/1.0): fallback 12/25/49/81, vis 7/14/30/53, u25 4/8/17/35. So at like settings Vision maps
  give about half the time, and the detail centers (0.3/0.5/0.8, tuned on the fallback) fell
  short: before the change the median vis decision ran 16 / 21 / 33 min.
- Detail center now rises one unit per unit of mean importance below 0.6
  (`detailPerImportance`, `referenceImportance`): 30 minutes needs detail 0.5 under the
  fallback, 0.7 under vis, about 0.9 under u25. Bands unchanged (the medians now land inside
  them; no evidence to move them).

Decisions (estimated minutes of the winner, median for 33 large / 36 small photos; below / in /
above band out of 33 large):

| map | Quick 8–25 | Relaxed 20–50 | Detailed 40–120 |
| --- | --- | --- | --- |
| fallback | 19 / 14 (2/27/4) | 33 / 16 (4/27/2) | 56 / 22 (6/27/0) |
| vis | 16 / 10 (3/29/1) | 26 / 14 (6/27/0) | 42 / 17 (12/21/0) |
| u25 | 13 / 9 (4/28/1) | 20 / 11 (17/15/1) | 30 / 12 (23/10/0) |

The three lengths stay distinct under every map. Small photos still can't fill Relaxed or
Detailed. Footers: Quick "about 15 minutes" and Relaxed "about half an hour" stay true (vis
16 and 26); Detailed changed from "about an hour" to "45 minutes or more" (vis 42, fallback 56,
u25 30) in `Preferences.swift` and the catalog (no test quotes it).

### 2. Decision noise

JPEG q92 re-save of 33 photos × 3 lengths (fallback map). Before: the winner's settings changed
on 79/99, materially (colours > 15 %, detail or smoothness ≥ 0.1) on 56/99. Two sources:

- The center itself moved materially on 17/99: the knee read the gain between neighbouring
  curve points (separate k-means runs; regatta 26 → 35 paints), and steps at thresholds
  (chroma spread 0.030 → 0.029 cost kodim05 6 of 40 paints). Now the knee is a power law
  fitted to the whole curve (mean |change| 10 % → 2 %, same level, median ratio 0.99) and every
  threshold of the rule is a ramp ±15 % around it. Center material changes: 0/99.
- Neighbour vs center: a re-save moves (neighbour total − center total) by a median 0.003
  (p90 0.010; colour error, p95 and the region estimate). The 0.001 tie window is replaced by
  `tieMargin` 0.006: the center wins unless a neighbour beats it by more, or the center's
  estimate runs over its band (then, as among tied neighbours, the time nearest the band's
  middle wins). Material flips by margin: 0.001 54, 0.004 43, 0.005 23, 0.006 15, 0.008 12.

After: winner settings changed on 52/99 (mostly ±2 colours from rounding to even, smoothness
±0.01); **materially on 16/99** (before 56/99). Determinism unchanged: byte-identical under
`taskset -c 0 / 0-1 / 0-3` (parrots, lynx, portrait-tunnel, hedgehog at Detailed with vis maps
and hints).

### 3. Monochrome cut on dark and hazy photos

A pixel is chromatic when its chroma exceeds 0.04 × min(1, max(L / 0.5, 0.25)): dark pixels
can't hold much absolute chroma. Chromatic fraction: night-moon 0.008 → 0.227 (no cut; 24
colours, was 16–20), portrait-tunnel 0.109 → 0.183, kodim17 0.095 → 0.232; grey copies of
night-moon, lynx and parrots still 0.000, snow-forest 0.000, snowy-road 0.017 (full cut kept).
Smoke-haze was never cut (0.59 chromatic): its 18-colour winner was the 0.75× neighbour beating
the center by 0.0045; under the margin the center (22 colours) wins and keeps the cool sky
(full size, by eye). Night-moon at full size now keeps the lamp post, its glow and the tree
line; its sky is a shade more neutral than 24/0.5's.

### By eye (round-two decisions, fallback map)

152 of 207 decisions changed materially from round one (most by the knee and the margin).
Sheets viewed: cake, dog, kodim08, portrait-dress, kodim18, bernina-snow, guineapig,
frontenac-night, hedgehog, tulips, night-moon, smoke-haze (both maps). Disagreements:

| photo | length | winner | preferred | why |
| --- | --- | --- | --- | --- |
| hedgehog | Relaxed | #0 34c d0.43 (64 min) | #3 34c d0.23 (33 min) | the center is the best total even after its 0.009 over-band cost; looks the same |
| kodim08 | Quick | #3 24c d0.44 (26 min) | #0 24c d0.24 (21 min) | #3 reads much better, but Quick and Relaxed then both run 26 min |

### Acceptance (Relaxed, full size, fallback map, 69 photos; round one in brackets)

- The first design's criterion (equal or better ΔE at equal or fewer regions vs 24/0.5/0.5):
  6/69 [14/69].
- Worse on both: 5 [2]: bernina-snow, clouds, night-moon (0.0176 vs 0.0165 at 151 vs 143
  areas; was 0.0195), kodim06, kodim11, each by ≤ 0.0011 ΔE.
- Inside 20–50 min: 44/69 [41].
- Equal painting time (24 colours, detail 0.3–0.9, interpolated at Auto's region count): 56/69
  (81 %) [56/69]; median ΔE ratio 0.976 at 1.13× regions. 3 of the 13 misses are below the
  curve's range (tulips, waterfall, papayas: Auto chose fewer areas than 24/0.3 makes).
- The dominance criterion fell because the margin keeps the center more often and the center
  now aims at the band's middle (more regions where 24/0.5 is short); the review's verdict
  stands: judge at equal time, as the owner decided.

Budget: `pbn suggest` Relaxed 415–430 ms on samples, 650–800 ms on 2048-px photos (first draft
140–245 ms). `auto-parrots.json` regenerated (draft unchanged); `tools/baseline/auto.json`
regenerated with `--update`; `tools/baseline/regression.json` kept byte-identical (its 18
legacy cases are "same"; `--update` only rewrote timings, which were reverted).
