# Coloring Book: color by outer boundary

The third line style (`LineArtSettings.Style.coloringBook`), built from the owner's annotated
screenshots of a layered painting of Arrieta's *Still Life with Cat and Birds*: a coloring book
whose areas are told apart by their numbers, not by lines.

## What a book must do

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
keeps its paint and its number. The research behind it (`research/lineart/results_color.md` in
the `archive/lineart-research` tag) compared this (C1, pbn's regions cut by the lines) with
segmenting the colors afresh inside each enclosed area (C2) and found C1 more faithful on every
picture, with fewer slivers. A second pipeline would re-derive the same cells
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

## Defaults

The coloring book is the app's default line style (`LineArtSettings()`), at settings of its
own (`LineArtSettings.init(style:)`): those of the reference books, measured on ten pictures
(the freight train, the Milkmaid, the turtle, the fox, the lighthouse, the parrots, the arch,
the duck, the Paris street and a portrait) with HED maps at the app's size and Suggested
settings at Relaxed.

| Setting | Value | Why |
| --- | --- | --- |
| Line Style | Coloring Book | the drawing alone is drawn, over the paint; no color edges, no selected outline |
| Lines From | 60 % | what is drawn, read off the drawing laid over the contours. 50 % draws about a tenth more lines, 70 % a sixth fewer; 60 % keeps the structure (the fox's ears and legs, the Milkmaid's sleeves) and drops the brushwork. A book has no texture lines, so Texture From is hidden |
| Outlines From | 60 % | read off the contour map (HED) alone: an object's boundary is an outline wherever HED found it, the drawing's fur and creases are detail whatever their ink (Detectors, below). Never below Lines From: the thresholds stay ordered |
| Shortest Line | 36 px | specks never become lines or cells |
| Gap Closing | 16 px | open strokes reach further for a line, paint boundary or the frame, so cells close |
| Line Smoothing | 70 % | flowing curves |
| Same Paint Across a Line | Join Across Detail | silhouettes split same-paint cells; fur, creases and strands are drawn inside their cells instead of walling slivers |
| Keep Color Edges | On | the paints inside an outline stay separate areas (numbered, never drawn) |
| Outline Eyes | On | eyes as closed outlines with an iris |
| Outline Subjects | On | the subjects' silhouettes (Vision's foreground mask) close the drawing where the detectors left it open (Closing the subjects, below) |
| Flatter paint | 1.5× smoothing, texture flattening and smallest area, built into the style (`SegmentationParameters.coloringBookFlattening`) | fewer small color cells inside the outlines, which are told apart by numbers only: a tenth to a third fewer cells on the ten pictures before Suggested settings re-balance the painting's length, and a calmer book after (the fox at 1× came out at 24 colors and detail 0.79 with numbered specks all over its body, at 1.5× at 32 colors and detail 0.59 with cells a painter can find). The Pipeline factors multiply it, so 1× there is the book's own paint |
| Line Appearance | default | a book reads only Line Weight (1×) |

The thresholds stay ordered (`LineArtSettings.normalized`): the outline threshold never sits
under the detail threshold, so an outline threshold of 0.5 would read as 0.6. Against the
previous defaults (the same thresholds read off one map, same-paint cells split by every
line), measured with the book sheets on the fox, the Milkmaid, the Arrieta and the turtle,
joining across detail gives 10–20 % fewer cells (the slivers fur strokes walled), two to
three times the strokes drawn inside cells (92 on the fox, 168 on the Milkmaid) and the same
ink. Lowering both thresholds to 0.5 would double the ink and the open ends (the fox 211
strokes, the Milkmaid 388), too busy for a book.

The layered style keeps the research's defaults (Outlines From 85 %, Detail 50 %, Texture
30 %, 18 px, 9 px, 50 %), and choosing a style in Settings › Advanced carries each style's
defaults along (`LineArtSettings.changing(to:)`): a number the painter changed stays. Under
the book, Settings › Advanced hides Texture From and shows Line Appearance's Line Weight only.

## Detectors, and what each decides

HED alone finds strong, closed silhouettes and little else: the fox is an outline with five
strokes inside, the Arrieta still life a row of blobs. The Informative Drawings
generator (`LineArt.mlpackage`, the network ControlNet's lineart annotator runs) draws what an
illustrator draws, fur, petals, cut glass, the cat's face, but its silhouettes are thin and
sometimes open. The app generates from the drawing laid over the HED map (`EdgeMap.combined`:
per pixel the larger of the drawing and 0.85 × HED, `EdgeMap.contourWeight`, measured on the
fox and the Arrieta; `pbn --contour-weight` tries another), and hands the HED map along by itself
(`LineArtInput.contours`): the combined map says what is drawn, the contours say what is an
outline. A stroke is an outline where HED's strength along it (smoothed like the lines, read
within two pixels of the stroke) holds the outline threshold, whatever the drawing made of it;
everything else drawn is detail. So the drawing's strong fur strokes never pose as silhouettes,
and a silhouette HED found is an outline even where the drawing traced it thinly. The drawing
runs at a long side of 768 (cleaner and four times faster than 1152) and is resampled up.

## Closing the subjects

A silhouette the detectors miss stays open, and the method's areas then leak: the fox's white
belly against snow gives HED and the drawing nothing, so the fox and the snow are one enclosed
area, a hundred pixels wide at the belly, however the thresholds are set. A gap may let the
background in (What a book must do), but a painter sees the fox as one shape. The subjects'
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

## Writing

The detectors draw no note or card legibly: the drawing runs at 768 px, where a pen stroke is
about a pixel, HED draws no letters, and tracing drops a letter's short pieces. Writing is traced
from the photo itself around the lines of text Vision found, painted out before segmenting, and
drawn in the book's ink inside the cells it crosses, with the numbers kept off it
(`docs/writing.md`; `Writing`'s doc comment).

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
six corpus photos (`Tests/Corpus`) as books from committed maps on every push.

Maps for evaluation come from the app's own networks, run with PyTorch:
`tools/models/convert_hed.py --map in.ppm out.pgm` writes the contour map `pbn --edges` reads,
and `tools/models/convert_lineart.py --map in.ppm out.pgm` the drawing `pbn --lines` reads, at
the levels the app computes (`--compare app.pgm` reports how far a map the app made is from
it). Reduce the photo first to the size the app runs each network at, at most 1152 px on the
long side for HED and 768 for the drawing (pbn's `working.ppm` can be larger). The committed
maps of the regression's book regime are `tools/baseline/lines/<name>-contours.png` and
`-drawing.png`.

## Presets and settings as text

Settings › Advanced › Presets sets Line Art, Line Appearance and Pipeline at once
(`AdvancedPreset`: a line style at its own defaults, the pipeline untuned and the lines drawn
as designed). Coloring Book is the app's defaults, so it is also Reset All; Layered and
Classic are the other two styles. A preset is recognized as long as the settings generate the
same template and draw the same lines (`GenerationKey`): a setting the style ignores can sit
anywhere.

Any other mix of settings travels as text: Copy Settings writes a JSON object
(`AdvancedReport.Snapshot`), and Paste Settings reads one back: an object with some of the
three groups, `lineArt`, `tuning` and `lineAppearance`, each naming only the fields it changes
(the others keep their defaults), a group left out staying as the painter has it, values
beyond a setting's range clamped.

Layered line art has a related per-layer *When Painted* slider in Line Appearance: how much
of a layer's lines stays once both sides are painted (0 % by default, dissolving every line
between painted cells as classic templates do). It gives a layered painting kept outlines
without the book's other rules.
