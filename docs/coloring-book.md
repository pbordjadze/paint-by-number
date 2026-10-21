# Coloring Book: color by outer boundary

The app's line style (`LineArtSettings.Style.coloringBook`), built from the owner's annotated
screenshots of a layered painting of Arrieta's *Still Life with Cat and Birds* (the layered
style, which faded fainter lines in as the painter zoomed, is retired): a coloring book whose
areas are told apart by their numbers, not by lines.

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
  before, and readers from before the byte draw a book layered). Since the layered style was
  retired, every renderer (Metal canvas, snapshots, time-lapse, thumbnails, share pictures, PDF,
  SVG) draws both as a book.
- Generation, in `LayeredLines.apply`: a book draws nothing below the detail threshold (its
  texture layer is empty), keeps every line it draws rather than trimming the stretches that
  bound no cell (those become interior strokes: the drawing's creases and fur), and drops
  stretches shorter than `LineLayering.minimumRun` as trimming slivers. Cells, merges and joins
  are the layered pipeline's; `samePaint = .joinTexture` splits like `.split` since there are no
  texture lines.
- Drawing (`ColoringBookLook`): every drawn layer alike in the paper's full ink, three times a
  classic line fitted (the canvas ramp 1.5 pt + 0.7 pt per zoom doubling, times Settings › Line
  Weight's factor, `LineWeight`), color edges never drawn, lines never dissolving under paint,
  nothing outlined for being selected (the fill's hatch shows the cells). On paper, where there
  is no hatch, color edges print as dotted guides.

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
| `style` | `coloringBook` | the drawing alone is drawn, over the paint; no color edges, no selected outline |
| `detailThreshold` | 0.6 | what is drawn, read off the drawing laid over the contours. 0.5 draws about a tenth more lines, 0.7 a sixth fewer; 0.6 keeps the structure (the fox's ears and legs, the Milkmaid's sleeves) and drops the brushwork. The create flow's Lines slider moves it (`CreateModel.lineArt(_:lines:)`) |
| `outlineThreshold` | 0.6 | read off the contour map (HED) alone: an object's boundary is an outline wherever HED found it, the drawing's fur and creases are detail whatever their ink (Detectors, below). Never below `detailThreshold`: the thresholds stay ordered |
| `minimumStrokeLength` | 36 px | specks never become lines or cells |
| `gapBridging` | 16 px | open strokes reach further for a line, paint boundary or the frame, so cells close |
| `lineSmoothing` | 0.7 | flowing curves |
| `samePaint` | `joinAllButOutlines` | silhouettes split same-paint cells; fur, creases and strands are drawn inside their cells instead of walling slivers |
| `keepColorEdges` | on | the paints inside an outline stay separate areas (numbered, never drawn) |
| `outlineEyes` | on | eyes as closed outlines with an iris |
| `outlineObjects` | on | the subjects' silhouettes (Vision's foreground mask) close the drawing where the detectors left it open (Closing the subjects, below) |
| Flatter paint | 1.5× smoothing, texture flattening and smallest area, built into the style (`SegmentationParameters.coloringBookFlattening`) | fewer small color cells inside the outlines, which are told apart by numbers only: a tenth to a third fewer cells on the ten pictures before Suggested settings re-balance the painting's length, and a calmer book after (the fox at 1× came out at 24 colors and detail 0.79 with numbered specks all over its body, at 1.5× at 32 colors and detail 0.59 with cells a painter can find). `PipelineTuning`'s factors (`pbn --tuning`) multiply it, so 1× there is the book's own paint |
| Line weight | Regular (1×) | drawing only: Settings › Line Weight steps every book's line to Fine (0.7×) or Bold (1.4×) |

The thresholds stay ordered (`LineArtSettings.normalized`): the outline threshold never sits
under the detail threshold, so an outline threshold of 0.5 would read as 0.6. Against the
previous defaults (the same thresholds read off one map, same-paint cells split by every
line), measured with the book sheets on the fox, the Milkmaid, the Arrieta and the turtle,
joining across detail gives 10–20 % fewer cells (the slivers fur strokes walled), two to
three times the strokes drawn inside cells (92 on the fox, 168 on the Milkmaid) and the same
ink. Lowering both thresholds to 0.5 would double the ink and the open ends (the fox 211
strokes, the Milkmaid 388), too busy for a book.

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

## Soft edges

A detector puts its line on the steepest part of an edge, and the paint changes wherever the colors
cross between two palette steps. On a sharp edge the two lie within a pixel or two (`CellMap`'s
first step moves a paint boundary within 2.5 px of a line onto it). On a soft one (a lens's shallow
focus: the red fox's tail and paws, which CI's `paint-book-progress` and `paint-book-dark-paper`
showed with a pale band painted past the outline) the blur is a ramp of a dozen pixels or more that
the segmentation labels with paints of its own, and the line cuts it into strips, one on each side. The
strip outside the line is a cell of the background's area, so the book paints it, and it shows
past the outline once painted (What a book must do: *no boundary of the painted cells appears*).
Reproduced on Linux with the fox's maps from PyTorch (HED at 1152 px, the drawing at 768, the
demo's default settings, no Vision): bands 6 to 15 px across along the tail's edge and underside and
under the paws, in the paint between the fox's and the snow's.

`CellMap.mergeBlurStrips` (after the walls are assigned, before cells too small for their number
merge across a line) gives such a strip the paint of the cell beside it, so the paint stops at the
line. A strip is a cell at most `LayeredLines.blurStripReach` (4) minimum radii deep (about 22 px
across) that a line runs along (30 % of its borders with other cells, 16 px at least), with a
line-free border to one cell three times its size (the one it joins) and a line between it and
another (the one across), and whose paint lies between theirs: on the line from the paint beside it
to the one across it (within a tenth of its length and a just-noticeable difference or half the
nearer distance off), the two at least 0.06 apart. Anything else stays, and so do the painter's
fills: a dark rim inside a line (darker than both sides), a cell of the paint across the line (a
line through flat paint), a shadow or a shade wider than a strip (the shadow on the snow under the
fox's tail is picture, not blur). Both strips of a ramp go, each into the cell it lay
against: the disc of `BlurStripTests` blurred over 25 px came out with a tan inside the line, a
pale beige outside it and the ground's paint beyond, and now has two cells, as a sharp edge has.

Measured on the six corpus books (24 colors, detail 0.5, the committed maps) and the fox's: 4 to
24 strips merged per picture (the fox 18), cells −1.7 to −3.9 % (the fox 196 → 186), mean ΔE +0.3 to
+1.6 % (the paint is the segmentation's, a strip takes its neighbour's), ink density within 0.4 %,
areas the lines enclose −2 to +4 % (where a strip goes, edges join, and an edge is classed by the
line along most of it), open ends per 1000 units −4 to +0 %. Every template stays valid; the
classic and Auto regimes' metrics are what they were.

## Writing

The detectors draw no note or card legibly: the drawing runs at 768 px, where a pen stroke is
about a pixel, HED draws no letters, and tracing drops a letter's short pieces. Writing is traced
from the photo itself around the lines of text Vision found, painted out before segmenting, and
drawn in the book's ink inside the cells it crosses, with the numbers kept off it
(`docs/writing.md`; `Writing`'s doc comment).

## The painter's edits

The app's Refine lets the painter draw lines, take them out and fill shapes before painting. Its
newest builds make those edits to the finished template (below, `TemplateEditor`); this section is
how the edits of earlier builds are read, and stay read: an input of line art
(`LineArtInput.edits`, in the order made; `pbn --line-edits edits.json`), never a change to a
template, so every invariant holds for them as for the drawing's own lines, and regenerating a
painting draws them again. Once the painter is in Refine they decide what is
drawn: an edit changes the drawing as it showed, and nothing else changes. So the template made
without the edits is vectorized and its drawing read back (`LayeredLines.shownLines`: its drawn
edges and the drawing's interior strokes), `LineEdits` applies the edits to that drawing and,
alike, to the lines it was made from (which still split the paint, so cells away from an edit
stay as they were), and the cells and the template are made again, drawing exactly the edited
drawing. Before, the edits joined the raw lines at the layer stage and the template decided again
what to draw: on the lighthouse book (`tools/regression.py`'s book regime), of 25 lines tapped
away, 14 brought up to 61 px of line the template hadn't drawn (stretches along an edge mostly
without a line, drawn once the edit made the edge's drawing exact, or free ends led elsewhere
once their line was gone), and 11 took out up to 26 px of line nobody erased. Now every edit
changes nothing beyond its reach but the same few pixels the round trip moves (10 px added and
14 lost, in specks, whatever the edit), for 25 lines tapped away, 12 rubbed out and 8 drawn; on
the barn, 3 px. It costs a refined painting a second vectorizing, about 40% more time (400 →
570 ms for the lighthouse):

- A drawn line is an outline at full strength, so a closed shape walls off a cell even inside one
  paint, as a silhouette does; an open one is drawn inside its cell. It is kept as it arrives,
  cut where it leaves the canvas (the app's help comes before: it smooths the finger's path, its
  Pen moves an end whose ink touches a line onto it, and its Smart Pen straightens lines and
  joins their ends to the lines on screen, `PenAssist`): nothing leads its ends on, and no line
  of the drawing reaches into it (the drawing's free ends closed before the painter saw it). An end
  on or beside a line, or on the frame, closes cells against it as it lies (cells are
  4-connected), and so does one on a line of the template shown: of 24 strokes across the
  lighthouse book's cells ended exactly on its edges, 23 made as many cells as the same stroke
  run 3 px past both lines, and the 24th differed only where the longer stroke led one of the
  drawing's own free ends elsewhere. One that stops short leaves the shape open, and a line
  drawn past the one it meets goes on past it, but for a tail shorter than
  `LineLayering.minimumRun`, which no line keeps inside a cell. Painters found their lines
  "connected" when ends were led up to 1.6 × `gapBridging` (26 px in a book) into the nearest
  line, paint boundary or frame, and trimmed back from a line they crossed. Where it stays
  inside a cell, the cell's numbers keep off it (`LabelKeepOut`, as they keep off writing): a
  number the line would cross out moves to the spot of the cell farthest from its outline and
  the line, where that spot holds a legible one.
- A drawn line keeps its shape in the template: where it bounds a cell, the edge along it takes
  its path (`EdgeGuides`: the edge's pixel outline keeps within `reach`, 1.75, of the line, and
  its ends, the junctions it shares, within 2.5), joined to the edge's end corners, instead of
  the curve fitted to the pixels, so a star keeps its points as outline and as painted area
  (`LineEditsTests.aDrawnShapeBoundsItsAreaAsDrawn`); the repair loop steps such an edge down
  like any other where the path would cross a neighbour. Inside a cell it is an interior stroke
  along its own path.
- The eraser's pass takes out every point within its reach of the lines made before it (the
  app's and those drawn earlier; a line drawn over an erased place stays), leaving no piece
  shorter than `LineLayering.minimumRun`. No edge is drawn where it passed but along a line drawn
  since, and no gap it left closes (`LineEdits.erasedPlaces`): a gap shorter than `minimumRun`
  plus an edge's reach for a line either side (`annotateNear`, 3), 12 px, closed again, so a dab
  zoomed in took out nothing (`LineEditsTests.aDabTakesOutWhatItTouches`).
- A line tapped away (`eraseLine`, the path its own) takes out only the points beside the path
  that run along it (within 35°), up to its ends: what meets it at a junction or crosses it keeps
  its points. The eraser's round reach would cut the line a branch ends on, and a gap there joins
  the cells that line kept apart (`LineEditsTests.aLineErasedWholeLeavesItsJunctionsAlone`).
- `annotate` draws each template edge only where a line of the edited drawing runs along it,
  its drawn stretches as interior strokes over an undrawn edge, instead of the whole edge by the
  most of it: otherwise a line erased along part of a boundary between two paints stays drawn,
  one drawn along part of an undrawn boundary doesn't show, and the cells an erased line kept
  apart, joining, would change which edges are drawn. A stretch shorter than `minimumRun` beside
  undrawn ones goes (the reach of the lines meeting an edge's ends), then a gap that short is
  drawn (but where the painter erased), so an edge still reaches its junctions.
- A fill (`LineEdit.Kind.fill`, one point) changes no line. Once the lines have split the paint
  (`CellMap.split`), the shape under it becomes one kept cell (`CellMap.fill`; on a line, the
  nearest cell within 2 px): every cell the lines enclose with it, whatever paints they had, so a
  shape drawn across a boundary between two paints fills whole
  (`FillTests.aFillTakesTheWholeShape`); where that area reaches the frame (a shape left open,
  or none) only the cell under it, so a fill never runs into the paints of the background. It
  takes the photo's color there (`LineEdit.photoColor`: the median, channel by
  channel in OKLab, of the pixels within 1/800 of the photo's long side, as the app's swatch
  shows it), as the paint within a just-noticeable difference of it (0.02) or else a new paint
  of that color, added last so no other number changes. A later fill of the shape replaces an
  earlier one. A kept cell is merged into nothing for its size, its thinness, a close paint or
  its own paint (`mergeSmallWithinAreas`, `mergeTiny`, `mergeCloseColors`, `joinSamePaint`);
  short of its room inside its enclosed area it takes its neighbours there in, so the shape the
  painter closed becomes the area, and its line joins it (the walls beside a kept cell are its
  own, `assignWalls`), so a star keeps its points. Its number needs only a detail area's room
  (`LabelSizing.detailMinimumRadius`, 0.48 of the usual floor: a 3-digit detail number has a
  1-digit number's usual room, `SegmentationParameters.detailMinRadius(digits:)` the raster's),
  which the vectorizer's label room keeps (`LabelRoom`) and `validate` checks; a shape too small
  even for that merges as any cell does, and no area is kept.
  The template lists the kept areas (`Template.detailRegions`, the `DETL` chunk), so every
  renderer draws their numbers down to that floor and the painter reads them zoomed in. A fill
  in a shape left open keeps the cell around it: it floods, plainly, and the painter takes it
  back.

A painter's Annunciation (Fra Angelico; 150 colors, detail 1, smoothness 0) has gold stars about
10 px across in a 950-px photo, on a dark blue arch. She outlined them in Refine, and a star
without room for its number went back into the arch, only her line drawn. On her photo with a
blank edge map (her lines alone) and 21 star outlines about 12 units across, the outlines alone
left 11 stars in the arch and the other 10 in brown or dark paints; filled, all 21 are areas of
their own in the gold paints the palette had, and the one numbered 100 holds it in 4.02 units of
room, short of the 4.39 a 3-digit number needs elsewhere. Outlined 15 units across, 6 had gone
back; filled, all 21 are gold. On the corpus's lighthouse with six such stars painted into its sky (its committed
maps, the same settings), the outlines alone made six cells, five in the sky's blue; filled, all
six are gold. Without fills the corpus templates are byte for byte what they were.

On the lighthouse (24 colors, detail 0.5, the committed maps) a loop drawn round a cloud became a
numbered cell, and erasing a stray cloud line and a stretch of the tower's outline left the
tower's cells apart with that stretch undrawn: 7 more cells, the template valid, nothing else
moved. There too, with the ends kept as drawn, a line stopping 13 px short of the horizon, one
across the sky 17 px off the tower and 15 px short of a cloud, a U whose legs stop 7 px short of
the horizon and one whose leg stops 3 px short of it end where they were drawn, inside the sky
(these six ends had been led into the nearest line, closing both Us), and one run 11 px into the
tower is drawn there (it had been trimmed back to the outline). Lines ended on the horizon, or
4 px past it (that tail undrawn), close their cells as before; one ended 3.5 px short of it no
longer does. Every template stays valid. Without edits the corpus books are byte for byte what
they were.

### Edits made to the template itself (`TemplateEditor`)

Regenerating for every edit, as above, keeps every invariant but not the painter's hand: on the
lighthouse book drawn lines ended up 1.7 to 3.2 px off their path in stretches, one lost 8 px of
ink, `smoothingFallbackEdges` grew with the edits, strips beside walls were repainted, numbers
moved and the palette changed, because each edit ran the whole pipeline again (segmentation,
smoothing, fitting). `TemplateEditor.apply(_:to:)` (`Sources/PaintCore/Edit/`, `pbn edit`) is
Refine without it: the edit is made to the finished template, with no photo, edge map,
segmentation, smoothing or fitting, so a line is the line drawn and everything the edit does not
reach is bit for bit what it was. All points are canvas units; the edits are
`draw(points, closed, paints)`, `split(points, closed, paints)`, `erase(path, radius)`,
`eraseLine(at, reach)` and `fill(at, color)`. They are `Codable` (a `kind`
and its `points`, the shape `pbn edit` reads: `EditCoding.swift`), and `EditTrail` lays a list on a
template and keeps the templates after the last few, so taking an edit back or putting it back
costs no editing; an edit that does nothing on a template (declined, or nothing to change) is left
out of what it shows and counted. The app's Refine makes every edit this way, and regenerating a
painting makes its base from the photo and lays its edits on it (`App/CLAUDE.md` › Create flow).
Refine's Blank start is a base with nothing drawn (`TemplateEditor.blank`): the photo as one area,
its ring the canvas frame and its paint the photo's color over it, with the edits laid on it as on
any other, so the Pen's first lines cut it into pieces of the photo's colors.

- **Exact.** Geometry is decided in `Int64` on the quantum grid (`Lattice`: orientation, segment
  contact, containment), so an edit gives the same bytes on every device and core count. A
  point the editor computes (two lines crossing, the eraser's edge) is the lattice point
  nearest the true one, by one rule whichever way round it is asked; nothing depends on the order
  of a `Set` or a `Dictionary`.
- **Draw.** The polyline is laid on the template as drawn, quantized and nothing else: parts off
  the canvas are cut away, an end within `inkWidth` (3 units) of ink (an edge, a stroke, the
  frame) is moved onto it (to its nearest vertex within `vertexSnap`, else to the nearest point,
  which becomes a vertex of that ink), an end near the other end closes the line. The line is cut
  at every point it meets the drawing (edges, itself, the strokes it touches: a stroke is ink for
  the next line, so a shape drawn in two strokes closes) and each stretch between is a *chain*.
  The chains in a region, with its outline, cut it exactly where they close off part of it
  (`EditWork.splitRegion`: the faces of the planar graph, traced at each vertex along the sharpest
  turn toward the region, as `BoundaryGraph` does on the lattice): each piece keeps the region's
  paint, has its own number, and the new boundary is an edge, inked as an outline at weight 255,
  whose points are the chain's verbatim. A stretch that closes nothing (a dangling end, a slit
  from a ring to its hole) is an interior stroke, verbatim. Where inserting a crossing nudges ink
  off its path (by under a quantum) and so makes it meet another line, the lines are noded again
  until they meet only at vertices (`EditWork.node`); a crossing within a step of an end of either
  line is that end (a stub a step long would be two edges one on the other), and an edit whose
  lines lie closer than that is made again with the reach of that rule grown, to 27 steps (0.1
  unit) at most, before it is given up.
- **The tiny-piece rule.** A piece gets the numbers `LabelSizing` asks of its paint (the label
  search of the pipeline, `PolyLabel`, kept where the old number still has 85% of the room, away
  from the lines it left inside). A piece with room for a detail area's number
  (`LabelSizing.detailMinimumRadius`) and not for the usual one becomes a detail area
  (`Template.detailRegions`); one with less is not cut off: the chains round it go back to being
  strokes and the cell stays as it was (`Outcome.tooSmall` says where). A line through a crowd
  cuts what it can. The app says a shape is too small only when its line cut nothing off
  (`EditTrail.Verdict.made`): a line through a crowd also closes slivers where it crosses ink
  beside a junction or runs within a unit of a line, and 7 of 12 random ovals on the parrots book
  set the toast off though every one was cut and numbered.
- **A drawn line's colors.** A draw with `paints` (every draw the app has made since; one without,
  saved before, is laid as it always was) changes the paint under it as well as the lines. First
  the line, and only the line, passes through each junction (an end of an edge) within `inkWidth`
  of where it crosses that edge (`EditWork.throughJunctions`; it moved lines by up to 2.1 units on
  the parrots and lighthouse books), so it doesn't clip the corner there into a sliver with no room
  for a number. Then each piece it cut takes the photo's color there: the app reads it over the
  piece's pixels (`TemplateEditor.painted`, `LineEdit.photoColor(ofRegion:in:image:)`: the median
  in OKLab, at most `areaSamples` pixels) and keeps it in the edit with a point inside the piece
  (`Paint`), so the edit lays the same way without the photo. The piece takes the paint nearest
  that color within `paintTolerance` (twice the palette's median spacing, the book's own tolerance
  for one color, `CellMap.mergeCloseColors`, between a just-noticeable difference and three), its
  own when that is nearest, else a new paint added last; it keeps its paint where the new one is a
  neighbour's across an undrawn edge or its number has no room for the new digits. Of 40 random
  closed shapes on each of the parrots and lighthouse books, 11 and 21 changed paints (26 and 96
  pieces), adding 5 paints and none; the rest lay where the photo agrees with the paint there, and
  stay so, each piece with its own number. Slivers the nudge doesn't reach (20 and 41, under a line
  running within a unit of another) are left as before.
  That tolerance held too much as one color: a piece's photo up to three just-noticeable
  differences from its paint kept it, so a line between two shades the book had flattened left
  both sides one paint, and Paul saw a line that didn't recalculate the colors (October 18:
  "colors should get recalculated when a new line is drawn"; on the parrots book, six strokes
  across the bokeh, the chest, the red back and the leaves recolored 3 pieces of 11). Now, where
  a boundary the line laid still has one paint on both sides and the photo's colors of the two
  sides are at least `splitShadeStep` (1.5 differences) apart, the side farther from the paint
  takes a shade toward its photo color as a split's side does (`shadeSplit`: the photo's own color,
  or a paint within a just-noticeable difference of it). Sides the photo holds as one keep their
  paint. Of 40 random shapes (one at a time) on the parrots, lighthouse, hibiscus and barn books,
  31, 25, 35 and 33 changed paints (24, 22, 32 and 30 before), recoloring 126, 147, 186 and 137
  pieces (56, 122, 136, 91) and adding 69, 22, 46 and 43 paints (2, 0, 1, 0): one to two a line,
  the price of the colors the book had flattened. Reusing the palette's nearest other paint
  within the book's tolerance instead added a third fewer, but gave a near-grey bokeh a green
  and a pink 2.5 differences off its photo, so a side takes its own color. None was declined.
- **Erase.** Ink within the radius of the path is cut out exactly at the edge of the reach
  (stadium by stadium; the cut is the lattice point nearest the circle). Ink between two regions
  that this breaks lets the paint through: the regions merge (the larger by area keeps its index
  and its paint), the stretches of that boundary the eraser left are strokes in the merged
  region, and the undrawn edges between them are nothing. Undrawn (paint) edges are never drawn
  and never merge regions: only broken ink does. A tapped line (`eraseLine`) goes from junction to
  junction (`LineChains`, on the template's drawn edges and strokes) and merges the same way.
- **Fill.** The shape under the point is flooded across undrawn edges and stopped by ink (the
  tapped region alone if the flood reaches the frame: a fill never runs into the background); its
  regions become one, painted with the nearest paint within `SegmentationParameters.jnd`, else a
  new paint appended last (the palette is never reordered), and a detail area, kept whatever its
  size, as `CellMap.fill` made it.
- **Paint one area** (`paintArea`, Refine's Only This Area). The generator often gives two things
  one paint (a husky's eyes took the sky's blue); the painter wants the one area another paint
  and the rest left as they are. The region under the point alone, with no flood, takes its paint
  as a fill does (`EditWork.paint(matching:)`: the nearest within `SegmentationParameters.jnd`,
  else a new paint appended last), and no other region's paint changes. It stays a detail area
  or not as it was, its numbers kept where they have room for the new paint's digits (a new paint
  can need one more); an area without that room is declined. A paint it leaves with no area
  leaves the palette and the numbers after it close up, as a repaint's merge closes them
  (`renumberPaints`: a number only loses digits), so no paint is left with nothing to paint.
  Where the area then meets one of its new paint across an undrawn boundary, the two become one
  area (`joinAreas`), as a repaint joins them. A color whose nearest paint the area has already
  changes nothing. Unlike a fill's photo color, its color is one of the template on screen
  (the area card's picker and its palette chips read it with every look in it), so looks and
  repaints laid before it leave it as sent (`TemplateEditor.recolored`): a paint's own color,
  picked after a look, lands on that paint.
- **Split.** Out of Refine's toolbar for now (Paul, October 18: "it's not working right, it like,
  says 'this area is too small to be a number' or else just doesn't really do it"; the Pen's line
  recolors what it cuts instead, above); the edit stays, so splits made meanwhile lay as ever.
  The Color Splitter (Paul, October 18, in place of the detail brushes: "a new brush
  to separate a color cell WITHOUT a line") lays the Pen's line as a draw with paints does,
  nudged the same way, but as undrawn boundaries (`LineLayer.color`): it divides the paint and
  draws nothing. Its ends meet any edge within `inkWidth`, inked or not (a color cell's outline
  is often undrawn), the drawing's strokes are no part of it, and what of it closes nothing
  leaves nothing. Its pieces take the photo's colors as a drawn line's do; where a boundary it
  laid still has one paint on both sides (the photo about one color across it), the smaller
  side, or the larger where the smaller has no room for its number, takes a shade of that
  paint toward its own photo color (`EditWork.shade(of:toward:step:)`: the photo's color where
  it is at least `splitShadeStep`, 1.5 just-noticeable differences, away, else the paint moved
  that far toward it, the other way where that would pass white or black, lighter where the
  photo is the paint itself), an existing paint within a just-noticeable difference of it or
  else a new one, stepping 1.5 differences farther out, twice, where a neighbour across an
  undrawn edge has it or its number has no room. A split that divides no area, or leaves one
  paint on both sides of a boundary it laid, is declined. On the parrots book four splits (across
  the macaw's yellow chest, a loop round the red parrot's eye patch, down the green background,
  a short one in even red) were all made, adding 11 paints (24 to 35): a split asks for areas
  told apart, which the palette often has no paint for. Without a reachable line nothing shows
  where a split was, so Undo is the way back.
- **Cell edge** (`cellEdge`, Refine's Cell Edge). Refine as a drawing app (Paul, October 21,
  the Refine Toolbox: ink, cells and paint are separate layers, and each tool does one visible
  thing): the Cell Edge draws a boundary between cells with no ink and changes no paint, so the
  Bucket can then paint one side. It lays the Pen's line as a split does, an undrawn boundary
  whose ends meet any edge and whose stretches that close nothing leave nothing, a piece with no
  room for a number not cut off, but it takes no paints: both pieces keep the paint the cell had,
  which is what it is for, not a reason to decline. One that divides no area is declined. Areas
  of one paint across an undrawn edge stay two until one is painted; painted back to that paint
  (`paintArea`), the two become one area again, as Only This Area joins them. A build from
  before it leaves a cell edge out of the edits it lays (an unknown kind), so a `paintArea` after
  one lands there on the whole undivided cell; only SideStore and Debug builds make them.
- **Merge** (`merge`, Refine's Merge). The Refine Toolbox's way to change a cell's shape by
  joining (Paul, October 21: "it should be possible to do ANYTHING with them"): a drag across
  cells joins them into one. The regions under the path (walked in steps of half a unit, a point
  off the canvas or in no region left out), in the order it first enters them, from the one under
  its first point: each next one joins if it shares an edge with those joined so far, else it is
  passed over, so a drag that slips through a junction into a cell touching the others only at a
  point leaves that cell out. Every edge between them goes, ink and all: unlike the eraser's
  join, which keeps the rest of a boundary's ink as strokes, a merged boundary leaves no stroke,
  since the painter asked for one cell where the line was (the strokes inside the cells stay).
  The joined area keeps the first region's index, paint and number (`EditWork.merge`, its rings
  traced again, so a cell joined with the one round it fills its hole), and is a detail area only
  if the first was: the painter dragged from it, so the area is it, grown. A paint left with no
  area leaves the palette and the numbers after it close up, as Only This Area's does
  (`dropPaints`). A merge that joins fewer than two areas is declined.
- **Paint brush** (`brush`, Refine's Paint Brush). The Toolbox's way to paint a cell's shape: what
  lies within the radius of the stroke (a disc for a dab; the app's Size, 4 to 48 points on
  screen at any zoom, `RefineGestures.brushSize`'s 12 by default) takes the paint a fill would (a color of the template on screen, as Only
  This Area's: the paint within a just-noticeable difference, else a new one added last). The
  footprint's outline (`BrushFootprint`) is traced on a grid of a quarter of the radius (coarser
  only past a million cells): each grid vertex is in or out exactly, in 128-bit integer
  arithmetic; where a grid edge goes from in to out, the outline crosses it where the eraser's
  reach (`Rub`, the same union of stadiums) ends along it, rounded to the lattice and kept off
  the edge's ends; marching squares join each cell's crossings (two diagonal corners in are
  joined). The crossings lie inside distinct grid edges and each segment inside one cell, so the
  rings are simple and apart; thinned within a fortieth of the radius, they are kept thinned
  only where they stay so. A self-overlapping stroke is one footprint, a loop's enclosed area a
  hole in it. The rings are laid as a closed cell edge is, undrawn, clipped to the canvas (each
  ring clipped from a vertex off it, so every run ends on the frame; no vertex lies on the
  frame's lines), a piece with no room for a number not cut off. An area is inside when it lies
  on the outline's left (the footprint's side) and on no boundary of it on the right; one that
  touches none of the outline, or both its sides, when the footprint covers it whole (each of
  its vertices), so a cell the stroke covers is painted whole and a stroke too thin to cut a piece
  off, crossing a cell's number, paints nothing there. Each area inside takes the paint, ink
  untouched: the areas either side of a drawn line stay two cells. Then areas of the paint
  that meet across an undrawn boundary, one of them inside or the boundary the outline itself,
  become one area (`mergeGroups`), so a stroke along a cell's edge in the cell's own paint grows
  the cell instead of adding a sliver, and the cell it cut is whole again. An area with no room
  for the paint's number, even a detail area's, keeps its paint and is one again with the rest of
  its cell (`Outcome.tooSmall`); a paint left with no area leaves the palette (`dropPaints`). A
  stroke that changes no area's paint changes nothing; one with no area inside it, not even a
  whole cell, is declined, as is one whose areas all lack room for the paint's number. On the
  parrots book (1152 × 768, 201 regions) through `pbn edit`, with the check of the result: a
  30-point stroke of radius 18 across the macaw's chest, the blue and the green, 61 ms (16 pieces
  cut, 6 joined); 30 points across the whole canvas, 250 ms at radius 14.4 (the app's brush on a
  13" iPad), 290 ms at 40 and 370 ms at 4. A merge's drag, about 35 ms.
- **Reshape** (`reshape`, Refine's Bend Line and Move Edge). One edit behind two tools: drag an
  inked line to bend it, or a cell's boundary, inked or not, to reshape the cell, its neighbour
  giving or taking the difference. The edit's `target` (`TemplateEditor.ReshapeTarget`) keeps
  each tool to its own lines: Bend Line's (`ink`) grabs only what is drawn (an edge of a drawn
  layer, `LineLayer.isDrawn`, or a drawn stroke), so an undrawn cell edge beside the line it
  meant is passed over; Move Edge's (`edge`) only boundaries between two cells, drawn or not,
  never a stroke inside one; `any`, what a reshape saved without a target means, grabs either.
  The line nearest the drag's start within a finger's reach (an edge, not the canvas's frame, or
  a drawn stroke) that the target grabs is taken with the chain it continues into:
  through every vertex where it and just one other edge alike (both inked, or both undrawn) end,
  from junction to junction, as the Smart Eraser finds its line (`EditWork.reshapePlan`). Its
  point nearest the drag's start goes where the finger lifts, and every other point by the drag
  times a weight along the chain's length: 1 at the grabbed point, 0 a spread away, a smoothstep
  between (`falloff`, the raised cosine's cubic twin in `+ - *` alone, so the same on every
  device). The spread is three times the drag, at least 24 units (`reshapeSpread`), on each side
  of the grabbed point, and at most to the chain's end there (a loop's far point, half its length
  round); where it ends the chain gets a vertex, and beyond it keeps its points exactly. So the
  bend is local, and the chain's ends stay on their junctions and the drawing connected; a
  junction grabbed is held, so nothing moves. A stroke's end that touches no line is free: within
  the spread, the stretch from the grabbed point to it moves whole (a short stroke free at both
  ends moves as it is); beyond it, the end stays. Strokes ending on the chain are carried, their
  end moving with the point of the chain they meet. A step whose ends move at least half a unit
  apart is bent: points are added along it so that, moved, they lie at most 3 units apart (the
  smoothstep is at its steepest 1.5 times its mean slope, which bounds a moved step's length), so
  a big bend is a smooth curve. The chain keeps its layer and weight; the regions on its sides
  keep their paints, their fills are made again, their numbers stay while they keep the room
  (`labelPlan`, off the strokes it moved), and the pixels between the old outline and the new go
  to the region whose outline now holds them (`reclaim`). Declined when the moved chain would
  cross itself or another line or touch one anywhere but its held ends and the strokes it
  carries, leave the canvas, turn an area inside out, carry an island or a stroke into the region
  across, or leave an area no room for its number. On the parrots book, laying a bend with the
  check of the result takes about 25 ms; the preview the app draws while the finger moves
  (`TemplateEditor.reshapedChain`, the same moved points without laying them) 0.4 ms. With the
  falloff spanning the whole chain, four of five drags of 25 to 45 units on that book's outlines
  were declined, a long outline moving along most of its length into the details beside it near
  its far ends. Bending within a spread of the grab (max(3 × the drag, 24 units) a side), three
  of the five were made; the two declined would have met a line beside them, which a bend that
  far must.
- **Move number** (`moveLabel`, Refine's Move Number). Drag a number where you want it inside its
  cell. The number nearest the drag's start, within its radius and the edit's reach (a finger's
  on screen, `RefineGestures.fingerReach`; `TemplateEditor.tapReach` in a file without one), goes
  where the finger lifts when that is inside its own region (not on its outline) and a number of
  its digits fits there: the room there, measured to the outline and to the strokes in the
  region (`LabelKeepOut`, as numbers are kept off ink elsewhere), at least the usual floor or, in
  a detail area, a detail area's. Its radius is that room, never more than the region's roomiest
  spot gives (`PolyLabel` over the region with the same keep-out), so a number dragged into open
  space doesn't grow huge. It must keep clear of the region's other numbers: a move whose circle
  there overlaps another's is declined, each circle the disc its digits are drawn in: its room,
  but no more than a number at the largest size a renderer draws fills (`largestNumberFraction`,
  the canvas's cap, 4.5% of the shorter side). A circle as large as the room alone would decline
  nearly every move in a large area, whose numbers' rooms reach past each other while the
  numbers themselves lie far apart: on the editor's test scene, the sky's number dragged 18.5
  units from another of the sky's, both drawn about 7 units across, though their rooms are 25
  and 18.5. `TemplateEditor.labelNear` is the grab's rule on its own,
  from which the app draws the number held. The region's other numbers, its outline, fill and
  pixels stay as they were; nothing is declined but the move itself. A later edit that plans the
  region's numbers again (a cut, a join, a repaint, a reshape of its outline) keeps the number
  where it was put while that spot keeps most of the room, as it keeps any number (`labelPlan`),
  and may move it otherwise.
- **Shapes** (`RefineShape`, `ShapePath`; drawn lines, laid as the Pen's are). A drag draws a
  straight line, a rectangle across it, an oval filling the box it spans, or a curve (a second
  drag bends it); a hexagon and a five-pointed star fill the box too: a regular hexagon, flat on
  top and bottom with its side corners on the box's sides, and a star with a point up and its
  inner corners 0.4 of the way out, each stretched to the box as the oval is a circle stretched
  to it. The closed ones are sent as closed lines, their start once; new shapes go last in
  `RefineShape`, whose order the app lists them in.
- **Colors** (`look`, `repaint`; `Recolor.swift`). Refine's Colors change paints alone: a look
  over every paint (`TemplateEditor.Look`, at a strength), or one paint made another color, with
  or without its family (the paints of about its hue, full within 30° and none past 60°, turning
  and growing as the swatch did; a gray's family is the colors within 0.1 of it). One swatch
  alone often looks wrong: the red parrot is six paints, and turning one of them blue leaves a
  patchy bird, which is why the family moves by default. Where a changed paint lands within a
  just-noticeable difference of another, the two become one paint (the lower number) and the
  numbers after the higher close up, so a number only loses digits; areas the two paints kept
  apart across an undrawn boundary become one, as the eraser joins them. Every look is a fixed
  function of a color (`+ - * /`, `min`, `max`, `sqrt`: the same bits everywhere, pinned by
  `EditRecolorTests.looksArePinned`), so edits laid after it bring their colors through it (a
  drawn line's pieces, a fill: `TemplateEditor.recolored`), and a line drawn under Moonlit takes
  Moonlit's paint. The painting looks place a paint on the painting's ramp by its rank among the
  palette's lightnesses, which the edit records when it is made (`lightness`, nine quantiles), so
  a color laid later finds its place among them. Of the eight looks at full strength on the
  parrots, lighthouse and hibiscus books (24 paints each) all 24 were made and validate, in 20 to
  150 ms; Moonlit, Golden Hour, Garden and the painters' looks merge 0 to 7 paints, Pastel 0 to 4
  (a first, narrower Pastel merged 10 on the lighthouse), Sepia 7 to 11 (hue is gone).
- **What stays.** Regions, outlines, fill triangles, numbers, edges, strokes and paints the edit
  does not reach are copied as they were (`EditWork.finish` lays the survivors out again, so
  indices after a merged region shift). Neighbours of an edit gain a vertex where a line meets
  their outline: their fill is triangulated again (`RegionFills`) and their numbers checked.
  `regionMap` follows the outlines: the pixels of a cut region go to the piece whose outline holds
  their centre (those the old outline left to a neighbour stay where the pixels were), those of a
  merged region to the merged one, and a stroke that has no pixel of its region beside it takes
  the nearest one (`Template.validate` asks); no other region's pixels move.
- **Limits.** An edit that cannot be made is declined (`Outcome.declined`: the template comes
  back as it was, and every result is checked by `Template.validate` first): a line that doubles
  back on itself, a fill whose paint's number (a new paint may need a digit more) or an area
  that a line's vertex has narrowed has no room for it, lines closer than the lattice can tell
  apart. Of 10,000 random edits on crowded templates 9 were declined: 3 doubling back, 4 fills,
  1 area beside a line and 1 pair of lines. A line laid exactly along ink adds nothing but
  vertices. A line crossing a stroke the generator made with a self-crossing is cut by it but
  does not close a shape with it. Without line art (a classic template) there is nothing to
  edit.
- **Measured.** `pbn edit` on the lighthouse book (423 regions) with 10 edits (a loop round open
  sky later tapped away, a dangling line, a line from the frame to the tower's lantern, a line
  across a cloud, an eraser pass over the cloud's outline, a star drawn and filled, a loop too
  small for a number, a fill of the tower): the ink strays at most 0.002 from the lines drawn (the
  quantum is 0.0039; an end that joined ink moved 1.9 at most), 408 of 423 regions are bit for
  bit as they were and no edit changed a region it did not touch, merge or sit beside
  (`unexpectedChanges`), the palette gains one paint, `labelsBelowLegibleSize` is 0 and the
  template validates. An edit takes 25 to 50 ms, its validation included; a line of 300 points
  across the whole book, cutting 61 regions, and an eraser pass over 90 regions, 0.24 s together.

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
