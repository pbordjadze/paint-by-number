# Core workstream report (wave 3: layered lines)

Branch `claude/layered-core`, cut from the contract commit 0ccb8df. Commits:

- `7ae42a1` the generator, the `LINE` chunk and the pbn flags (pushed early, merged by the
  orchestrator for the app workstreams);
- `43e372a` tuned defaults, `PipelineTuning`, the Auto pass-through, the fixture, eval and bench;
- `823dd2e` closed interior strokes, `CLAUDE.md`;
- this report.

Everything is in PaintCore, `pbn` and `tools/`. The app is untouched.

## What I built

### `Sources/PaintCore/LineArt/`: the layered pipeline

`LayeredLines.apply(segmentation, input:, importance:, settings:)` runs between segmentation
and vectorizing when `lineArt.style == .layered` and an edge map is given; layered settings
without a map give the classic template. Stages, timed as `lineArt.*`:

1. **detect** (`LineDetection`). The 8-bit map is resampled to the working size (area
   average when shrinking, linear when enlarging). Ridges are found by Hessian non-maximum
   suppression, with the Hessian at 1.5 map pixels so it spans HED's soft lines, and they need
   real downward curvature so a saturated plateau is no ridge. Then hysteresis at
   `textureThreshold` (candidates down to half of it, ±15 % by importance), a 3×3 closing,
   Zhang–Suen thinning and removal of staircase corners. A clutter map measures line density
   relative to the canvas size, so a lone line never counts as crowded at any canvas size.
2. **trace** (`StrokeGraph`), a port of the research's `strokes.py` graph:
   - nodes and chains, then popped bubbles and pruned spurs and specks;
   - gap bridging (`gapBridging`): end to end, or end onto a line;
   - fragments under `minimumStrokeLength` dropped, free ends led into the frame;
   - edges joined through junctions by alignment, Gaussian-smoothed with the ends pinned
     (σ = 4 × `lineSmoothing`).

   Every point carries its edge strength.
3. **layer** (`LineLayering`).
   - Per point, 1D hysteresis along the stroke for outline, detail and texture. A stretch
     above 60 % (outline) or 50 % of a threshold belongs to that layer once it has held the
     threshold for 5 units. The sustained seed matters: without it, a faint line touching a
     strong one is promoted by the strength blurred into the junction.
   - Short layer flickers follow their neighbours.
   - The outline threshold rises toward 1 with clutter, except on outline stretches longer
     than 150 units (on a 1500-unit canvas).
   - Eyes: lines inside an eye are cleared, lines around it are promoted one layer, and its
     polygons become closed outlines.
   - Free ends reach for the nearest line, paint boundary or frame (`gapBridging` × 1.6,
     1.2 or 1 by layer).
4. **cells** (`CellMap`).
   - The segmentation is split along the rasterized lines, with the research's snap of thin
     strips onto walls; cells keep their paint.
   - Cells too small for their number merge inside their enclosed area, then wall pixels are
     assigned.
   - Cells still too small merge across a line: into the same paint across the weakest line
     first, else into the closest paint.
   - Room is the vectorizer's own measure (`interiorDistance` ≥ `minRadius(digits:)`), so
     every label keeps its legibility guarantee.
   - With `keepColorEdges` off, line-free neighbours within two palette steps merge.
5. **trim**: lines keep only the stretches along a cell boundary; eyes are kept whole.
6. **join**: same-paint neighbours join per `SamePaint`. Lines that end up inside a cell
   become interior strokes, split by cell. Unused paints are dropped and cells renumbered,
   with 4-connectivity checked.
7. **annotate** (after `Vectorizer`). Each template edge takes the layer of the drawn line
   along most of it (within 3 units), or `color`. Its weight is the line's mean strength, or
   for color edges the paint difference. Interior strokes are simplified (Douglas–Peucker,
   0.3), moved to canvas coordinates and quantized. A stroke that closes on itself (an eye
   inside one cell) repeats its first point.

`Template.lineArt` is filled, and `TemplateGenerator.Output.lineArtStats` reports what
happened: cells at each step, joins, ends closed, eyes, and line length per layer on cell
boundaries and inside cells.

### Coding and validation

- **`LINE` extension chunk**: optional, so old readers draw every edge alike. Layout:
  `edgeCount` (must equal the template's), a layer and a weight byte per edge, the
  interior-stroke points, and 14-byte strokes. Hostile-input checks:
  - counts against the bytes left;
  - edge count, layer values, stroke spans in `Int` arithmetic, regions, and points
    (finite, inside the canvas) in `validateReferences`;
  - duplicate chunk; a short payload is `corrupt("LINE")`, trailing fields are allowed.
- **`validate()`** gains `badLines`, nil for classic templates, so their report text is
  unchanged. It checks counts, layers and spans, and that every interior-stroke point lies in
  or touches its region's pixels. `pbn check` prints edges per layer and interior strokes.
- **Fixture** `Tests/PaintCoreTests/Fixtures/template-v2-lines.pbnt` (11 152 bytes), made by
  `pbn` from the committed scene `layered-photo.ppm` / `layered-edges.pgm` (36 KB + 12 KB). It
  has every layer and one interior stroke. Tests:
  - its decode test pins the bytes and re-encodes them identically;
  - it joins the every-prefix truncation and random-corruption tests;
  - crafted references and malformed sections each throw `corrupt`.

### `PipelineTuning` and Auto

- `SegmentationParameters.init` multiplies the knobs each factor names:
  - smoothing → `smoothSpatial`;
  - texture flattening → `textureFlattening`;
  - minimum cell size → `minArea`;
  - subject emphasis → `importanceStrength` and `importanceSharpening`;
  - accent colors → `paletteSaliency`;
  - colorfulness → `chromaScale`.

  Palette separation is measured in plain OKLab, so the paint-distance floor holds at any
  colorfulness. A factor of exactly 1 is bit-for-bit neutral; a Mirror-based test checks that
  each factor moves exactly its knobs.
- `AutoSettings.choose(…, lineArt:, tuning:)` (the orchestrator approved this): optional, and
  nil means unchanged behaviour. Every candidate carries them; the tuning reaches the drafts
  Auto scores, while line art doesn't (drafts get no edge map). pbn passes its own values.

### SVG, pbn, tools

- SVG: a layered template draws one group per layer (`lines-color`, `-texture`, `-detail`,
  `-outline`, faintest first), with edges and interior strokes in ink `#2b2530`, at the app's
  default `LineAppearance` 1× opacity and width (`SVGExport.Options.layerStyles`).
- `pbn generate --line-style layered --edges map.pgm [--eyes eyes.json] [--line-art key=value]…
  [--tuning key=value]…` (field names, validated with clear errors). `stats.json` gains:
  - `lineArt`: settings, stats, edges and length per layer, interior strokes, `cellsVsClassic`;
  - `tuning`, when not default.

  `pbn bench --edges` times the layered stages.
- `eval.py --edges-dir/--eyes-dir` (per-image `<name>.pgm` / `<name>.json`; the caption adds the
  layered numbers).
- `CLAUDE.md`: layout, pbn, eval and saved-data notes.

## Tests and gates

- `tools/swift.sh test`: **189 tests in 14 suites passed** (160 before). New:
  - `LineArtTests` (23): generation validity; classic ignores the map; determinism; the three
    `SamePaint` modes; eyes, including one too small for a number; close-color merging; a map
    at half resolution; an empty map; hysteresis; clutter; thinning; gap bridging;
    cancellation at every stage; coding round trip, optional chunk, truncation, corruption,
    crafted references, validation; the fixture.
  - `PipelineTuningTests` (6): factor isolation, clamping, effect on cells, tolerant decoding
    of settings, Auto pass-through.
- `python3 tools/regression.py`: **24 cases: all pass, every template "same" as the
  baseline**; no baseline change. `--self-test` passed (74 checks).
- **Determinism**: two runs give byte-identical templates (test). On real pictures
  (red-fox, barn), runs pinned to 1, 3 and 4 cores also give identical bytes.
- **Robustness**, all valid:
  - a pure-noise edge map at 1152 px: 1.7 s, 3672 cells;
  - a saturated map: detect was 1.5 s before the curvature guard, 0.2 s after;
  - every threshold at 0, and gap 40, at 2100 px: ~4 s;
  - a 12×9 photo.

## Timings (`pbn bench --edges`, lighthouse, 1152×768, median of 5, this shared 4-core box)

| stage | ms |
| --- | ---: |
| lineArt.detect | 41 |
| lineArt.trace | 13 |
| lineArt.layer | 5 |
| lineArt.cells (split 36, small 18, walls 2, tiny 14) | 72 |
| lineArt.trim | 12 |
| lineArt.join | 19 |
| **lineArt** | **180** |
| lineArt.annotate | 37 |
| layered total (640 cells) | 420 |
| classic total (563 regions) | 242 |

Two changes got here:

- The tiny-cell merge measures room once, then only for groups of short cells, with
  neighbour scans limited to their bounds. Adjacency counts run in parallel. Output is
  unchanged (byte-compared), and cells went from 113 to 72 ms.
- The longest stretch without a cancellation check fell from 76 to 23 ms (classic at
  detail 1: 18–28 ms).

At the research's working sizes (~1690 px) the layered stages take 340–560 ms plus 55–150 ms of
annotation.

## Sheets I looked at, and the defaults

Inputs: HED maps made with the research's `lines_learned.py` at ≤ 1152 px (the app's
`EdgeDetector` size), in `/tmp/pbn-layered/edges1152/`. Their strength statistics match the
research's working-size maps; ridge p50 is 0.81–0.98, so HED saturates on most contours.
Eye stand-ins for the fox and the Milkmaid were made from the research's eye boxes with its
almond and pupil rule (`/tmp/pbn-layered/eyes/`). Settings are the research's for each picture.

Sheets are `/tmp/pbn-layered/runs/<run>/<pic>.jpg`. Each shows photo | painted, then ours |
research at 1×, 2× and 4× on the research's crop rects, ours drawn with the app's
`LineAppearance.default` widths and opacities. Layer debug renders are
`/tmp/pbn-layered/dbg-*.png`: outline black, detail blue, texture green, color orange.

- **First port** (research thresholds 0.8/0.5/0.3). Valid everywhere; it looks like the
  research's renders but lighter, mostly because the app's lines are about 2.4× thinner than
  the research's 1.4 CSS px. HED saturation made 65–72 % of the drawing outlines, which was
  the owner's "too strong" on the arch, turtle and freight train.
- **Clutter rule.** Where centerlines crowd, the outline threshold rises (first as a factor,
  now toward 1).
  - Turtle: the silhouette stays black, the scutes become detail and the pattern texture
    (`dbg-turtle7.png`).
  - Freight: the gantry and locomotive silhouettes stay outlines, the truss becomes detail
    (`dbg-freight1.png`).
  - Arch: its outline and the horizon stay; the rock strata become detail and color.
- **Wheat Field.** Full clutter removed every outline, the cypress's included. HED gives the
  cypress's edge the same 0.8–0.9 as its brush strokes (I sampled it); the research's renders
  got the cypress from 2D hysteresis spreading through the connected web, plus importance. So
  long outline stretches (≥ 150 units on a 1500-unit canvas) are now exempt, which brings back
  the cloud and field contours. The cypress itself stays detail. This is the one trade-off of
  the defaults; lowering the outline threshold in Advanced brings back more.
- **Eyes** (fox, Milkmaid): closed almond and pupil outlines, as in the research's z4
  (`dbg-fox-eyes.png`, `dbg-milkmaid.png`); lines around them are one layer stronger. An eye
  too small for a number stays drawn as a closed interior stroke.
- **Milkmaid** (`runs/final/milkmaid.jpg`): a clean drawing of the figure, lighter than the
  research render. The face keeps the eye but loses some of the research's face lines; the
  research promoted all HED detail on a YuNet face, and this wave gets eyes, not faces.

Defaults, in `LineArtSettings`, with the reasons on its init:

| setting | value |
| --- | --- |
| outline | 0.85, rising toward 1 where lines crowd, except long contours |
| detail | 0.5 |
| texture | 0.3 |
| minimum stroke | 18 |
| gap bridging | 9 |
| smoothing | 0.5 |
| same paint | `joinTexture` |
| color cells | kept |
| eyes | outlined |

### Cells and outline share against the research

Final runs, 1152-px maps, default settings, eye stand-ins.

| picture | classic | ours | research `joined` | `joined`, mid lines split | outline share, ours | research top share (`hed-layers`) |
|---|---:|---:|---:|---:|---:|---:|
| santa-fe-freight | 322 | 489 (1.52×) | 383 | 456 | 0.45 | 0.57 |
| hawksbill-turtle | 950 | 1010 (1.06×) | 816 | 897 | 0.30 | 0.50 |
| red-fox | 234 | 291 (1.24×) | 252 | 294 | 0.52 | 0.56 |
| great-wave | 420 | 792 (1.89×) | 533 | 746 | 0.26 | 0.45 |
| milkmaid | 486 | 670 (1.38×) | 506 | 640 | 0.38 | 0.41 |
| wheat-field | 643 | 1526 (2.37×) | 846 | 1494 | 0.10 | 0.23 |
| cezanne-apples | 538 | 709 (1.32×) | 569 | 657 | 0.49 | 0.45 |
| delicate-arch | 618 | 689 (1.11×) | 617 | 675 | 0.45 | 0.55 |
| lassen-lupine | 815 | 1292 (1.59×) | 926 | 1257 | 0.12 | 0.29 |

- **Cells**: within a few percent of the research's "joined, mid lines also split", the
  owner's choice (join across texture and color only). We keep a detail layer at 0.5, so it
  runs slightly above.
- **Outline share**: lower than the research's on the busy and "too strong" pictures, about
  equal on the fox, Milkmaid and Cézanne. The research's top layer also held the
  silhouette and pbn closures, which the owner declined.
- Every template validates with label room: no label below legible size, no fallback edges.

## Unresolved, and notes for the other workstreams

- **Wheat Field cypress** (above). If the owner wants subject outlines amid brushwork, the
  next step would be an importance- or paint-contrast-protected outline on long paint
  boundaries.
- **No layered regime in `tools/regression.py`.** It would need HED maps for the six samples
  (~1 MB each as PGM); the plan says not to commit big maps. Layered generation is covered by
  `LineArtTests` and the fixture.
- **Shared files I touched**, minimally:
  - `CLAUDE.md`;
  - `Model/Template.swift`: only the `InteriorStroke` doc, now "repeats its first point when
    closed";
  - `Model/LineArtSettings.swift`: defaults and docs;
  - `Segmenter.swift`: an internal `segmentWithImportance` that also returns the weights;
  - `SegmentationParameters.swift`, `AutoSettings.swift`, `TemplateGenerator.swift`,
    `TemplateCoding.swift`, `TemplateValidation.swift`, `SVGExport.swift`.

  No contract API was renamed. `Output` gained `lineArtStats`, and `AutoSettings.choose`
  gained optional `lineArt:`/`tuning:`.
- **Render workstream**:
  - Interior strokes are polylines in canvas units; closed ones repeat their first point.
  - Weights are edge strength 0–255 for drawn layers, and the paint difference
    (saturating at ΔE 0.15) for color edges.
  - Canvas-border edges are `color` with weight 0 unless a drawn line runs along them.
- **Model workstream**: eyes are expected as closed polygons normalized to the photo
  (contours and irises); a 1–2 px iris is fine, it is drawn as a closed interior stroke when
  its cell is too small.
