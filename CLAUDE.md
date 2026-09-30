# Paint by Numbers — engineering notes

Native iOS/iPadOS 26 app that turns photos into paint-by-numbers templates on-device and
makes painting them fluid and satisfying. Swift 6, SwiftUI (Liquid Glass) shell, Metal canvas.

## Layout

- `Package.swift`, `Sources/PaintCore` — portable, dependency-free template pipeline
  (builds on Linux too). `Sources/pbn` — headless CLI. `Tests/PaintCoreTests` — Swift Testing.
  - `Foundation/` grids, color science (OKLab, Display P3), EDT, connected components, resampling
  - `Model/` `Template` (the product of the pipeline) + binary coding, `GenerationSettings`, `Segmentation`
  - `Segmentation/` photo → region label map + palette (`Segmenter.segment`; pipeline overview in
    its doc comment, all tunables in `SegmentationParameters`)
  - `Vector/` label map → shared smoothed boundaries, fill mesh, labels (`Vectorizer.vectorize`)
  - `Export/` SVG (and later PDF helpers)
  - `TemplateGenerator.swift` entry point composing the stages, with `StageClock` timings
- `App/` Xcode project (`PaintByNumber.xcodeproj`, synchronized folders — adding files needs no
  project edits) with the SwiftUI app, Metal renderer and UI tests.
- `tools/` evaluation tooling (`swift.sh`, `eval.py`, `svg2png.mjs`).
- `.github/workflows/` macOS CI: builds the app, runs tests, captures simulator screenshots.

## Building & testing on Linux (no Xcode here)

- `tools/swift.sh build -c release --static-swift-stdlib` — builds `pbn` in the `swift:6.2-noble`
  Docker image; the static binary at `.build/release/pbn` then runs directly on the host.
- `tools/swift.sh test` — runs the package tests in Docker.
- `python3 tools/eval.py run <images...> --out <dir> [-- --colors 24 --detail 0.5]` — runs the
  pipeline and writes contact sheets (`<dir>/<name>/sheet.png`: source | painted | template),
  `overview.png` and `summary.json` with metrics (region count, mean ΔE, tiny regions, label
  legibility — `labelsBelowLegibleSize` must be 0, `minLabelRadius`, `minLabelRoom`, `valid` —
  and timings). The metrics are `pbn generate`'s `stats.json`, a stable interface for regression
  tooling: add fields, never rename them. Look at the PNGs with the Read tool. The sheet's second row shows the raw region raster, a 2×
  `boundaries.png` (1-px region outlines, best for judging segmentation shapes) and the palette;
  `--importance-dir DIR` passes `DIR/<name>.pgm` as the importance map (Vision stand-in).
- Test photos: the Kodak suite (`kodim01..24.png`, 768×512) and scikit-image samples are a good
  corpus (download Kodak from raw.githubusercontent.com/MohamedBakrAli/Kodak-Lossless-True-Color-Image-Suite).
- `pbn trace <flat.ppm> <outdir>` vectorizes a flat-color image directly (one palette entry per
  distinct color) — ideal for judging curve quality on synthetic shapes. `pbn check <t.pbnt>`
  runs `Template.validate()` (planarity, ring orientation, mesh coverage/watertightness, labels,
  and every label's room for its number: `--min-label-radius R`, default
  `LabelSizing.minimumRadius`, `0` skips it). `pbn bench <ppm...>` times the pipeline, including
  a preview, detail 1 on a large photo and 150 colors at detail 1.
- Vector geometry conventions (orientation, junctions, closed edges, coordinate quantum) are
  documented on `BoundaryEdge`, `Ring` and `FillMesh` in `Model/Template.swift`.

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
- Library (`Model/`): `Library` (@Observable, injected via `.environment`) keeps `Artwork` metadata
  in memory; `ArtworkStore` does the file IO (`Application Support/Artworks/<uuid>/` with
  `meta.json`, LZFSE `template.pbnt`, `progress.bin`, `source.jpg`, `thumbnail.png`; atomic writes,
  staging/trash folders). Writes are queued per artwork off the main actor; deletes are undoable.
  `ArtworkPaintingView` hosts `PaintView` and autosaves (debounced, on background, on close). It is
  pushed with a zoom transition whose swipe-down/pinch dismissal it turns off (they stole canvas
  gestures; `PaintingNavigationTests` guards this).
- Rendering without Metal: `Export/TemplateRasterizer` (CoreGraphics; vector geometry, falls back to
  the region map) backs thumbnails, share PNGs, create-flow previews and `PDFExporter`.
- Preferences: `SettingsKey` / `Preferences` (UserDefaults, `@AppStorage`).
- Demo scenarios: launch with `-demo <name>` (see `DemoMode`, `RootView`). CI screenshots every
  scenario listed in `ci/scenarios.txt` ~2 s after the app calls `DemoMode.markReady()` (a new
  scenario must call it once its content is on screen; `name@seconds` is only the timeout).

## CI feedback loop (no Xcode locally)

1. Commit, push to a branch: `git push -u origin HEAD:<branch>` (CI runs on every branch).
2. Run `CI_BRANCH=<branch> ci/fetch.sh <sha> <outdir>` in the background; it waits for the
   report CI publishes to `ci-shots/<branch>`: `STATUS.md`, trimmed `*.log`, and per device
   `errors.txt` (compiler errors), `shots/*.png` plus `*-app.log` (the app's os_log output) and
   `*-steps.log` (readiness, crashes). iPad is the primary device: every push builds Debug on a
   13" iPad Pro simulator and adds `ipad/test-results.json`, `ipad/attachments/` and
   `ipad/bench.txt` (pipeline timings on the M1 runner, only when `Sources/` changed). The
   iPhone job (the same on an iPhone 17 Pro, without the benchmark) runs on
   `claude/paint-by-numbers-app` or via workflow_dispatch with `iphone: true`. Turnaround
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
- Canvas units = pixels of the working image; origin top-left, +y down.
- Keep `PaintCore` free of Apple-only frameworks (guard any Accelerate/Metal use with
  `#if canImport(...)` and keep a portable path).
- Deterministic output for identical inputs + settings (seeded `SplitMix64`).
- Comments explain *why*, sparingly. No dead code, no TODO litter.
