# Line-art research: a drawing first, color inside it

Exploration only, on `claude/lineart-research` under `research/lineart/` (Python). Nothing
here touches `Sources/`, `App/` or the regression baselines. The goal is pictures the owner
can judge, not an implementation.

## The idea being tested

Today every region boundary is an ink line, which is right for printing but turns gradients
into outlined rings. The zen-mode idea splits two layers:

- **Line art**: strokes that read as a drawing of the picture on their own. Strokes may be
  open (a crease, a strand of hair), vary in weight and follow structure (silhouettes,
  features, folds), not texture.
- **Color regions**: the cells you paint. **No region crosses a line**, but not every region
  boundary is a line: inside one area enclosed by lines, a cheek can hold three tonal regions
  with no ink between them. An open stroke is a wall along its whole length; a region may
  wrap around its free end.

While painting, ink sits on top of the paint, and unlined boundaries are faint guides that
vanish once both sides are painted. The finished painting can blend across unlined
boundaries, so a sky's bands become a gradient again.

The questions the owner wants answered by looking: does the line art read as a drawing on
its own? Does the finished piece look like an illustration rather than a posterized photo?
Which kind of line looks best?

## Test set

8–10 pictures from the new library, chosen to stress different things: a face (Vermeer or a
Mucha), a Japanese print (already line plus flat color: the ceiling for this idea), an
impressionist canvas (no lines to find), a still life, a landscape photo with a sky gradient,
an animal photo with fur or feathers, a busy texture (foliage, a market), and Earthrise or
another large soft gradient. Until the library is chosen, build and tune on the six current
samples and a few Kodak photos (`kodim04` face, `kodim23` parrots, `kodim03` hats).

Work at `pbn`'s working resolution: run `pbn generate --auto --length relaxed` per picture
and use its `working.ppm` as the photo and `raster.ppm` as the color segmentation, so every
layer lines up pixel for pixel.

## Stage 1: the drawing

Families (each a script `lines_<family>.py`, image in, line map out at working resolution):

| Family | Method | Expect |
| --- | --- | --- |
| A. Flow DoG | Coherent line drawing (Kang, Lee, Chui 2007): edge tangent flow, then a flow-guided difference of Gaussians | pen sketch, long flowing strokes |
| B. XDoG | Winnemöller et al. 2012, thresholded for ink | graphic, comic-like |
| C. Curated boundaries | `pbn`'s own region boundaries kept where the OKLab contrast across them is strong, pruned by length | tidy, closed; closest to today |
| D. Learned | `controlnet_aux` detectors (weights from Hugging Face `lllyasviel/Annotators`): `LineartDetector` (Informative Drawings, fine and coarse), `PidiNetDetector`, `HEDdetector`, `TEEDdetector`, `LineartAnimeDetector`; CPU is fine at this resolution | closest to an illustrator; strongest on faces |

Note each learned model's license in `results.md` (it matters only if one ships later).
Generative image models are out of scope: they redraw rather than trace.

Shared cleanup (`strokes.py`), applied to every family's map so they compete on the lines
they find, not on cleanup:

1. Threshold (hysteresis) and thin to one-pixel centerlines.
2. Trace into polylines; prune spurs and fragments below a length; bridge small gaps along
   the tangent.
3. Simplify and smooth into curves.
4. Weight each stroke by its contrast, and by importance (more line detail on the subject).
   Variants: uniform weight; tapered weight; ink color (near-black, or a dark shade of the
   paint beside it, "colored line").
5. Detail levels: 3 per family (sparse, medium, rich), set by the pruning length and
   threshold.

## Stage 2: color inside the lines

For the 2–3 best drawings per picture:

- **C1, split pbn's regions by the lines.** Connected components of `raster.ppm` colors,
  each split wherever a line crosses it; fragments too small to hold a number merge into
  a neighbour in the same enclosed area (never across a line). Color edges running within a
  couple of pixels of a line are snapped onto it, so no slivers.
- **C2, segment inside each enclosed area.** Flood-fill the areas the lines enclose
  (with wraparound at open stroke ends), then cluster OKLab colors within each, using `pbn`'s
  palette. Fewer regions, softer shapes. Try both and keep the better.

Report per variant: regions, regions per enclosed area, slivers, the smallest region's
inscribed radius (labels need `LabelSizing.minimumRadius`).

## Panels (every option renders all three, 2× working size, PNG)

1. **Lines alone**: ink on the `paper` color `#F4EFE6`. Is it a drawing?
2. **Painting plan**: lines, faint dotted guides on unlined boundaries, numbers in New York
   (or a serif fallback) at region poles of inaccessibility.
3. **Finished**: flat paint, blurred across unlined boundaries only (a blur that never
   crosses a line, e.g. normalized convolution with the line mask), ink on top.

Plus, for comparison, the current template (`pbn`'s `template.svg` rendered, and its painted
raster).

## Judging and narrowing

Automatic measures, as a filter, not a verdict: ink coverage, stroke count and mean length,
fragments, strong-edge recall (share of high-contrast, high-importance edges the strokes
cover), regions, slivers.

Legibility check: give a fresh subagent only the "lines alone" panel and ask what it shows
and how sure it is. A drawing that can't be named fails.

Then the orchestrator looks at every surviving option and narrows to the best **3–4 per
picture**, keeping different families where they're comparably good, so the owner chooses
between kinds, not between near-identical tunings. The rest go under "more variants".

## What goes to the morning page

Per picture: the options side by side with a panel toggle, pick and notes per option.
Then a short verdict: the family that wins most often, where each family fails (with an
example image), what a production version would need (model size, speed on the CPU here as a
proxy, determinism concerns for a learned model), and the next round you'd run.

`results.md` in `research/lineart/` carries the same verdict and every measure, so the next
session can pick up from the owner's picks.
