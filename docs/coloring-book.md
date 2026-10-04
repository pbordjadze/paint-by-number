# Coloring Book: color by outer boundary

The third line style (`LineArtSettings.Style.coloringBook`), built from the owner's annotated
screenshots of a layered painting of Arrieta's *Still Life with Cat and Birds*: a coloring book
whose areas are told apart by their numbers, not by lines.

## What the owner asked for

- Zoomed out: thick black outlines with a sensible shape to objects; no inner lines or colors
  visible.
- Zoomed in, nothing selected: the outlines as before, no interior "detail" lines for the
  colors. Each area the outer lines enclose holds several colors but is closed off in some way
  to form a boundary (one leaf = one enclosed area). A small area can have only one color.
  Detail lines can show texture, like a fur pattern, at the same thickness as the outlines;
  they need not enclose anything.
- A color selected: its cells highlighted, but with no outline, so the outer boundaries that
  define the shapes stay what the eye reads.
- Painted: the outer boundaries stay visible and no boundary of the painted cells appears.
  The drawing must stay over the paint from the first fill to the last, or the method breaks
  as the paint hides it.
- The enclosed area is what the lines close: a gap in a line lets the background's area reach
  into a leaf, and that is expected.

## Why a refactor, not a second pipeline

The layered pipeline already does the one thing this method needs from generation: it splits
the paint regions along a learned drawing (HED) so that no cell crosses a line, and every cell
keeps its paint and its number. The research behind it compared this (C1, pbn's regions cut by
the lines) with segmenting the colors afresh inside each enclosed area (C2) and found C1 more
faithful on every picture, with fewer slivers. A second pipeline would re-derive the same cells
and the same drawing. What the method changes is the *contract between the template and its
renderers*, so that is where the style lives:

- `TemplateLineArt.style` (`layered` or `coloringBook`), stored in the LINE chunk as an
  optional trailing byte (absent = layered, so layered templates encode byte for byte as
  before, and readers from before the byte draw a book layered). Every renderer (Metal canvas,
  snapshots, time-lapse, thumbnails, share pictures, PDF, SVG) switches on it, so a painting
  looks the same whatever Settings › Advanced says later.
- Generation, in `LayeredLines.apply`: a book draws nothing below the detail threshold (its
  texture layer is empty, `textureThreshold` unused), keeps every line it draws rather than
  trimming the stretches that bound no cell (those become interior strokes: the drawing's
  creases and fur), and drops stretches shorter than `LineLayering.minimumRun` as trimming
  slivers. Cells, merges and joins are the layered pipeline's; `samePaint = .joinTexture`
  splits like `.split` since there are no texture lines.
- Drawing (`ColoringBookLook`): every drawn layer alike in the paper's full ink, three times a
  classic line fitted (the canvas ramp 1.5 pt + 0.7 pt per zoom doubling, times
  `LineAppearance.coloringBookWeight`), color edges never drawn, lines never dissolving under
  paint, nothing outlined for being selected (the fill's hatch shows the cells). On paper,
  where there is no hatch, color edges print as dotted guides.

## Evaluation

`pbn generate --line-style coloringBook --edges <hed.pgm>` on the Arrieta still life and eight
library pictures (HED maps at ≤ 1152 px from the model the app ships, run with PyTorch): every
template valid, cells 1.04–1.50× the classic regions. The red fox and the freight train show the
method plainly: the silhouette and features in thick ink, the numbers floating inside with no
line between paints, the sky bands numbered only. Cells are identical to the layered style's at
the same settings except where texture lines (now absent) used to split them.

The coloring book is the app's default line style (`LineArtSettings()`): lines from 0.6 of
the combined map (the owner's own books' threshold), outlines where HED holds 0.5, same-paint
cells joined across everything but outlines (`samePaint = .joinAllButOutlines`, the book's own
default), a 36 px shortest line, 16 px gap closing and flowing curves
(`LineArtSettings.init(style:)`; layered lines keep the research's values, and choosing a style
in Settings › Advanced carries each style's defaults along), over paint flattened 1.5×
(`SegmentationParameters.coloringBookFlattening`). Measured with the book sheets on the fox,
the Milkmaid, the Arrieta and the turtle against the previous defaults (0.6 for both thresholds,
same-paint cells split by every line): cells 10–20 % fewer (the slivers fur strokes walled),
the strokes drawn inside cells two to three times as many (92 on the fox, 168 on the Milkmaid),
the same ink; lowering what is drawn to 0.5 would double the ink and the open ends (the fox 211
strokes, the Milkmaid 388), too busy for a book. Settings › Advanced exposes the thresholds for
the book with the texture threshold hidden; Coloring Book in its Presets row is the defaults.

## Detectors, and what each decides

HED alone (build 176) finds strong, closed silhouettes and little else: the fox is an outline
with five strokes inside, the Arrieta still life a row of blobs. The Informative Drawings
generator (`LineArt.mlpackage`, the network ControlNet's lineart annotator runs) draws what an
illustrator draws, fur, petals, cut glass, the cat's face, but its silhouettes are thin and
sometimes open. The app generates from the drawing laid over the HED map (`EdgeMap.combined`:
per pixel the larger of the drawing and 0.85 × HED), and hands the HED map along by itself
(`LineArtInput.contours`): the combined map says what is drawn, the contours say what is an
outline. A stroke is an outline where HED's strength along it (smoothed like the lines, read
within two pixels of the stroke) holds the outline threshold, whatever the drawing made of it;
everything else drawn is detail. So the drawing's strong fur strokes never pose as silhouettes,
and a silhouette HED found is an outline even where the drawing traced it thinly. The drawing
runs at a long side of 768 (cleaner and four times faster than 1152) and is resampled up.

## Closing the subjects

A silhouette the detectors miss stays open, and the method's areas then leak: the fox's white
belly against snow gives HED and the drawing nothing, so the fox and the snow are one enclosed
area, a hundred pixels wide at the belly, however the thresholds are set. The owner's notes
allow a gap to let the background in, but a painter sees the fox as one shape. The subjects'
silhouettes (`LineArtInput.objects`) come from a foreground mask, in the app Vision's
foreground instance mask, every subject together, scaled to 384 px and traced by
`MaskContours` (a crack-following walk around each shape of at least 1.5 % of the mask, the
staircase simplified), and `LineLayering.addObjects` draws, as outlines at full strength, only
the stretches of a silhouette that run more than 12 px (on a 1500-px canvas) from every drawn
line, dropping stretches under 24 px as the mask's wobble; the stretches' free ends then reach
the lines they stopped short of like any other free end. Where the detectors drew the silhouette
it stays theirs, precise; where they left it open the mask closes it. `pbn --objects` takes a
mask (any image, inside at half) or polygons; the Linux evaluation stands in for Vision with a
mask made from HED itself (the shapes HED at 0.2 encloses), which the eval sheets show closing
the fox.

## Measuring a book

A book is judged the way its painter sees it. `pbn generate` writes, for a template with line
art, `selected.svg` (the cells of the paint with the most of them hatched, nothing outlined,
as the canvas shows the selected color) and `areas.ppm` (a color per area the drawn lines
enclose, light where the area is one cell, red rings where widening the lines closes an
opening), and `stats.json`'s `lineArt` reports the drawing: its length and `inkDensity`
(drawn length per 1000 canvas pixels), the share inside cells (`interiorFraction`), open stroke
ends per 1000 units, the areas the lines enclose (`enclosedAreas`, cells per area, the share
with a single cell, `largestAreaFraction`: the background's share unless a silhouette is open),
the areas the outlines alone enclose, and `enclosedByWidening`, the share of the canvas the lines
wall off as drawn and widened by 1 to 4 px, whose jumps say how wide the openings are
(`openings` says where). `tools/eval.py book` lays these out per picture: one column per
setting variant, the drawing fitted, its middle zoomed, the selected view, the finished painting
and the areas, with the numbers under each; `tools/regression.py`'s book regime generates the
six retired samples as books from committed maps on every push.
