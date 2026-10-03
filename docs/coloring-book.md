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

Not done here: per-style defaults. The thresholds, shortest line and gap closing default to the
layered values; the owner's own books used stronger thresholds (0.6) and longer lines. Settings ›
Advanced exposes them for the book with the texture threshold hidden.
