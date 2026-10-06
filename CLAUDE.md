# Paint by Moonlight — engineering notes

Native iOS/iPadOS 26 app that turns photos into paint-by-numbers templates on-device and makes
painting them fluid and satisfying. Swift 6, SwiftUI (Liquid Glass) shell, Metal canvas.

This file is the map and the rules. An area's reference is its entry type's doc comment (named
below); the tools' docstrings and `Sources/pbn/main.swift`'s header are their manuals; `docs/` holds
the measurements and provenance the code cites.

**App feature notes and gotchas: `App/CLAUDE.md`** (loaded when you read files under `App/`; read it
before planning app work).

## Map

- `Package.swift`: `PaintCore`, `pbn`, `PaintCoreTests`. The Xcode project builds PaintCore from
  this package (local reference `..`), so its flags change the app's builds too (release
  `-Ounchecked`); its iOS 18 / macOS 15 platforms are only a floor (the app's 26.0 is the
  project's).
- `Sources/PaintCore`: the portable, dependency-free pipeline (builds on Linux too).
  `TemplateGenerator.generate(from:importance:lineArt:…)` composes the stages, timed by
  `StageClock`; `TemplateGenerator.pipelineVersion` is recorded in every template.
  - `Foundation/`: grids, `ColorScience` (OKLab, Display P3), resampling, morphology, `DisjointSet`,
    `MinHeap`, `Netpbm` (pbn's only image input off Apple platforms), `SplitMix64` (the only RNG),
    `Parallel` (bands, chunks, `CancellationCheck`; its doc comment is the determinism contract),
    `ColorName` and `ColorNickname` (the doc comment of `ColorNicknameVocabulary.swift`'s table is
    the style guide `ColorNicknameTests` lints).
  - `Model/`: `Template` + `TemplateCoding` (geometry conventions on `BoundaryEdge`, `Ring`,
    `FillMesh`, `Template.coordinateQuantum` and `points`), `GenerationSettings`, `Segmentation`,
    `LabelSizing`, `TemplateLineArt`, `RegionRemap`, `PaintingTime` (the one painting-time
    estimate), `LineArtSettings` (`init(style:)` carries each style's own defaults; `normalized`
    keeps detail ≤ outline, and the generator reads normalized values) and `PipelineTuning`
    (`pbn --tuning` factors on `SegmentationParameters`' knobs: exactly 1 leaves every knob bit
    for bit; the app sets none, but a painting's recorded tuning regenerates as it was made).
  - `Segmentation/`: photo → region label map + palette (`Segmenter.segment`; stages in its doc
    comment). `SegmentationParameters` holds the knobs derived from the settings and canvas size;
    each stage's constants sit beside their use. After `RegionSimplifier.simplify`, later stages
    only merge or recolor whole regions; a paint's number is its final palette index + 1, so
    `enforceLabelRoom` drops unused paints in order and nothing reorders them. `Auto/` reuses
    `WorkingImage`, `StructureMap`, `ImportanceMap`, `BoxBlur`, `PaletteBuilder` and
    `SegmentationParameters`, so a refactor there that keeps templates byte-identical can still move
    Auto's decisions. `Vectorizer` and `LayeredLines` rebuild `SegmentationParameters` without the
    coloring-book flattening, which must therefore never change `minRadius`. Gradient rings
    (`BandRings`): `docs/gradient-rings.md`.
  - `Vector/`: label map → shared smoothed boundaries, fill mesh, labels (`Vectorizer`; the pipeline
    calls `vectorizeWithStats`); `EdgeSmoother` repairs until `GeometryValidator` and every
    `LabelRoom` hold. `Template.validate` (`TemplateValidation.swift`) is the oracle of `pbn check`,
    the regression gate and the create flow's Debug check.
  - `LineArt/` (`LayeredLines.apply` and `Writing`, see Line art), `Auto/` (`AutoSettings`, see Suggested
    settings), `Export/` (`SVGExport`: the headless preview pbn writes for `tools/eval.py`; the app
    prints and shares through CoreGraphics in `App/PaintByNumber/Export`).
- `Sources/pbn`: `main.swift` is the usage header (the manual) and the dispatch; `Options.swift`
  (flags; the hand-kept `Fields` tables of `--line-art`/`--tuning` keys), `Inputs.swift`,
  `Commands.swift`, `Bench.swift`, `Metrics.swift` (stats.json), `LineArtReport.swift` (its
  `lineArt` block; the field docs define the drawing metrics), `Rasters.swift`, `Timing.swift`.
- `Tests/PaintCoreTests` (Swift Testing; helpers in `TestSupport.swift`, `TestScenes.swift`,
  `ColorTestSupport.swift`). `Fixtures/`: `template-*.pbnt` are frozen (Saved data);
  `layered-photo.ppm`, `layered-edges.pgm` and `shapes.ppm` are inputs that tests and the line
  fixtures' recorded commands read (edit them and those recipes stop reproducing);
  `auto-parrots.json` + `auto-parrots-draft.ppm` pin one Auto decision (the draft is also a test
  photo) and are regenerated on purpose, by the recipe above
  `AutoSettingsTests.parrotsDecisionIsPinned`, when a change moves that decision.
- `Tests/Corpus`: the six photos the regression gate and the CI benchmark run on, pinned by name,
  never shipped (provenance and credits in its `README.md`).
- `App/`: `PaintByNumber.xcodeproj` (synchronized folders: adding files needs no project edit),
  `PaintByNumber/`, `PaintByNumberTests` (Swift Testing), `PaintByNumberUITests` (XCTest),
  `Config/Info.plist`; map and notes in `App/CLAUDE.md`.
- `tools/`: evaluation (`eval.py`, `compare.py`, `auto_sheet.py`), the quality gate (`regression.py`
  with `baseline/`), `strings_check.py`, `swift.sh` (SwiftPM in Docker) and `models/convert_*.py`
  (the app's Core ML models from their source weights).
- `ci/` scripts and `.github/workflows/ci.yml`: jobs `core` (Linux: PaintCore tests, quality
  regression, string catalog), `ipad` (every push: Debug build, screenshots, tests, Release check,
  benchmark), `iphone` and `ipa` (unsigned IPA, SideStore source) on `main`, `report`.
- `docs/`: notes the code cites: `auto-tuning.md` (and `auto-corpus.md`), `coloring-book.md`,
  `writing.md`, `picture-library.md`, `gradient-rings.md`, `cleanroom-curve-fitter.md`. Plans, agent briefs and
  per-agent reports are not committed (they live on their branch and in commit messages); a
  measurement the code relies on goes into its feature's doc or the constant's doc comment.
- `ACKNOWLEDGEMENTS.md`: credits and license texts (also shown in the app). Tags
  `archive/lineart-research` (`research/lineart/`, which `LineArtSettings`, `convert_hed.py` and
  `docs/coloring-book.md` cite) and `archive/resume-notes` keep unmerged history
  (`git show <tag>:<path>`).

## Line art

`LayeredLines.apply` (stages and constants in its doc comment) turns an 8-bit `EdgeMap`
(`LineArtInput`) into cells bounded by lines, each line in a `LineLayer`. Detect and trace read the
edge map alone; eyes and the subjects' silhouettes enter at the layer stage (`LineLayering.addEyes`,
`addObjects`), where `LineArtInput.contours` decides the outlines; `CellMap` splits the segmentation
along the lines; lines inside cells become `InteriorStroke`s (`Template.lineArt`). It makes the
**coloring book** (`LineArtSettings.Style.coloringBook`: the default, and every template the app
makes): the drawing as its only lines, on flatter paint
(`SegmentationParameters.coloringBookFlattening`, by style, edge map or not), drawn in full ink over
the paint (`docs/coloring-book.md`). The layered style it grew from is retired: its templates keep
decoding and draw as books, and its recorded settings decode as the book's defaults. Writing (`LineArtInput.writing`: the lines of text Vision
found, `TextFinder`) is traced from the photo itself, painted out before segmenting and drawn as
interior strokes with the numbers kept off it (`Writing`, `LabelKeepOut`; `keepWriting`;
`docs/writing.md`, whose corpus every change to it is judged on). Without an edge map, book
settings generate a classic template; the same maps and settings give the same bytes on any core
count.

## Suggested settings

`AutoSettings` (`analyze`, `candidates`, `score`, `choose`) suggests settings for a photo and a
`PaintingLength`. Features are quantized and thresholds are ramps, so a decision is reproducible
from the same pixels, importance, hints, Painting Length, line style, tuning and candidate count
(the app runs 3 candidates below 6 cores, 5 otherwise); decisions are never stored. Constants are
documented where declared (`AutoSettings`, `PaintingLength`, `PhotoAnalyzer`); `docs/auto-tuning.md`
logs the tuned ones.

## Working here (Linux, no Xcode)

| Task | Command (manual: its docstring) |
| --- | --- |
| Build pbn (static; runs on the host) | `tools/swift.sh build -c release --static-swift-stdlib` |
| PaintCore tests | `tools/swift.sh test` |
| Sheets and metrics | `tools/eval.py run <images> --out <dir> [-- <pbn options>]` |
| Line-art tuning (always) | `tools/eval.py book`: `docs/coloring-book.md` › Measuring a book |
| Suggested settings | `pbn suggest <image> --out <dir>`, `tools/auto_sheet.py <dir>` |

- Look at the PNGs with the Read tool. An eval sheet's second row is the raw region raster, a 2×
  `boundaries.png` (best for judging segmentation shapes) and the palette.
- stats.json, decision.json and the file names pbn writes are read by `tools/*.py` by key and name:
  add fields and files, never rename or repurpose them, nor the properties of the PaintCore types
  they embed (listed on pbn's `Metrics`); a field leaves only with its readers.
  `labelsBelowLegibleSize` and `labelRoomUnmet` must be 0.
- pbn has no tests: CI runs `generate`, `check` and `bench`; run `suggest`, `trace` and `names` by
  hand after touching them. A new `LineArtSettings` or `PipelineTuning` field needs its `Fields`
  entry. `pbn trace`'s `valid` skips the label-room check: run `pbn check`. pbn is classic unless
  `--line-style` says otherwise and reads PPM/PGM (other formats only on Apple platforms);
  `tools/eval.py` needs node (`cd tools && npm ci`) and Pillow, the others Pillow. pbn has no
  Vision: its fallback importance map rates busy texture important, so its region counts run above
  the app's, and Auto follows.
- Test photos: `Tests/Corpus`, the rest of the Kodak suite (its URL is in that folder's `README.md`)
  and scikit-image's samples.
- `App/` compiles only on CI: after editing an App Swift file, re-read it whole and check its
  imports (`MemberImportVisibility`), actor isolation at each boundary, API names and signatures
  against iOS 26 / Swift 6.2, and every call site of anything renamed; when unsure of an API, mirror
  an existing use in the repo.
- "database is locked" from `tools/swift.sh`: another build is using `.build`; wait and retry.
- Scratch output goes outside the repo. Never commit `.build/`, eval output, `tools/node_modules`,
  `.claude/worktrees/` or `.claude/corpus/`. Keep a diff to what the task needs; edits to shared
  files (`Localizable.xcstrings`, `ci/scenarios.txt`) are minimal.

## Quality gate

`tools/regression.py` (CI, every push) generates the six `Tests/Corpus` photos, pinned by name
(`SAMPLE_NAMES`; the picture library's curation must move neither the baselines nor CI's time), in
three regimes twice each, as coloring books from the committed maps in `tools/baseline/lines/`, and
at Auto's suggestion; it checks hard invariants (`pbn check` valid, byte-identical runs, minimum
radius and palette distance, `labelsBelowLegibleSize == 0`, Auto's choice inside its bands) and
bands against `tools/baseline/regression.json`, all listed in its docstring. Its template
same/changed column means something only for an identical build and input decode. `swift test` fails
`AutoSettingsTests.parrotsDecisionIsPinned` when a change moves that draft: regenerate the fixture
with the baselines. No regime passes eyes or subjects: `LineArtTests` alone guards `addEyes`,
`addObjects` and `MaskContours`.

**Whenever a change alters pipeline output, run `tools/regression.py --update` (it only writes a
baseline that satisfies the hard invariants), look at the `--sheets`, and commit
`tools/baseline/regression.json` and `tools/baseline/auto.json` together with the change**: CI fails
once a metric leaves its band, and a fresh baseline keeps the table's deltas meaningful.

## Saved data compatibility (never lose a painting)

Saved paintings must open in every later build. The format history is documented on
`Template.formatVersion` and in `Model/TemplateCoding.swift`.

- Never change how an existing template format is read: `readPayloadV1` is frozen, and
  `Tests/PaintCoreTests/Fixtures/template-v1.pbnt` / `template-v2.pbnt` / `template-v2-lines.pbnt`
  (the optional `LINE` chunk of layered templates) / `template-v2-book.pbnt` (the chunk's trailing
  style byte, written only for coloring books) must keep decoding (they are never regenerated). Add
  a fixture file and decode test for every new `formatVersion`, chunk or trailing field.
- New template data goes in an extension chunk (FourCC tag, flags, length; see
  `TemplateCoding.swift`). Old readers skip optional chunks; flag a chunk `required` only when
  ignoring it would misrender the painting. Bump `Template.formatVersion` only when the base layout
  itself changes.
- Bump `TemplateGenerator.pipelineVersion` in the same commit as any change that alters generated
  output for identical inputs and settings; templates record it.
- Decoders treat files as hostile: check every count against the bytes left before allocating, and
  every span, reference and coordinate (inside the canvas) in `Int` arithmetic before anything
  indexes with it. PaintCore is compiled `-Ounchecked` in release, so a missed check is a silent
  out-of-bounds read; the truncation, random-corruption and crafted-reference tests in
  `TemplateCodingTests` and `LineArtCodingTests` guard this.
- An artwork's recorded settings are what regeneration uses: a `meta.json` without `settings` or
  `lineArt` (saved before line art existed) means classic lines (`Artwork.settingsBeforeLineArt`,
  the `GenerationSettings` decoder), never the current default style. Its `lineArt` and `tuning`
  decode tolerantly (a retired layered `lineArt` is the coloring book's defaults); never rename a
  settings field. A setting the app retires leaves UserDefaults at launch
  (`Preferences.removeRetiredSettings`), so nothing unseen shapes new paintings.
- A file from a newer app is never reset or rewritten: it throws a "newer" error
  (`Template.CodingError.newerFormat` or `.requiredExtension`, whose `requiresNewerReader` is true;
  `PaintProgress.CodingError.newerVersion`) and the app says it needs an update. `PaintProgress`
  fields are append-only (readers ignore trailing bytes); bump its `formatVersion` only when an
  existing field changes meaning. Bump `Artwork.currentFormat` when older apps must not open or
  rewrite an artwork folder (a template `formatVersion` bump or a new required chunk).
- Damaged data never traps: progress that doesn't fit its template is a recoverable error
  (`PaintingSession.init(template:progress:) throws`), and `LibraryTests` cover each failure. A
  progress file that can't be read right now (an I/O or protection error) throws
  `Library.OpenError.unreadable` and is kept, never replaced with fresh progress
  (`LibraryTests.unreadableProgressIsKept`).
- Paint nicknames are derived at load, never stored (`ColorNickname.assign(_:seed:)`, seeded from
  the artwork id): editing the vocabulary table, `ColorNickname`'s constants or `ColorName`'s
  thresholds renames the colors of saved paintings, so treat them like a file format
  (`ColorNicknameTests.parrotsPaletteGetsDistinctNicknames` pins one assignment).

## App rules

- Deployment target iOS 26.0, iPhone + iPad. Build with Xcode 26.6 (CI). Swift 6 with
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and approachable concurrency: app types are MainActor
  by default; mark pure/background helpers `nonisolated` and CPU-heavy async work `@concurrent`.
  PaintCore is a separate module (nonisolated). The test targets have neither setting: their suites
  that touch app types are `@MainActor`.
- `MemberImportVisibility` is enabled: every file that touches members of a type from another module
  must import that module itself (`import PaintCore`, `import simd`, …).
- Closures handed to system APIs that call back on arbitrary threads (AVFoundation, Core Haptics,
  Metal completion handlers, NotificationCenter with a queue) must not be MainActor-isolated — form
  them in `nonisolated` code or they trap at runtime under Swift 6.
- Liquid Glass design language (`.glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)`,
  `.glassProminent`), SF Symbols, Dynamic Type, dark mode, VoiceOver labels.
- Identity: the app is called **Paint by Moonlight** (display name, gallery title, permission texts,
  PDF footer; App Store subtitle "Turn any photo into a painting"). Pipo is only the working name
  and never appears in the product; target, module and repository keep the PaintByNumber names.
  Native first: system controls stay system controls. Every new `.glassProminent` button gets
  `.tint(Theme.signature)`; `Theme.gold` is for stars, sparkles and the crescent only; titles and
  numerals use New York, buttons and body text SF. The design system, tokens, canvas sheet and app
  icon: `App/CLAUDE.md` › Design.
- Localization: every user-facing string of the app target lives in
  `Resources/Localizable.xcstrings` (English, no translations yet: the translator hand-off), the
  Info.plist texts in `Resources/InfoPlist.xcstrings` (keyed by the `INFOPLIST_KEY_*` names);
  `PaintCore` and `pbn` stay English. Three code forms, and nothing else: a SwiftUI literal with no
  interpolation (`Text("Done")`, `Button`, `Label`, `.navigationTitle`, …: the literal is the key);
  `String(localized: "key", defaultValue: "…\(x)…", comment: "…")` for an interpolation, a count or
  a non-SwiftUI destination (dotted keys; the comment says where it shows and what the arguments
  are); `String(localized: "literal")` for a plain string. `Text(someString)` is verbatim, so build
  such strings with the second or third form first. Counts are catalog plurals (`one`/`other` with
  `%lld`; never an `"s"` suffix); several arguments use numbered placeholders (`%1$@ %2$lld`);
  durations, percentages and numbers go through `.formatted(...)` or `PaintingTimeText`'s catalog
  units, never concatenation; errors are `LocalizedError`; no conditional or `+` of literals in a
  SwiftUI literal position (one call per literal). Helper views taking a `LocalizedStringKey` are
  listed in `WRAPPERS` and counted in `KEY_TYPE_DECLARATIONS` of the checker. The one runtime key
  family is `sample.<id>`, the library's titles (checked against `library.json`). A new string needs
  its catalog entry, written by hand (`"comment"`, `"extractionState": "manual"`; an explicit key
  also `localizations.en`, with plural forms for a count): Xcode extracts nothing
  (`STRING_CATALOG_GENERATE_SYMBOLS = NO`: "Finished" and "Finished!" would collide).
  `tools/strings_check.py` (CI runs it) fails on any drift between sources and catalogs and on
  prose-like literals that bypass localization (`ALLOWED_LITERALS` / `VERBATIM_FILES` hold the
  justified exceptions); `LocalizationTests` checks what ships. After UI text changes, read the
  screenshots of every scenario whose name contains `long-text` (doubled strings; raw placeholders
  like `1$lld` in the first copy are expected).
- Demo scenarios: `-demo <name>`; the catalogs are the doc comments of `ShellDemo`, `PaintDemoView`
  and `RootView`. A screenshotted scenario is one `name@seconds` line of `ci/scenarios.txt` (no
  comments; `@seconds` is only the timeout; the file merges as a union) and calls `DemoMode.markReady()` once its content is on
  screen. Demo mode is DEBUG-only: `DemoMode`, `ShellDemo`, `PaintDemoView`, `SyntheticTemplate`,
  `LineArtMapsCache` and `DemoTemplateCache` are wrapped in `#if DEBUG`, and every other reference
  (`RootView`, `Library.forLaunch`, `AppShellView`, `SettingsView`, `LineArtInputs`,
  `ArtworkFactory`, …) sits in an `#if DEBUG`
  block, so Release builds and the IPA have no `-demo` switch. New demo code follows the same rule;
  `ci/check_release.sh` (run by the iPad job on a Release build) fails if a Debug-only type name
  shows up in the Release binary.
- Done means: a test for each new behaviour in the right target (Swift Testing in
  `Tests/PaintCoreTests` and `App/PaintByNumberTests`, XCTest in `App/PaintByNumberUITests`), a demo
  scenario for any new screen worth a CI screenshot, catalog entries for its strings, VoiceOver
  labels and values, Dynamic Type, Reduce Motion and dark mode for every new control, and the
  CLAUDE.md pointers kept current. No stubs or flags hiding unfinished work.
- Ship hygiene: `Resources/PrivacyInfo.xcprivacy` is the privacy manifest (no tracking, no collected
  data; required-reason APIs: UserDefaults `CA92.1`, file timestamps `C617.1` for purging the app's
  own export folders). Using another required-reason API (file timestamps, disk space, boot time via
  `systemUptime`/`mach_absolute_time`, active keyboards) means adding its category and reason code
  there; `AboutTests` fails when the sources of the app or of `Sources/PaintCore` (not `pbn`) and
  the manifest disagree. Export compliance (`ITSAppUsesNonExemptEncryption`) and the app category
  are in `Config/Info.plist` and the target's `INFOPLIST_KEY_*` settings.
- Picture library: public-domain pictures only, under hard license rules (reject on any doubt);
  `library.json` is its single source of truth. Read `docs/picture-library.md` before adding,
  replacing or removing a picture.

## Licensing and credits

Ported or adapted code, the methods the pipeline implements and the bundled models (with their
weights' license) are credited in Settings › About › Acknowledgements (`Acknowledgements.swift`) and
`ACKNOWLEDGEMENTS.md`, which `AboutTests` keeps in step: add an entry when adding any.
`Vector/Earcut.swift` and `PolyLabel.swift` are ISC (Mapbox); nothing else is third-party code, and
nothing is GPL. The models' weights are Apache-2.0 (HED, ControlNet) and MIT (the line-drawing
network); the evidence is in `tools/models/convert_*.py`. `Vector/CurveFitter.swift` is a clean-room
implementation of the method in Selinger's paper "Potrace: a polygon-based tracing algorithm"
(2003), written from the paper alone (provenance: `docs/cleanroom-curve-fitter.md`); it replaced a
GPL translation of potrace's source and is credited as a method. Never consult potrace's source, or
any port of it, when changing the fitter: work from the paper.

## CI feedback loop (no Xcode locally)

1. Commit, push to a branch: `git push -u origin HEAD:<branch>` (CI runs on every branch).
2. Run `CI_BRANCH=<branch> ci/fetch.sh <sha> <outdir>` in the background; it waits for the report CI
   publishes to the ref `refs/ci-shots/<branch>` (not fetched by a clone) and unpacks it:
   `STATUS.md` (job results and verdicts), trimmed logs, `core/` (tests, strings check,
   `regression/` with its table and `sheets/<regime>/<sample>.jpg`), and per device `errors.txt`
   (compiler errors), `shots/*.png`, `*-app.log` (the app's os_log), `*-steps.log` (readiness,
   crashes), `test-app.log` (the app's library, demo, canvas and feedback lines during the tests),
   test results and `attachments/`. iPad is the primary device: every push builds Debug on
   a 13" iPad Pro simulator, screenshots, tests, builds Release for `ci/check_release.sh` (problems
   land in `ipad/errors.txt` too), and benchmarks the pipeline (`ipad/bench.txt`, only when
   `Sources/` or `Package.swift` differ from `main`). The iPhone job (an iPhone 17 Pro) runs on
   `main`, via workflow_dispatch with `iphone: true`, or for a commit whose message contains
   `[iphone]`.
3. Turnaround is about 70 min (the iPad job takes about an hour of its 75-minute cap, so a slow new
   UI test needs a matching saving), longer when branches queue (only 5 macOS jobs run at once).
   `ci/fetch.sh` waits up to 100 min. A newer push to the same branch cancels the older run, which
   then never reports. Work on something else while it runs.
4. Read errors/screenshots, fix, repeat. Batch fixes; one validated push beats many guesses.
5. Device builds: every push to `main` also archives an unsigned Release IPA (version `1.0.<run>`),
   publishes it as the `build-<run>` prerelease (the five newest are kept) and rewrites the
   SideStore source on the `sidestore` branch (`ci/sidestore_source.py`), which users add in
   SideStore as
   `https://raw.githubusercontent.com/pbordjadze/paint-by-number/sidestore/source.json`.

**Branches.** `main` is the default and shipping branch (iPhone job, IPA, SideStore source; the
benchmark's base). Work on `claude/<topic>` branches and merge into `main`; once merged, the branch
and its report ref can go. CI owns `sidestore` (never delete or push it) and the `refs/ci-shots/*`
reports. Local `main` may lag: fetch before comparing.

## Conventions

- Swift 6 language mode, strict concurrency. Core types are `Sendable` value types.
- Hot loops use `withUnsafe(Mutable)BufferPointer` + `Parallel.forEachBand`; wrap raw pointers in
  `UncheckedSendable` to share them with workers writing disjoint ranges.
- Color math happens in OKLab (`ColorScience`). Distances in true OKLab ≈ ΔE (palettes,
  `PaletteColor.oklab`, `ColorScience.distance`); 0.02 ≈ just noticeable, and paints are never
  closer than that (`SegmentationParameters.jnd`). Segmentation grids
  (`WorkingImage.okLab(_:chromaScale:)`) stretch the chroma axes by
  `SegmentationParameters.chromaScale` (1.6 × `PipelineTuning.colorfulness`): a distance there is
  not ΔE; unscale it (`PaletteBuilder.Separation`'s `metric`) before comparing it with one.
- Numbers are sized only by `LabelSizing` (`Model/LabelSizing.swift`): SVG, `TemplateRasterizer`
  (thumbnails, PDF) and the Metal canvas all use it and never drop a number. The pipeline gives
  every label room for its digit count (raster `minRadius(digits:)`, vector `LabelRoom`), so no
  number is smaller than `LabelSizing.minimumFontSize`; `validate(minLabelRadius:)` checks it. Print
  legibility is the PDF exporter's job, not a renderer floor: `PDFExporter.sheets` prints a detailed
  template on overlapping sheets so the smallest number is at least 2.6 pt.
- Canvas units = pixels of the working image (long side min(1100 + 1000 × detail, 1.5 × the
  photo's): `GenerationSettings.workingSize`); origin top-left, +y down.
- Keep `PaintCore` free of Apple-only frameworks (guard any Accelerate/Metal use with
  `#if canImport(...)` and keep a portable path).
- Deterministic output for identical inputs + settings (seeded `SplitMix64`), on every device:
  parallel floating-point reductions must not depend on the core count: fixed-size chunks summed in
  chunk order (`RegionAdjacency.boundarySteps`: 32-row chunks), or each output computed whole by one
  task in a fixed order (`RegionRuns.accumulate`: a region's pixels in raster order); never one
  partial sum per band or core (bands follow the core count).
- Comments explain *why*, sparingly. No dead code, no TODO litter.
