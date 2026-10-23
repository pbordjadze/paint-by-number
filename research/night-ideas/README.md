# Night ideas (October 23, 2026)

Off-device prototypes from the "Overnight creative ideas" session, argued with the "Creative project
oversight" session. Not app code, not merged. The page Paul decides from is
the "Ideas by Moonlight" artifact.

Inputs are `pbn generate` output dirs: the corpus photos as coloring books from the committed maps
(`--line-style coloringBook --edges <name>-contours.pgm --lines <name>-drawing.pgm --colors 24
--detail 0.5`, the maps converted from `tools/baseline/lines/` as `tools/regression.py` does).
Python 3 with numpy, scipy, Pillow; `cairosvg` for the light renders.

- Hold it to the light: `impasto.py` (height field: paint domed from each area's edge, optional
  brush marks along the photo's structure tensor by line integral convolution; lighting),
  `stills.py <dir> <out> x,y` (one crop at four strengths), `clip2.py <dir> <out> [frames] [x,y]
  [brush]` (a tilt sweep from the template's own SVG), `stills2.py` and `clip_rmap.py` (the same,
  with the relief built from the region map, as PaintCore would: smoother, no serration along
  straight edges; these made the page's pictures).
- Mixing recipes: `km.py` (Kubelka–Munk: Wyman, Sloan & Shirley 2013 CMF fit, Burns' smoothest
  reflectance, KM mixing; nine estimated tubes, uncalibrated), `make_recipes.py <book dir> <out.json>`.
  Untested against real paint: the gate is on the page.
- `first-paint.py <dirs>`: how much canvas paint 1 covers (handed to the first-five-minutes session).
