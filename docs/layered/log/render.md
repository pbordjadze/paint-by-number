# Render workstream: layered lines on the canvas, in pictures and in print

Branch `claude/layered-render` (cut from the contract commit 0ccb8df; core merged twice, last at
fb4f96b). Head: the commit that adds this report, CI'd on iPad and iPhone (`[iphone]`); its SHA
and run link are in the report message to the orchestrator. Earlier rounds:
[round 1](https://github.com/pbordjadze/paint-by-number/actions/runs/37066690123) (three
compile errors), [round 2](https://github.com/pbordjadze/paint-by-number/actions/runs/37069069888)
(iPad green, 304 tests passed, 0 failed; Linux core tests, regression and strings green).

## What I built

- **`Canvas/LineStyle.swift`** (new):
  - `LineStyle`: per-layer opacity and width as factors of a renderer's classic line.
    `.classic` sets every factor to 1, `.print` is for PDFs, and `init(_:zoom:classicStrength:)`
    turns a `LineAppearance` at a zoom into a style. `classicStrength(depth:)` and
    `classicWidthPoints(depth:)` are the canvas's existing zoom ramps (0.7→1 of full ink,
    0.5→1 pt), moved here unchanged so classic frames compute the same values.
  - `DrawableLineArt` checks `Template.lineArt` against the template. When the counts don't
    match the edges, the template draws as classic. Malformed strokes (short spans, spans out of
    range, bad region or layer) are dropped, and layers are clamped. It also gives each line a
    weight factor: its strength over its layer's mean, within 0.6–1.4.
  - `OutlineGeometry`: one "line" per boundary edge, then one per interior stroke (its cell on
    both sides), each with (layer, weight), plus the segments. Classic templates get exactly
    the segments and regions they always had, every line in layer 0 at weight 1.
  - `LineAppearance.stored(in:)` and `decoded(_:)` read Settings › Advanced off the main actor.
    `SettingsKey.lineAppearance` became `nonisolated` for this.
- **Canvas**:
  - `CanvasScene` uploads `OutlineGeometry` (`lineRegions`, `lineStyles`, `isLayered`).
  - The outline vertex shader reads the new `CanvasUniforms.lineAlpha/lineWidth/lineMode`.
    These are three float4s after `photo`, matched in `Shaders.metal`, stride 256 → 304.
  - `setLines(_:)` derives the uniforms from `ink.w` and `outline.x`.
  - `CanvasView.lineAppearance` redraws on change. `PaintCanvas.lineAppearance` feeds it, and
    `PaintView` reads `@AppStorage(SettingsKey.lineAppearance)`, so an open canvas follows
    Advanced at once.
- **Pictures**:
  - `CanvasSnapshot.Options.lineAppearance` (nil means the stored one) and `lineZoom`
    (default 1, the 1× look). The time-lapse reads the stored appearance once per export.
  - `TemplateRasterizer.Style.lines`: `.screen(appearance?, zoom:)` (default nil at 1×) or
    `.print`, which `.printable` uses, so PDFs and their overview pages get it.
  - Layered drawing paths go faintest first, one path per layer (and per tenth of width when
    weighted), relative to each style's own line. Interior strokes follow
    `hidesOutlinesBetweenPainted`.
- **Demos**:
  - Scenarios `paint-layered`, `-progress`, `-zoom2`, `-zoomed` and `-dark-paper`, appended to
    `ci/scenarios.txt`.
  - They generate the freight train through core's real layered pipeline.
    `SyntheticTemplate.edgeMap` (DEBUG; the photo's OKLab gradient after a 1.2 px blur,
    normalized at its 99th percentile, power 0.8) stands in for the HED model, which hasn't
    landed. Core's committed fixture is ~110 px and lives in the PaintCore test bundle, so it is
    no use to the app.
  - The `-mosaic` variants use `SyntheticTemplate.layered`, which layers edges by paint
    contrast and adds strokes under labels.
- **`CLAUDE.md`**: one "Layered lines (drawing)" bullet after Paper.

## Decisions

1. **Units.**
   - `LineAppearance` opacities are fractions of the paper's full ink. Full ink is the darkest a
     classic line gets: zoomed in, 0.62 on light paper and 0.5 on dark paper. Widths are
     factors of the classic width at that zoom, as the contract says.
   - The canvas's classic line is 0.7 of full ink when fitted, so its factor is
     opacity / classicStrength.
   - Pictures draw their classic line at their style's full ink, so their factor is the opacity
     itself. A layered line then looks the same against its classic sibling in every renderer.
2. **Painted.**
   - A line between two painted cells dissolves whatever its layer, so finished areas read as
     paint, as in classic.
   - A stroke dissolves with its cell.
   - A line with one unpainted side keeps its layer's look.
3. **Selected.**
   - The selected color's unpainted cells keep at least the classic selected outline (classic
     ink × 1.3, classic selected width), whatever the layer of their boundary. A cell bounded
     only by faint color lines would otherwise be invisible at 1×, where the painter is choosing
     what to paint.
   - Strokes inside a selected cell keep their layer's look. In the shader, a line with the same
     region on both sides is drawing, not a boundary, so the cell still reads as one cell.
4. **Weighted** (off by default, as the owner chose "even weight"). Strength over the layer's
   mean, within 0.6–1.4, so it works whatever range of strengths each layer has. Core's weights
   are mean strength for drawn edges and paint difference for color edges.
5. **Pictures.**
   - Images use the stored appearance at the 1× look.
   - A thumbnail keeps the appearance it was drawn with until the next save redraws it.
   - PDFs ignore the appearance and use fixed print weights (`LineStyle.print`), because paper
     can't zoom and every line bounds a cell that has to be painted.
     - Opacity: outline 1, detail 0.85, texture 0.7, color 0.55 of the printable gray.
     - Width: 1.5, 1.15, 0.9 and 0.8 × 0.4 pt.
6. **`LineAppearance.default` retuned.**
   - New values: outline 1/1/1 at width 1.3/1.3/1.35; detail 0.5/0.8/0.9 (0.95/1/1.05); texture
     0.25/0.55/0.8 (0.8/0.85/0.95); color 0.15/0.35/0.55 (0.75/0.8/0.9).
   - Why: I rendered real layered templates of the freight train (pbn with the research's HED
     map) at iPad resolution. With the contract values, the outlines came out about as heavy as
     a classic line at 1×, so the drawing didn't read.
   - The new outlines are still far lighter and thinner than the research's: solid ink, about
     2.8× a classic line's width.
   - They are close to how core's tuning sheets drew outlines: SVG ink at 0.85 opacity.
7. **Classic is untouched.**
   - `.classic` multiplies by exactly 1.
   - The shader's selected and width terms reduce to the old expressions in the same order.
   - The CG classic path is the old one: a shared polyline helper was factored out, behaviour
     unchanged.
   - Tests prove pixel equality, below.

## Screenshots and pictures I looked at (round 2, iPad)

- `ipad-paint-layered`:
  - The gantry and locomotive outlines read as a drawing: thin, mid-gray, not heavy. Sky band
    boundaries (color layer) are barely there, and detail and texture are faint around the
    column.
  - The selected color 1 cells are hatched with crisp outlines.
  - Numbers are as in classic.
- `-zoom2` / `-zoomed` (4×): the sky bands and texture lines come in. At 4× every layer is
  clearly drawn, outlines still the strongest. Painted cells have no lines between them, and
  the selected cell is outlined.
- `-progress`: painted sky bands dissolve their lines, and unpainted cells keep their layered
  lines.
- `-dark-paper`: light lines on dark paper, the same hierarchy.
- Test attachments:
  - `layered-parrots-canvas-z1/2/4` (share-picture renders): the fade by zoom.
  - `layered-parrots-thumbnail`: whisper-faint lines, as classic thumbnails.
  - `layered-parrots-template` (create-flow preview).
  - `layered-parrots-pdf-page1`: every layer prints. Outlines are dark and heavier, color and
    texture lines light gray but plainly visible.
  - `layered-mosaic-z1/z4` and `layered-selected`: the controlled checks.

## Tests

`App/PaintByNumberTests/LayeredLinesTests.swift`, 16 tests, all passed in round 2:

- **Interpolation**: keys, log-zoom midpoints, holding beyond 1× and 4×.
- **Styles**:
  - relative to the canvas ramp and to pictures;
  - `.classic`, neutral and `.print`;
  - the default's per-layer order and fade-in.
- **Stored appearance**: round trip and fallbacks.
- **Weights.**
- **Geometry**: classic is the old segments exactly; layered appends strokes as same-region
  lines; malformed line art is skipped or falls back to classic.
- **Uniforms**: classic gives every layer `ink.w` / `outline.x` exactly; layered snapshot
  uniforms.
- **Classic unchanged**:
  - Metal: a layered template at a neutral appearance (selection and painting included) renders
    0 differing pixels from the classic one;
  - CoreGraphics: identical PNG bytes for thumbnail, template and finished styles.
- **Metal pixels**:
  - layers fade by opacity at 1× and come in at 4×;
  - strokes ink inside their cell and dissolve with it;
  - selected cells are outlined boldly over faint layers.
- **Live canvas**: `CanvasView.lineAppearance` reaches the next frame; zoom 4 uses the 4×
  values; classic ignores it.
- **CoreGraphics pictures**: the outline/color/stroke hierarchy, strokes hidden when painted,
  print showing every layer.
- **Review pictures**: from the real layered pipeline.

The existing stride test is updated to 304. Round 2 overall: 304 passed, 1 skipped, 0 failed.
Linux core tests passed, regression passed (24 cases), and strings_check is ok (351 entries).

## Shared files touched (minimal)

- `App/Preferences.swift`: `nonisolated` on the `lineAppearance` key.
- `App/LineAppearance.swift`: doc comment (opacity units) and the default values.
- `tools/strings_check.py`: allow-listed the contract's `"three zooms"` decoding diagnostic,
  which failed the checker on the contract commit.
- `ci/scenarios.txt`: appended.
- `CLAUDE.md`: one bullet.
- `PaintView` / `PaintCanvas`: one property each.

## Unresolved, for the orchestrator

- `SVGExport.defaultLayerStyles` (core) still holds the contract's values, and its doc says
  "the app's default line appearance". They are absolute opacities of solid ink, which is not
  the app's unit, and no longer the app's defaults. Pbn and eval output only. I left PaintCore
  alone.
- The demos use the stand-in edge map. Once the model workstream lands, switching
  `PaintDemoView.layeredTemplate` to `LineArtInputs.make(for:settings:)` is a few lines.
- For the ui workstream's live preview:
  - `PaintCanvas(…, lineAppearance:)` with a throwaway `PaintingSession` gives pinch zoom and
    live appearance;
  - for stills, `CanvasSnapshot.Options.lineAppearance/lineZoom` or `TemplateRasterizer.Style.lines
    = .screen(appearance, zoom:)`. Those change the look, not the framing.
- Merge commit 9c7f046 (the first core merge) went in with git's default message, without the
  attribution lines. Per the rules it was not amended.
