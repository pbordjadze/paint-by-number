# Start from a drawing

A second way into a painting (painting-company row 190): a photo of a line drawing on paper, a
pen or pencil sketch, a coloring page, a sketchbook page taken with a phone, becomes a
paint-by-number whose areas the drawn lines bound, the way a coloring book works. The code is
`Sources/PaintCore/Drawing/` (`DrawingScan`, `DrawingGenerator`, `DrawingPalette`),
`Model/DrawingSettings.swift` and `GenerationSettings.drawing`; `pbn drawing` runs it; the app's
entry is the create flow's From a Drawing (SideStore and Debug builds, `#if UNRELEASED`). Each
type's doc comment is its reference; this note holds what was measured and decided.

## How it works, in short

1. **The sheet** (`DrawingScan.clean`). The paper's brightness under every pixel is a grey
   closing (a maximum wider than any line, blurred), so lines vanish from it and the light's
   gradient stays; a fill wider than the closing is caught by a much wider closing on a coarse
   grid, used only where the closing fell far below it. The sheet is what the closed luma flows
   over from the picture's middle without a step (a table or frame is a step; a slanted edge's
   staircase is caught by a brightness floor against the neighbourhood's brightest); its hull's
   four corners are pulled square by a homography, the sheet's own proportions kept, inset 2 %
   for the paper's edge and shadow. Ink is darkness below the paper, scaled from the paper's
   texture (the histogram's middle) to the ink's body, less for a coloured wash. The cleaned
   sheet (white paper, the ink alone) is the painting's photo from then on: the comparison, the
   photo peek, Refine's photo layer and regeneration read it.
2. **The ink** (`DrawingScan.ink`). At the working size: the strongest scan pixel under each
   working pixel (a hair line survives the shrink), widened to three pixels; solid fills found on
   the mean ink (a fill is ink all over, hatching never is): ink deeper than half a percent of the
   long side that goes twice the drawing's own pen width deep over a quarter of its core, or is
   compact; a fill's inside is taken out past the line's width, its edge is the line, and paper
   gaps inside it (a white curl in black hair) become lines. Dots within reach of each other on
   opposite sides are joined (`chainDots`), so a dotted outline closes.
3. **The lines** (`LayeredLines.apply` with `Tracing.drawing`, `DrawingSettings.lineArt`). The
   ink thinned to its skeleton (no ridge detection: a thick stroke and a hair line each give one
   line, junctions whole), then the book's own tracing: bubbles, spurs and specks, gaps bridged
   along a line's direction up to 24 px, strokes under 10 px dropped, a free end led to the frame
   only from 6 px. The ink's strength is capped at 0.7 and the clutter around it lifts the outline
   threshold, so hatching, fur and scribbled shadows draw inside their cell instead of splitting
   it; a long stroke stays an outline by its length. The lines of small writing
   (`DrawingScan.textRows`: rows of pieces of a letter's or a word's size) go through `Writing`
   as a photo's text does, traced finely and drawn legibly off the paint, and what `Writing`
   leaves of them is held between the thresholds, drawn as detail, never a wall; a row's whole
   box keeps the numbers off, a number's radius around it, so none reads as one of its letters.
4. **The cells** (`CellMap`). The sheet starts as the paper and its fills, paints of their own.
   Small cells in clusters of five or more (the strips between hatch strokes, the chips of
   crosshatching) become one cell (`mergeHatchClusters`); cells with less room than 6 px at 1500
   merge into a neighbour; same-paint cells join across everything but outlines.
5. **The paints** (`DrawingPalette.assign`). A set of twelve (crayons, pastels, earth, sea,
   garden; the painter's choice in the preview), the first the paper's light tint for the ground,
   laid largest area first so neighbours never share one, as many paints as the areas call for
   (one more per three areas, from six); the fills take the ink paint, always last.

Deterministic throughout (fixed orders, integer or sequential float arithmetic), so a drawing
gives the same template on every device, and a saved painting regenerates from its cleaned sheet.

## The test set and the loop

`Tests/Drawings/` holds eighteen freely licensed drawings (provenance in its README) and a
simulated phone photo of each (`tools/drawings/phone_photo.py`: the sheet on a table, askew,
unevenly lit, textured, blurred, noisy, JPEG). `tools/drawings/convert.py --out <dir>` converts
them all and lays each out as input | cleaned | template | painted, with a contact sheet. Each
round, a fresh critic (an illustrator told she would be offended to see her line work mangled,
shown only the sheets) listed every way the conversion disrespects the drawing, worst first.

| Round | Worst complaint (severity) | What changed for the next |
| --- | --- | --- |
| 1 | Hatching shattered into "crazy paving"; dense hatching and thick strokes became black fills; text became pseudo-script; the sheet's edge drawn as a line; whiskers led to the page edge; letter counters filled at random (mangling) | Hatch clusters become one cell; fills judged on depth against the drawing's pen and on compactness, with their paper gaps kept as lines; small writing through `Writing`; coloured washes not ink; the sheet inset; a free end led to the frame only from 6 px |
| 2 | Hatching still cobbles; dense hatching still black; captions eroded; dotted outlines never close; creases drawn; lines reaching the frame split the ground (mangling) | Fills on the mean ink; dots chained into lines; writing held as detail where `Writing` dropped it |
| 3 | Same hatching complaint; new-star's plumes coloured; faces lost in sketches; typeset letters broken; thick tufts and whiskers taken for fills; outline lettering only partly paintable (mangling) | Fills must go two pen widths deep; the paper under a fill; the clutter's gain eased so crowded outlines keep their areas; the room floor lowered for thin letter bodies; gaps bridged to 24 px |
| 4 | Same hatching complaint for the engravings and dense illustrations; sheet edges as painted strips in two photos; the cat's whiskers cut the ground into panels; captions worst on phone photos (mangling). Simple coloring pages: "yes, the areas follow the lines faithfully". Sketches and captioned pages: mostly no. Dense illustrations: no | Stopped here (below) |

Where the loop stopped, and why: the simple coloring pages pass, and the critic's worst
complaint for the dense illustrations is overruled with these reasons.

- **Hatching as cells.** Checked at full size (the artichoke's bracts, the manticore's flank):
  every hatched patch is one area of one paint with the hatch strokes drawn over it in ink,
  which is what the critic herself says a book maker would do; drawn in full ink over paint, a
  dense hatch reads as a net in the painted panel. The black puddles among them are the
  engravings' own solid shadows, ink all over at the working size. Drawing hatching lighter is a
  renderer change (every drawn line is one weight: Settings › Line Weight), out of this scope.
- **Lines that reach the frame split the ground** (the cat's whiskers, a drawing cut by the
  sheet's edge): a coloring book's would too; the areas are real.
- **Captions and typeset text**: small type is at the resolution limit of a 1600-px canvas, and
  `Writing` drops some strokes of cursive; the rows stay line art, never paint, which was the
  point. Handwriting below about 10 px stays as drawn.
- **Paper creases**: a faint long line is a pencil line to the scan; Refine's Line Eraser
  takes it out.
- **Faces in pencil sketches**: a sketch's shading has no contour to follow; the sketch pages
  are best started as a drawing and finished in Refine (Merge, the Pen).

What a painter fixes in Refine: a merged area (the Pen or a Shape closes it), a split one
(Merge), a missing wall (the Pen with Snap), a crease (the Line Eraser), a paint (the Bucket,
Edit Paint). Refine's Color from Photo and Make Cell read the cleaned sheet, so they give paper
white: a drawing's new area takes its paint from the palette instead.
Refine's Text tool reads the generator's writing corrections, which a drawing's path doesn't:
marking or unmarking text makes the painting again unchanged (a drawing's captions are found
by `DrawingScan.textRows` alone).

## Known limits

- A coloured print (a Greenaway page) is read as ink where its wash is dark; the feature is
  for line drawings. A wash lighter and more colourful than a pen's line is left as paper.
- The sheet's proportions are the photographed quadrilateral's, not the paper's.
- A white table under white paper has no edge to find: the whole photo is the sheet.
- The drawing's stroke weight is not kept: every line draws at Settings › Line Weight.
