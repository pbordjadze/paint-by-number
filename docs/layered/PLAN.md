# Layered lines + Advanced settings (wave 3)

Status: in progress on `claude/layered-lines` (integration branch, cut from
`claude/paint-by-numbers-app` at 8416129). Read `CLAUDE.md`, then `docs/wave2/RULES.md` (binding
here too, with the branch rules below in place of its "Do not push"), then this file.

## What the owner asked for

> Let's implement a new version of the app with this stuff [layered lines]. Let's also add an
> advanced settings section so my very few users can tweak things too — let them really have
> access to the sliders and stuff, toggle things on and off, make it deeply customizable in-app
> under advanced settings so that I can get you some real feedback. And show live previews as
> they tweak them — make it easy to understand what they're tweaking and its ramifications.
> Make the UX of tweaking settings feel first class.

The research behind it: `research/lineart/results_layers.md` on `claude/lineart-research`
(the model, the variants, the numbers) and its scripts (`research/lineart/*.py`). The owner's
answers on the report (the defaults of this wave):

| Question | Answer |
| --- | --- |
| Line style | fade by opacity, **even weight** ("can't tell a huge difference") |
| Texture layer | **HED only** (no TEED) |
| Closing outlines (silhouette + pbn boundaries) | **not for now** |
| Faint color cells | **keep** ("we want more colors!") |
| Same paint split by a line | **join across texture (and color) lines only**; detail and outline lines split |
| Outlines | **too thick / too strong** on the arch, turtle, freight train: lighter and thinner |
| Eyes | "eyes NEED to be detailed and NEED to be outlined" |
| Finished gradient | not loved on the Cézanne: not in this wave |
| Per picture | layered preferred on the freight train, Milkmaid, Wheat Field, lupine; today's on the arch, turtle, fox |

So layered lines are an **option next to Classic**, not a replacement: Classic stays the default
line style, and Settings › Advanced turns Layered on (and tunes everything).

## Architecture

```
photo ──► Segmenter ──► Segmentation ─┐
  │                                    ├─► LineArt (PaintCore, new) ─► Segmentation' + line data ─► Vectorizer ─► Template (+ lineArt)
  └─► HED (Core ML, app) ─► EdgeMap ───┘        ▲
      Vision face landmarks ─► eyes ────────────┘
```

- **PaintCore stays portable and deterministic.** The learned model runs in the app (Core ML)
  or offline (`pbn generate --edges map.pgm`); PaintCore takes an 8-bit `EdgeMap` and does the
  rest: strokes, layers, the region split, same-paint joins, small-cell rules, line data. Same
  edge map + settings → byte-identical template on every device.
- **Every line bounds a cell** except texture lines between same-paint cells (the owner's join
  choice), which are kept as `InteriorStroke`s drawn inside the joined cell.
- **Generation vs drawing.** `LineArtSettings` and `PipelineTuning` (PaintCore, inside
  `GenerationSettings`) change templates; `LineAppearance` (app) only changes how layered lines
  are drawn per zoom, so it previews instantly and applies to every layered painting.

## Contracts (on the integration branch; extend, don't break)

- `Sources/PaintCore/Model/LineArtSettings.swift`: `LineArtSettings` (style, thresholds,
  stroke length, gap bridging, smoothing, `SamePaint`, keepColorEdges, outlineEyes) and
  `PipelineTuning` (six multipliers, 1 = untuned). Both tolerant-decoding.
- `GenerationSettings.lineArt`, `.tuning` (tolerant: old `meta.json` files decode).
- `Sources/PaintCore/LineArt/EdgeMap.swift`: `EdgeMap` (UInt8, any size), `LineArtInput`
  (edges + eyes as closed polygons normalized to the photo).
- `Template.lineArt: TemplateLineArt?` with `LineLayer` (outline, detail, texture, color),
  per-edge layers and weights, and `InteriorStroke`s. Not yet encoded: the core workstream adds
  the `LINE` extension chunk.
- `TemplateGenerator.generate(from:importance:lineArt:cancel:progress:)`.
- `App/PaintByNumber/App/LineAppearance.swift`: per-layer opacity and width at 1×/2×/4×,
  `weighted`, defaults from the owner's picks.
- `Preferences.lineArt`, `.tuning`, `.lineAppearance` (JSON in UserDefaults under
  `SettingsKey.lineArt`, `.pipelineTuning`, `.lineAppearance`; `Preferences.store(_:forKey:)`).
- The app-side detector API, owned by the model workstream (others code against this):
  `nonisolated enum EdgeDetector { static func edgeMap(for image: CGImage, maxLongSide: Int = 1152) throws -> EdgeMap }`
  and `nonisolated enum EyeFinder { static func eyes(in image: CGImage) -> [[SIMD2<Float>]] }`,
  plus `nonisolated enum LineArtInputs { static func make(for image: CGImage, settings: LineArtSettings) async throws -> LineArtInput? }`
  (nil for classic settings; cached per image identity).

## Workstreams

Each runs in its own worktree on its own branch cut from the integration branch's contract
commit. App workstreams push their branch to run CI (`git push -u origin <branch>`, then
`CI_BRANCH=<branch> ci/fetch.sh <sha> <dir>`); iterate on the iPad job alone and put `[iphone]`
in the subject only for the final round (five macOS jobs run at once across all branches).
Never push any other branch. The orchestrator merges in the order core → model → render → ui
and resolves conflicts in shared files (`CLAUDE.md`, `Localizable.xcstrings`,
`ci/scenarios.txt`: keep your edits there minimal and append-only).

### core — `claude/layered-core` (PaintCore, `pbn`, `tools/`)
1. `Sources/PaintCore/LineArt/`: the layered pipeline, ported from the research scripts to
   Swift with this wave's defaults (HED only: layers by strength thresholds; no closure; keep
   color edges, or merge close colors when `keepColorEdges` is off; joins per `SamePaint`,
   default `joinTexture`; eyes from `LineArtInput.eyes` as outline contours and irises).
   Stages: resample the edge map to the working size → thin + hysteresis → trace → prune
   (`minimumStrokeLength`) → bridge gaps (`gapBridging`) → smooth (`lineSmoothing`) → strength →
   layer → walls → split the segmentation (cells keep their paint) → small-cell rules (no cell
   below `LabelSizing`'s room; merge into same paint across the weakest line first) →
   same-paint joins → `Vectorizer` → per-edge layer and weight → interior strokes →
   `Template.lineArt`. Layered settings without an edge map give the classic template.
2. Template coding: the optional `LINE` chunk (old readers draw every edge alike), hostile-input
   checks, `validate()` coverage, tests (round trip, truncation, corruption, crafted references),
   a committed fixture with the chunk and its decode test.
3. `PipelineTuning`'s effect on the derived segmentation knobs, exactly neutral at 1:
   `tools/regression.py` passes with no baseline change.
4. SVG export of layered templates (a group per layer).
5. `pbn generate --line-style layered --edges <pgm> [--eyes <json>] [--line-art key=value …]
   [--tuning key=value …]`; `stats.json` gains a `lineArt` section; `pbn check` validates line
   data; `eval.py` passes the flags through.
6. Edge maps for evaluation come from the research's HED (`$S/lineart/out/<pic>/_cache/learned_hed.npy`
   and `research/lineart/lines_learned.py`); compare against the research's renders and tune the
   `LineArtSettings` defaults (update them in the contract file) toward the owner's picks.
   Commit small edge-map fixtures for tests, not the big maps.
7. Determinism (byte-identical runs) and speed (report layered-stage timings at ~1150 px).
8. `CLAUDE.md` (PaintCore layout, pbn, regression).

### model — `claude/layered-model` (Core ML HED, eyes, generation wiring)
1. Convert ControlNet's HED (`lllyasviel/Annotators` `ControlNetHED.pth`; Apache-2.0 per
   controlnet_aux) to `App/PaintByNumber/Resources/Models/HED.mlpackage` with coremltools on
   Linux (fp16, flexible input up to 1152 px long side), reproducibly (`tools/models/convert_hed.py`,
   source weights' sha256). Aim for ≤ 16 MB.
2. `EdgeDetector`, `EyeFinder`, `LineArtInputs` (API above): `.cpuOnly` compute units and
   8-bit output so maps are the same on every device; cancellable, off the main actor.
3. Wiring: new paintings get `Preferences.lineArt` and `.tuning` on top of the Suggested or
   slider settings (make sure Auto's candidates carry them); layered settings compute the
   inputs once per photo and pass them to the generator (create flow, regeneration from the
   stored photo or bundled sample, opened files). Classic paths unchanged.
4. Tests on the simulator: the model against a PyTorch-made fixture map (tolerance), two runs
   identical, eyes on a face fixture, settings carried into the artwork's `meta.json`.
5. Acknowledgements (HED, Xie & Tu 2015; the ControlNet weights, Apache-2.0) in both places
   (`AboutTests`). `CLAUDE.md`.

### render — `claude/layered-render` (canvas, rasterizer, exports)
1. `CanvasScene`: per-edge layer and weight from `Template.lineArt`, interior strokes as extra
   segments; classic templates render exactly as before.
2. Shaders and uniforms: per-layer opacity and width for the current zoom (1 = fitted) from
   `LineAppearance` (a `CanvasView.lineAppearance` property fed from Preferences, updating open
   canvases live), `weighted` honored. Painted and selected regions behave sensibly with layers.
3. `TemplateRasterizer` (thumbnails, share PNG, PDF), `CanvasSnapshot`, time-lapse: layered at 1×
   for images; PDF prints every layer at print weights.
4. Demo scenarios (`paint-layered`, `paint-layered-zoomed`, …) with a layered template (a
   synthetic one, or one generated from a committed edge map) and their screenshots; tests.
5. `CLAUDE.md`.

### ui — `claude/layered-ui` (Settings › Advanced)
A first-class tweaking experience:
- Settings gets **Advanced** (marked Experimental) → a screen with a **live preview pinned on
  top** (beside the controls on wide iPad): a picture (the library's pictures to choose from,
  or the painter's most recent photo) generated with the current settings. Settings that change
  templates regenerate a draft (debounced, cancellable, keeping the last result until the new
  one is ready, with a quiet progress cue); appearance settings update instantly. Zoom (1×, 2×,
  4×, pinch) to see layers fade in, Template / Painted, and live stats chips: cells, colors,
  estimated painting time, each with its change from the defaults.
- Sections: **Line Art** (Classic / Layered with visual swatches; Layered's thresholds as a
  sensitivity group with a live count per layer, minimum line length, gap closing, smoothing,
  same paint, keep color edges, outline eyes); **Line Appearance** (per layer opacity and width
  at 1×/2×/4× in a compact editor, even/weighted, quick presets Fade / Grow / Even);
  **Pipeline** (`PipelineTuning` as log-scale sliders 0.25×–4× with plain explanations);
  **Feedback** (reset a section or all, copy the settings as text, share them with a note).
- Every control: title, value, one line on what it does, and a live line on its ramification
  ("+212 cells · about 8 minutes longer").
- Applies to new paintings (said on screen).
- Strings in the catalog, VoiceOver values, Dynamic Type, Reduce Motion, dark mode, demo
  scenarios (`settings-advanced`, `settings-advanced-layered`, `-long-text`, dark), UI tests.
- Depends on core (generation), model (inputs) and render (drawing): build against the
  contracts and the documented detector API; the orchestrator merges the others first.

## Done means

Linux tests, regression (unchanged baselines) and strings check pass; iPad and iPhone CI green;
screenshots of every new scenario reviewed; `CLAUDE.md` updated; each workstream's report in
`docs/layered/log/<workstream>.md`. Then the orchestrator merges into
`claude/paint-by-numbers-app` and `main` and the build ships to SideStore.
