# Round 3: layered cells (results)

**In short.** The model works as decided: one fixed set of cells, every cell bounded by a line,
every line on a cell boundary, and each line in a layer (`top`, `mid`, `inner`, `color`) that
sets how strongly it draws at a zoom. At 1x the pictures read as clean drawings: full-strength
object outlines, the drawing's detail in grey, texture and colour cells faint. Zooming in brings
the fainter layers up without changing a single cell. Closure delivers on the fox: a BiRefNet
silhouette traces the whole outline, white fur on snow included, and an eye detector plus pbn's
darkest paint draws both eyes as closed almonds that read as eyes at 1x. The finished view, now
blended more widely, turns the train's banded sky into a real gradient. **The cost is cells:**
1.33-3.0x today's (median 1.72x for `recommended`). Nearly all of the increase is cells that
exist only because a drawn line divides one paint (`samePaintSplits`). Without those, every
picture is back at 0.8-1.0x today's count. That trade-off is the main decision for the owner
(see Recommendations).

Outputs: `$S/lineart/layers/<pic>/<variant>/` and `$S/lineart/layers/manifest.json` (all paths
in this document are relative to `$S/lineart/layers/`; `$S` is the session scratchpad).

## What was built

| File | What |
| --- | --- |
| `layers.py` | the model: line sources, layering, closure, cells, trimming, colour lines, numbers, SVG, renders, finished/flat, metrics, manifest, report |
| `subject.py` | the subject silhouette (stand-in for Vision's foreground instance mask) |
| `eyes.py` | eye boxes (stand-in for Vision's face landmarks / animal body pose eye joints) |
| `svg_render.mjs` | batch rasterizing of SVGs with resvg (the static renders, the finished view's ink) |
| `svg_check.cjs` | opens SVGs in Chromium (Playwright) and checks the groups render |
| `layers_notes.json` | the one-sentence notes per picture and variant that go into the manifest |

### Lines and layers

Every line source runs stage 1's shared cleanup (`strokes.extract`) on the cached raw maps.

| layer | source (high / low threshold, cleanup detail) | at 1x, `fade` preset |
| --- | --- | --- |
| **top** | HED 0.85 / 0.50 sparse; gaps closed by pbn's strongest colour boundaries (`lines_boundaries`, 0.45 / 0.25 sparse); the subject silhouette; eye outlines; HED detail on a YuNet face | opacity 1, width 1.4 CSS px |
| **mid** | HED 0.50 / 0.25, medium cleanup, minus what top already draws | opacity 0.55, 1.0 CSS px |
| **inner** | TEED 0.60 / 0.35 medium (`hed-layers`: HED 0.30 / 0.15 rich), minus the layers above | opacity 0.25, 0.75 CSS px |
| **color** | every cell boundary no drawn line covers (banded skies, shading, pbn's tonal steps) | opacity 0.15, 0.6 CSS px |

How the layers are put together (`assemble`):

- **Deduplication.** A lower-layer point within 3.5 px of a higher line is that line. Leftover
  runs reconnect to the nearest higher pixel; runs under 10 px go unless they join two lines.
  The silhouette dedupes at 5 px, because on fur the mask's edge sits a few px off HED's line.
- **pbn's strong boundaries only close gaps.** A piece becomes top when it starts within 6 px
  of a free end of a top line, joins two top lines and is at most 50 px long. First tried as a
  full union: the turtle's shell pattern (every brown/cream edge has high contrast) went to
  full strength and the turtle turned into a black mesh.
- **Free ends** are extended along their tangent (cone 40°) to the nearest line, pbn colour
  boundary or frame. The reach is 16 / 12 / 10 px for top / mid / inner. An open stroke then
  closes cells.
- **Trimming.** After the cells are made, lines are trimmed to where a cell boundary runs within
  2.2 px. What survives the trim (top / mid / inner): 94-99 %, 83-92 % and 69-91 % of each
  detector's length; the rest dangled inside a cell. Cell boundaries more than 3 px from any
  drawn line are traced at 2x as `color` lines.

So both rules hold by construction. A line's strength can change along a boundary: a top line
may end where its boundary continues as a mid or colour line.

**Line weight** is a per-path factor, 0.5-1.3, on the layer's base width:

- photo contrast across the line, importance and length (stage 1's formula);
- times an inker's rule, heavier around dark masses: x0.75 when the line's darker side has
  OKLab L 0.8, up to x1.25 at L 0.3;
- top lines at least 0.75, silhouette and eyes at least 0.9;
- colour lines weighted by the paint difference across them.

The weight rule is aimed at the owner's "soft lines between clouds, bold cypress". It only
partly gets there on the wheat field, because Van Gogh painted dark blue strokes into the sky
too.

### Subject silhouette (closure) and eyes

- **Silhouette:** BiRefNet (Zheng et al. 2024), the `onnx-community/BiRefNet-ONNX` export,
  **MIT**, 973 MB. Runs on CPU in 39-62 s per picture at 1024 x 1024 (onnxruntime, 4 threads).
  Contours of the mask at 0.5 are kept:
  - only where the mask edge is crisp (gradient >= 0.05 per px);
  - only where the photo differs across the edge at a wide scale (OKLab, sigma 3, +-7 px,
    >= 0.015 over any 30 px stretch). This drops the Great Wave's mask, which cut straight
    through open sky; the fox's white fur on snow still differs by >= 0.047 there;
  - only when the mask covers 0.5-70 % of the picture. Wheat field 94 % and lupine 0 % get no
    silhouette.

  The masks are excellent on the fox (white fur included), turtle, gantry plus train, Milkmaid,
  Cézanne's fruit and the arch. On the Great Wave the mask is the wave plus the whole sea.
- **Eyes:**
  - Animals: OWLv2 (Minderer et al. 2023, `google/owlv2-base-patch16-ensemble`,
    **Apache-2.0**), queried with "an eye" / "the eye of an animal" over tiles of the subject,
    score >= 0.25, inside the subject. It finds the fox's eyes (0.56, 0.51). It misses the
    turtle's (best "turtle eye" box 0.02) and the Milkmaid's downcast eyes (0.15 / 0.09).
  - People: YuNet's eye landmarks (MIT), the stand-in for Vision's face landmarks.
  - Drawing: in each box, the paint at least 0.20 darker (OKLab L) than the box's rim, clipped
    to the ellipse inscribed in the box, becomes a closed top line, and the paint 0.35 darker
    inside it a pupil. Other strokes inside the eye are cleared, so an eye is an outline and a
    pupil. Its cells are exempt from the small-cell merge.
  - On device: Vision's `VNDetectAnimalBodyPoseRequest` (cats and dogs: eye joints; a fox
    probably works, a turtle does not) and face landmarks would replace both models.
- 2 of 9 pictures had eyes: fox (OWLv2) and Milkmaid (YuNet). No false positives on the other
  six.

### Cells

- C1 as in stage 2 (`color_split.finish`): pbn's regions split by all drawn lines (top + mid +
  inner), snap, small-fragment merge inside each enclosed area, and cells too small for a
  number joining a same-paint region across the line or vanishing when all ink.
- Then **no cell stays below its number's size**: the remaining few (6-99 per picture) merge
  into their most similar neighbour across the line, and that line piece is trimmed away.
  Every variant ends with 0 cells below size; the smallest room is 2.33 px against the 2.12
  minimum.
- `merged-color` then merges neighbouring cells of one enclosed area (not across a drawn line)
  whose paints are within 2 palette steps (0.08-0.12 ΔE). The larger cell keeps its paint, and
  each merge is checked against that paint, so colours don't drift along a chain.

### Numbers

LabelSizing at each cell's pole outside the ink (walls dilated by 1 px), plus pbn-style extras
over big cells; font size capped at 1/64 of the long side. `data-minzoom` is the zoom at which
the digits (0.72 em) are 8 CSS px tall on a 390 CSS px phone showing the whole picture at 1x:
`8 / (font-size x 0.72 x 390 / W)`.

**No number is legible at 1x on any picture.** The largest numbers need 1.8x; the median number
needs 4.3-7.3x; 6-21 % of numbers are legible at 2x and 20-43 % at 4x. This follows from the
8 px rule and today's number sizes, not from layering.

### Finished view

Stage 2's line-respecting domain-transform blur:

- drawn lines are hard barriers;
- colour boundaries blend freely up to **1.6 palette steps** (stage 2: 1.2), with a sigma of
  **40 working px** where cells are big (stage 2: 24).

In this model every object edge is a drawn line, so the colour boundaries left are bands and
shading. At stage 2's settings the train's sky still showed its bands
(`_look/sky_params.jpg` compares the settings); now it is a gradient. The drawn layers go on top
at their 1x preset weights; colour lines are not drawn there, since the paint blends across
them.

## Outputs

Per picture `<pic>/`:

- `photo.jpg` (1600 px);
- `today_template.jpg`, `today_painted.jpg` (pbn's SVGs rendered at 1600 px);
- `today_z2.jpg`, `today_z4.jpg` (pbn's template cropped to the same rects as the variants);
- `_subject.png` and `_eyes.json` (caches).

Per variant `<pic>/<variant>/`:

- `lines.svg`:
  - viewBox `0 0 W H` in working px;
  - groups `color`, `inner`, `mid`, `top` (drawn in that order) with `fill="none"`, round caps
    and joins, and a group `data-base` (the layer's 1x width in working px);
  - paths with `stroke-width` = base x weight and `data-w` = the weight;
  - `<g id="numbers">` with `<text x y font-size data-minzoom>`: x is the centre
    (`text-anchor="middle"`), y the baseline that centres the digits on the pole.
  - Coordinates have 1 decimal (RDP 0.3 px); 87-736 KB.
- `flat.jpg`, `finished.jpg` (2x working size).
- `z1.jpg`, `z2.jpg`, `z4.jpg` (1080 px wide, paper `#F4EFE6`, ink `#2B2530`, numbers
  `#706876` in Source Serif 4, default preset; numbers shown when `minzoom <= z`).
- `metrics.json`:
  - cells and today's;
  - `samePaintSplits`;
  - cells by the strongest layer on their boundary;
  - strokes, length and share per layer;
  - drawn length kept after trimming;
  - cell-rule counts, smallest room, numbers per zoom, subject and eye info, seconds.

`manifest.json` follows the requested format. Additions:

- `render_notes` (units, colours);
- `"weighted"` and `"label"` per preset;
- `"note"` per picture;
- each variant's metrics carry `samePaintSplits`.

**Render presets.** Opacity and width multiplier at zoom 1 / 2 / 4, log-linear between. The
drawn width is stroke-width x multiplier, i.e. width x multiplier x zoom x 390 / W CSS px on
screen.

- `fade` (default): top 1 / 1 / 1; mid 0.55 / 1 / 1; inner 0.25 / 0.6 / 1; colour
  0.15 / 0.3 / 0.5. All layers use width multiplier 1 / 0.6 / 0.36, so the on-screen width grows
  only slowly with zoom (top 1.4, 1.7, 2.0 CSS px).
- `grow`: fades by width instead. Mid is 0.45x, inner 0.3x and colour 0.35x as thick as top at
  1x, at 0.45-0.85 opacity, and reach full width by 2-4x. It gives a fine hairline web.
- `fade-uniform`: as `fade`, ignoring per-path weights (uses `data-base`).

`_look/presets_red-fox_recommended_z1.jpg` and `_look/presets_hawksbill-turtle_recommended_z2.jpg`
show the three presets stacked (top to bottom: fade, grow, fade-uniform).

Validation: every file listed in the manifest exists and loads. All 36 `lines.svg` open in
Chromium (390 px viewport, DPR 3) with all five groups present and top paths of nonzero length.
`layers.py --manifest` checks the files; `svg_check.cjs` does the browser check.

## Cells versus today

| picture | today | recommended | no-closure | hed-layers | merged-color |
|---|---:|---:|---:|---:|---:|
| santa-fe-freight | 322 | 555 (1.72x) | 556 (1.73x) | 578 (1.79x) | 320 (0.99x) |
| hawksbill-turtle | 950 | 1267 (1.33x) | 1265 (1.33x) | 1050 (1.10x) | 802 (0.84x) |
| red-fox | 234 | 374 (1.60x) | 383 (1.64x) | 325 (1.39x) | 153 (0.65x) |
| great-wave | 420 | 934 (2.22x) | 927 (2.21x) | 902 (2.15x) | 747 (1.78x) |
| milkmaid | 486 | 861 (1.77x) | 863 (1.78x) | 733 (1.51x) | 419 (0.86x) |
| wheat-field | 643 | 1955 (3.04x) | 1959 (3.05x) | 2198 (3.42x) | 882 (1.37x) |
| cezanne-apples | 538 | 765 (1.42x) | 763 (1.42x) | 767 (1.43x) | 248 (0.46x) |
| delicate-arch | 618 | 992 (1.60x) | 998 (1.61x) | 721 (1.17x) | 489 (0.79x) |
| lassen-lupine | 815 | 1661 (2.04x) | 1670 (2.05x) | 1507 (1.85x) | 1041 (1.28x) |
| **median** | | **1.72x** | 1.73x | 1.51x | 0.86x |

**Where the extra cells come from.** `samePaintSplits` counts cells that would be one cell if
neighbours with the same paint were joined: cells a drawn line divides although the paint is the
same on both sides. In `recommended`:

| picture | cells | same-paint splits | without them | vs today |
|---|---:|---:|---:|---:|
| santa-fe-freight | 555 | 252 | 303 | 0.94x |
| hawksbill-turtle | 1267 | 514 | 753 | 0.79x |
| red-fox | 374 | 139 | 235 | 1.00x |
| great-wave | 934 | 551 | 383 | 0.91x |
| milkmaid | 861 | 404 | 457 | 0.94x |
| wheat-field | 1955 | 1323 | 632 | 0.98x |
| cezanne-apples | 765 | 238 | 527 | 0.98x |
| delicate-arch | 992 | 419 | 573 | 0.93x |
| lassen-lupine | 1661 | 852 | 809 | 0.99x |

The full detail table (cells by strongest boundary layer, line shares, trim, numbers, SVG size,
seconds) is printed by `layers.py --report`.

## The variants, picture by picture

What each variant looks like is in `manifest.json` (`note`, from `layers_notes.json`). Across
pictures:

- **`recommended`** gives the cleanest 1x drawing that is still complete. Best:
  - `santa-fe-freight/recommended/` (crisp gantry and locomotive, a sky of faint cells that
    becomes a gradient in `finished.jpg`);
  - `red-fox/recommended/` (whole outline, eyes);
  - `hawksbill-turtle/recommended/z1.jpg` (outline and scutes black, pattern grey, texture
    faint; exactly the turtle note);
  - `milkmaid/recommended/z2.jpg` (the figure is cells: cap, face, collar, bodice, sleeves);
  - `cezanne-apples/recommended/` (every fruit closed);
  - `delicate-arch/recommended/`;
  - `great-wave/recommended/` (a full ink copy).
- **`no-closure`** differs only where HED misses a soft outline. On the fox it is decisive
  (`red-fox/no-closure/z1.jpg`): the white back, tail and chest have no full-strength line and
  the top layer's share of the drawing falls from 16 % to 9 %. Elsewhere HED already closes the
  outline, and the difference is a few stretches (Cézanne's fruit, the arch's top, the Milkmaid's
  outline).
- **`hed-layers`** is calmer zoomed in. On faint-texture pictures it has fewer cells (turtle
  1.10x, arch 1.17x vs 1.33x / 1.60x); on brushwork it has more (wheat 3.42x). At 1x it looks
  like `recommended`, since inner is faint there. TEED's inner layer is what draws the turtle
  shell's web and the arch's rock texture at 4x.
- **`merged-color`** shows what the faint colour cells are for:
  - cells drop to 0.46-1.78x today's (median 0.86x);
  - the plan is calmer;
  - but `finished.jpg` loses its gradients: the train's sky becomes three flat bands, the fox's
    orange back merges into beige, and Cézanne's fruit lose their modelling. The faint colour
    cells are what carry the finished view's gradients.

### The fox: outline and eyes

- **Outline.** The whole silhouette is traced at full strength
  (`red-fox/recommended/z1.jpg`), including the white back, tail and chest against the snow,
  where HED and pbn see almost nothing. 2885 px of the 6959 px top layer come from the
  silhouette. Small notches remain where the HED line along the fur is jagged (z2, right flank).
- **Eyes.** Both are closed almonds at full strength. The left one has its dark slit as a pupil
  outline; the right one is a single almond around lid and iris. At 1x they read as two eyes
  under the ears (z1); at 2x and 4x (`z2.jpg`, `z4.jpg`) they are clearly drawn eyes with their
  own cells. `today_z4.jpg` has a scatter of small cells there instead.
- **Getting there.** The first attempt promoted every stroke inside the eye box to top and gave
  dark scribbles. The second outlined paint darker than the box's rim, but that paint (eyeliner,
  the fox's tear line, orange fur) runs out of the box, so the outline followed the box edges.
  Clipping to the ellipse inscribed in the box, with a 0.20 / 0.35 darkness step, gave the
  final shapes. All three depend on OWLv2 finding the eyes; on device it would be Vision's
  animal pose.

## Where it fails

1. **Cell count** (above): 1.3-3x today's, almost all of it same-paint splits. Worst on busy
   pictures (wheat field 3x, lupine 2x, Great Wave 2.2x).
2. **Busy texture is a web of lines.** The lupine meadow, the wheat field's brushwork and the
   Great Wave's foam get dense mid and inner lines. Faint at 1x, but at 2-4x they are a maze
   of tiny same-number cells (`lassen-lupine/recommended/z2.jpg`). Only 4-6 % of the lupine's
   and the wheat field's numbers are legible at 2x.
3. **Line weight doesn't separate soft from bold on paintings.** Clouds versus cypress: the
   darkness rule helps a little, but Van Gogh's sky has dark strokes too.
4. **Top lines can end mid-air.** Where a top line's boundary continues only as a colour or
   inner line, it looks open at 1x (the fox's forehead strokes, inner HED strokes). Closing top
   outlines along cell boundaries (a path search) would be the next step.
5. **The subject mask can be wrong.** It has no subject on landscapes and paintings (wheat 94 %,
   lupine 0 %), so there is no closure there. It also cut through the Great Wave's sky; the
   side-contrast rule catches that. On device, Vision's mask may fail the same ways, so the
   same checks apply.
6. **Eyes need a detector.** The turtle's eye and the Milkmaid's downcast eyes were not found by
   OWLv2. The Milkmaid gets one lid shape from YuNet; the turtle gets nothing special (its eye is
   a HED top line).
7. **Numbers at 1x:** none legible under the 8 px rule (see Numbers). The presentation should
   not read this as a flaw of layering.
8. **Small artifacts:**
   - a few dashed stretches where a trimmed line alternates with a colour line;
   - doubled lines where the silhouette sits more than 5 px from HED's line;
   - pbn's wobbly band boundaries become wobbly colour lines (the train's sky at 2x).

## Recommendations for the owner's taste decisions

1. **Same-paint splits.** This is the decision that matters most:
   - **(a)** keep them, as built: the same number on both sides of a line, 1.3-3x cells;
   - **(b)** drop a mid or inner line wherever the paint is the same on both sides: about
     today's cell count, but the turtle's shell texture and the fox's fur strokes go;
   - **(c)** allow those lines inside a cell as pure drawing: breaks "every line bounds cells"
     but keeps both.

   Show `red-fox` and `hawksbill-turtle` `recommended` next to today with the cell counts.
2. **Faint colour cells (`recommended` vs `merged-color`).** They are what makes the finished
   piece a gradient, and at 1x opacity 0.15 they read as a light pencil texture. My
   recommendation is to keep them. The decisive comparison is `santa-fe-freight` and
   `cezanne-apples`, `finished.jpg` side by side.
3. **Closure: keep the silhouette.** It is decisive on the fox and harmless elsewhere (it never
   fires without a subject); compare `red-fox` `recommended` vs `no-closure` at z1.
4. **Inner layer: TEED or HED?** Taste: TEED's web on the turtle shell at z4 vs HED's calmer
   version (`hawksbill-turtle/*/z4.jpg`). HED-only is one model and fewer cells on smooth
   subjects.
5. **Presets.** `fade` reads best at 1x (clear hierarchy). `grow` keeps 1x lighter and makes
   zooming feel like the drawing sharpening. `fade-uniform` loses the soft-vs-bold distinction.
   Let the owner toggle them on the fox and the turtle.
6. **Avoid leading with** `lassen-lupine` and `wheat-field`: no subject, a busy web, and 2-3x
   the cells. They are the honest stress cases.

## What a production version would need

- **Vision instead of the stand-ins:**
  - `VNGenerateForegroundInstanceMaskRequest` for the silhouette, with the same
    crisp-and-contrast checks;
  - face landmarks and `VNDetectAnimalBodyPoseRequest` for eyes;
  - the line models (HED, Apache-2.0; TEED, MIT) in Core ML, with their maps quantized to 8 bits
    before the cleanup so templates stay deterministic (stage 1's finding).
- **Template format, a new optional extension chunk** (no `formatVersion` bump; old readers draw
  every edge as today):
  - per boundary edge, a layer (top / mid / inner / color) and a weight byte;
  - per eye, its protected cells.

  Lines coincide with cell boundaries after trimming, so the layer is a property of the existing
  boundary edges, not separate stroke geometry. That makes it simpler than stage 2's
  stroke-list proposal.
- **Canvas.** Line opacity and width as functions of zoom, uniforms per layer in the shader
  (log-zoom interpolation between three keys, as in the presets). Numbers fade in by
  `minzoom`. Colour lines fade once both sides are painted.
- **Finished view.** The domain-transform blend with drawn edges as barriers, computed once at
  generation time or when a painting completes.
- **Pipeline.**
  - The cleanup, dedupe, closure, C1 and trimming in PaintCore. In numpy, lines plus cells take
    6-12 s per picture and variant, and the 2x finished/flat 13-30 s (the blur dominates).
    Sources take 1-3.6 s each after the raw maps.
  - A decision on same-paint splits (above).
  - `pipelineVersion` bumped with any of it.

## Reproducing

See README § Layered cells: `layers.py <pics> --jobs 2`, then `layers.py --manifest` and
`layers.py --report`. Add `LAYERS_DEBUG=1` for per-layer colour renders in `_look/`.
`subject.py` and `eyes.py` cache `_subject.png` / `_eyes.json` per picture (BiRefNet ~50 s,
OWLv2 1-3 min on 4 shared cores). Everything is deterministic except timings; the models run
with fixed thread counts.
