# Stage 2: color inside the lines (results)

Stage 2 of the line-art exploration (spec: `docs/overnight/lineart.md`, § Stage 2 and § Panels).
It takes each stage-1 drawing (`walls.png`, `ink.png`) and pbn's own segmentation of the same
picture (`raster.ppm`, `stats.json`) and makes the color regions you paint, the painting plan
and the finished piece. Python only, nothing in `Sources/`, `App/` or the baselines.

**In short.** C1 (pbn's regions split by the lines) beats C2 (re-segmenting inside each
enclosed area) on every picture and keeps the better: as faithful as pbn where the paint shows
(ΔE 1.02x pbn's vs C2's 1.12x), fewer slivers and fewer cells below the number's minimum, and it
keeps the small tonal shapes C2 drops. The finished panel does what the idea promises: skies,
walls and bokeh that are bands today come back as gradients (best: `santa-fe-freight`,
`lighthouse`, `delicate-arch`, `milkmaid`), with every line crisp. The price is regions: C1 has
1.16x pbn's on the dev picks and 1.28x on the test set, because lines cut pbn's regions, and
drawings that close many tiny cells (lineart, TEED medium) need a rule for them (same-paint
cells join the region across the line). It fails where the drawing leaves busy texture unlined:
foliage, snow fields and flower meadows read as soft photo, not drawing. Outputs:
`$S/lineart/out/<pic>/<option>/{plan,finished,flat}_c1.png` (and `_c2`), 108 options x 2 methods.

## What was built

| File | What |
| --- | --- |
| `color_common.py` | IO, OKLab, LabelSizing (2.12 = `LabelSizing.minimumRadius`, read from `Template.swift`), region bookkeeping: components, adjacency, room (inscribed radius outside the ink), the small-fragment merge, the wall snap, wall assignment, a domain-transform filter with walls as hard barriers |
| `color_split.py` | **C1**: pbn's regions split by the lines, plus the shared tail (`finish`) |
| `color_segment.py` | **C2**: segmentation inside each enclosed area with pbn's palette |
| `panels.py` | plan, finished and flat panels at 2x; pbn's `template.svg` / `painted.svg` rendered for comparison |
| `run_color.py` | runner for one option or a batch (every stage-1 option, or a picks file); metrics; `summary_color.json` / `summary_color.tsv` |
| `color_report.py` | the markdown tables below, from `summary_color.json` |
| `panel_sheet.py` | a contact sheet per option for looking (current template, current painted, lines alone, plan / finished / flat for C1 and C2) |
| `color_dev_walls.py` | stand-in walls (thinned Canny) used before stage 1's drawings existed |
| `color_test_picks.json` | the test-set options run (every family at the picture's detail level) |

Outputs sit next to stage 1's in `$S/lineart/out/<pic>/<option>/` (no names collide: stage 1
writes `metrics.json`, stage 2 `metrics_c1.json` / `metrics_c2.json`): `regions_c1.png` /
`regions_c2.png` (uint16 label map, every pixel labelled, walls included), `regions_*.json`
(palette index per region), `plan_*.png`, `finished_*.png`, `flat_*.png` (paint unblurred, ink
on top), `metrics_*.json`, and `sheet.jpg` where one was made for looking; per picture
`$S/lineart/out/<pic>/current_template.png` and `current_painted.png`; across everything
`$S/lineart/out/summary_color.json` / `.tsv`. All panels are 2x the working size.

### The contract with stage 1

Regions are 4-connected components of non-wall pixels, walls being stage 1's 8-connected 1-px
centerlines; so an open stroke is a wall along its length and a region wraps around its free
end with no special case. "Room" for a number is the inscribed radius of the region's pixels
that the ink (`ink.png` alpha >= 0.5, downsampled, plus the walls) leaves visible, minus half a
pixel to the boundary crack, compared with `LabelSizing.minimumRadius(digits:)` (2.12 for one
digit, 3.17 for two).

### C1: pbn's regions split by the lines

1. Every pbn region is cut by the walls (same-color 4-components of non-wall pixels).
2. **Snap**: where a color edge runs within 2.5 px of a wall, the strip between them (pixels
   outside the opening of their color by a radius-2 disc) goes to the neighbouring color on the
   same side of the wall, grown ring by ring; the color edge lands on the line. Without it the
   cut leaves 1-3 px slivers of the far color along every line.
3. **Merge**: fragments whose room is below the number's minimum merge, smallest first, into the
   4-adjacent neighbour (hence in the same enclosed area, never across a line) with the longest
   shared border discounted by color difference (`border / (ΔE + 0.03)`).
4. **Cells too small for a number**: a fragment left alone in its enclosed area is a cell the
   drawing closed too small to number. Most have the *same paint* as a region across the line
   (the line cut through one pbn region; first measured on kodim04 / great-wave / parrots:
   41 of 45, 184 of 199, 31 of 38). Those join that region (ΔE <= 0.06): the ink stays on top,
   the cell just has no number of its own and fills when its neighbour does. This is the one
   place a region spans a line, and only where the paint is the same on both sides. A cell
   with nothing visible beside the ink (room < 1 px) and no same-paint neighbour goes to the
   nearest region like a wall pixel; the rest keep their own color and a minimum-size number
   (reported as `regionsBelowMinimumRadius`).
   Over the final 108 options 88 % of such cells joined, 3 % were absorbed.
5. Wall pixels go to the nearest region (ink covers them).

### C2: segmentation inside each enclosed area

1. Enclosed areas = 4-connected non-wall components (wraparound at open ends is automatic).
2. The photo is smoothed in OKLab by the domain-transform filter with the walls as barriers
   (sigma_s 10 px, sigma_r 0.06), so texture goes and no color leaks across a line.
3. Data term per pixel and palette color: half the ΔE from the smoothed photo, half from the
   color pbn's raster gave the pixel.
4. Each area chooses a few of the palette colors pbn uses in it (>= 0.2 % of the area or 60 px)
   greedily: the color that best represents the area, then more while one pays off (its pixels
   improve by >= 0.03 ΔE on average over >= 300 px, or by >= 0.08 over >= 40 px for salient
   bits like an eye; at most one color per 6000 px).
5. Potts smoothing (red-black ICM, beta 0.02), then the same snap, merge (asking 1.5 px more
   room than the number needs, so regions are fewer and bigger, except salient ones that
   differ from their neighbour by > 0.12), cell handling and wall assignment as C1.

### Panels

- **Painting plan** (`plan_*.png`): paper `#F4EFE6`; dotted guides (dots 4.4 px apart, radius
  0.8 px, 55 % of `#706876`) on region boundaries that are not lines and not under the ink;
  stage 1's `ink.png` on top; numbers = palette index + 1 in **Source Serif 4 Regular** (New York
  isn't available on Linux; Source Serif is Adobe's, SIL OFL 1.1, downloaded into the
  scratchpad; DejaVu Serif is the fallback), `#706876`, centred on the digits' ink box at the
  region's pole of inaccessibility (the most spacious visible pixel), sized exactly by
  `LabelSizing.fontSize(radius:digits:maximum:)` with the SVG exporter's cap (1/64 of the long
  side) and floor (`minimumFontSize`); big regions get extra numbers spread like
  `Vectorizer.addExtraLabels`.
- **Finished** (`finished_*.png`): flat paint blurred by a domain-transform recursive filter
  (Gastal & Oliveira 2011) on OKLab: a step into or out of a wall pixel is impossible (so paint
  never crosses a line, at any distance), a step across an unlined boundary between colors up to
  1.2 palette steps apart (the median nearest-paint distance of the palette) costs nothing, a
  bigger jump costs `1 + (sigma_s / 0.07) * (ΔE - free)` px; sigma_s = 24 working px where
  regions are big (inscribed radius >= 10 px, smoothed), shrinking to 3 px where they are small
  (<= 3 px: foliage, foam, fur), so texture softens instead of melting into mush. Then a 0.6 px
  anti-alias and the ink on top. Tonal bands melt into gradients, distinct colors stay crisp,
  lines stay crisp.
- Both panels first round pbn's pixel staircases off at 2x (each pixel takes the paint with the
  most Gaussian-weighted votes, sigma 2.5 px at 2x; untouched within 3 px of a wall), so they
  compare fairly with pbn's smoothed vector template.
- **Current template** (`current_template.png`, `current_painted.png`): pbn's `template.svg`
  and `painted.svg` rendered at 2x with resvg (`tools/svg2png.mjs`, `@resvg/resvg-js` installed
  into the scratchpad).

All outputs are deterministic: two runs give byte-identical PNGs and label maps (only the
timings in `metrics_*.json` differ).

### Metrics (`metrics_*.json`)

`regions` (pbn's count beside it), `enclosedAreas` (areas holding paint), `regionsPerArea`
(mean, median, max, areas with several), `slivers` (room < 2 px or area/perimeter < 1), `minRoom`
(smallest region's room outside the ink; `minRoomIgnoringInk` too), `regionsBelowMinimumRadius`,
`cellsTooSmall` / `cellsJoinedAcrossLine` / `cellsAbsorbed`, `unlinedBoundaryShare` (share of
region boundary that is a guide, not a line), `colorsUsed`, `meanDeltaE` of the flat paint
against the photo (OKLab; `pbnMeanDeltaE` is pbn's raster measured the same way),
`meanDeltaEOutsideInk` / `pbnMeanDeltaEOutsideInk` (the same where the paint shows: on prints
the photo's own dark lines are ink here but paint in pbn's raster) and `finishedMeanDeltaE` of
the blurred paint (all pixels).

## What was tried, what failed

Developed first on stand-in Canny walls (`color_dev_walls.py`), then on stage 1's drawings as
they appeared. In order:

- **C1 without the snap** left 1-3 px slivers of the far color along most lines (pbn's color
  edges and stage 1's strokes follow the same edges but are offset by a pixel or two). The
  opening-based snap removes them; slivers now come almost only from cells the drawing closes.
- **Tiny cells**: the drawings close many cells too small for a number (mean per option over
  the final 108: lineart coarse / anime / fine 210-260, TEED 130, flow DoG 76, boundaries 58,
  XDoG 36, HED 30, PiDiNet 11). First kept with a
  minimum-size number: crowded, overflowing numbers all over textured areas. Then filled with
  ink when nothing showed beside the ink: black blots the drawing never had. Now: joined to the
  same-paint region across the line (88 % of them over all options), absorbed when invisible
  (3 %), kept otherwise.
- **C2 on the photo alone** picked foreign palette colors on soft transitions (a blue-gray halo
  around the parrots' white bokeh, red patches on kodim04's cheeks) because the nearest palette
  color to an in-between tone is often another object's paint. Fixed by mixing in pbn's raster
  as half the data term and allowing only colors pbn itself uses in that area.
- **C2's "colors pbn uses here" at 1 % of the area** dropped minority hues in big areas (the red
  macaw's pink face turned gray); 0.2 % or 60 px keeps them.
- **C2's bigger minimum room** (fewer, bigger regions) merged eyes away; salient regions (ΔE >
  0.12 from the neighbour they would join) are exempt, and the color choice has a salient path
  (>= 0.08 ΔE gain over >= 40 px). Eyes are back; small highlights still go (espresso spoon).
- **C2 without the snap** left a yellow strip along the cheek line of the blue-and-yellow
  macaw: the snap now runs in both.
- **Finished, range-only domain transform** (crossing cost proportional to ΔE, sigma_r 0.12):
  bands soften but every band edge stays visible as a kink; with sigma_r 0.2-0.5 the clouds and
  the lighthouse's shading vanish. A free step (blend freely up to ~one palette step, then a
  steep cost) gives real gradients in skies and bokeh while hue changes stay crisp.
- **One blur size everywhere** turned busy unlined texture (the barn's foliage) into a smeared
  watercolor; the blur now shrinks with region size (big bands blend, small texture regions
  only soften). Skies are unchanged by this.
- **Nearest-neighbour 2x upscaling** showed pbn's raster staircases as 2-px jaggies on every
  unlined edge, unlike the smooth vector template; the Gaussian vote at 2x rounds them off.
- A bug worth noting for production: the snap's ring-by-ring growth cannot reach a cell that
  is thin everywhere and closed by walls; those pixels had silently become walls (cells
  vanishing into neighbours). They now keep their color and go through the cell rule.

## Verdict: C1

**Keep C1.** On stage 1's picks for the dev pictures (27 options; the Great Wave's three picks
are counted with the test set) and on the test set (9 pictures x 9 families at the picture's
detail level, 81 options), both methods run on the same drawings:

| set | method | options | regions / pbn (median) | slivers (mean) | cells too small (mean) | kept below min (mean) | ΔE flat / pbn, outside ink (median) | ΔE finished (median) | unlined share (median) |
|---|---|---|---|---|---|---|---|---|---|
| dev picks | C1 | 27 | 1.16 | 2.0 | 29.3 | 4.3 | 1.02 | 0.0322 | 0.72 |
| dev picks | C2 | 27 | 0.80 | 2.7 | 25.0 | 5.4 | 1.12 | 0.0350 | 0.70 |
| test set | C1 | 81 | 1.28 | 5.0 | 136.9 | 9.1 | 1.02 | 0.0429 | 0.73 |
| test set | C2 | 81 | 1.07 | 9.3 | 114.4 | 16.4 | 1.12 | 0.0447 | 0.71 |

- **C1 keeps pbn's tonal structure**: the clouds in the Great Wave's sky, the planes of
  kodim04's face, the pink of the red macaw's face, the espresso spoon's highlight. Where the
  paint shows (outside the ink) it is as faithful as pbn's own raster (ΔE 1.02x),
  and the finished panel melts its bands back into gradients, which is what C2 was meant to
  buy.
- **C2** has fewer regions on the dev picks (0.80x pbn's vs C1's 1.16x) but barely on the test
  set (1.07x vs 1.28x: the busy test pictures leave big unlined areas where its per-area color
  choice keeps many colors), it is less faithful (ΔE 1.12x pbn's), it leaves about twice the
  slivers and cells below the number's minimum (test set: 9.3 vs 5.0 slivers, 16.4 vs 9.1 kept
  cells per option), and it drops what matters in small doses: the Great
  Wave's clouds (`great-wave/flowdog-medium/finished_c2.png`), the espresso spoon's highlight
  (`espresso/learned_hed-medium/finished_c2.png`), the lighthouse lantern's tone
  (`lighthouse/learned_hed-medium/flat_c2.png`), and it posterizes kodim04's cheek into dark
  patches (`kodim04/learned_teed-sparse/finished_c2.png`). It is also much slower (regions in
  7-25 s per picture vs 1-3 s for C1, numpy; panels take 10-45 s either way). If fewer regions are wanted, tune pbn's own merging instead.
- Lines stay crisp with both; slivers along lines are gone with both (the snap); what slivers
  remain are cells the drawing closed that keep a distinct paint.

So the morning page should show C1 (`plan_c1.png`, `finished_c1.png`); `*_c2.png` sit beside
them for every option run.

## The owner's questions

- **Illustration or posterized photo?** With a drawing that outlines the subject the finished
  C1 reads as an illustration: crisp ink, flat-ish shapes with soft gradients inside, no
  contour rings, e.g. `great-wave/learned_lineart_fine-medium`, `espresso/learned_hed-medium`,
  `kodim03/learned_hed-medium`, `kodim04/learned_teed-sparse`, `lighthouse/learned_hed-medium`,
  `parrots/learned_hed-medium`, `cezanne-apples/learned_pidinet-medium`,
  `red-fox/learned_pidinet-medium` (all under `$S/lineart/out/`). Paintings come out as soft
  gouache copies (milkmaid, wheat field, Cézanne). Where the drawing leaves a busy area unlined
  it reads as a soft-focus photo or as blotches (see failure modes).
- **Do the sky's bands become a gradient again while lines stay crisp?** Yes: the lighthouse
  and Delicate Arch skies, the Milkmaid's wall, the parrots' bokeh and the Great Wave's clouds
  come back as smooth gradients; nothing blends across a line at any distance (walls are hard
  barriers in the filter), so the ink edges stay sharp.
- **Slivers or crowded numbers in the plan?** Slivers along lines: no. Crowded numbers: only
  where the drawing closes cells too small for a number that keep a distinct paint (a few per
  picture, drawn at the minimum size and overflowing their cell, e.g. the eye area of
  `parrots/learned_teed-medium/plan_c1.png`); the many same-paint ones join the region across
  the line. pbn's own small regions keep their minimum-size numbers as in today's template, so
  textured areas (kodim04's hat, the Great Wave's foam) stay dense, as they are today.

## Test set: what to put in front of the owner

Detail level per picture (stage 1's rule: faces sparse, prints medium; busy brushwork and
flower fields sparse too): milkmaid, wheat-field, lassen-lupine **sparse**; great-wave,
cezanne-apples, delicate-arch, red-fox, santa-fe-freight, hawksbill-turtle **medium**. All nine
families ran at that level with C1 and C2. Three per picture, of different kinds, judged on the
C1 plan and finished panels next to the lines alone:

| picture (detail) | options, C1 regions (pbn) | why |
| --- | --- | --- |
| great-wave (medium) | `flowdog-medium` 877 (420)<br>`learned_lineart_fine-medium` 928 (420)<br>`learned_hed-medium` 683 (420) | flow DoG and lineart fine are full ink copies of the print (stage 1's picks too); HED outlines only the big shapes and lets the foam become soft paint, the most painterly version. All three close 100-300 cells too small for a number; nearly all join a same-paint neighbour |
| milkmaid (sparse) | `learned_teed-sparse` 594 (486)<br>`learned_hed-sparse` 542 (486)<br>`flowdog-sparse` 584 (486) | TEED draws face, jug and window with nothing on the skin; HED gives the clean silhouette; flow DoG is the pen version. The wall's soft gradient is the finished piece's best feature in all three |
| wheat-field (sparse) | `learned_pidinet-sparse` 663 (643)<br>`learned_hed-sparse` 779 (643)<br>`flowdog-sparse` 1086 (643) | no lines to find: PiDiNet keeps only cypress, hills and cloud edges, so the finished reads as a soft gouache; HED adds the cloud swirls; flow DoG draws the brushwork as hatching (most Van Gogh, busiest plan) |
| cezanne-apples (medium) | `learned_pidinet-medium` 585 (538)<br>`learned_hed-medium` 640 (538)<br>`flowdog-medium` 554 (538) | clean fruit outlines with the shading left to gradients, the most illustration-like set; TEED and lineart draw the canvas texture as scribbles |
| delicate-arch (medium) | `learned_hed-medium` 689 (618)<br>`learned_pidinet-medium` 679 (618)<br>`learned_teed-medium` 1055 (618) | arch and horizon in a few lines, the sky one clean gradient; TEED adds the rock's texture. The snowy plateau stays pbn's blotches in all (unlined, small regions) |
| red-fox (medium) | `learned_pidinet-medium` 270 (234)<br>`learned_teed-medium` 380 (234)<br>`learned_lineart_fine-medium` 488 (234) | PiDiNet: silhouette, ears and face, the fur left to watercolor gradients; TEED adds fur strokes; lineart fine is a pen sketch of the fur |
| lassen-lupine (sparse) | `learned_pidinet-sparse` 851 (815)<br>`learned_hed-sparse` 951 (815)<br>`learned_teed-sparse` 1127 (815) | the busy-texture stress case: no family draws the flower field well. PiDiNet and HED keep mountain, tree line and rocks so the plan stays calm; TEED adds flower clumps. The field reads as a soft photo, not a drawing |
| santa-fe-freight (medium) | `learned_teed-medium` 574 (322)<br>`learned_hed-medium` 451 (322)<br>`flowdog-medium` 527 (322) | the clearest demonstration of the idea: today's banded sky becomes one gradient while the signal gantry stays crisp. TEED draws ladder, poles and locomotive; HED is the clean version; flow DoG the pen version |
| hawksbill-turtle (medium) | `learned_pidinet-medium` 1011 (950)<br>`learned_teed-medium` 1608 (950)<br>`flowdog-medium` 1399 (950) | PiDiNet outlines body and scutes and lets the shell pattern be paint; TEED and flow DoG draw the pattern (busier plans, 1400-1600 regions) |

## Failure modes

1. **Unlined busy texture goes soft or blotchy.** Foliage, rocks, snow fields and water that the
   drawing leaves without lines either blend into a soft watercolor (big regions: the foliage
   in `barn/learned_hed-medium/finished_c1.png`, the meadow in
   `lassen-lupine/learned_pidinet-sparse/finished_c1.png`) or stay pbn's small blotches, only
   softened (small regions: the snowy plateau behind
   `delicate-arch/learned_hed-medium/finished_c1.png`). The plan is fine; the finished piece
   looks like a photo there, not a drawing.
2. **Sparse drawings make the finished piece a blur with a few lines**: e.g.
   `red-fox/flowdog-medium/finished_c1.png` (a few face strokes; the fox's back melts into the
   snow), `lassen-lupine/learned_lineart_anime-sparse/finished_c1.png`. Line density matters more for the finished look than
   for the plan.
3. **Chains of small steps leak.** pbn sometimes renders a hue change as a run of small tonal
   steps; unlined, the filter takes the run for a gradient and the hues mix: the red and slate
   stripes of the regatta's second sail with flow DoG's lines
   (`$S/lineart/examples/regatta/flowdog-medium/finished_c1.png`, run outside the batch), crisp
   with HED's (`regatta/learned_hed-medium/finished_c1.png`).
4. **Drawings that close many tiny cells** (lineart fine / coarse / anime, TEED medium; up to
   ~300 on the Great Wave, `great-wave/learned_lineart_fine-medium`) depend on the cell rule;
   without it the plan is covered in overflowing numbers. The few cells with a distinct paint
   still get a minimum-size number that overflows its cell.
5. **Raster shapes.** Region edges come from pbn's pixel raster, smoothed at 2x; hard unlined
   edges are a little wobblier than the vector template's (compare `current_painted.png`).
6. **Paintings lose their brushwork** in the finished panel (wheat-field, Cézanne): the blur
   removes the texture that made them paintings; the result is pleasant but generic.
7. **C2-specific**: dropped highlights and subtle shapes, posterized patches (above).

## For a production version

- **C1 maps onto the existing pipeline.** pbn already labels regions, measures room, merges
  small regions and computes adjacency; C1 adds a barrier mask (the strokes' centerlines) to the
  region labelling, the opening-based snap and the cell rule. In numpy it takes 1-3 s per
  picture (1152x768 to 1690x1260; C2 7-25 s); in Swift with `Parallel.forEachBand` it would be a small
  fraction of `segment`.
- **Template format**: edges need a kind (line or guide) and lines their own stroke geometry and
  weight (stage 1's strokes), separate from region boundaries, which coincide with the stroke
  centerline after the snap. That is a new optional extension chunk (an edge-kind table plus a
  stroke list), not a format bump; old readers would draw every edge as today.
- **Label room must subtract the ink**: `LabelRoom` / `validate(minLabelRadius:)` measure against
  the region polygon; with weighted ink on top a number needs its room outside the ink's
  half-width, as measured here.
- **Cells too small for a number**: either stage 1 prunes or opens strokes that close a cell
  below `LabelSizing.minimumRadius(digits:)`, or the template lets a region span a line where
  the paint is the same on both sides (the rule used here; 85-90 % of such cells). The tap
  target then fills both sides and the line stays decorative; the drawing stays intact.
- **Finished rendering**: the domain-transform filter is separable and recursive (rows, then
  columns, three iterations, twice: one wide, one narrow, mixed by region size), deterministic;
  in numpy it dominates the 10-45 s the panels take per picture at 2x. On device it could run once when a painting completes (a
  Metal compute pass per row or column), or be precomputed at generation time and stored as a
  texture. Guides need the per-edge kind so they can fade once both sides are painted.
- **Determinism**: nothing is random; filters and merges are order-defined; two runs give
  byte-identical outputs. In Swift, row-parallel passes stay deterministic (rows are independent
  within a pass).

## Numbers

ΔE is the mean OKLab distance to the photo where the paint shows (outside the ink; pbn's raster
measured on the same pixels). "Cells too small" counts cells the drawing closed that cannot hold
a number: joined to a same-paint region across the line / absorbed (all ink) / kept with a
minimum-size number (= C1's regions below the minimum). Min room 1.50 = a kept cell. Slivers =
regions with room < 2 px or area/perimeter < 1 (almost all kept cells).

### Dev pictures, stage 1's picks (the Great Wave's are in the test table)

| picture | option | regions C1 / C2 (pbn) | areas | regions per area C1 / C2 | slivers C1 / C2 | cells too small (joined / absorbed / kept) | min room C1 / C2 | ΔE flat outside ink C1 / C2 (pbn) | ΔE finished C1 / C2 |
|---|---|---|---|---|---|---|---|---|---|
| barn | learned_hed-medium | 586 / 388 (482) | 91 | 6.8 / 4.6 | 1 / 3 | 52 (46 / 0 / 5) | 1.50 / 1.50 | 0.0336 / 0.0371 (0.0330) | 0.0355 / 0.0381 |
| barn | learned_pidinet-medium | 538 / 359 (482) | 49 | 11.2 / 7.6 | 1 / 2 | 22 (18 / 0 / 4) | 1.50 / 1.50 | 0.0340 / 0.0373 (0.0331) | 0.0363 / 0.0387 |
| barn | learned_teed-sparse | 511 / 359 (482) | 32 | 16.5 / 11.7 | 4 / 4 | 32 (21 / 3 / 5) | 1.50 / 1.50 | 0.0338 / 0.0369 (0.0330) | 0.0365 / 0.0385 |
| espresso | learned_hed-medium | 210 / 138 (198) | 14 | 15.6 / 10.1 | 1 / 4 | 12 (10 / 1 / 1) | 1.74 / 1.50 | 0.0313 / 0.0355 (0.0309) | 0.0334 / 0.0366 |
| espresso | learned_lineart_fine-medium | 234 / 160 (198) | 47 | 5.6 / 4.3 | 2 / 3 | 54 (50 / 0 / 4) | 1.50 / 1.50 | 0.0321 / 0.0365 (0.0313) | 0.0349 / 0.0383 |
| espresso | learned_teed-medium | 244 / 181 (198) | 67 | 4.1 / 3.1 | 8 / 12 | 59 (44 / 5 / 9) | 1.50 / 1.50 | 0.0311 / 0.0353 (0.0302) | 0.0339 / 0.0373 |
| hibiscus | boundaries-medium | 544 / 344 (506) | 195 | 2.9 / 1.9 | 4 / 4 | 40 (21 / 2 / 14) | 1.50 / 1.50 | 0.0321 / 0.0352 (0.0315) | 0.0351 / 0.0377 |
| hibiscus | learned_pidinet-medium | 629 / 330 (506) | 117 | 5.4 / 2.9 | 0 / 1 | 5 (5 / 0 / 0) | 2.33 / 1.74 | 0.0336 / 0.0386 (0.0326) | 0.0359 / 0.0407 |
| hibiscus | learned_teed-medium | 649 / 379 (506) | 236 | 3.1 / 1.9 | 2 / 3 | 98 (79 / 2 / 15) | 1.50 / 1.50 | 0.0322 / 0.0377 (0.0310) | 0.0361 / 0.0410 |
| kodim03 | learned_hed-medium | 164 / 131 (157) | 23 | 7.1 / 5.7 | 0 / 0 | 2 (0 / 0 / 1) | 3.11 / 3.11 | 0.0245 / 0.0251 (0.0243) | 0.0243 / 0.0247 |
| kodim03 | learned_lineart_fine-medium | 195 / 157 (157) | 66 | 3.5 / 2.9 | 2 / 2 | 43 (38 / 1 / 3) | 1.50 / 1.50 | 0.0256 / 0.0264 (0.0246) | 0.0260 / 0.0267 |
| kodim03 | learned_teed-medium | 211 / 168 (157) | 67 | 3.3 / 2.6 | 2 / 3 | 14 (10 / 0 / 4) | 1.50 / 1.50 | 0.0247 / 0.0254 (0.0242) | 0.0248 / 0.0255 |
| kodim04 | boundaries-medium | 417 / 286 (405) | 82 | 5.2 / 3.5 | 2 / 3 | 20 (8 / 2 / 8) | 1.74 / 1.50 | 0.0283 / 0.0308 (0.0276) | 0.0294 / 0.0315 |
| kodim04 | learned_hed-medium | 453 / 279 (405) | 53 | 8.7 / 5.5 | 0 / 0 | 10 (10 / 0 / 0) | 2.33 / 2.50 | 0.0286 / 0.0325 (0.0279) | 0.0293 / 0.0332 |
| kodim04 | learned_teed-sparse | 430 / 286 (405) | 26 | 16.7 / 11.1 | 1 / 1 | 4 (3 / 0 / 1) | 1.50 / 1.50 | 0.0285 / 0.0336 (0.0279) | 0.0296 / 0.0333 |
| kodim23 | learned_hed-medium | 278 / 207 (239) | 35 | 8.2 / 6.1 | 0 / 0 | 8 (8 / 0 / 0) | 2.33 / 2.33 | 0.0317 / 0.0349 (0.0313) | 0.0322 / 0.0350 |
| kodim23 | learned_lineart_fine-medium | 339 / 257 (239) | 58 | 6.2 / 5.1 | 2 / 2 | 28 (23 / 0 / 4) | 1.50 / 1.50 | 0.0322 / 0.0348 (0.0312) | 0.0329 / 0.0354 |
| kodim23 | learned_teed-medium | 320 / 248 (239) | 73 | 4.7 / 3.6 | 1 / 3 | 27 (22 / 1 / 3) | 1.50 / 1.50 | 0.0315 / 0.0341 (0.0309) | 0.0322 / 0.0346 |
| lighthouse | learned_hed-medium | 673 / 481 (607) | 79 | 8.8 / 6.3 | 1 / 2 | 27 (24 / 0 / 3) | 1.50 / 1.50 | 0.0332 / 0.0372 (0.0326) | 0.0349 / 0.0386 |
| lighthouse | learned_pidinet-medium | 644 / 466 (607) | 63 | 10.3 / 7.4 | 0 / 1 | 4 (4 / 0 / 0) | 2.33 / 2.33 | 0.0335 / 0.0367 (0.0330) | 0.0348 / 0.0378 |
| lighthouse | learned_teed-sparse | 669 / 490 (607) | 56 | 12.3 / 9.1 | 2 / 1 | 25 (20 / 1 / 2) | 1.50 / 1.50 | 0.0328 / 0.0364 (0.0323) | 0.0350 / 0.0376 |
| parrots | learned_hed-medium | 289 / 218 (257) | 26 | 11.3 / 8.5 | 1 / 1 | 6 (4 / 0 / 2) | 1.50 / 1.50 | 0.0304 / 0.0317 (0.0301) | 0.0314 / 0.0325 |
| parrots | learned_lineart_fine-medium | 343 / 245 (257) | 53 | 7.0 / 5.1 | 4 / 2 | 33 (27 / 1 / 4) | 1.50 / 1.74 | 0.0310 / 0.0321 (0.0300) | 0.0322 / 0.0333 |
| parrots | learned_teed-medium | 328 / 234 (257) | 66 | 5.3 / 3.9 | 1 / 2 | 30 (25 / 1 / 4) | 1.50 / 1.50 | 0.0302 / 0.0316 (0.0297) | 0.0314 / 0.0328 |
| regatta | learned_hed-medium | 319 / 211 (276) | 84 | 4.0 / 2.7 | 5 / 5 | 32 (24 / 0 / 7) | 1.50 / 1.50 | 0.0260 / 0.0279 (0.0252) | 0.0273 / 0.0290 |
| regatta | learned_pidinet-medium | 320 / 203 (276) | 65 | 5.1 / 3.3 | 3 / 3 | 15 (10 / 0 / 5) | 1.50 / 1.50 | 0.0267 / 0.0292 (0.0254) | 0.0279 / 0.0303 |
| regatta | learned_teed-medium | 384 / 222 (276) | 153 | 2.9 / 1.8 | 5 / 5 | 88 (70 / 12 / 8) | 1.50 / 1.50 | 0.0255 / 0.0284 (0.0246) | 0.0274 / 0.0301 |

### Test set

| picture | option | regions C1 / C2 (pbn) | areas | regions per area C1 / C2 | slivers C1 / C2 | cells too small (joined / absorbed / kept) | min room C1 / C2 | ΔE flat outside ink C1 / C2 (pbn) | ΔE finished C1 / C2 |
|---|---|---|---|---|---|---|---|---|---|
| cezanne-apples | boundaries-medium | 577 / 460 (538) | 53 | 11.2 / 8.7 | 3 / 3 | 28 (21 / 3 / 5) | 1.50 / 1.50 | 0.0308 / 0.0352 (0.0307) | 0.0315 / 0.0351 |
| cezanne-apples | flowdog-medium | 554 / 458 (538) | 8 | 69.9 / 57.9 | 1 / 1 | 8 (6 / 1 / 1) | 1.74 / 1.74 | 0.0320 / 0.0363 (0.0312) | 0.0335 / 0.0365 |
| cezanne-apples | learned_hed-medium | 640 / 502 (538) | 64 | 10.3 / 8.4 | 0 / 0 | 25 (24 / 0 / 1) | 2.33 / 2.33 | 0.0311 / 0.0333 (0.0309) | 0.0318 / 0.0337 |
| cezanne-apples | learned_lineart_anime-medium | 731 / 595 (538) | 307 | 3.1 / 2.6 | 4 / 9 | 249 (238 / 2 / 8) | 1.50 / 1.50 | 0.0322 / 0.0366 (0.0311) | 0.0333 / 0.0366 |
| cezanne-apples | learned_lineart_coarse-medium | 715 / 551 (538) | 260 | 3.5 / 2.8 | 6 / 14 | 276 (250 / 5 / 11) | 1.50 / 1.50 | 0.0319 / 0.0354 (0.0310) | 0.0330 / 0.0358 |
| cezanne-apples | learned_lineart_fine-medium | 791 / 632 (538) | 343 | 3.0 / 2.6 | 11 / 18 | 323 (302 / 3 / 18) | 1.50 / 1.50 | 0.0318 / 0.0359 (0.0310) | 0.0327 / 0.0359 |
| cezanne-apples | learned_pidinet-medium | 585 / 479 (538) | 25 | 23.7 / 19.4 | 1 / 1 | 9 (7 / 0 / 1) | 1.50 / 1.50 | 0.0313 / 0.0341 (0.0310) | 0.0320 / 0.0342 |
| cezanne-apples | learned_teed-medium | 759 / 562 (538) | 170 | 5.0 / 3.8 | 1 / 4 | 110 (101 / 1 / 6) | 1.50 / 1.50 | 0.0312 / 0.0343 (0.0308) | 0.0318 / 0.0345 |
| cezanne-apples | xdog-medium | 686 / 546 (538) | 78 | 9.1 / 7.4 | 1 / 3 | 33 (30 / 1 / 2) | 1.50 / 1.50 | 0.0333 / 0.0378 (0.0312) | 0.0343 / 0.0377 |
| delicate-arch | boundaries-medium | 736 / 570 (618) | 383 | 2.1 / 1.6 | 8 / 9 | 83 (58 / 5 / 19) | 1.50 / 1.50 | 0.0389 / 0.0399 (0.0385) | 0.0399 / 0.0408 |
| delicate-arch | flowdog-medium | 1176 / 774 (618) | 350 | 3.7 / 2.5 | 5 / 12 | 187 (159 / 10 / 13) | 1.50 / 1.50 | 0.0416 / 0.0429 (0.0383) | 0.0447 / 0.0460 |
| delicate-arch | learned_hed-medium | 689 / 559 (618) | 71 | 10.0 / 8.2 | 2 / 4 | 30 (26 / 0 / 4) | 1.50 / 1.50 | 0.0397 / 0.0406 (0.0395) | 0.0405 / 0.0414 |
| delicate-arch | learned_lineart_anime-medium | 1158 / 944 (618) | 714 | 2.3 / 2.0 | 21 / 42 | 612 (571 / 11 / 26) | 1.50 / 1.50 | 0.0416 / 0.0430 (0.0389) | 0.0435 / 0.0449 |
| delicate-arch | learned_lineart_coarse-medium | 1183 / 869 (618) | 620 | 2.5 / 2.0 | 26 / 44 | 564 (494 / 17 / 39) | 1.50 / 1.50 | 0.0409 / 0.0427 (0.0387) | 0.0429 / 0.0447 |
| delicate-arch | learned_lineart_fine-medium | 1455 / 987 (618) | 1068 | 1.9 / 1.5 | 33 / 48 | 823 (709 / 39 / 57) | 1.50 / 1.50 | 0.0414 / 0.0432 (0.0385) | 0.0437 / 0.0454 |
| delicate-arch | learned_pidinet-medium | 679 / 554 (618) | 28 | 24.4 / 20.0 | 0 / 0 | 5 (5 / 0 / 0) | 2.33 / 2.33 | 0.0400 / 0.0412 (0.0398) | 0.0404 / 0.0415 |
| delicate-arch | learned_teed-medium | 1055 / 762 (618) | 478 | 2.8 / 2.2 | 4 / 14 | 398 (364 / 15 / 16) | 1.50 / 1.50 | 0.0394 / 0.0408 (0.0385) | 0.0410 / 0.0424 |
| delicate-arch | xdog-medium | 881 / 733 (618) | 130 | 7.0 / 6.0 | 0 / 2 | 40 (36 / 0 / 4) | 2.33 / 1.50 | 0.0434 / 0.0453 (0.0397) | 0.0446 / 0.0465 |
| great-wave | boundaries-medium | 493 / 548 (420) | 295 | 1.8 / 1.9 | 7 / 8 | 44 (31 / 3 / 10) | 1.50 / 1.50 | 0.0406 / 0.0435 (0.0399) | 0.0440 / 0.0466 |
| great-wave | flowdog-medium | 877 / 645 (420) | 366 | 2.7 / 2.1 | 3 / 7 | 139 (125 / 4 / 7) | 1.50 / 1.50 | 0.0437 / 0.0505 (0.0381) | 0.0531 / 0.0601 |
| great-wave | learned_hed-medium | 683 / 611 (420) | 267 | 2.9 / 2.6 | 1 / 4 | 107 (102 / 1 / 3) | 1.50 / 1.50 | 0.0397 / 0.0417 (0.0388) | 0.0448 / 0.0466 |
| great-wave | learned_lineart_anime-medium | 969 / 682 (420) | 670 | 1.9 / 1.5 | 5 / 20 | 397 (374 / 6 / 13) | 1.50 / 1.50 | 0.0433 / 0.0492 (0.0379) | 0.0521 / 0.0580 |
| great-wave | learned_lineart_coarse-medium | 950 / 657 (420) | 582 | 2.0 / 1.5 | 4 / 9 | 290 (280 / 2 / 7) | 1.50 / 1.50 | 0.0432 / 0.0506 (0.0384) | 0.0515 / 0.0587 |
| great-wave | learned_lineart_fine-medium | 928 / 691 (420) | 584 | 2.0 / 1.6 | 11 / 16 | 306 (285 / 4 / 18) | 1.50 / 1.50 | 0.0418 / 0.0470 (0.0378) | 0.0507 / 0.0559 |
| great-wave | learned_pidinet-medium | 600 / 602 (420) | 121 | 5.1 / 5.2 | 2 / 1 | 27 (24 / 0 / 3) | 1.50 / 1.50 | 0.0416 / 0.0457 (0.0407) | 0.0449 / 0.0484 |
| great-wave | learned_teed-medium | 975 / 715 (420) | 753 | 1.7 / 1.3 | 6 / 18 | 356 (343 / 2 / 10) | 1.50 / 1.50 | 0.0360 / 0.0404 (0.0349) | 0.0445 / 0.0491 |
| great-wave | xdog-medium | 982 / 945 (420) | 494 | 2.2 / 2.1 | 3 / 6 | 106 (96 / 2 / 6) | 1.74 / 1.50 | 0.0513 / 0.0559 (0.0395) | 0.0578 / 0.0613 |
| hawksbill-turtle | boundaries-medium | 1157 / 762 (950) | 675 | 1.8 / 1.2 | 36 / 43 | 229 (113 / 23 / 74) | 1.50 / 1.50 | 0.0415 / 0.0448 (0.0406) | 0.0439 / 0.0475 |
| hawksbill-turtle | flowdog-medium | 1399 / 951 (950) | 251 | 5.8 / 4.1 | 5 / 8 | 100 (76 / 10 / 14) | 1.50 / 1.50 | 0.0450 / 0.0476 (0.0418) | 0.0473 / 0.0501 |
| hawksbill-turtle | learned_hed-medium | 1054 / 838 (950) | 142 | 7.8 / 6.3 | 6 / 11 | 85 (64 / 3 / 12) | 1.50 / 1.50 | 0.0435 / 0.0459 (0.0424) | 0.0442 / 0.0466 |
| hawksbill-turtle | learned_lineart_anime-medium | 1406 / 1043 (950) | 621 | 2.9 / 2.3 | 17 / 36 | 548 (499 / 14 / 27) | 1.50 / 1.50 | 0.0448 / 0.0477 (0.0420) | 0.0464 / 0.0494 |
| hawksbill-turtle | learned_lineart_coarse-medium | 1436 / 980 (950) | 539 | 3.2 / 2.4 | 7 / 48 | 467 (422 / 25 / 12) | 1.50 / 1.50 | 0.0450 / 0.0489 (0.0421) | 0.0464 / 0.0503 |
| hawksbill-turtle | learned_lineart_fine-medium | 1374 / 1010 (950) | 445 | 3.6 / 2.9 | 14 / 29 | 362 (310 / 15 / 25) | 1.50 / 1.50 | 0.0444 / 0.0469 (0.0418) | 0.0464 / 0.0490 |
| hawksbill-turtle | learned_pidinet-medium | 1011 / 889 (950) | 41 | 24.8 / 21.8 | 0 / 2 | 9 (7 / 3 / 1) | 2.33 / 1.50 | 0.0436 / 0.0461 (0.0428) | 0.0437 / 0.0461 |
| hawksbill-turtle | learned_teed-medium | 1608 / 836 (950) | 956 | 2.1 / 1.3 | 35 / 70 | 678 (542 / 30 / 69) | 1.50 / 1.50 | 0.0428 / 0.0491 (0.0404) | 0.0462 / 0.0526 |
| hawksbill-turtle | xdog-medium | 1366 / 896 (950) | 259 | 5.5 / 3.7 | 4 / 10 | 83 (66 / 3 / 10) | 1.50 / 1.50 | 0.0466 / 0.0495 (0.0428) | 0.0474 / 0.0503 |
| lassen-lupine | boundaries-sparse | 956 / 991 (815) | 145 | 6.8 / 7.4 | 4 / 7 | 39 (34 / 1 / 4) | 1.50 / 1.50 | 0.0624 / 0.0666 (0.0615) | 0.0664 / 0.0697 |
| lassen-lupine | flowdog-sparse | 1603 / 1373 (815) | 199 | 8.4 / 8.3 | 0 / 4 | 88 (83 / 5 / 1) | 2.33 / 1.50 | 0.0664 / 0.0718 (0.0615) | 0.0709 / 0.0754 |
| lassen-lupine | learned_hed-sparse | 951 / 942 (815) | 44 | 21.8 / 22.0 | 2 / 5 | 17 (14 / 0 / 3) | 1.50 / 1.50 | 0.0632 / 0.0673 (0.0624) | 0.0667 / 0.0691 |
| lassen-lupine | learned_lineart_anime-sparse | 845 / 915 (815) | 21 | 40.8 / 44.1 | 1 / 1 | 12 (11 / 0 / 1) | 1.50 / 1.50 | 0.0634 / 0.0669 (0.0631) | 0.0657 / 0.0681 |
| lassen-lupine | learned_lineart_coarse-sparse | 1143 / 1050 (815) | 130 | 9.5 / 9.5 | 2 / 7 | 104 (101 / 1 / 2) | 1.50 / 1.50 | 0.0642 / 0.0681 (0.0623) | 0.0676 / 0.0707 |
| lassen-lupine | learned_lineart_fine-sparse | 1131 / 1104 (815) | 137 | 8.9 / 8.8 | 0 / 6 | 105 (99 / 4 / 4) | 2.33 / 1.50 | 0.0644 / 0.0682 (0.0625) | 0.0677 / 0.0705 |
| lassen-lupine | learned_pidinet-sparse | 851 / 864 (815) | 19 | 45.1 / 48.1 | 0 / 1 | 6 (6 / 0 / 0) | 2.33 / 1.50 | 0.0635 / 0.0672 (0.0628) | 0.0665 / 0.0689 |
| lassen-lupine | learned_teed-sparse | 1127 / 1099 (815) | 153 | 8.0 / 8.0 | 2 / 9 | 111 (105 / 0 / 5) | 1.50 / 1.50 | 0.0627 / 0.0670 (0.0615) | 0.0669 / 0.0702 |
| lassen-lupine | xdog-sparse | 892 / 925 (815) | 20 | 44.9 / 46.5 | 0 / 0 | 6 (5 / 1 / 0) | 2.33 / 2.33 | 0.0641 / 0.0680 (0.0630) | 0.0667 / 0.0699 |
| milkmaid | boundaries-sparse | 519 / 432 (486) | 47 | 11.2 / 9.3 | 4 / 5 | 17 (7 / 2 / 8) | 1.50 / 1.50 | 0.0315 / 0.0342 (0.0313) | 0.0310 / 0.0338 |
| milkmaid | flowdog-sparse | 584 / 481 (486) | 25 | 23.7 / 19.6 | 0 / 0 | 11 (9 / 1 / 1) | 2.33 / 2.33 | 0.0331 / 0.0359 (0.0317) | 0.0331 / 0.0359 |
| milkmaid | learned_hed-sparse | 542 / 448 (486) | 20 | 27.2 / 22.6 | 0 / 0 | 8 (3 / 0 / 3) | 2.33 / 2.33 | 0.0318 / 0.0341 (0.0316) | 0.0310 / 0.0334 |
| milkmaid | learned_lineart_anime-sparse | 542 / 488 (486) | 44 | 13.2 / 12.5 | 1 / 2 | 47 (46 / 0 / 1) | 1.50 / 1.50 | 0.0327 / 0.0351 (0.0320) | 0.0318 / 0.0342 |
| milkmaid | learned_lineart_coarse-sparse | 583 / 494 (486) | 72 | 8.8 / 7.7 | 3 / 7 | 72 (63 / 5 / 3) | 1.50 / 1.50 | 0.0331 / 0.0356 (0.0318) | 0.0327 / 0.0351 |
| milkmaid | learned_lineart_fine-sparse | 605 / 519 (486) | 136 | 5.2 / 4.6 | 7 / 9 | 129 (108 / 9 / 9) | 1.50 / 1.50 | 0.0332 / 0.0358 (0.0318) | 0.0327 / 0.0354 |
| milkmaid | learned_pidinet-sparse | 541 / 440 (486) | 13 | 41.8 / 34.0 | 0 / 0 | 2 (2 / 0 / 0) | 2.33 / 2.50 | 0.0320 / 0.0343 (0.0317) | 0.0310 / 0.0333 |
| milkmaid | learned_teed-sparse | 594 / 500 (486) | 66 | 9.4 / 8.0 | 3 / 4 | 45 (36 / 0 / 8) | 1.50 / 1.50 | 0.0316 / 0.0344 (0.0313) | 0.0313 / 0.0341 |
| milkmaid | xdog-sparse | 565 / 492 (486) | 24 | 23.8 / 20.8 | 1 / 1 | 8 (7 / 0 / 1) | 1.50 / 1.50 | 0.0336 / 0.0362 (0.0320) | 0.0326 / 0.0353 |
| red-fox | boundaries-medium | 270 / 198 (234) | 54 | 5.1 / 3.7 | 9 / 9 | 29 (5 / 5 / 13) | 1.50 / 1.50 | 0.0165 / 0.0185 (0.0164) | 0.0179 / 0.0189 |
| red-fox | flowdog-medium | 248 / 167 (234) | 6 | 41.7 / 28.2 | 0 / 0 | 3 (3 / 0 / 0) | 2.33 / 2.50 | 0.0172 / 0.0191 (0.0169) | 0.0181 / 0.0192 |
| red-fox | learned_hed-medium | 272 / 189 (234) | 8 | 34.1 / 23.8 | 0 / 0 | 1 (1 / 0 / 0) | 2.33 / 2.33 | 0.0168 / 0.0187 (0.0166) | 0.0178 / 0.0187 |
| red-fox | learned_lineart_anime-medium | 259 / 177 (234) | 33 | 8.5 / 5.9 | 0 / 0 | 36 (34 / 1 / 1) | 2.33 / 2.50 | 0.0171 / 0.0191 (0.0169) | 0.0179 / 0.0190 |
| red-fox | learned_lineart_coarse-medium | 584 / 406 (234) | 172 | 4.1 / 3.0 | 2 / 7 | 152 (148 / 1 / 3) | 1.50 / 1.50 | 0.0174 / 0.0198 (0.0167) | 0.0181 / 0.0198 |
| red-fox | learned_lineart_fine-medium | 488 / 326 (234) | 151 | 3.8 / 2.8 | 3 / 3 | 110 (104 / 4 / 3) | 1.50 / 1.50 | 0.0173 / 0.0194 (0.0167) | 0.0182 / 0.0197 |
| red-fox | learned_pidinet-medium | 270 / 187 (234) | 7 | 38.9 / 27.0 | 0 / 0 | 2 (2 / 0 / 0) | 2.33 / 2.33 | 0.0167 / 0.0188 (0.0166) | 0.0178 / 0.0190 |
| red-fox | learned_teed-medium | 380 / 268 (234) | 51 | 7.9 / 5.7 | 0 / 0 | 30 (27 / 0 / 3) | 2.33 / 2.33 | 0.0167 / 0.0188 (0.0165) | 0.0179 / 0.0191 |
| red-fox | xdog-medium | 282 / 183 (234) | 23 | 12.3 / 8.0 | 0 / 0 | 3 (1 / 0 / 2) | 2.33 / 2.50 | 0.0174 / 0.0196 (0.0168) | 0.0184 / 0.0196 |
| santa-fe-freight | boundaries-medium | 376 / 318 (322) | 157 | 2.6 / 2.2 | 8 / 9 | 59 (40 / 9 / 13) | 1.50 / 1.50 | 0.0211 / 0.0217 (0.0209) | 0.0186 / 0.0192 |
| santa-fe-freight | flowdog-medium | 527 / 426 (322) | 122 | 4.5 / 3.7 | 5 / 6 | 38 (29 / 1 / 7) | 1.50 / 1.50 | 0.0235 / 0.0245 (0.0213) | 0.0226 / 0.0236 |
| santa-fe-freight | learned_hed-medium | 451 / 371 (322) | 172 | 2.9 / 2.5 | 3 / 4 | 65 (57 / 1 / 6) | 1.50 / 1.50 | 0.0214 / 0.0222 (0.0210) | 0.0194 / 0.0203 |
| santa-fe-freight | learned_lineart_anime-medium | 623 / 490 (322) | 366 | 2.3 / 1.9 | 5 / 7 | 257 (241 / 3 / 9) | 1.50 / 1.50 | 0.0238 / 0.0255 (0.0213) | 0.0223 / 0.0239 |
| santa-fe-freight | learned_lineart_coarse-medium | 688 / 479 (322) | 437 | 2.1 / 1.6 | 13 / 13 | 312 (280 / 6 / 17) | 1.50 / 1.50 | 0.0240 / 0.0256 (0.0213) | 0.0226 / 0.0242 |
| santa-fe-freight | learned_lineart_fine-medium | 685 / 514 (322) | 467 | 2.0 / 1.6 | 21 / 27 | 331 (275 / 18 / 29) | 1.50 / 1.50 | 0.0236 / 0.0251 (0.0212) | 0.0224 / 0.0238 |
| santa-fe-freight | learned_pidinet-medium | 467 / 346 (322) | 149 | 3.3 / 2.5 | 2 / 3 | 39 (34 / 0 / 5) | 1.50 / 1.50 | 0.0218 / 0.0229 (0.0212) | 0.0195 / 0.0207 |
| santa-fe-freight | learned_teed-medium | 574 / 418 (322) | 338 | 2.2 / 1.7 | 6 / 15 | 207 (190 / 18 / 9) | 1.50 / 1.50 | 0.0209 / 0.0221 (0.0204) | 0.0192 / 0.0205 |
| santa-fe-freight | xdog-medium | 499 / 392 (322) | 164 | 3.2 / 2.5 | 1 / 0 | 31 (22 / 3 / 5) | 1.50 / 2.33 | 0.0251 / 0.0262 (0.0216) | 0.0236 / 0.0245 |
| wheat-field | boundaries-sparse | 694 / 622 (643) | 58 | 12.5 / 12.2 | 3 / 5 | 45 (39 / 0 / 6) | 1.50 / 1.50 | 0.0548 / 0.0583 (0.0545) | 0.0574 / 0.0596 |
| wheat-field | flowdog-sparse | 1086 / 847 (643) | 123 | 9.6 / 7.7 | 0 / 0 | 111 (109 / 2 / 0) | 2.33 / 2.33 | 0.0554 / 0.0592 (0.0540) | 0.0586 / 0.0611 |
| wheat-field | learned_hed-sparse | 779 / 633 (643) | 41 | 19.6 / 16.0 | 0 / 0 | 25 (25 / 0 / 0) | 2.33 / 2.33 | 0.0549 / 0.0578 (0.0545) | 0.0574 / 0.0600 |
| wheat-field | learned_lineart_anime-sparse | 707 / 629 (643) | 23 | 31.6 / 28.1 | 0 / 1 | 32 (31 / 1 / 0) | 2.33 / 1.50 | 0.0550 / 0.0587 (0.0547) | 0.0577 / 0.0600 |
| wheat-field | learned_lineart_coarse-sparse | 807 / 693 (643) | 76 | 11.4 / 9.9 | 0 / 1 | 78 (73 / 4 / 0) | 2.33 / 1.50 | 0.0553 / 0.0590 (0.0546) | 0.0582 / 0.0606 |
| wheat-field | learned_lineart_fine-sparse | 800 / 698 (643) | 83 | 10.5 / 9.5 | 0 / 3 | 83 (79 / 4 / 0) | 2.33 / 1.50 | 0.0554 / 0.0592 (0.0546) | 0.0582 / 0.0606 |
| wheat-field | learned_pidinet-sparse | 663 / 566 (643) | 5 | 133.0 / 113.6 | 0 / 0 | 3 (3 / 0 / 0) | 2.50 / 2.33 | 0.0550 / 0.0578 (0.0548) | 0.0577 / 0.0601 |
| wheat-field | learned_teed-sparse | 783 / 631 (643) | 34 | 23.8 / 19.2 | 1 / 1 | 32 (31 / 0 / 1) | 1.50 / 1.50 | 0.0545 / 0.0573 (0.0542) | 0.0575 / 0.0600 |
| wheat-field | xdog-sparse | 714 / 633 (643) | 24 | 30.2 / 27.9 | 1 / 1 | 12 (11 / 0 / 1) | 1.50 / 1.50 | 0.0553 / 0.0590 (0.0548) | 0.0580 / 0.0604 |

### By family (all options above)

| family | method | options | regions / pbn (median) | slivers (mean) | cells too small (mean) | kept below min (mean) | ΔE flat / pbn, outside ink (median) | ΔE finished (median) | unlined share (median) |
|---|---|---|---|---|---|---|---|---|---|
| boundaries | C1 | 11 | 1.15 | 8.0 | 57.5 | 15.8 | 1.01 | 0.0351 | 0.50 |
| boundaries | C2 | 11 | 0.89 | 9.5 | 49.0 | 18.2 | 1.09 | 0.0377 | 0.53 |
| flowdog | C1 | 9 | 1.64 | 2.1 | 76.1 | 4.9 | 1.08 | 0.0447 | 0.60 |
| flowdog | C2 | 9 | 1.25 | 4.2 | 65.3 | 10.3 | 1.14 | 0.0460 | 0.59 |
| learned_hed | C1 | 17 | 1.16 | 1.4 | 30.1 | 3.0 | 1.01 | 0.0322 | 0.79 |
| learned_hed | C2 | 17 | 0.87 | 2.5 | 25.2 | 4.9 | 1.08 | 0.0350 | 0.77 |
| learned_lineart_anime | C1 | 9 | 1.36 | 6.0 | 243.3 | 9.6 | 1.04 | 0.0435 | 0.79 |
| learned_lineart_anime | C2 | 9 | 1.11 | 13.1 | 205.1 | 19.6 | 1.13 | 0.0449 | 0.78 |
| learned_lineart_coarse | C1 | 9 | 1.51 | 7.0 | 257.2 | 10.4 | 1.04 | 0.0429 | 0.67 |
| learned_lineart_coarse | C2 | 9 | 1.29 | 16.7 | 203.4 | 24.0 | 1.14 | 0.0447 | 0.62 |
| learned_lineart_fine | C1 | 13 | 1.42 | 8.5 | 210.0 | 13.7 | 1.04 | 0.0329 | 0.72 |
| learned_lineart_fine | C2 | 13 | 1.09 | 12.9 | 180.1 | 22.0 | 1.12 | 0.0359 | 0.71 |
| learned_pidinet | C1 | 13 | 1.11 | 0.7 | 11.4 | 1.5 | 1.02 | 0.0359 | 0.83 |
| learned_pidinet | C2 | 13 | 0.89 | 1.2 | 10.3 | 2.1 | 1.10 | 0.0387 | 0.82 |
| learned_teed | C1 | 18 | 1.34 | 4.7 | 130.2 | 9.9 | 1.02 | 0.0330 | 0.70 |
| learned_teed | C2 | 18 | 1.01 | 9.4 | 107.8 | 18.6 | 1.12 | 0.0359 | 0.67 |
| xdog | C1 | 9 | 1.28 | 1.2 | 35.8 | 3.4 | 1.07 | 0.0446 | 0.78 |
| xdog | C2 | 9 | 1.01 | 2.6 | 33.0 | 6.1 | 1.16 | 0.0465 | 0.77 |

| detail | method | options | regions / pbn (median) | slivers (mean) | cells too small (mean) | kept below min (mean) | ΔE flat / pbn, outside ink (median) | ΔE finished (median) | unlined share (median) |
|---|---|---|---|---|---|---|---|---|---|
| medium | C1 | 78 | 1.33 | 5.4 | 135.5 | 10.1 | 1.03 | 0.0334 | 0.69 |
| medium | C2 | 78 | 0.99 | 9.5 | 112.9 | 16.7 | 1.13 | 0.0365 | 0.66 |
| sparse | C1 | 30 | 1.16 | 1.4 | 43.6 | 2.3 | 1.01 | 0.0576 | 0.84 |
| sparse | C2 | 30 | 1.01 | 2.9 | 37.8 | 5.5 | 1.09 | 0.0600 | 0.83 |

## Reproducing

Panels need Source Serif 4 (`$S/fonts/SourceSerif4-Regular.ttf`, from
`raw.githubusercontent.com/adobe-fonts/source-serif`, release branch, TTF; set `PANEL_FONT` to
use another) and, for the current-template comparison, node 22 with `@resvg/resvg-js`
installed in `$S/node` (`npm install @resvg/resvg-js`, plus a copy of `tools/svg2png.mjs`;
`PANEL_NODE` / `PANEL_NODE_DIR` override). Python: the shared venv (numpy, scipy, pillow,
opencv-python-headless, scikit-image).

```sh
cd research/lineart
# one option
python run_color.py $S/lineart/inputs/parrots $S/lineart/out/parrots/learned_hed-medium --method both --flat
# stage 1's picks, then a picks file per picture for the test set; outputs go next to stage 1's
python run_color.py --batch $S/lineart/out --picks $S/lineart/out/stage1_picks.json --flat --jobs 2
python run_color.py --batch $S/lineart/out --picks color_test_picks.json --flat --jobs 2
python run_color.py --summarize $S/lineart/out
python color_report.py $S/lineart/out/summary_color.json --by-family
python panel_sheet.py $S/lineart/out/parrots/learned_hed-medium      # sheet.jpg for looking
```
