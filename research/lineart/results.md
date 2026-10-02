# Line-art research: results

## Overall verdict (orchestrator, after both stages and the blind check)

**The idea works; the drawing is the open question.** Splitting pbn's regions by a drawing's
lines (C1, `results_color.md`) and blending only across unlined boundaries turns banded skies
back into gradients while every line stays crisp; the finished pieces read as illustrations
rather than posterized photos (clearest on Freight Train, Delicate Arch, the Great Wave). C2,
segmenting inside each enclosed area, drops small details and is ten times slower: C1 is kept.

**Family to develop: HED** (Apache-2.0, 29 MB, 2-6 s at ~1150 px on 4 CPU cores). **TEED** if
the model must be tiny (58 k parameters, 0.2 MB, MIT; dataset terms unverified; 0.5-2 s).
PiDiNet looks calmest but is probably research-only. Flow DoG and Informative Drawings (fine)
draw the Great Wave best, i.e. prints, where any family does well.

**Blind legibility** (a fresh agent saw only the "lines alone" panels, 36 drawings, four per test
picture; `narrowing/`): "reads as a drawing" yes / partly / no and mean confidence of naming the
subject:

| Family | yes · partly · no | confidence |
| --- | --- | --- |
| HED | 5 · 3 · 0 | 68 % |
| PiDiNet | 5 · 3 · 0 | 65 % |
| TEED | 2 · 6 · 1 | 68 % |
| Informative Drawings, fine | 1 · 2 · 0 | 92 % (prints, photos with clear subjects only) |
| Flow DoG | 2 · 0 · 0 | 80 % (Great Wave, Freight Train) |
| XDoG | 0 · 1 · 0 | 93 % (Great Wave only) |
| Curated boundaries | 0 · 4 · 1 | 61 % |

Per picture, the subject was named with high confidence for the Great Wave (93-96 %), the
Milkmaid (85-93 %), the turtle (92-96 %) and Delicate Arch (88-90 %); poorly for the
fox (40-60 %, read as a puppy at sparse detail in all four drawings; medium detail restores the
silhouette), Lassen lupine (35-45 %, no family draws the flower field) and Wheat Field (25-65 %).

**Where every family fails:** impressionist canvases (no lines to find, brushwork gets inked);
soft silhouettes on white at sparse detail; flower fields and foliage (the finished piece is
blotches). TEED inks shading and fur; Flow DoG misses equal-brightness color edges; XDoG lines sit
off the edges; Anime2Sketch draws almost nothing on photos; curated boundaries have no hierarchy.

**Shown to the owner** (`narrowing/shown_to_owner.json`, the morning page): three or four options
per test picture, different families where comparably good, C1 colouring; every other family
under "more variants". The owner's picks and notes live in the morning page's database
(collections `lineart`, `notes`, `swaps`, `decisions`), readable with ArtifactData.

**Production would need:** the chosen model in Core ML; its edge map quantized to 8 bits before
cleanup (HED and TEED differ in the 7th decimal with the thread count) so templates stay
byte-identical; the cleanup, the region split and a lined/unlined flag per boundary in PaintCore;
ink over paint, fading dotted guides and the line-respecting blur in the app; and a fallback to
today's template for pictures with no lines to find.

**Next round:** start from the owner's picks; tune detail per kind of picture (sparse for faces,
medium for prints and photos); try HED united with pbn's strongest boundaries so soft
silhouettes keep their outline; time the Core ML model on device and test determinism.

## Stage 1: the drawing

Everything below can be rerun with the commands in `README.md`. Outputs for the ten dev
pictures are in `$S/lineart/out/<pic>/<family>-<detail>/` (`$S` = the session scratchpad).
Contact sheets are in `$S/lineart/look/`: `<pic>_<detail>.png` shows every family at one
detail level, and `picks_<pic>.png` shows the picks below in tapered ink. The picks are also in
`$S/lineart/out/stage1_picks.json` for stage 2.

### Verdict

**The learned edge detectors win, and TEED wins most often.** On photos, two detectors give
a drawing that reads on its own:

- TEED gives the most detail with the least noise: eyes, mouths, rigging, window louvres.
- HED gives bold, closed silhouettes and the cleanest page, with fewer interior details.

PiDiNet is an even sparser HED. On the Japanese print the lines are already in the picture,
and there the classic methods are as good or better: flow DoG and Informative Drawings
("lineart fine") draw the best Great Wave. pbn's own boundaries (C) are a strong fallback
that costs nothing extra. They have the highest precision of all and good recall, but every
paint edge with contrast becomes a line, so the drawing has little hierarchy. XDoG gives the
weakest drawing on photos. The detail level matters as much as the family: faces need
*sparse* (at medium the skin shading is already drawn as wrinkles), prints need *medium*.

Picks (2-3 per picture, from different families where they are about as good). Each pick
gives its stroke count n, its ink coverage and its strong-edge recall:

| picture | picks | why |
| --- | --- | --- |
| parrots / kodim23 (same photo) | **teed-medium** (n 145, 1.9 %, 0.72), hed-medium (66, 1.4 %, 0.46), lineart_fine-medium (169, 1.8 %, 0.66) | TEED keeps both eyes, the facial stripes and the beaks; HED gives two bold silhouettes; lineart fine adds a hint of feathers |
| kodim04 (face) | **teed-sparse** (61, 1.5 %, 0.77), hed-medium (103, 1.8 %, 0.74), boundaries-medium (160, 2.4 %, 0.81) | eyes, nose, lips, hat and beads with nothing on the skin; at medium, TEED adds shading strokes on the cheeks and forehead that age the face |
| great-wave (print) | **flowdog-medium** (805, 5.4 %, 0.69), lineart_fine-medium (953, 4.9 %, 0.67), xdog-medium (865, 3.7 %, 0.40) | all three are a convincing ink copy of the print; TEED draws the paper grain in the sky |
| lighthouse | **hed-medium** (155, 2.2 %, 0.43), teed-sparse (147, 2.3 %, 0.53), pidinet-medium (105, 1.6 %, 0.34) | buildings plus a few rock masses; every other option turns the rocks into a mesh |
| barn | **hed-medium** (219, 2.6 %, 0.73), pidinet-medium (115, 1.7 %, 0.63), teed-sparse (89, 1.5 %, 0.71) | the barn's planes and roofline; every family draws the foliage as scattered strokes |
| espresso | **hed-medium** (37, 1.9 %, 0.66), lineart_fine-medium (106, 3.0 %, 0.87), teed-medium (138, 3.2 %, 0.87) | clean ellipses for cup and saucer; the two richer options add the spoon's reflections |
| hibiscus | **pidinet-medium** (218, 3.5 %, 0.49), teed-medium (372, 6.2 %, 0.91), boundaries-medium (305, 5.6 %, 0.82) | only PiDiNet keeps the window's stone frame and the leaves without clutter; TEED draws the louvres |
| regatta | **hed-medium** (138, 2.1 %, 0.74), teed-medium (258, 3.1 %, 0.85), pidinet-medium (107, 2.1 %, 0.70) | sails, stripes and hulls; the water stays light |
| kodim03 (hats) | **hed-medium** (43, 1.6 %, 0.73), lineart_fine-medium (174, 2.1 %, 0.80), teed-medium (136, 2.1 %, 0.82) | five clean hat shapes; the other two add the lettering and the shadows |

How often each family is picked, out of 10 pictures: TEED 9, HED 8, PiDiNet 4, lineart fine
4, boundaries 2, flow DoG 1 and XDoG 1 (both on the print). The legibility check (a fresh
agent names each "lines alone" panel) is the orchestrator's next step.

### What was built

- **Four families.** Each one is `response(pic) -> float map` at working resolution, with
  1 = line:
  - `lines_flowdog.py`: edge tangent flow (ETF), 3 separable iterations, radius 5; flow DoG
    with sigma_c 1, rho 0.99, sigma_m 3, two iterations; lightness = OKLab L.
  - `lines_xdog.py`: sigma 1.6, k 1.6, p 24, eps 0.30, phi 6, after two bilateral passes.
  - `lines_boundaries.py`: the boundaries of raster.ppm. Strength =
    sqrt(photo gradient / 0.045 x paint deltaE / 0.16), averaged along the boundary.
  - `lines_learned.py`: six controlnet_aux networks. They run on the working image itself,
    reflect-padded, not resized to 512.
- **`strokes.py`, the shared cleanup** (details in its docstring):
  - ridge non-maximum suppression plus hysteresis, with thresholds scaled by importance and
    clutter, and strong photo edges protected;
  - fills replaced by their outlines;
  - graph tracing, bubble popping, spur pruning and texture-mesh suppression;
  - gap bridging along the tangent;
  - fragment pruning scaled by contrast and importance;
  - frame sealing and joining through junctions;
  - Gaussian smoothing with pinned ends, then Douglas-Peucker simplification;
  - weights by contrast, importance and length, in uniform, weighted and tapered widths, with
    near-black or colored ink;
  - 8-connected walls and anti-aliased capsule rendering at 2x.
- **The importance proxy** (`lines_common.importance_map`):
  - spectral-residual saliency (Hou & Zhang 2007) at 64 px, on OKLab L, a and b;
  - blended 0.65 x saliency + 0.35 x a centered Gaussian (sigma 0.35), stretched to its 99th
    percentile and floored at 0.1;
  - faces found by OpenCV's YuNet are set to 1 (MIT license, weights from Hugging Face
    `opencv/face_detection_yunet`). Without the face prior, the sparse levels lost kodim04's
    eyes: a face is smooth, so saliency misses it.
- **The walls contract, checked on a synthetic picture.** The picture has a circle, a
  rectangle split by two T-junction lines, an open stroke and a line crossing the frame. It
  gives the 6 expected 4-connected regions, and only those, at all three detail levels.
  Open strokes create no region.

The detail levels share `strokes.DETAIL`:

| setting | sparse | medium | rich |
| --- | ---: | ---: | ---: |
| spur (px) | 14 | 10 | 7 |
| gap (px) | 10 | 9 | 8 |
| fragment (px) | 56 | 36 | 18 |
| mesh density | 0.085 | 0.11 | 0.14 |
| mesh edge length (px) | 40 | 28 | 20 |
| clutter density | 0.05 | 0.07 | 0.10 |

The hysteresis thresholds are set per family (`run_lines.FAMILIES`), tuned by eye so that each
family is at its best. Each detector has its own response scale: TEED's background sits at
0.17, PiDiNet's lines saturate near 1, and the lineart models peak at 0.3-0.5.

### What failed on the way (and what fixed it)

- **Thresholding, then skeletonizing.** HED's and PiDiNet's soft 6-10 px lines came out as
  doubled outlines, because my first fills-to-outlines rule fired on them, and junctions
  grew bubbles. Ridge NMS fixed both, since it finds the centerline whatever the width.
  Fills now need a core of at least 80 px above the family's sparse threshold, so a junction
  of thick lines no longer counts as a fill.
- **Fills detected on the low-threshold mask.** Recall fell as the detail rose: TEED's wide
  responses turned into fills, which means parallel outlines 8 px off the edge. Fills now
  use a fixed level per family.
- **XDoG at the paper's sigma of about 1.** Every feather, brick and grain of film inked,
  and the porous dark areas skeletonized into mazes. Fixed with sigma 1.6, a bilateral
  prefilter and fill level 0.7.
- **Texture.** Weaves (kodim04's hat and net), rocks (lighthouse) and foliage (barn) became
  meshes of small cells. Two shared steps help:
  - thresholds raised where lines are cluttered, the bigger effect: lineart fine on kodim04
    went from 1042 to 226 strokes at medium;
  - mesh suppression.

  The rich levels keep some texture on purpose.
- **The frame.** Kodak's dark rim and vignettes drew lines along the border. Ridges parallel
  to the frame within 12 px are now dropped, and free ends near the frame are extended to it.
- **Eyes vanished at sparse,** removed by fragment pruning. The fragment length now scales
  with photo contrast and importance, and faces count as important.
- **TEED's normalization.** With TEED's original normalization (BGR, mean-subtracted) instead
  of controlnet_aux's (RGB 0..255), it draws more texture, so I kept controlnet_aux's.

### Per family: where it works, where it fails

- **A. Flow DoG**
  - Works: long, coherent pen strokes, high precision (0.85); the best Great Wave.
  - Fails: it sees only lightness, so edges between colors of equal lightness disappear (the
    red parrot's back against green leaves is gone). Soft silhouettes break into dashes, and
    rocks turn into hatching (`lighthouse_medium.png`).
  - Lines sit on the dark side of edges: recall 0.60 at 2 px, 0.87 at 4 px.
  - About 6-7 s in numpy, an obvious GPU candidate.
- **B. XDoG**
  - Works: graphic, comic-like; dark masses become outlined shapes; good on the print.
    Cheapest family (0.2 s).
  - Fails as a drawing on photos: light-on-light contours are missing (kodim04's hair and
    cheek). Bokeh and shadows become outlined blobs (the background in `parrots_medium.png`,
    the table in `espresso_medium.png`), and sparse is thin.
  - Lowest recall, 0.25 at 2 px: its lines sit 2-3 px off the edge (0.79 at 4 px). Lowest
    precision too (0.40).
- **C. Boundaries**
  - Works: tidy and exactly on the paint edges (precision 0.95, recall 0.75 at 2 px). Costs
    nothing extra, since pbn computes the boundaries anyway. Closest to today.
  - Fails on hierarchy: every paint edge with photo contrast becomes a line, so bokeh discs
    and feather patches get outlines (`parrots_medium.png`). The curves inherit the raster's
    wobble.
- **D. TEED** (58 k parameters)
  - Works: best recall (0.82 at medium) with precision 0.93; faces, rigging, louvres. Fastest
    learned model.
  - Fails by drawing shading: skin creases on kodim04 at medium, paper grain in the Great
    Wave's sky at rich.
- **D. HED** (lllyasviel's retraining, Apache-2.0)
  - Works: bold, closed silhouettes; the page that reads fastest (precision 0.96).
  - Fails on interior detail, such as the parrots' eyes (recall 0.46 there).
- **D. PiDiNet**
  - Works: the most minimal drawing (102 strokes at medium, mean length 145 px).
  - Fails by leaving things out (the lighthouse rocks, the Great Wave's foam). The slowest
    model at full resolution.
- **D. lineart fine** (Informative Drawings, style 1)
  - Works: delicate, like an illustrator's line; the best learned Great Wave.
  - Fails on textures at medium and rich (hat weave, rocks), and doubles the contour on some
    edges.
- **D. lineart coarse** (style 2)
  - A sketchier lineart fine, with strokes slightly off the edges (recall 0.59). Never better
    than fine here.
- **D. lineart anime** (Anime2Sketch)
  - Trained on anime, so weak on photos: sparse is nearly empty on several pictures
    (lighthouse: 16 strokes), the espresso saucer gets hatching artifacts, and the lighthouse
    comes out broken.
  - Fine on the print.

### Numbers (means over the ten dev pictures)

| family | detail | strokes | mean length (px) | fragments (<24 px) | ink coverage | recall 2 px | recall 4 px | edge precision |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| A flowdog | sparse | 124 | 104 | 16 | 1.6 % | 0.49 | 0.73 | 0.86 |
| A flowdog | medium | 216 | 84 | 39 | 2.3 % | 0.60 | 0.87 | 0.85 |
| A flowdog | rich | 353 | 64 | 92 | 2.9 % | 0.63 | 0.92 | 0.84 |
| B xdog | sparse | 85 | 124 | 12 | 1.1 % | 0.14 | 0.56 | 0.36 |
| B xdog | medium | 264 | 76 | 78 | 2.1 % | 0.25 | 0.79 | 0.40 |
| B xdog | rich | 510 | 53 | 208 | 2.8 % | 0.32 | 0.85 | 0.44 |
| C boundaries | sparse | 94 | 135 | 11 | 2.1 % | 0.65 | 0.73 | 0.98 |
| C boundaries | medium | 225 | 92 | 55 | 3.3 % | 0.75 | 0.84 | 0.95 |
| C boundaries | rich | 441 | 73 | 140 | 4.7 % | 0.78 | 0.87 | 0.86 |
| D lineart_fine | sparse | 119 | 101 | 25 | 1.6 % | 0.53 | 0.67 | 0.92 |
| D lineart_fine | medium | 395 | 63 | 155 | 3.0 % | 0.69 | 0.88 | 0.86 |
| D lineart_fine | rich | 981 | 42 | 517 | 4.6 % | 0.75 | 0.94 | 0.78 |
| D lineart_coarse | sparse | 111 | 105 | 25 | 1.6 % | 0.49 | 0.68 | 0.88 |
| D lineart_coarse | medium | 319 | 69 | 126 | 2.7 % | 0.59 | 0.82 | 0.83 |
| D lineart_coarse | rich | 735 | 49 | 369 | 4.0 % | 0.67 | 0.90 | 0.78 |
| D pidinet | sparse | 45 | 215 | 3 | 1.5 % | 0.46 | 0.52 | 0.97 |
| D pidinet | medium | 102 | 145 | 20 | 2.0 % | 0.53 | 0.60 | 0.96 |
| D pidinet | rich | 174 | 104 | 58 | 2.3 % | 0.58 | 0.66 | 0.94 |
| D hed | sparse | 64 | 162 | 8 | 1.6 % | 0.51 | 0.56 | 0.97 |
| D hed | medium | 161 | 107 | 43 | 2.3 % | 0.60 | 0.67 | 0.96 |
| D hed | rich | 337 | 70 | 145 | 2.9 % | 0.66 | 0.73 | 0.92 |
| D teed | sparse | 118 | 122 | 21 | 2.0 % | 0.68 | 0.76 | 0.98 |
| D teed | medium | 343 | 74 | 108 | 3.5 % | 0.82 | 0.91 | 0.93 |
| D teed | rich | 768 | 49 | 361 | 4.7 % | 0.87 | 0.95 | 0.87 |
| D lineart_anime | sparse | 101 | 91 | 22 | 1.2 % | 0.38 | 0.56 | 0.79 |
| D lineart_anime | medium | 321 | 59 | 129 | 2.4 % | 0.59 | 0.84 | 0.79 |
| D lineart_anime | rich | 778 | 41 | 405 | 3.8 % | 0.67 | 0.93 | 0.75 |

Strong-edge recall (2 px) at medium, per picture:

| family | parrots | kodim04 | kodim23 | great-wave | lighthouse | barn | espresso | hibiscus | regatta | kodim03 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| A flowdog | 0.59 | 0.49 | 0.59 | 0.69 | 0.61 | 0.70 | 0.64 | 0.42 | 0.60 | 0.67 |
| B xdog | 0.31 | 0.18 | 0.31 | 0.40 | 0.24 | 0.22 | 0.21 | 0.12 | 0.32 | 0.19 |
| C boundaries | 0.69 | 0.81 | 0.69 | 0.53 | 0.76 | 0.78 | 0.78 | 0.82 | 0.82 | 0.84 |
| D lineart_fine | 0.66 | 0.69 | 0.69 | 0.67 | 0.52 | 0.73 | 0.87 | 0.63 | 0.66 | 0.80 |
| D lineart_coarse | 0.58 | 0.48 | 0.56 | 0.61 | 0.51 | 0.63 | 0.73 | 0.48 | 0.61 | 0.76 |
| D pidinet | 0.42 | 0.62 | 0.41 | 0.34 | 0.34 | 0.63 | 0.62 | 0.49 | 0.70 | 0.71 |
| D hed | 0.46 | 0.74 | 0.46 | 0.52 | 0.43 | 0.73 | 0.66 | 0.54 | 0.74 | 0.73 |
| D teed | 0.72 | 0.84 | 0.73 | 0.80 | 0.77 | 0.84 | 0.87 | 0.91 | 0.85 | 0.82 |
| D lineart_anime | 0.65 | 0.53 | 0.64 | 0.63 | 0.45 | 0.59 | 0.56 | 0.42 | 0.67 | 0.73 |

Strokes at medium, per picture:

| family | parrots | kodim04 | kodim23 | great-wave | lighthouse | barn | espresso | hibiscus | regatta | kodim03 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| A flowdog | 73 | 88 | 75 | 805 | 397 | 158 | 93 | 260 | 138 | 76 |
| B xdog | 173 | 241 | 176 | 865 | 261 | 250 | 89 | 325 | 152 | 109 |
| C boundaries | 147 | 160 | 120 | 444 | 425 | 264 | 102 | 305 | 172 | 107 |
| D lineart_fine | 169 | 299 | 170 | 953 | 836 | 436 | 106 | 539 | 264 | 174 |
| D lineart_coarse | 154 | 331 | 139 | 908 | 567 | 319 | 65 | 353 | 204 | 153 |
| D pidinet | 35 | 55 | 36 | 275 | 105 | 115 | 33 | 218 | 107 | 36 |
| D hed | 66 | 103 | 68 | 524 | 155 | 219 | 37 | 257 | 138 | 43 |
| D teed | 145 | 219 | 156 | 1113 | 497 | 399 | 138 | 372 | 258 | 136 |
| D lineart_anime | 162 | 191 | 168 | 999 | 483 | 196 | 149 | 465 | 182 | 211 |

How the measures are defined:

- **Strong edges** (`strong_edges.png` per picture): the Di Zenzo color gradient of OKLab
  (sigma 1.5), non-maximum suppressed. A pixel counts as strong where gradient x importance
  > 0.03 and it lies in a run of at least 10 px.
- **Recall:** the share of strong-edge pixels within 2 px (and within 4 px) of a wall pixel.
- **Edge precision:** the share of wall pixels within 2 px of a suppressed gradient maximum
  above 0.012.
- **Ink coverage:** the mean alpha of `ink.png`.

These measures are a filter, not a verdict: TEED's high recall includes shading lines, and
PiDiNet's low recall is mostly fine detail it leaves out on purpose.

### Learned models: license, size, CPU runtime

Inference times are for 1152 x 768 with 4 threads.

| model | weights (Hugging Face) | origin | license | params / file | inference time |
| --- | --- | --- | --- | --- | --- |
| lineart fine | lllyasviel/Annotators `sk_model.pth` | Informative Drawings (Chan, Durand, Isola, CVPR 2022), "style 1" | MIT. The file is byte-identical (sha256) to `model.pth` in the first author's own Space `carolineec/informativedrawings`, which declares MIT | 17 MB | 3.7-11 s |
| lineart coarse | `sk_model2.pth` | same paper, "style 2" (identical to the Space's `model2.pth`) | MIT (same evidence) | 17 MB | 3.4-8.6 s |
| lineart anime | `netG.pth` | Anime2Sketch (Xiang et al. 2021, github Mukosame/Anime2Sketch); byte-identical to `public-data/Anime2Sketch` | MIT according to the GitHub repo. I recall this from memory because github.com is blocked here: verify before shipping | 218 MB | 1.2-5 s |
| PiDiNet | `table5_pidinet.pth` | Su et al., ICCV 2021 (github hellozhuo/pidinet), trained on BSDS500 + PASCAL VOC | **Uncertain, probably research-only.** As I recall (GitHub is blocked), the LICENSE that ControlNet ships with it allows research use, and commercial use only with the authors' permission. Treat it as not shippable until checked | 3 MB | 5-19 s (slowest) |
| HED | `ControlNetHED.pth` | lllyasviel's re-implementation and retraining of HED (Xie & Tu 2015) | Apache-2.0. The controlnet_aux source header says "improved version and model of HED edge detection with Apache License, Version 2.0. Please use this implementation in your products" | 29 MB | 2.2-5.9 s |
| TEED | fal-ai/teed `5_model.pth` | Soria et al., ICCV-W 2023 (github xavysp/TEED), trained on BIPED | MIT according to the model card; the repo is MIT as far as I know. BIPED's own terms are unverified | 58 k params, 0.2 MB | 0.5-2.3 s |

Notes on the licenses:

- The Hugging Face card of `lllyasviel/Annotators` only says `license: other`. The provenance
  in the table is what identifies each file.
- controlnet_aux itself (the code) is Apache-2.0.
- YuNet, used by the importance proxy, is MIT.

Notes on runtime and memory:

- The ranges are wall-clock inference times on a shared 4-core machine. Another agent's batch
  ran alongside, which explains the spread.
- Loading a model adds about 3 s.
- Each model process peaks at 1.0-2.7 GB RSS (PiDiNet highest). The cost is the activations
  at full resolution, not the weights.
- Classic families: flow DoG 6-8 s (numpy), XDoG 0.2 s, boundaries 0.3-0.8 s.
- Per option, the cleanup takes 0.5-2 s and rendering the four ink variants 0.8-3 s. The
  driver peaks at about 0.45 GB.

### Determinism

- Seeds are fixed, with `torch.use_deterministic_algorithms(True)`, eval mode and a fixed
  thread count of 4. The cleanup is plain numpy, scipy and skimage with fixed iteration
  orders.
- I reran `run_lines.py` on parrots from scratch into a new directory, recomputing all nine
  raw maps in fresh processes. All 281 files came out **byte-identical** (PNGs,
  strokes.json, raw caches).
- The thread count matters:
  - HED and TEED at 1 thread differ from 4 threads by up to 4e-7, on about 30-45 % of the
    pixels. lineart fine was identical.
  - Downstream, a difference like this can flip a hysteresis decision at an exact tie. A
    product would fix the thread count, or quantize the raw map to 8 bits before the cleanup.
  - The same applies across CPUs, where oneDNN takes different SIMD paths.
  - On device (Core ML on the Neural Engine or GPU), bit-exact output is not to be expected
    at all, so the cleanup should stay stable when the map changes slightly.

### What a production version would need

- **A model in the TEED class:** 58 k parameters, about 0.2 MB, 0.5-2 s on this CPU at
  1152 px (a phone's Neural Engine would be far faster), MIT. HED is the conservative
  alternative (29 MB, Apache-2.0). PiDiNet's license needs checking first.
- **The shared cleanup, ported to Swift.** Most of the quality here comes from it: ridge NMS,
  clutter-aware thresholds, mesh suppression, contrast-aware fragment pruning and the face
  prior. Its hot loops are image filters and a graph walk.
- **A real importance map:** the app's Vision saliency and faces instead of the proxy.
- **A detail level chosen per picture:** sparse for faces, medium for prints. Auto could
  pick it the way it picks colors.

### Next round I would run

- Fuse two families: TEED or HED for the structure, plus boundaries (C) where the two agree.
  That should keep TEED's features and drop its shading lines.
- Run TEED at a coarser scale on faces (detect at 768 px, then upsample) to cut the skin
  creases.
- Try a color-aware flow DoG (the ETF from an OKLab structure tensor, DoG on L plus chroma)
  to recover the contours between colors of equal lightness.
- Run the final library pictures (a Vermeer or Mucha face, an impressionist canvas,
  Earthrise) once the orchestrator adds them: `run_lines.py <pic-dir> --out ...` works on
  them as is.
