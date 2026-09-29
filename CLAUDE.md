# Paint by Numbers — engineering notes

Native iOS/iPadOS 26 app that turns photos into paint-by-numbers templates on-device and
makes painting them fluid and satisfying. Swift 6, SwiftUI (Liquid Glass) shell, Metal canvas.

## Layout

- `Package.swift`, `Sources/PaintCore` — portable, dependency-free template pipeline
  (builds on Linux too). `Sources/pbn` — headless CLI. `Tests/PaintCoreTests` — Swift Testing.
  - `Foundation/` grids, color science (OKLab, Display P3), EDT, connected components, resampling
  - `Model/` `Template` (the product of the pipeline) + binary coding, `GenerationSettings`, `Segmentation`
  - `Segmentation/` photo → region label map + palette (`Segmenter.segment`)
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
  `overview.png` and `summary.json` with metrics (region count, mean ΔE, tiny regions, timings).
  Look at the PNGs with the Read tool.
- Test photos: the Kodak suite (`kodim01..24.png`, 768×512) and scikit-image samples are a good
  corpus (download Kodak from raw.githubusercontent.com/MohamedBakrAli/Kodak-Lossless-True-Color-Image-Suite).
- `pbn trace <flat.ppm> <outdir>` vectorizes a flat-color image directly (one palette entry per
  distinct color) — ideal for judging curve quality on synthetic shapes. `pbn check <t.pbnt>`
  runs `Template.validate()` (planarity, ring orientation, mesh coverage/watertightness, labels).
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
- Demo scenarios: launch with `-demo <name>` (see `DemoMode`, `RootView`). CI screenshots every
  scenario listed in `ci/scenarios.txt` (`name@seconds` sets the settle delay) on an iPhone Pro
  and a 13" iPad Pro simulator.

## CI feedback loop (no Xcode locally)

1. Commit, push to a branch: `git push -u origin HEAD:<branch>` (CI runs on every branch).
2. Run `CI_BRANCH=<branch> ci/fetch.sh <sha> <outdir>` in the background; it waits for the
   report CI publishes to `ci-shots/<branch>`: `STATUS.md`, `*-errors.txt` (compiler errors),
   trimmed `*.log`, `test-results.json`, screenshots (`app-screens/shots/*.png`), test
   attachments. Typical turnaround ~8–12 min.
3. Read errors/screenshots, fix, repeat. Batch fixes; one validated push beats many guesses.

## Conventions

- Swift 6 language mode, strict concurrency. Core types are `Sendable` value types.
- Hot loops use `withUnsafe(Mutable)BufferPointer` + `Parallel.forEachBand`; wrap raw pointers in
  `UncheckedSendable` to share them with workers writing disjoint ranges.
- Color math happens in OKLab (`ColorScience`). Distances there ≈ ΔE; 0.02 ≈ just noticeable.
- Canvas units = pixels of the working image; origin top-left, +y down.
- Keep `PaintCore` free of Apple-only frameworks (guard any Accelerate/Metal use with
  `#if canImport(...)` and keep a portable path).
- Deterministic output for identical inputs + settings (seeded `SplitMix64`).
- Comments explain *why*, sparingly. No dead code, no TODO litter.
