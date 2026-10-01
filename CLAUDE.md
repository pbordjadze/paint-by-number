# Paint by Numbers — engineering notes

Native iOS/iPadOS 26 app that turns photos into paint-by-numbers templates on-device and
makes painting them fluid and satisfying. Swift 6, SwiftUI (Liquid Glass) shell, Metal canvas.

## Layout

- `Package.swift`, `Sources/PaintCore` — portable, dependency-free template pipeline
  (builds on Linux too). `Sources/pbn` — headless CLI. `Tests/PaintCoreTests` — Swift Testing
  (`Fixtures/` holds files written by past encoders, e.g. `template-v1.pbnt`).
  - `Foundation/` grids, color science (OKLab, Display P3), EDT, connected components, resampling,
    color naming (`ColorName`: OKLab → structured name, e.g. "dark grayish green"; `english` for the CLI)
  - `Model/` `Template` (the product of the pipeline) + versioned binary coding, `GenerationSettings`,
    `Segmentation`, `RegionRemap` (carries painted regions onto a regenerated region map)
  - `Segmentation/` photo → region label map + palette (`Segmenter.segment`; pipeline overview in
    its doc comment, all tunables in `SegmentationParameters`)
  - `Vector/` label map → shared smoothed boundaries, fill mesh, labels (`Vectorizer.vectorize`)
  - `Export/` SVG (and later PDF helpers)
  - `TemplateGenerator.swift` entry point composing the stages, with `StageClock` timings
- `App/` Xcode project (`PaintByNumber.xcodeproj`, synchronized folders — adding files needs no
  project edits) with the SwiftUI app, Metal renderer and UI tests.
- `tools/` evaluation tooling (`swift.sh`, `eval.py`, `compare.py`, `regression.py` + its
  committed `baseline/regression.json`, `svg2png.mjs`) and `strings_check.py` (string catalog
  drift check, see Localization).
- `.github/workflows/` CI: Linux PaintCore tests + quality regression; macOS builds the app, runs
  tests, captures simulator screenshots.
- `ACKNOWLEDGEMENTS.md` credits and license texts for the ported code and published methods (also shown in the app).

## Building & testing on Linux (no Xcode here)

- `tools/swift.sh build -c release --static-swift-stdlib` — builds `pbn` in the `swift:6.2-noble`
  Docker image; the static binary at `.build/release/pbn` then runs directly on the host.
- `tools/swift.sh test` — runs the package tests in Docker.
- `python3 tools/eval.py run <images...> --out <dir> [-- --colors 24 --detail 0.5]` — runs the
  pipeline and writes contact sheets (`<dir>/<name>/sheet.png`: source | painted | template),
  `overview.png` and `summary.json` with metrics (region count, mean ΔE, tiny regions, label
  legibility — `labelsBelowLegibleSize` and `labelRoomUnmet` must be 0, `minLabelRadius`,
  `minLabelRoom`, `valid` — timings, palette and `colorNames`; the sheet's palette panel labels
  each swatch with its name). The metrics are `pbn generate`'s `stats.json`, a stable interface
  for regression tooling: add fields, never rename them. Look at the PNGs with the Read tool.
  The sheet's second row shows the raw region raster, a 2× `boundaries.png` (1-px region
  outlines, best for judging segmentation shapes) and the palette; `--importance-dir DIR` passes
  `DIR/<name>.pgm` as the importance map (Vision stand-in).
- Test photos: the Kodak suite (`kodim01..24.png`, 768×512) and scikit-image samples are a good
  corpus (download Kodak from raw.githubusercontent.com/MohamedBakrAli/Kodak-Lossless-True-Color-Image-Suite).
- `pbn trace <flat.ppm> <outdir>` vectorizes a flat-color image directly (one palette entry per
  distinct color) — ideal for judging curve quality on synthetic shapes. `pbn check <t.pbnt>`
  prints the file's format and pipeline versions and runs `Template.validate()` (planarity, ring
  orientation, mesh coverage/watertightness, labels, and every label's room for its number:
  `--min-label-radius R`, default `LabelSizing.minimumRadius`, `0` skips it). `pbn bench
  <ppm...>` times the pipeline, including a preview, detail 1 on a large photo and 150 colors
  at detail 1.
- Vector geometry conventions (orientation, junctions, closed edges, coordinate quantum) are
  documented on `BoundaryEdge`, `Ring` and `FillMesh` in `Model/Template.swift`.
- `tools/regression.py [--sheets DIR] [--json FILE]` — the quality gate CI runs on every push:
  the six bundled samples in three regimes (24 colors/detail 0.5, 150/1.0, 12/0.0), each
  generated twice. Hard invariants: `pbn check` valid, byte-identical runs, no region under
  radius 2, palette distance ≥ the floor pbn reports (`GenerationSettings.minPaletteDistance`),
  and `labelsBelowLegibleSize == 0` once pbn's stats report that field. Bands versus
  `tools/baseline/regression.json`: mean ΔE ≤ baseline × 1.05, regions ±15 %, template bytes
  ±20 %; timings are informational. Prints a table with deltas, exits 1 on any failure;
  `--self-test` checks the rules themselves. Needs the release `pbn` and Pillow (no node: its
  sheets are source | painted raster | region outlines + palette).
- **Whenever a change alters pipeline output, run `tools/regression.py --update` (it only writes
  a baseline that satisfies the hard invariants), look at the `--sheets`, and commit
  `tools/baseline/regression.json` together with the change**: CI fails once a metric leaves
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
- Key model types: `PaintingSession` (@Observable; painting rules, tap tolerance, drag-paint, undo,
  per-color progress, events) + `PaintProgress` (persisted). The Metal canvas conforms to
  `PaintingCanvas` and is driven by the session.
- iPad first: `PaintView.PaletteLayout` wraps the palette into rows (bottom) or columns (trailing
  edge of wide windows) so every color shows at once; `PaintCommands` is the Paint menu (iPadOS
  menu bar, single-key shortcuts) fed by the focused `PaintingFocus`; fills are registered with
  the window's `UndoManager` (⌘Z/⇧⌘Z, Edit menu, three-finger undo); the Pencil paints while
  fingers navigate (and only navigate under "Only Draw with Apple Pencil"). The app is single
  window: one live `PaintingSession` per painting.
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
- Save failures: `Library.writeFailures` records failed progress/metadata writes per artwork (the
  newest unsaved progress is kept for `retrySaving`); the painting screen and the gallery show a
  Retry toast, and the next successful save clears it. Thumbnail and trash writes only log.
  Tests make writes fail through `ArtworkStore.writeFaults` (`WriteFaults`).
- Sharing: the time-lapse renders under `TimelapseExportSheet`/`TimelapseExportModel` (progress,
  Cancel, Try Again) and is handed to `ActivityShareSheet`, which reports when the share sheet
  closes so the movie is deleted (also when the sheet is dismissed). Every export lives in
  `tmp/Exports/<uuid>/` (`ArtworkExporter`); picture/template `ShareLink`s can't report
  completion, so they rely on the launch purge and the sweep of exports older than ten
  minutes that each new export runs (`ArtworkExporter.staleExportAge`).
- Image caches (`ImageCache`): LRU by decoded bytes (thumbnails 48 MB, samples 16 MB), emptied on
  memory warnings; gallery tiles decode thumbnails at their own pixel size.
- Drag painting scans the capsule the brush sweeps (`PaintingSession.drag`), radius capped at
  `PaintingSession.maxBrushRadius` canvas units (a cost bound never reached on current devices).
- Rendering without Metal: `Export/TemplateRasterizer` (CoreGraphics; vector geometry, falls back to
  the region map) backs thumbnails, share PNGs, create-flow previews and `PDFExporter`.
- Create flow `PhotoSourceView`: the inline `PhotosPicker` runs out of process, so it must never
  sit inside a ScrollView (UIKit can't arbitrate their pans across the process boundary: neither
  scrolls). It fills the page; compact windows switch Photos/Samples with a segmented control,
  wide windows put a scrolling samples column beside it. "Browse All…" presents the full picker.
- Preferences: `SettingsKey` / `Preferences` (UserDefaults, `@AppStorage`).
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
  (`paint-long-text`, `paint-complete-long-text`, `gallery-long-text`, `settings-long-text`) are
  launched by `ci/screenshots.sh` with `-NSDoubleLocalizedStrings YES`, which doubles every
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
  (`Acknowledgements.swift`). Ported or adapted third-party code and the methods the pipeline
  implements are credited there and in `ACKNOWLEDGEMENTS.md` (`AboutTests` keeps the two in
  step): add an entry when adding either.
- Licensing: `Vector/Earcut.swift` and `PolyLabel.swift` are ISC (Mapbox); `Vector/CurveFitter.swift`
  is a translation of potrace 1.16 and therefore GPL-2.0-or-later (Peter Selinger). Settings ›
  Acknowledgements and `ACKNOWLEDGEMENTS.md` carry the full license texts and the GPL source
  notice (the repository is public); keep them when touching the fitter. Distributing the app
  (IPA, SideStore, and above all the App Store, which GPLv2 is generally held incompatible
  with) needs that settled first: license the app GPL-compatibly or replace `CurveFitter`.

## Saved data compatibility (never lose a painting)

Saved paintings must open in every later build. The format history is documented on
`Template.formatVersion` and in `Model/TemplateCoding.swift`.

- Never change how an existing template format is read: `readPayloadV1` is frozen, and
  `Tests/PaintCoreTests/Fixtures/template-v1.pbnt` / `template-v2.pbnt` must keep decoding (they
  are never regenerated). Add a fixture file and decode test for every new `formatVersion`.
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
