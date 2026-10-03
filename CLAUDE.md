# Paint by Numbers — engineering notes

Native iOS/iPadOS 26 app that turns photos into paint-by-numbers templates on-device and
makes painting them fluid and satisfying. Swift 6, SwiftUI (Liquid Glass) shell, Metal canvas.

## Layout

- `Package.swift`, `Sources/PaintCore` — portable, dependency-free template pipeline
  (builds on Linux too). `Sources/pbn` — headless CLI. `Tests/PaintCoreTests` — Swift Testing
  (`Fixtures/` holds files written by past encoders, e.g. `template-v1.pbnt`).
  - `Foundation/` grids, color science (OKLab, Display P3), EDT, connected components, resampling,
    color naming (`ColorName`: OKLab → structured name, e.g. "dark grayish green"; `english` for the CLI),
    `ColorNickname` (playful names like "Harbor Fog": the hex-anchored table in
    `ColorNicknameVocabulary.swift`, whose doc comment is the style guide `ColorNicknameTests` lints;
    `assign(_:seed:)` picks one per paint, unique in the palette and varied by seed)
  - `Model/` `Template` (the product of the pipeline) + versioned binary coding, `GenerationSettings`,
    `Segmentation`, `RegionRemap` (carries painted regions onto a regenerated region map),
    `LineArtSettings` (classic or layered lines and their knobs; defaults and why on its init) and
    `PipelineTuning` (Settings › Advanced factors on `SegmentationParameters`' knobs, applied in its
    init: a factor of exactly 1 leaves every knob bit for bit, so classic output never moves)
  - `LineArt/` layered line art (`LayeredLines.apply`; stages in its doc comment): an 8-bit
    `EdgeMap` (the app's HED, or `pbn --edges`) and eye polygons → ridges, hysteresis and thinning
    (`LineDetection`), traced and cleaned strokes (`StrokeGraph`), a `LineLayer` per point by
    hysteresis along the stroke, the outline threshold rising toward 1 where lines crowd except on
    long contours (`LineLayering`), the segmentation split along the lines (`CellMap`: cells keep
    their paint and hold their number; small ones merge, same-paint ones join per `SamePaint`),
    then after the vectorizer each edge's layer and weight and the lines inside cells
    (`InteriorStroke`s) as `Template.lineArt`. Layered settings without an edge map generate the
    classic template; same edge map and settings give the same bytes on any core count.
  - `Segmentation/` photo → region label map + palette (`Segmenter.segment`; pipeline overview in
    its doc comment, all tunables in `SegmentationParameters`)
  - `Vector/` label map → shared smoothed boundaries, fill mesh, labels (`Vectorizer.vectorize`)
  - `Export/` SVG (layered templates draw a group per `LineLayer`, faintest first; and later PDF helpers)
  - `Auto/` Suggested settings: `AutoSettings.analyze` (photo → `PhotoAnalysis` features at the
    draft size), `candidates` (a named rule: a center from the palette curve's knee and the
    features, plus neighbours in colors × detail), `score` (importance-weighted ΔE, p95, rings,
    crumbs, a price per paint and the distance of `PaintingTime.estimate` from the
    `PaintingLength`'s time band) and `choose` (runs the candidates on the draft in parallel,
    cancellable, calls `firstDraft` with the center, returns an `AutoDecision`). Every constant
    carries what it was tuned on (`docs/wave2/log/auto-tuning.md`). Features are quantized (3
    decimals; palette curve and noise 4) before the rule reads them, so a decision is reproducible
    from the same pixels, importance, hints and length on every device; decisions are never stored.
    The rule's thresholds are ramps and the knee a power-law fit, and the center wins any score
    within `tieMargin` (0.006, measured JPEG re-encode noise) unless it runs over its band, so a
    re-saved photo rarely gets materially different settings (16 of 99 decisions). Bands: Quick
    8–25 min, Relaxed 20–50, Detailed 40–120 at 3 s per area; a draft's region count is scaled to
    the full canvas by area^(−0.18 + 0.42 × detail + 0.77 × mean importance), and the detail
    center rises one unit per unit of mean importance below 0.6, so Vision maps (which protect
    less of the frame than pbn's fallback) still reach the band.
  - `TemplateGenerator.swift` entry point composing the stages, with `StageClock` timings
    (`generate(from:importance:lineArt:…)`; `Output.lineArtStats` for layered templates)
- `App/` Xcode project (`PaintByNumber.xcodeproj`, synchronized folders — adding files needs no
  project edits) with the SwiftUI app, Metal renderer and UI tests.
- `tools/` evaluation tooling (`swift.sh`, `eval.py`, `compare.py`, `regression.py` + its
  committed `baseline/regression.json` and `baseline/auto.json`, `auto_sheet.py`, `svg2png.mjs`),
  `strings_check.py` (string catalog drift check, see Localization) and `models/convert_hed.py`
  (the app's HED Core ML model from its source weights, see Layered line art inputs).
- `.github/workflows/` CI: Linux PaintCore tests + quality regression; macOS builds the app, runs
  tests, captures simulator screenshots.
- `ACKNOWLEDGEMENTS.md` credits and license texts for the ported code, bundled models and published methods (also shown in the app).

## Building & testing on Linux (no Xcode here)

- `tools/swift.sh build -c release --static-swift-stdlib` — builds `pbn` in the `swift:6.2-noble`
  Docker image; the static binary at `.build/release/pbn` then runs directly on the host.
- `tools/swift.sh test` — runs the package tests in Docker.
- `python3 tools/eval.py run <images...> --out <dir> [-- --colors 24 --detail 0.5]` — runs the
  pipeline and writes contact sheets (`<dir>/<name>/sheet.png`: source | painted | template),
  `overview.png` and `summary.json` with metrics (region count, mean ΔE, tiny regions, label
  legibility — `labelsBelowLegibleSize` and `labelRoomUnmet` must be 0, `minLabelRadius`,
  `minLabelRoom`, `valid` — `bandRings` (`BandRings.count`: regions bounded mostly by weak,
  ramp-like boundaries, the rings a gradient is posterized into), timings, palette, `colorNames`
  and `colorNicknames`; the sheet's palette panel labels each swatch with its nickname and name).
  The metrics are `pbn generate`'s `stats.json`, a stable interface for regression tooling: add
  fields, never rename them. Look at the PNGs with the Read tool. The sheet's second row shows the
  raw region raster, a 2× `boundaries.png` (1-px region outlines, best for judging segmentation
  shapes) and the palette; `--importance-dir DIR` passes `DIR/<name>.pgm` as the importance map
  (Vision stand-in); `--edges-dir DIR [--eyes-dir DIR]` passes `DIR/<name>.pgm` as the edge map
  (and `<name>.json` as eyes) and generates layered templates (the caption adds cells against the
  classic regions and edges per layer).
- Test photos: the Kodak suite (`kodim01..24.png`, 768×512) and scikit-image samples are a good
  corpus (download Kodak from raw.githubusercontent.com/MohamedBakrAli/Kodak-Lossless-True-Color-Image-Suite).
- `pbn trace <flat.ppm> <outdir>` vectorizes a flat-color image directly (one palette entry per
  distinct color) — ideal for judging curve quality on synthetic shapes. `pbn check <t.pbnt>`
  prints the file's format and pipeline versions and runs `Template.validate()` (planarity, ring
  orientation, mesh coverage/watertightness, labels, and every label's room for its number:
  `--min-label-radius R`, default `LabelSizing.minimumRadius`, `0` skips it; layered line data
  too, with its edges per layer and interior strokes counted). `pbn bench
  <ppm...>` times the pipeline, including a preview, detail 1 on a large photo, 150 colors
  at detail 1 and Auto's suggestion (`--edges map.pgm`: also layered line art, stage by stage).
- Layered line art: `pbn generate <in.ppm> <out> --line-style layered --edges map.pgm [--eyes
  eyes.json] [--line-art key=value]… [--tuning key=value]…` (eyes: closed polygons of `[x, y]`
  normalized to the photo; keys are the `LineArtSettings` / `PipelineTuning` field names);
  `stats.json` gains `lineArt` (settings, `LineArtStats`, edges and length per layer, interior
  strokes, `cellsVsClassic`) and `tuning` when not default. Edge maps for evaluation come from the
  research's HED (`research/lineart/lines_learned.py` on `claude/lineart-research`) quantized to
  8-bit PGM; the app runs the same model at ≤ 1152 px, so evaluate with maps at that size. The
  regression gate covers classic output only; `LineArtTests` and the `template-v2-lines.pbnt`
  fixture cover layered generation and coding.
- Suggested settings: `pbn suggest <image> [--importance m.pgm] [--hints h.json] [--length
  quick|relaxed|detailed] [--candidates 5] [--out dir]` prints the candidate table (every score
  term, the winner starred) and writes `decision.json`; with `--out` also every candidate's
  preview for `tools/auto_sheet.py <dir>` (one sheet per photo, winner framed). `pbn generate
  --auto [--length …] [--hints …]` generates at the suggestion (`stats.json` gains `auto` and
  `analysis`; `eval.py run … -- --auto` captions the chosen settings). pbn has no Vision: without
  `--importance` it uses the pipeline's fallback map, which rates busy texture important, so at
  like settings its region counts run above the app's (CI's simulator gave the lighthouse and
  parrots samples a third to a half of pbn's areas); Auto reads the map's mean importance, so its
  suggestions follow (Vision stand-in maps for tuning: `docs/wave2/log/auto-tuning.md`).
- Vector geometry conventions (orientation, junctions, closed edges, coordinate quantum) are
  documented on `BoundaryEdge`, `Ring` and `FillMesh` in `Model/Template.swift`.
- `tools/regression.py [--sheets DIR] [--json FILE]` — the quality gate CI runs on every push:
  the six retired samples, pinned by name (`SAMPLE_NAMES`; CI's `pbn bench` step lists the same
  files), never the picture library beside them, whose curation must move neither the baselines
  nor CI's time; in three regimes (24 colors/detail 0.5, 150/1.0, 12/0.0), each
  generated twice, plus the `auto` regime (`pbn generate --auto`, Relaxed): its hard invariant is
  that the choice lies inside the length's bands; the chosen settings and metrics are compared
  with `tools/baseline/auto.json` for information only (choices move when the pipeline moves). Hard invariants: `pbn check` valid, byte-identical runs, no region under
  radius 2, palette distance ≥ the floor pbn reports (`GenerationSettings.minPaletteDistance`),
  and `labelsBelowLegibleSize == 0` once pbn's stats report that field. Bands versus
  `tools/baseline/regression.json`: mean ΔE ≤ baseline × 1.05, regions ±15 %, template bytes
  ±20 %; timings and `bandRings` are informational (±1 noise on the decoded input moves the
  ring count by up to half). Prints a table with deltas, exits 1 on any failure;
  `--self-test` checks the rules themselves. Needs the release `pbn` and Pillow (no node: its
  sheets are source | painted raster | region outlines + palette).
- **Whenever a change alters pipeline output, run `tools/regression.py --update` (it only writes
  a baseline that satisfies the hard invariants), look at the `--sheets`, and commit
  `tools/baseline/regression.json` and `tools/baseline/auto.json` together with the change**: CI fails once a metric leaves
  its band, and a fresh baseline keeps the table's deltas meaningful. The `template
  same/changed` column is informational: it only means something where the templates come
  from an identical build and input decode (CI's pbn and Pillow differ from the host's). Use
  `eval.py`/`compare.py` for deeper before/after looks (vector previews with numbers).

## iOS app (App/)

- Deployment target iOS 26.0, iPhone + iPad. Build with Xcode 26.6 (CI). Swift 6 with
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and approachable concurrency: app types are
  MainActor by default; mark pure/background helpers `nonisolated` and CPU-heavy async work
  `@concurrent`. PaintCore is a separate module (nonisolated).
- `MemberImportVisibility` is enabled: every file that touches members of a type from another
  module must import that module itself (`import PaintCore`, `import simd`, …).
- Closures handed to system APIs that call back on arbitrary threads (AVFoundation, Core Haptics,
  Metal completion handlers, NotificationCenter with a queue) must not be MainActor-isolated —
  form them in `nonisolated` code or they trap at runtime under Swift 6.
- Liquid Glass design language (`.glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)`,
  `.glassProminent`), SF Symbols, Dynamic Type, dark mode, VoiceOver labels.
- Identity: the app is called **Paint by Moonlight** (display name, gallery title, permission texts,
  PDF footer; App Store subtitle "Turn any photo into a painting"). Pipo is only the working name:
  it never appears in the product; the target, module and repository keep the PaintByNumber names.
  Styled by its design system (claude.ai/artifact/HRz1Lc9bkLACNvPKhctojF: README, tokens, icon,
  motifs). Native first: system
  controls stay system controls. `Theme` and the asset catalog carry its tokens: Paper =
  `surface-base` (`#F2F1F4` / `#141117`), Surface = `surface-elevated`, Outline, AccentColor = `tint`
  (Nightshade `#7B3F7E` by day, antique gold `#C9A24A` at night), `signature` (Nightshade in both,
  under the labels of `.glassProminent` buttons and tinted glass badges: give every new prominent
  button `.tint(Theme.signature)`), `gold` (stars, sparkles, crescent only) and the `Sparkle` shape.
  The canvas sheet is the `paper` token (`#F4EFE6`) with `ink` lines in both appearances. Titles
  and numerals use New York: `Font.display(_:weight:)`, serif navigation titles
  (`Theme.styleNavigationTitles`), swatch numerals and canvas digits (`DigitAtlas`); buttons and body
  text stay SF. The fill moment's two gold sparkles are `CAShapeLayer`s over the canvas
  (`CanvasView.popSparkles`). The app icon is rendered from the system's `pipo-app-icon-v2.svg` at
  1024 px (dark: the same art; tinted: its grayscale).
- Key model types: `PaintingSession` (@Observable; painting rules, tap tolerance, drag-paint, undo,
  per-color progress, events) + `PaintProgress` (persisted). The Metal canvas conforms to
  `PaintingCanvas` and is driven by the session.
- iPad first: `PaintView.PaletteLayout` wraps the palette into rows (bottom) or columns (trailing
  edge of wide windows) so every color shows at once; Settings › Palette and More › Palette choose
  its lines (`PaletteRows`: Auto, 1–6, All at Once; never thicker than 45 % of the height, 40 % of
  the width beside) and order (`PaletteOrder`: number, rainbow, lightness, areas left, or Custom,
  arranged per painting in `PaletteArrangeSheet` and kept under its nickname seed), and picking
  the next color follows that order (`PaintingSession.colorOrder`; demo `paint-palette`); `PaintCommands` is the Paint menu (iPadOS
  menu bar, single-key shortcuts) fed by the focused `PaintingFocus`; fills are registered with
  the window's `UndoManager` (⌘Z/⇧⌘Z, Edit menu, three-finger undo); the Pencil paints while
  fingers navigate (and only navigate under "Only Draw with Apple Pencil"). The app is single
  window: one live `PaintingSession` per painting.
- Color names: each paint goes by a nickname ("Harbor Fog") from `ColorNickname.assign`, seeded by
  the artwork id folded to 64 bits (`ColorNickname.seed(for:)`, XOR of the UUID's halves), so a
  painting's names never change; `PaintingSession.colorNicknames`/`nickname(of:)` (nil under Settings ›
  Color Names › Plain, and for every color unless the app runs in English: the vocabulary is English
  data, `ColorNameText.nicknamesAvailable`) feed the palette caption, current-color, VoiceOver
  ("12, Harbor Fog, dark grayish blue"), the swatch's long-press popover (number, name, shade, hex)
  and the PDF key. Nicknames reach the UI as variables shown verbatim, never as literals, so the
  string checker needs no exceptions; `pbn names <template.pbnt> [--seed N]` prints a palette's.
- Photo peek: `PhotoPeek`/`PhotoPeekButton` (hold to peek, tap to latch, `p` in the Paint menu)
  drive `CanvasView.showsPhoto`. The canvas loads the photo once through `sourcePhotoLoader`
  (bounded by the canvas size) and draws it in the canvas pass (`photoFragment`,
  `RenderContext.makePhotoTexture`), so it tracks zoom and pan exactly. Canvas touches hide a
  latched photo instead of painting. Launched with `-tracePhotoPeek YES`, the control's
  accessibility identifier lists its values so UI tests can check a hold.
- Paper: Settings › Paper (`PaperAppearance`: light, dark, automatic; `SettingsKey.paperAppearance`)
  reaches `CanvasView.paperAppearance`, which resolves a `CanvasPalette` (`.light`, `.dark` = light
  paper on a dark backdrop, `.darkPaper`) from it and the trait collection every frame, and redraws
  on a trait change. The chrome colors are uniforms (`CanvasUniforms.paper/ink/rim/accent`, set by
  `setChrome`/`select`), so the shaders have one path and no paper, ink or accent literals (the
  brush and the paint sheen keep theirs). `accent` is the selected paint lifted until it reads on
  the paper (`CanvasPalette.accent(for:)`; the paint itself on light paper). Exports, thumbnails and
  the time-lapse stay on light paper (`CanvasSnapshot.Options.palette`). `-tracePaper YES` makes the
  canvas's accessibility identifier `canvas-paper-light|dark`; demo scenario `paint-dark-paper`.
- Layered lines (drawing): a template with `lineArt` draws each boundary edge in its `LineLayer` and
  its interior strokes inside their cells. `LineAppearance` (Settings › Advanced, JSON under
  `SettingsKey.lineAppearance`; `LineAppearance.stored()` reads it off the main actor) gives each layer
  an opacity (fraction of the paper's full ink, which classic lines reach zoomed in) and a width
  (factor of the classic width) at 1×/2×/4× (1 = fitted). `LineStyle` turns it into factors of a
  renderer's classic line (the canvas divides by its zoom ramp `classicStrength`; pictures draw their
  classic line at full ink); `.classic` (every factor 1) keeps classic frames and pictures exactly as
  they were, `.print` prints every layer in PDFs. `DrawableLineArt` checks the line data (bad strokes are
  dropped, counts that don't match the edges draw as classic) and `OutlineGeometry` gives the canvas a
  line per edge, then per stroke with its cell on both sides, each with (layer, weight); the outline
  shader reads `CanvasUniforms.lineAlpha/lineWidth/lineMode`. `weighted` scales a line's width by its
  strength over its layer's mean (0.6–1.4). Painted: lines between painted cells dissolve, strokes with
  their cell. Selected: the selected color's unpainted cells keep at least the classic selected outline
  whatever their layer; strokes inside them keep their layer's look. `PaintView` reads the preference
  with `@AppStorage`, so an open canvas follows a change at once (`PaintCanvas`/`CanvasView.lineAppearance`).
  Pictures show the 1× look: `CanvasSnapshot.Options.lineAppearance`/`lineZoom` (nil = stored; the
  time-lapse reads it once per export) and `TemplateRasterizer.Style.lines` (`.screen(appearance?,
  zoom:)`, faintest layer first relative to the style's line; `.print` for `.printable`). Demo scenarios
  `paint-layered`, `-progress`, `-zoom2`, `-zoomed`, `-dark-paper`: the freight train through the real
  layered pipeline, with `SyntheticTemplate.edgeMap` (blurred OKLab gradient, DEBUG) standing in for the
  learned detector; `-mosaic` uses `SyntheticTemplate.layered` (layers by paint contrast).
- Tips: `Features/Paint/PaintTips.swift` (TipKit), configured in `PaintByNumberApp.init`. Donations
  and invalidations come from session events in `PaintChromeState` (plus double-tap zoom and
  Pencil strokes from the canvas); one tip at a time through a `TipGroup`, anchored to the
  selected swatch or the middle of the canvas. Tip types are `nonisolated struct`s driven by
  `Tips.Event`s (plus a `hasPaint` parameter for the first tip); their ids carry a generation
  that Settings ▸ Show Tips Again bumps. Invalidations, like donations, go to TipKit at most
  once per tip and launch (strokes report paint many times a second).
- Library (`Model/`): `Library` (@Observable, injected via `.environment`) keeps `Artwork` metadata
  in memory; `ArtworkStore` does the file IO (`Application Support/Artworks/<uuid>/` with
  `meta.json`, LZFSE `template.pbnt`, `progress.bin`, `source.jpg`, `thumbnail.png`; atomic writes,
  staging/trash folders). Writes are queued per artwork off the main actor; deletes are undoable.
  `Library.loadForPainting` classifies failures (`Library.OpenError`: `needsNewerApp` or
  `damaged(canRegenerate:)`), resets unusable progress with a one-time `OpenNotice` and repairs
  stale metadata; `Library.regenerate(artwork:settings:)` re-runs the pipeline on the stored photo
  (or bundled sample) off the main actor, carries progress over by region overlap
  (`PaintProgress.remapped`) and swaps the folder in atomically (`ArtworkStore.replaceContents`).
  Artworks written by a newer app (`Artwork.needsNewerApp`) are listed read-only: delete only.
  `ArtworkPaintingView` hosts `PaintView` and autosaves (debounced, on background, on close). It is
  pushed with a zoom transition whose swipe-down/pinch dismissal it turns off (they stole canvas
  gestures; `PaintingNavigationTests` guards this).
- Favorites and search: `Artwork.isFavorite` (tolerant `decodeIfPresent`, no format bump;
  `Library.setFavorite` persists metadata like rename; the card badge is hidden from VoiceOver and
  the card's *value* says "Favorite", its label stays the title). `Library.inProgress`/`finished`
  list favorites first. The gallery's Show menu (`GalleryFilter`, `@SceneStorage("galleryFilter")` in
  `AppShellView`) and `.searchable` make a `GalleryQuery`, which `Library.inProgress(matching:)`/
  `finished(matching:)` apply and the subtitle counts; `TitleSearch.matches` (pure, unit-tested) needs
  every query word to start a title word, ignoring case, diacritics and width ("ba" finds "Red Barn",
  "arn" doesn't). Placeholders show only while nothing is narrowed. Demo scenarios `gallery-favorites`,
  `gallery-search` (+ `-dark`) and `gallery-no-favorites-long-text`.
- Save failures: `Library.writeFailures` records failed progress/metadata writes per artwork (the
  newest unsaved progress is kept for `retrySaving`); the painting screen and the gallery show a
  Retry toast, and the next successful save clears it. Thumbnail and trash writes only log.
  Tests make writes fail through `ArtworkStore.writeFaults` (`WriteFaults`).
- Sharing: the time-lapse renders under `TimelapseExportSheet`/`TimelapseExportModel` (progress,
  Cancel, Try Again; its Pace control, `timelapsePace`, picks Even or As painted, which
  `TimelapseSchedule` maps from the strokes' recorded times: pauses clamp to 2 s, all-zero times
  fall back to Even, the frame count never changes; another pace restarts the render) and is
  handed to `ActivityShareSheet`, which reports when the share sheet closes so the movie is deleted (also when the sheet is dismissed). Every export lives in
  `tmp/Exports/<uuid>/` (`ArtworkExporter`); picture/template `ShareLink`s can't report
  completion, so they rely on the launch purge and the sweep of exports older than ten
  minutes that each new export runs (`ArtworkExporter.staleExportAge`).
- Image caches (`ImageCache`): LRU by decoded bytes (thumbnails 48 MB, samples 16 MB: about a
  dozen 640 px tiles, so a long library's far tiles decode again), emptied on memory warnings;
  gallery tiles decode thumbnails at their own pixel size.
- Drag painting scans the capsule the brush sweeps (`PaintingSession.drag`), radius capped at
  `PaintingSession.maxBrushRadius` canvas units (a cost bound never reached on current devices).
- Rendering without Metal: `Export/TemplateRasterizer` (CoreGraphics; vector geometry, falls back to
  the region map) backs thumbnails, share PNGs, create-flow previews and `PDFExporter`.
- Create flow `PhotoSourceView`: the inline `PhotosPicker` runs out of process, so it must never
  sit inside a ScrollView (UIKit can't arbitrate their pans across the process boundary: neither
  scrolls). It fills the page; compact windows switch Photos/Samples with a segmented control,
  wide windows put a scrolling samples column beside it. "Browse All…" presents the full picker.
  The samples come in two sections, Paintings then Photographs (`Sample.all(of:)`); a painting's
  tile shows its creator under the title while there is room (`ViewThatFits`: long text and large
  sizes drop the creator, then truncate the title), every tile's VoiceOver label names the
  creator, and tiles widen with Dynamic Type (`@ScaledMetric`, capped at the column).
- Picture library (`Resources/Samples/`, `Model/Sample.swift`): public-domain paintings and
  photographs. `library.json` is its single source of truth: which pictures ship, in which order
  (`Sample.all` follows the file; reorder there, not in Swift), and a record per picture (`id` =
  the file name `<id>.jpg`, `kind` painting|photograph, English `title`, `creator`, `year`,
  `credit`, `license`, `source`, `image`, `evidence`, `retrieved`, `crop`, `sha256` of the shipped
  file; optional `work_title`, the source's own title where `title` shortens it, and
  `evidence_url`; format in `docs/overnight/library.md`). It holds 25 paintings and 19
  photographs (21.5 MB), each re-verified from its source by an independent license audit
  before it shipped. The app decodes it at runtime: creator, year,
  credit and license are proper names and facts shown verbatim, so they stay in the audited
  record instead of a Swift copy that could drift from it (and would need `VERBATIM_FILES`).
  Titles are translatable, so they live in Swift: `Sample.title(of:)` holds one
  `String(localized: "sample.<id>", …)` per picture (its comment names the work for
  translators); a record without one isn't offered. `Sample.starters` names the two pictures
  (a painting and a photograph) prepared on first launch. License rules (hard; reject on any
  doubt): paintings and prints by creators dead by 1955, made before 1931, from a source that
  releases the file as CC0 or public domain (The Met, AIC, NGA, Rijksmuseum, Cleveland,
  Smithsonian, …); photographs CC0, by the US federal government (NASA credited alone, NOAA,
  NPS, USFWS, USGS, LoC) or published before 1931; never Italian state museums, Unsplash/Pexels/
  Pixabay/Flickr licenses, aggregator "PD" claims or AI pictures; `evidence` quotes the source's
  own license statement. `SampleLibraryTests` fails when file, titles and JPEGs disagree (every
  record offered in order with the catalog title equal to its `title`, complete fields, checksum,
  long edge 1024–2048 px, starters a painting and a photograph); `AboutTests` keeps the Pictures
  credits of Settings › Acknowledgements and `ACKNOWLEDGEMENTS.md` in step. **Adding a picture**:
  (1) `Resources/Samples/<id>.jpg` (2048 px long edge, sRGB, metadata stripped; the whole library
  ≤ 25 MB); (2) its record in `library.json` at its place in the order; (3) a `case "<id>":` in
  `Sample.title(of:)`; (4) the `sample.<id>` catalog entry (`comment`, `"extractionState":
  "manual"`, `localizations.en` = the record's `title`); (5) its `### <title>` entry at the same
  place in `ACKNOWLEDGEMENTS.md`'s Pictures section ("creator, year", credit and license lines).
  Removing one undoes the same five; synchronized folders need no project edit. The **retired
  samples** (`Sample.retired`: parrots, hibiscus, lighthouse, barn, espresso, regatta, the photos
  the app first shipped) stay bundled for good: saved artworks name them by `sampleName`, and
  regeneration falls back to the bundled photo when an artwork has no `source.jpg`
  (`Sample.named` resolves offered and retired ids; `SampleRegenerationTests`). Nothing records
  their provenance, so they are never offered or credited; they are the regression and benchmark
  corpus, the paint demos' photo and the fixtures of tests. Demos: the scenarios a viewer judges
  the app by (`gallery`, `create-preview`, `create-suggested`, the Samples pane) show the library
  by position (the first six of `Sample.all`, `Sample.starters`), so curation needs no demo edit;
  the rest keep the retired samples, and UI tests that name paintings launch with
  `-demoRetiredSamples YES`. `create-samples-paintings`/`-photographs` scroll the pane to a
  section, `create-samples-long-text` doubles its strings.
- Suggested settings in the create flow (`CreateModel`): every photo (picker, camera, sample, drop,
  opened file) goes loading → analyzing (`SubjectImportance.analyze`: importance map plus
  `SubjectHints` — faces, animals, allowlisted scene labels, quantized to hundredths — in one Vision
  pass) → suggesting (`AutoSettings.choose` on the draft image, `sourceSize` = the photo's size,
  `maxCandidates` 3 below 6 cores; its first candidate shows as a draft at once, sliders and Start
  wait) → the winner's draft (unless it is that candidate) and its full resolution. A new photo or
  closing the flow cancels it (a `withTaskCancellationHandler` flag reaches every candidate's
  thread). `settingsOrigin` is `.suggested` until the painter moves a slider (`.custom`; the view
  reports moves through `settingsChanged()`, the model's own slider updates don't); the chip in
  `TemplatePreviewView` offers Reset to Suggested, which restores the kept `AutoDecision` without
  choosing again. Decisions are reproducible from the photo and the painting length and never
  stored: `meta.json` records only `settingsOrigin` and `paintingLength` (tolerant strings), and
  regeneration reuses an artwork's recorded settings. Demo scenarios `create-suggested`,
  `create-custom`, `create-custom-long-text`.
- Open in Paint by Moonlight: images from the share sheet and Files arrive through an image document type
  (`CFBundleDocumentTypes` in `Config/Info.plist`, `Alternate` rank, not opened in place, so the system
  copies each file into `Documents/Inbox`) and `.onOpenURL` → `AppShellView.openFile`. `IncomingFile`
  reads it off the main actor (security scope tried), deletes it only if it is inside the app's inbox,
  and titles the painting after the file name; the create flow opens like a drop (`droppedPhoto`; an
  unreadable file is an empty photo, so "Couldn't Open Photo" shows), after the library's first-launch
  samples are done, the settings or gallery time-lapse sheet is closed (both live on `AppShellView`;
  their `onDismiss` resumes the open) and an open painting is dismissed (it autosaves as it goes); only
  the first of several files opens. A document type's name is localized in
  `InfoPlist.xcstrings` under its own English text (`strings_check.py` checks it). No Share Extension:
  it would be a hand-written `.appex` target in the pbxproj that can't open its containing app and
  would hand the image over through an app group. Debug builds: `-openFile <path>` calls the same
  handler at launch (`DemoMode.openFileURL`; scenario `create-from-file`).
- Layered line art inputs (`Generation/`): `EdgeDetector.edgeMap(for:maxLongSide:)` runs
  `Resources/Models/HED.mlpackage` (ControlNet's HED, `ControlNetHED.pth` from Hugging Face
  `lllyasviel/Annotators`, Apache-2.0, sha256 and conversion in `tools/models/convert_hed.py`; 29 MB
  of float16 weights computed in float32) on the photo drawn into sRGB and area-resampled to ≤ 1152
  px, reflect-padded to a multiple of 16; the edge probability is rounded to 8 bits (`EdgeMap`).
  `.cpuOnly` keeps maps the same across devices, up to a level where a value sits on a rounding
  boundary (the Neural Engine and GPU compute in reduced precision that differs by chip); the target
  has `COREML_CODEGEN_LANGUAGE = None` and loads `HED.mlmodelc` by URL. `EyeFinder.eyes(in:)`:
  Vision face landmarks → per eye a smoothed contour and an iris (a circle around the pupil, 0.2 ×
  the eye's width, clipped to the lids), closed polygons normalized to the photo, contours then
  irises, quantized to 1/4096. `LineArtInputs.make(for:settings:)` (nil for classic) caches both per
  `CGImage` instance (two photos; shared computation, cancelled when all its waiters are);
  `forGeneration(of:settings:cached:)` turns a model failure into nil (a layered template then comes
  out classic). New paintings get `Preferences.lineArt`/`.tuning` on top of the suggested or slider
  settings: `CreateModel(lineArt:tuning:)` computes the inputs once per photo in the analyzing
  phase, beside Vision, and hands them to the generator; `AutoSettings.choose(lineArt:tuning:)`
  gives every candidate the line art and tuning (its drafts get no edge map, so a layered winner is
  drafted again with it).
  `ArtworkFactory.template` (regeneration, samples) computes the inputs per template. `meta.json`
  records them in `settings`. Tests: the model against a PyTorch-made map
  (`App/PaintByNumberTests/HEDFixture.ppm` → `.pgm`, written by the conversion script; ≤ 2 levels
  apart), eyes on `FaceFixture.jpg` (NASA's 1962 portrait of John Glenn).
- Preferences: `SettingsKey` / `Preferences` (UserDefaults, `@AppStorage`). Settings › Painting Length
  (Quick, Relaxed by default, Detailed; `Preferences.paintingLength`) is what suggestions aim for;
  nothing starts from fixed settings any more (the old Starting Colors value is never read).
- Settings › Advanced (Experimental; `Features/Settings/Advanced/`): `LineArtSettings`,
  `LineAppearance` and `PipelineTuning` for testers, stored as they change (`Preferences.store`;
  values equal to the defaults are removed, so better defaults reach them). Pushed inside the
  settings sheet in compact widths, a full-screen cover in regular ones (the sheet is a small card
  there). `AdvancedSettingsModel` prepares the chosen picture once (a library picture or the most
  recent photo, `SettingsKey.advancedPreviewPicture`): decoded like the create flow, Vision
  importance, `AutoSettings.choose` with one candidate at the draft size, whose template is the
  defaults' preview and whose estimate scales draft areas to the full painting. Settings that
  change templates (`GenerationKey`: canonical, classic keys drop the layered fields) queue a
  generation: debounced, coalesced while a slider moves, the last preview kept until the next,
  every template kept in a small LRU. Each changed setting's effect (`AdvancedControl`) is the
  preview's `AdvancedStats` against the same key with that setting reset, generated once the
  painter pauses. The preview is the real `CanvasView` (`AdvancedPreviewCanvas`: no paint
  selected, so touches only navigate; Painted paints every area; a new template opens at the old
  one's camera); `TemplateRasterizer` stands in without Metal. Sliders are single adjustable
  VoiceOver elements stepping by `SliderSpec.accessibilityStep`, with a detent and haptic at
  the default. Copy Settings / Share with a Note hand over `AdvancedReport` (the JSON reproduces
  the preview of a library picture). Demo scenarios `settings-advanced` (+ `-dark`,
  `-long-text`), `settings-advanced-layered` (Line Appearance, 2×) and `settings-advanced-tuned`
  (Pipeline, effects measured) register their settings instead of storing them. Its Sounds,
  Haptics and Sparkles & Shine sections (`PaintingEffectsSections`) put each `PaintingEffect` (the
  painting notes, the color finished jingle, the fanfare, the wrong-color sound, three haptics,
  the fill sparkles, the finishing shine) on its own `@AppStorage` switch (absent means on), read
  where it plays (`FeedbackEngine`, `CanvasView`) under Settings' Sounds and Haptics; Try buttons
  play a sound or haptic once (`FeedbackEngine.preview`). Demo `settings-advanced-effects` (the
  jingle off).
- Localization: every user-facing string of the app target lives in
  `Resources/Localizable.xcstrings` (source language English; no translations yet, so the catalog
  is the translator hand-off) and the Info.plist texts in `Resources/InfoPlist.xcstrings` (keyed by
  the `INFOPLIST_KEY_*` names). `PaintCore` and `pbn` stay English. Three code forms, and nothing
  else: a SwiftUI literal with no interpolation (`Text("Done")`, `Button`, `Label`, `.navigationTitle`,
  … ; the literal is the key), `String(localized: "key", defaultValue: "…\(x)…", comment: "…")` for
  anything with an interpolation, a count or a non-SwiftUI destination (the dotted explicit keys; the
  comment says where it shows and what the arguments are), and `String(localized: "literal")` for a
  plain string. `Text(someString)` is verbatim in SwiftUI, so build such strings with the second or
  third form first. Counts are catalog plurals (`one`/`other` variations with `%lld`; never an
  `"s"` suffix); several arguments use numbered placeholders (`%1$@ %2$lld`); durations, percentages
  and numbers go through `.formatted(...)` or `PaintingTime`'s catalog units, never string
  concatenation; errors are `LocalizedError`. Neither a conditional nor `+` of literals goes inside a
  SwiftUI literal position (write one call per literal). Helper views that take a `LocalizedStringKey`
  are listed in `WRAPPERS` of the checker. Adding a string means adding its catalog entry (`"comment"`
  and `"extractionState": "manual"` included; an explicit key also needs `localizations.en`, with
  the plural forms for a count). `tools/strings_check.py` (Python 3, stdlib only; the Linux CI job
  runs it with `--self-test`) reads the sources with a small Swift lexer and fails on a literal
  missing from the catalog, an English value that differs from the code's `defaultValue`, a catalog
  key no source uses, a malformed entry or plural, `InfoPlist.xcstrings` drifting from the build
  settings, and prose-like literals that bypass localization (`ALLOWED_LITERALS` / `VERBATIM_FILES`
  hold the justified exceptions: license texts, credit names). Xcode itself extracts nothing here:
  `SWIFT_EMIT_LOC_STRINGS` is on for the app target, but entries are `manual`, so the catalog is
  edited by hand and checked by the script; generated string symbols are off for the app
  (`STRING_CATALOG_GENERATE_SYMBOLS = NO`: keys like "Finished" and "Finished!" would name the same
  symbol, and the code reads keys as literals). `LocalizationTests` checks what ships (bundle lookup,
  plurals, Info.plist). Layout under longer text: demo scenarios named `*-long-text`
  (`paint-long-text`, `paint-complete-long-text`, `gallery-long-text`, `gallery-timelapse-long-text`,
  `settings-long-text`, `settings-advanced-long-text`) are launched by `ci/screenshots.sh` with `-NSDoubleLocalizedStrings YES`, which doubles every
  localized string; read their screenshots after UI text changes (bars scale or wrap their text,
  no text sits in a fixed-width frame). Foundation doubles format strings before substituting, so
  the first copy shows raw placeholders (`1$lld · 2$@`, `@ painted`): expected, length is what
  counts there. `LongTextTests` (UI tests) keeps the bars' controls, the
  color name and the toast on screen under the same doubling.
- Accessibility: `CanvasView` is a VoiceOver container (`CanvasAccessibility`): up to 40
  `canvas-area-<region>` buttons for the unpainted areas of the selected color in view (activating
  one paints it), a `canvas-placeholder` when none are, custom actions Paint next area / Zoom to
  next area / Hint / Zoom to fit, an "Unpainted areas" rotor and `accessibilityScroll` (three-finger
  swipes page the camera; the container hides the scroll view); it posts `layoutChanged` on
  selection, progress and camera settle, and hints move VoiceOver focus to the revealed area.
  Swatches are `swatch-N` labelled "N, <color name>" (`PaintSpeech` holds all spoken strings,
  `ColorNameText` the localizable color names); `current-color` shows the selected color's name
  (progress badge on regular widths, palette caption on compact). `PaletteMetrics` scales swatches
  with Dynamic Type up to 1.4×; the fixed-height top and completion bars clamp at `.xxLarge` and use
  the Large Content Viewer. Reduce Motion reaches the canvas via `CanvasView.reduceMotion` (instant
  fills and undos, no shine, stepped replay; hint highlights and wrong-paint numbers fade in place,
  flagged to the shaders in `CanvasUniforms.numbers.w`). UI tests query these identifiers; demo
  scenarios `paint-ax` and `paint-ax-large` cover the color name and the largest text size.
- Demo scenarios: launch with `-demo <name>` (see `DemoMode`, `RootView`; `ShellDemo` owns the
  gallery, create and settings ones, e.g. `create` on the Photos pane, `create-samples` on the
  Samples pane). CI screenshots every scenario listed in `ci/scenarios.txt` ~2 s after the app
  calls `DemoMode.markReady()` (a new scenario must call it once its content is on screen;
  `name@seconds` is only the timeout). Failure states have scenarios too: `gallery-damaged`
  (recovery screen), `gallery-timelapse` (time-lapse progress sheet), `paint-unavailable` (the
  painting screen's stand-in when Metal is unavailable). Demo launches and the unit-test host
  (`DemoMode.isTestHost`) reset TipKit and hide every tip except in `paint-tip`.
  Demo mode is DEBUG-only: `DemoMode`, `ShellDemo`, `PaintDemoView`, `PipelineCheckView` and
  `SyntheticTemplate` are wrapped in `#if DEBUG`, and every other reference (`RootView`,
  `Library.forLaunch`, `AppShellView`, `SettingsView`, …) sits in an `#if DEBUG` block, so Release
  builds and the IPA have no `-demo` switch. New demo code follows the same rule;
  `ci/check_release.sh` (run by the iPad job on a Release build) fails if a demo type name
  shows up in the Release binary.
- Ship hygiene: `Resources/PrivacyInfo.xcprivacy` is the privacy manifest (no tracking, no
  collected data; required-reason APIs: UserDefaults `CA92.1`, file timestamps `C617.1` for purging
  the app's own export folders by creation date). Using another required-reason API
  (file timestamps, disk space, boot time via `systemUptime`/`mach_absolute_time`, active
  keyboards) means adding its category and reason code there; `AboutTests` fails when the
  sources of the app or of `Sources/PaintCore` (not the `pbn` CLI) and the manifest disagree.
  Export compliance (`ITSAppUsesNonExemptEncryption`) and the app category are in
  `Config/Info.plist` and the target's `INFOPLIST_KEY_*` settings.
- Settings › About shows the bundle version/build (`AppInfo`) and Acknowledgements
  (`Acknowledgements.swift`). It opens on the Pictures section (every offered picture with
  its `library.json` record: title, "creator, year", credit, license). Ported or adapted
  third-party code and the methods the pipeline implements are credited there and in
  `ACKNOWLEDGEMENTS.md` (`AboutTests` keeps the two in step): add an entry when adding either.
  Bundled models are credited under Models with their weights' license (`Acknowledgements.models`).
- Licensing: `Vector/Earcut.swift` and `PolyLabel.swift` are ISC (Mapbox); nothing else is
  third-party code, and nothing is GPL. The HED model's weights are Apache-2.0 (ControlNet; the
  evidence is in `tools/models/convert_hed.py`). `Vector/CurveFitter.swift` is a clean-room implementation
  of the method in Selinger's paper "Potrace: a polygon-based tracing algorithm" (2003), written
  from the paper alone (provenance: `docs/cleanroom-curve-fitter.md`); it replaced a GPL
  translation of potrace's source in pipeline version 3 and is credited as a method. Never consult
  potrace's source, or any port of it, when changing the fitter: work from the paper.

## Saved data compatibility (never lose a painting)

Saved paintings must open in every later build. The format history is documented on
`Template.formatVersion` and in `Model/TemplateCoding.swift`.

- Never change how an existing template format is read: `readPayloadV1` is frozen, and
  `Tests/PaintCoreTests/Fixtures/template-v1.pbnt` / `template-v2.pbnt` / `template-v2-lines.pbnt`
  (the optional `LINE` chunk of layered templates) must keep decoding (they are never
  regenerated). Add a fixture file and decode test for every new `formatVersion` or chunk.
- New template data goes in an extension chunk (FourCC tag, flags, length; see
  `TemplateCoding.swift`). Old readers skip optional chunks; flag a chunk `required` only when
  ignoring it would misrender the painting. Bump `Template.formatVersion` only when the base
  layout itself changes.
- Bump `TemplateGenerator.pipelineVersion` in the same commit as any change that alters generated
  output for identical inputs and settings; templates record it.
- Decoders treat files as hostile: check every count against the bytes left before allocating,
  and every span, reference and coordinate (inside the canvas) in `Int` arithmetic before
  anything indexes with it. PaintCore is compiled `-Ounchecked` in release, so a missed check is a
  silent out-of-bounds read; the truncation, random-corruption and crafted-reference tests in
  `TemplateCodingTests` guard this.
- A file from a newer app is never reset or rewritten: it throws a "newer" error
  (`Template.CodingError.requiresNewerReader`, `PaintProgress.CodingError.newerVersion`) and the
  app says it needs an update. `PaintProgress` fields are append-only (readers ignore trailing
  bytes); bump its `formatVersion` only when an existing field changes meaning. Bump
  `Artwork.currentFormat` when older apps must not open or rewrite an artwork folder (a template
  `formatVersion` bump or a new required chunk).
- Damaged data never traps: progress that doesn't fit its template is a recoverable error
  (`PaintingSession.init(template:progress:) throws`), and `LibraryTests` cover each failure.

## CI feedback loop (no Xcode locally)

1. Commit, push to a branch: `git push -u origin HEAD:<branch>` (CI runs on every branch).
2. Run `CI_BRANCH=<branch> ci/fetch.sh <sha> <outdir>` in the background; it waits for the
   report CI publishes to `ci-shots/<branch>`: `STATUS.md` (job results and the regression
   verdict), trimmed `*.log`, `core/core-test.log` and `core/regression/` (`regression.txt`
   table, `regression.json`, `sheets/<regime>/<sample>.jpg`) from the Linux job, and per device
   `errors.txt` (compiler errors), `shots/*.png` plus `*-app.log` (the app's os_log output) and
   `*-steps.log` (readiness, crashes). iPad is the primary device: every push builds Debug on a
   13" iPad Pro simulator and adds `ipad/test-results.json`, `ipad/attachments/` and
   `ipad/bench.txt` (pipeline timings on the M1 runner, only when `Sources/` changed). The iPad
   job also builds Release and runs `ci/check_release.sh` (privacy manifest present, no demo
   code); its problems land in `ipad/errors.txt` too. The
   iPhone job (the same on an iPhone 17 Pro, without the benchmark) runs on
   `claude/paint-by-numbers-app`, via workflow_dispatch with `iphone: true`, or on any branch
   when the pushed commit's message contains `[iphone]`. Turnaround
   ~15–20 min (longer if several branches are queued: only 5 macOS jobs run concurrently).
   Work on something else while it runs.
3. Read errors/screenshots, fix, repeat. Batch fixes; one validated push beats many guesses.
4. Device builds: every push to `claude/paint-by-numbers-app` also archives an unsigned Release
   IPA (version `1.0.<run>`, build `<run>`), publishes it as the `build-<run>` prerelease (the
   five newest are kept) and rewrites the SideStore/AltStore source on the `sidestore` branch
   (`ci/sidestore_source.py`). Users add
   `https://raw.githubusercontent.com/pbordjadze/paint-by-number/sidestore/source.json` in
   SideStore; it signs the IPA with their Apple ID and offers each new build as an update.

## Conventions

- Swift 6 language mode, strict concurrency. Core types are `Sendable` value types.
- Hot loops use `withUnsafe(Mutable)BufferPointer` + `Parallel.forEachBand`; wrap raw pointers in
  `UncheckedSendable` to share them with workers writing disjoint ranges.
- Color math happens in OKLab (`ColorScience`). Distances there ≈ ΔE; 0.02 ≈ just noticeable,
  and paints are never closer than that (`SegmentationParameters.jnd`).
- Numbers are sized only by `LabelSizing` (`Model/Template.swift`): SVG, `TemplateRasterizer`
  (thumbnails, PDF) and the Metal canvas all use it and never drop a number. The pipeline gives
  every label room for its digit count (raster `minRadius(digits:)`, vector `LabelRoom`), so no
  number is smaller than `LabelSizing.minimumFontSize`; `validate(minLabelRadius:)` checks it.
  Print legibility is the PDF exporter's job, not a renderer floor: `PDFExporter.sheets` prints a
  detailed template on overlapping sheets so the smallest number is at least 2.6 pt.
- Canvas units = pixels of the working image; origin top-left, +y down.
- Keep `PaintCore` free of Apple-only frameworks (guard any Accelerate/Metal use with
  `#if canImport(...)` and keep a portable path).
- Deterministic output for identical inputs + settings (seeded `SplitMix64`), on every device:
  parallel floating-point reductions accumulate fixed-size chunks and add them in order
  (`RegionRuns.accumulate`, `RegionAdjacency.boundarySteps`), never one partial sum per core.
- Comments explain *why*, sparingly. No dead code, no TODO litter.
