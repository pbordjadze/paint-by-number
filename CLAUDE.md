# Paint by Moonlight — engineering notes

Native iOS/iPadOS 26 app that turns photos into paint-by-numbers templates on-device and makes
painting them fluid and satisfying. Swift 6, SwiftUI (Liquid Glass) shell, Metal canvas.

This file is the map and the rules. An area's reference is its entry type's doc comment (named
below); the tools' docstrings and `Sources/pbn/main.swift`'s header are their manuals; `docs/` holds
the measurements and provenance the code cites.

**App feature notes and gotchas: `App/CLAUDE.md`** (loaded when you read files under `App/`; read it
before planning app work).

## Map

- `Package.swift`: `PaintCore`, `pbn`, `PaintCoreTests`, and the separate `MakingOf`,
  `MakingOfTests`. The Xcode project builds PaintCore from this package (local reference `..`), so
  its flags change the app's builds too (release `-Ounchecked`); its iOS 18 / macOS 15 platforms
  are only a floor (the app's 26.0 is the project's).
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
    `LabelSizing`, `TemplateLineArt`, `RegionRemap`, `SharedPainting` (the `.moonlight` file Send
    Template… writes: a template, its title and, by the painter's choice, its photo), `PaintingTime` (the one painting-time
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
    `LabelRoom` hold; an edge along a painter's line takes the line's path (`EdgeGuides`). `Template.validate` (`TemplateValidation.swift`) is the oracle of `pbn check`,
    the regression gate and the create flow's Debug check.
  - `LineArt/` (`LayeredLines.apply`, `Writing` and `LineEdits`, see Line art), `Auto/` (`AutoSettings`, see Suggested
    settings), `Export/` (`SVGExport`: the headless preview pbn writes for `tools/eval.py`; the app
    prints and shares through CoreGraphics in `App/PaintByNumber/Export`).
  - `Edit/`: `TemplateEditor`, the painter's pen, Cell Edge, Merge, Paint Brush, Bend Line and Move Edge (`reshape`), Move Number, eraser, line eraser, fill, Only
    This Area (`paintArea`), Looks and Edit Paint (looks and repaints, `Recolor.swift`) and the
    retired Color Splitter's splits made to a finished
    coloring-book `Template` exactly and with no image processing (`Lattice` is its exact arithmetic;
    `docs/coloring-book.md` › Edits made to the template itself; a drawn line's paints, the
    photo's colors of the pieces it cuts, are read beforehand by `painted`);
    `EditTrail`, a base with a list of edits laid on it, with undo and redo from kept templates;
    `EditCoding`, the shape of an edit in a file (the app's `refinements.json`).
  - `Refine/`: what Refine's screen makes of a gesture, shared by the app's `RefineView` and
    `pbn refine` (`RefineGestures` with `RefineScreen`: the Pen, Shapes, the Eraser, the Line
    Eraser, Fill's taps; `RefineGeometry.swift`: `PenPath`, `PenAssist`, `ShapePath`, `SnapLines`,
    `LineChains`; `RefinePractice`, the Tool Guide's practice picture, drawn and laid as edits; `RefineCells`,
    the cells VoiceOver offers and its actions' edits).
    The app keeps only drawing (`PenPath.path`) and its toolbar.
- `Sources/pbn`: `main.swift` is the usage header (the manual) and the dispatch; `Options.swift`
  (flags; the hand-kept `Fields` tables of `--line-art`/`--tuning` keys), `Inputs.swift`,
  `Commands.swift`, `Edit.swift` (`pbn edit`), `Refine.swift` (`pbn refine`), `Practice.swift` (`pbn practice`, the Tool Guide's picture for it), `Bench.swift`, `Metrics.swift` (stats.json), `LineArtReport.swift` (its
  `lineArt` block; the field docs define the drawing metrics), `Rasters.swift`, `Timing.swift`.
- `Sources/MakingOf` (depends on PaintCore only; Debug `-O`, Release checked): the making-of show,
  which plays after Start when Settings › The Making-of is on (off by default): `FieldShow` (its and
  `ShowFrame`'s doc comments say what the app's view draws), each pipeline step grown from seeds
  over the painter's photo. It is built once from a generation's `ShowPictures`, the finished
  template (`ShowTemplate`), the strict `ShowSpec` (`making-of.json`, bundled in Release too) and a
  seed, and then `frame(at:)` is a pure function of the time. Inside: `ShowLayers` and `Compositor`
  (the pictures, `RevealStyle`: what a pixel looks like), the fields (`Geodesic`, `FieldNoise`,
  `FieldMath`, `FieldSteps`), `PaintSeeds`, `Outlines` and `Timeline` (when and where,
  `ScheduleStyle`). Every random draw is a `ShowStreams` stream of SplitMix64; discrete decisions are
  exact (integers, `+ - * /`, `sqrt`) and the pictures are within measured tolerances of the Python
  reference `tools/factory/making_of_{exact,inputs,layers,compose,reveal,fields}.py`, which
  `making_of_clip.py` plays with Pillow (stills and video). The first show, with a crew, is gone: its
  Swift port was retired on October 23, 2026, and its Python left with the Marginarium (below).
  `making_of_pets.py` keeps its planner, SplitMix64 and streams, which the fixtures' inputs are
  still drawn with; what the crew show shared and the field show doesn't use (`Arrival`'s visits,
  `PaintFlow`, `StopWeights`, `StrokeSchedule`'s traces) stays, pinned by the fixtures, until it
  leaves with its checks (backlog). Fixtures in
  `Tests/MakingOfTests/Fixtures/` are written by that Python and replayed by the tests:
  `show-small/inputs-small.json` by `making_of_inputs.py` (recipe in `test_making_of_inputs.py`),
  `reveal-small.json` by `making_of_reveal.py --fixture`, `layers-small.json` and
  `compose-small.json` by `tools/tests/test_making_of_layers.py --write-goldens`, and
  `fields-small.json` by `tools/tests/test_making_of_fields.py --write-goldens`. `python3 -m unittest discover -s tools/tests -p 'test_making_of_*.py'` (numpy,
  Pillow; CI `core`) fails when a committed fixture is not what the Python makes now.
- `Tests/PaintCoreTests` (Swift Testing; helpers in `TestSupport.swift`, `TestScenes.swift`,
  `ColorTestSupport.swift`). `Fixtures/`: `template-*.pbnt` are frozen (Saved data), and so is
  `edits-v1.json` (every kind of edit, as `refinements.json` keeps them: `EditGoldenTests`);
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
- `ci/` scripts and `.github/workflows/ci.yml`: jobs `core` (Linux: PaintCore tests, the feedback relay's
  tests, quality regression, string catalog), the simulator matrix `apple` (every push: `ipad`, Debug build,
  screenshots, unit and Settings UI tests, Release check, benchmark; `ipad-ui`, the other UI tests;
  on `main`: `iphone`, all of it; a branch's `[compile]` or `[test …]` runs one entry instead, CI
  feedback loop), `ipa` (unsigned IPA, SideStore source) on `main`, `report`
  (`ci/report.py` writes `STATUS.md`); `.github/workflows/testflight.yml`, the TestFlight upload
  (on request; its header says how); `.github/workflows/feedback-relay.yml`, the deploy of
  `feedback-relay/` (see below); `.github/workflows/qa-explore.yml`, exploratory QA on request: an
  agent uses the app in a simulator through Maestro's MCP server and reports what it finds
  (`ci/qa/`: `explore.md` its brief, `qa.py` the probe, relay and report tools, `prepare.sh` the
  feedback host's block and the photo; the workflow's header is the manual). The workflow and
  `ci/qa/` are generated from the copy all the apps share (painting-company row 152): change them
  there and sync, never here. Each device and build has one queue (relay runs share one), and a new
  dispatch cancels the run waiting in it: look first, and give the run a `label`. Every run holds
  a macOS runner for up to two hours, out of the five CI shares. What a session taught goes into
  the brief (its By design list, its tools' notes) for the next, in the shared copy.
  `.github/workflows/store-screenshots.yml` puts the App Store screenshots on the version being
  prepared (`ci/store_screenshots_upload.py`), reading them from the private feedback
  repository's `store-slides` branch, since the slides show the painter's own photos;
  `.github/workflows/store-listing.yml` fills in its text, categories, age rating, review notes
  and accessibility labels from `ci/store-listing.json` (`ci/store_listing.py`).
- `feedback-relay/`: the Cloudflare Worker behind Give Feedback's Send (`worker.js`'s header is its
  contract and manual; `worker.test.js` runs with `node --test feedback-relay/worker.test.js`, in
  CI's `core` job too). It files each report in the developers' private GitHub repository. Its
  deploy workflow needs the secrets `CLOUDFLARE_API_TOKEN` and `FEEDBACK_GITHUB_TOKEN` and writes
  the Worker's URL to its run summary, which `FeedbackUploader.endpoint` must match.
- `docs/`: notes the code cites: `auto-tuning.md` (and `auto-corpus.md`), `coloring-book.md`,
  `writing.md`, `picture-library.md`, `gradient-rings.md`, `cleanroom-curve-fitter.md`. Plans, agent briefs and
  per-agent reports are not committed here (they live in painting-company; a commit message says
  what changed and why); a
  measurement the code relies on goes into its feature's doc or the constant's doc comment.
  Paul's ideas and the backlog are in the private `painting-company` repository (Working with
  Paul › Three layers); `docs/ideas.md` and `docs/backlog.md` only point there.
- The Marginarium, the app's storybook, is gone from the app and the repository (its chapters,
  sprites, tools and public preview). Paul's decision (October 23): the Marginarium is private for
  now; it leaves every build and this repository. Its archive is in the private painting-company
  repository.
- `ACKNOWLEDGEMENTS.md`: credits and license texts (also shown in the app). Tags
  `archive/lineart-research` (`research/lineart/`, which `LineArtSettings`, `convert_hed.py` and
  `docs/coloring-book.md` cite) and `archive/resume-notes` keep unmerged history
  (`git show <tag>:<path>`).

## Line art

`LayeredLines.apply` (stages and constants in its doc comment) turns an 8-bit `EdgeMap`
(`LineArtInput`) into cells bounded by lines, each line in a `LineLayer`. Detect and trace read the
edge map alone; eyes and the subjects' silhouettes enter at the layer stage (`LineLayering.addEyes`,
`addObjects`), where `LineArtInput.contours` decides the outlines; `CellMap` splits the segmentation
along the lines (the strips a line cuts from the blur of a soft edge join the cell beside them, so
no paint shows past an outline: `docs/coloring-book.md` › Soft edges); lines inside cells become
`InteriorStroke`s (`Template.lineArt`). It makes the
**coloring book** (`LineArtSettings.Style.coloringBook`: the default, and every template the app
makes): the drawing as its only lines, on flatter paint
(`SegmentationParameters.coloringBookFlattening`, by style, edge map or not), drawn in full ink over
the paint (`docs/coloring-book.md`). The layered style it grew from is retired: its templates keep
decoding and draw as books, and its recorded settings decode as the book's defaults. Writing (`LineArtInput.writing`: the lines of text Vision
found, `TextFinder`) is traced from the photo itself, painted out before segmenting and drawn as
interior strokes with the numbers kept off it (`Writing`, `LabelKeepOut`; `keepWriting`;
`docs/writing.md`, whose corpus every change to it is judged on); text under 48 px is read on a
finer window and the template marks its strokes (`TemplateLineArt.writingStrokes`, the `WRIT`
chunk), which renderers draw in the paper's tone over a painted dark paint
(`Template.writesOnDarkPaint`). The painter's edits from the
app's Refine (`LineArtInput.edits`, `pbn --line-edits`: lines drawn, the eraser's passes, lines
tapped away, shapes filled, in order) change the drawing the template without them draws, and
nothing else (`LayeredLines.shownLines`, `LineEdits`; `docs/coloring-book.md` › The painter's
edits); a line drawn stays as drawn, as the outline of the areas it closes too (`EdgeGuides`);
without any, a template is byte for byte what it was. A fill keeps the
cell under it, once the lines split the paint, as a detail area (`CellMap.fill`,
`Template.detailRegions`): the photo's color there, merged into nothing, its number down to
`LabelSizing.detailMinimumRadius`. Without an edge map, book settings generate a classic
template; the same maps and settings give the same bytes on any core count.

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
| Refine's gestures, off the device | `pbn refine <photo> <gestures.json> --out <dir> --edges … --lines …`, `tools/refine_sheet.py <dir>` |

- Look at the PNGs with the Read tool. An eval sheet's second row is the raw region raster, a 2×
  `boundaries.png` (best for judging segmentation shapes) and the palette.
- stats.json, decision.json and the file names pbn writes are read by `tools/*.py` by key and name:
  add fields and files, never rename or repurpose them, nor the properties of the PaintCore types
  they embed (listed on pbn's `Metrics`); a field leaves only with its readers.
  `labelsBelowLegibleSize` and `labelRoomUnmet` must be 0.
- pbn has no tests: CI runs `generate`, `check` and `bench`; run `suggest`, `trace`, `names`,
  `edit`, `refine` and `practice` by hand after touching them. A new `LineArtSettings` or `PipelineTuning` field needs its `Fields`
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
- Compiler warnings fail CI (`ci/warnings.sh` on the build logs of `core` and the simulator jobs;
  `main` has none): fix a new one, never silence it.
- "database is locked" from `tools/swift.sh`: another build is using `.build`; wait and retry.
- Scratch output goes outside the repo. Never commit `.build/`, eval output, `tools/node_modules`,
  `.claude/worktrees/` or `.claude/corpus/`. Keep a diff to what the task needs; edits to shared
  files (`Localizable.xcstrings`, `ci/scenarios.txt`) are minimal.
- A tool you write to check or measure your own work (a harness, a preview, a shim) is committed
  before you finish, in `tools/` (or painting-company's when it holds anything private), its
  header saying how to run it: a scratch directory dies with its session (painting-company row 159).

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
  style byte, written only for coloring books) / `template-v2-detail.pbnt` (the optional `DETL`
  chunk of detail areas) / `template-v2-writing.pbnt` (the optional `WRIT` chunk of writing
  strokes) must keep decoding (they are never regenerated). Add
  a fixture file and decode test for every new `formatVersion`, chunk or trailing field. A
  painting sent to someone else (`SharedPainting`, its own format and chunks, read as hostile
  input) follows the same rules: `shared-v1.moonlight` and `shared-v1-photo.moonlight` (the
  optional `PHOT` chunk) keep decoding.
- `LINE` can't grow in place: every reader since 1.0 reads a layer past `color` as a corrupt
  painting (`validateReferences`) and a style byte it doesn't know as layered, whatever the
  chunk's flags (a reader that knows a chunk never reads its `required` flag). A new layer or
  style goes in a chunk of its own, flagged `required` where an older app must not draw it
  otherwise (backlog row 93).
- New template data goes in an extension chunk (FourCC tag, flags, length; see
  `TemplateCoding.swift`). Old readers skip optional chunks; flag a chunk `required` only when
  ignoring it would misrender the painting. Bump `Template.formatVersion` only when the base layout
  itself changes.
- Bump `TemplateGenerator.pipelineVersion` in the same commit as any change that alters generated
  output for identical inputs and settings; templates record it.
- Bump `TemplateEditor.version` in the same commit as any change to what a list of edits makes on
  a given template, and pin its digest (`EditGoldenTests`, never editing a pin or `edits-v1.json`);
  a refined painting's `refinements.json` records it (`TemplateRefinements.editorVersion`).
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
- Paint nicknames are derived at load, never stored (`ColorNickname.assign(_:seed:version:)`,
  seeded from the artwork id), with the frozen vocabulary version recorded per artwork in
  `meta.json` (`nicknameVersion`). Missing or unreadable means 1, never the current version;
  new artworks record `ColorNickname.currentVersion`, regeneration keeps the recorded value,
  and unknown future values round-trip unchanged while resolving to the newest known version.
  Treat each version's table, math, draw and fallback like a file format: never edit them.
  v1 preserves each platform's original libm behavior, not agreement across platforms:
  `ArtworkNicknameTests` pins Apple's current names against a future iOS libm change;
  `ColorNicknameTests` keeps Linux's different v1 pin. `ColorName` remains frozen for v1.
  v2 uses the same table with canonical Q16 anchors and integer distances, weights, multiply-high
  RNG mapping and structured fallback (`ColorNicknameV2`): identical stored OKLab bits, seed and
  palette order give identical nicknames everywhere. New artworks record 2; no migration of v1.
  `ColorNicknameV2Tests` and the app read the same `nickname-v2.json` pins; CI runs the core v2
  suite on Linux and macOS, and the app pins on iOS. `pbn names` and `pbn vocab check` default to 2.

## App rules

- Deployment target iOS 26.0, iPhone + iPad. Build with Xcode 26.6 (CI; named once, in `ci/xcode.sh`, and
  the simulators run its SDK's iOS). Swift 6 with
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
- Taste: every new screen or control, and every one not yet in the release, goes to the
  **Lamplit Table** before it ships (Paul, October 17, 2026): the Lamp's standing jury for the
  app's UI, the Astrologer, Rikyū, the Child at Bedtime, the Hedge Witch, Madeleine and
  Originality (who can only veto). Its charters and how a round runs (a low-effort Opus subagent
  per seat, the charter word for word, blind ballots, every reply kept) are `factory/GUARDIANS.md`
  › The Lamplit Table and `factory/ORCHESTRATOR.md` in the private `painting-company` repository
  (until October 23 on this repository's `claude/vibe-factory` branch, which older comments
  name); a round's brief, replies and decisions go in its `factory/pieces/<piece>/`, and its
  outcome in the commit that acts on it. Its answers are proposals: Paul decides.
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
  screen. Demo mode is DEBUG-only: `DemoMode`, `ShellDemo`, `PaintDemoView`, `MakingOfDemoView`,
  `SyntheticTemplate`, `LineArtMapsCache`, `DemoTemplateCache`, `MainThreadWatchdog`,
  `FeedbackUploadStub` (Debug builds' stand-in for the feedback relay, picked by
  `-feedback-upload`: tests and CI never upload) and `UnlockStoreStub` (the App Store's, for
  every demo and test launch: nothing is bought) are wrapped in `#if DEBUG`,
  and every other reference (`RootView`, `Library.forLaunch`, `AppShellView`, `SettingsView`,
  `LineArtInputs`, `ArtworkFactory`, …) sits in an `#if DEBUG`
  block, so Release builds and the IPA have no `-demo` switch. New demo code follows the same rule;
  `ci/check_release.sh` (run by the `ipad` job on a Release build) fails if a type of a file wholly in
  `#if DEBUG`, or of one Release excludes, shows up in the Release binary (both read from the sources). The Making-of ships (its screen and Settings switch have no
  `#if`; `making-of.json` is bundled, which the same check requires). The Marginarium is in no
  build (the Map), and the same check fails if any of it comes back. Refine is left out of the
  release for now (October 21, until a good one is ready): its button, tip and the gallery's draft
  row under `#if UNRELEASED`, its screen's files left out of Release by the target's Release
  `EXCLUDED_SOURCE_FILE_NAMES` (App/CLAUDE.md › Create flow).
  `UNRELEASED` is what tells SideStore builds from the release: Debug defines it, and the `ipa`
  job archives Release with it defined and the exclusion cleared, so Paul's SideStore build has
  what the release (TestFlight, App Store, the Release check) leaves out. It gates only
  features Paul chose to try before shipping; demo code stays `#if DEBUG`.
- Done means: a test for each new behaviour in the right target (Swift Testing in
  `Tests/PaintCoreTests` and `App/PaintByNumberTests`, XCTest in `App/PaintByNumberUITests`), a demo
  scenario for any new screen worth a CI screenshot, catalog entries for its strings, VoiceOver
  labels and values, Dynamic Type, Reduce Motion and dark mode for every new control, and the
  CLAUDE.md pointers kept current. No stubs or flags hiding unfinished work.
- Monetization (Paul, October 22): free to download; Unlimited Paintings, one non-consumable
  in-app purchase ($4.99; Refine joins it when it ships), lifts the free paintings of the
  painter's own photos (three, one back each day). Library pictures, received and remade
  paintings are always free; no ads, no subscription. StoreKit 2 checks it on the device and
  SideStore builds sell nothing (`UnlimitedPaintings`; App/CLAUDE.md › Unlimited Paintings).
- Ship hygiene: `Resources/PrivacyInfo.xcprivacy` is the privacy manifest (no tracking; the one
  thing the app sends off the device is the feedback a painter chooses to send, declared as
  collected data not linked to them and used only for App Functionality: customer support, other
  diagnostic data, photos or videos; `AboutTests` pins the list and `PRIVACY.md` says the same, so
  a change to what Send uploads changes all three; required-reason APIs: UserDefaults `CA92.1`, file
  timestamps `C617.1` for purging the app's own export folders). Using another required-reason API (file timestamps, disk space, boot time via
  `systemUptime`/`mach_absolute_time`, active keyboards) means adding its category and reason code
  there; `AboutTests` fails when the sources of the app or of `Sources/PaintCore` (not `pbn`) and
  the manifest disagree. Export compliance (`ITSAppUsesNonExemptEncryption`) and the app category
  are in `Config/Info.plist` and the target's `INFOPLIST_KEY_*` settings. `ACCESSIBILITY.md` is
  the page the App Store's accessibility link opens (`ci/store-listing.json`): a change to what the
  app offers with VoiceOver, Reduce Motion, Dynamic Type or without color changes it too.
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
   `STATUS.md` (job results and verdicts, then per simulator job the steps that failed, its test
   counts, each failed test with its first message, tests that passed only when run again, scenarios
   that never signalled readiness, main-thread stalls and crashes), logs (those over 3000 lines
   trimmed), `core/` (tests, strings check, `regression/` with its table and
   `sheets/<regime>/<sample>.jpg`), and per job
   (`ipad`, `ipad-ui`, `iphone`, or the one `compile` or `test`) `errors.txt` (compiler errors), `shots/*.png`, `*-app.log` (the
   app's os_log), `*-steps.log` (readiness, crashes), `test-app.log` (the app's own log lines
   during the run, every category of `Log`), test results and `attachments/`. iPad is the primary
   device, a 13" iPad Pro simulator, its work in two jobs on every push: `ipad` builds Debug,
   screenshots, runs the unit tests and the Settings UI tests, builds Release for
   `ci/check_release.sh` (problems land in `ipad/errors.txt` too) and benchmarks the pipeline
   (`ipad/bench.txt`, only when `Sources/` or `Package.swift` differ from `main`); `ipad-ui` builds
   Debug and runs the other UI tests (the Plan step in `ci.yml` divides them). `iphone` (an
   iPhone 17 Pro: screenshots, unit and UI tests) runs on `main`, via workflow_dispatch with
   `iphone: true`, or for a commit whose message contains `[iphone]`. Simulator builds are arm64
   only. A test that fails runs once more and passes if that run does (`-retry-tests-on-failure`);
   STATUS.md names it, and a flake still needs its cause found. Demo and test launches keep the
   templates and line-art maps they make on disk (DEBUG `DemoTemplateCache`, `LineArtMapsCache`),
   and each job keeps them between runs in the Actions cache (`ci/demo_caches.sh`), keyed by the
   files that make them; on a miss `ipad-ui` makes the UI tests' first (its warm-up).
3. Turnaround is about 30 min on idle runners (both iPad jobs take about that), about 40 when the
   caches miss (a change to the pipeline, the models or the pictures: the screenshots take twice
   as long and `ipad-ui` warms up first), and 60 to 100 under load (the night of October 17: a
   median of 78), since only 5 macOS jobs run at once: a branch push takes 2, `main` 4 (`iphone`,
   about 110 min, is main's longest, cut off at 160). `ci/fetch.sh` waits up to 180 min. A newer
   push to the same branch cancels the older run, which then never reports. Work on something
   else while it runs.
4. Read errors/screenshots, fix, repeat. Batch fixes; one validated push beats many guesses.
   Compile first: `[compile]` in a branch commit's message runs only the Debug and Release builds,
   `ci/check_release.sh`, the SideStore build (Release with `UNRELEASED`, as the `ipa` job makes
   it, which nothing else builds before a merge) and the warnings gate, on one runner with no simulator (`compile` in
   STATUS.md; `core` only builds and checks the strings): about 6 min once a runner takes it (its
   first, October 18), but it waits for one like any macOS job. Run it before asking
   for a full slot. It isn't a slot, but one runs at a time, and never while the branch's own full
   run is going (the push cancels it).
   A UI test's quick try: `[test RefineUITests]` (several classes, or `Class/testMethod`; a run
   started by hand takes `tests`) runs only those UI tests, on the iPad after the Debug build
   (`test` in STATUS.md, instead of every other entry, `[iphone]`'s too; no screenshots, no
   Release; on a cache miss the warm-up first), on one runner like `[compile]`: 17 min for two
   small classes on an idle runner, 12 of them the build (October 29, run 653). A name the
   sources lack fails its Plan step at once (`test/errors.txt` says why); a choice that still ran
   no test fails its Test step. The full run still comes before a merge.
5. Device builds: every push to `main` also archives an unsigned Release IPA (version `1.0.<run>`,
   with `UNRELEASED`: App rules; `[ipa]` in a branch commit's message archives without publishing),
   publishes it as the `build-<run>` prerelease (the five newest are kept) and rewrites the
   SideStore source on the `sidestore` branch (`ci/sidestore_source.py`), which users add in
   SideStore as
   `https://raw.githubusercontent.com/pbordjadze/paint-by-number/sidestore/source.json`, and
   asks the combined source in `pbordjadze/sidestore` to rebuild (secret
   `SIDESTORE_DISPATCH_TOKEN`, issue #1; without it that source catches up on its 15-minute
   schedule). TestFlight builds are separate and on request: the `TestFlight` workflow archives,
   cloud-signs with an App Store Connect API key and has App Store Connect validate the app; Run
   workflow from `main` with Upload ticked uploads it (version `MARKETING_VERSION`, build
   `<run>.<attempt>`) and, once App Store Connect has processed it, puts it in the external
   Friends & Family group (public link on) with its What to Test and submits it for Beta App
   Review (`ci/testflight_testers.py`; the `TestFlight testers` workflow does the same for a build
   by hand); a push to a `claude/testflight-dryrun*` branch (which CI ignores) is a dry run of its
   commit. The repository is
   public, so GitHub's standard runners cost no minutes; the limit is 5 macOS jobs at once.

**Branches.** `main` is the default and shipping branch (`iphone` job, IPA, SideStore source; the
benchmark's base). Work on `claude/<topic>` branches and merge into `main`; once merged, the branch
and its report ref can go. CI owns `sidestore` (never delete or push it) and the `refs/ci-shots/*`
reports. Local `main` may lag: fetch before comparing.

**The night train.** Several small branches through one full run, then into `main` as one push;
the train holds one CI slot. Whoever starts it picks who boards: branches reviewed (the last
commit's message carries the review's notes, which the train's merge keeps), green on a compile
check, and touching different files. A conductor session (on Sonnet) runs `ci/train.sh make <name>
<branch>…` (merges each into `claude/train-<name>`, fresh from `origin/main`, leaves off one that
conflicts, and pushes), waits with `CI_BRANCH=claude/train-<name> ci/fetch.sh`, and on green runs
`ci/train.sh land <name>`: `main` fast-forwards to the train, the one merge of that `main` run (it
refuses a red, stale, compile-only or test-only report, or a `main` that moved: make the train again). On red,
`ci/train.sh who <name> <path>…` names the branch that changed the failing file; the conductor
makes the train again without it, and that branch goes back to its session. The conductor reports
each step to the session that started it.

## Working with Paul

Paul talks to each session himself. When a session ships, gets blocked or needs Paul, it tells
him itself, with a push notification once he has gone quiet.

- **Three layers** (October 23). What Paul advertises (the App Store app); what is public if you
  dig (this repository and the SideStore build); and what is private: the
  `pbordjadze/painting-company` repository holds the backlog, his ideas and words, plans, the
  Lamp and its rounds, the chronicles and the Marginarium, and its CLAUDE.md the rest of how he
  works. Nothing of it comes here: a new commit, comment or doc cites it ("painting-company row
  12") and quotes no one; quotes already here stay. A session that needs it attaches it
  (`add_repo`).

- **Merging is standing permission, given once.** When a branch's CI is green, its review is done
  (below) and the change is what Paul asked for, merge it into `main` without asking (a docs-only
  branch, `[skip ci]`, once its review is done: it has no CI to wait for). Put
  anything not yet chosen for the release behind `#if UNRELEASED`, so it reaches his SideStore
  build only. Don't wait for a "yes".
- **A fresh reader before every merge.** Before merging into `main`, have a reviewer that didn't
  write the code read `git diff origin/main...HEAD` (the `/code-review` skill, or an Opus
  subagent). Fix what it confirms; anything large or design-level goes to Paul. The merge
  commit's message lists what the review found and what was fixed. No PR, no
  extra CI run. A commit message holds CI's tags only to mean them: GitHub runs nothing for a
  head commit with `[skip ci]` (or `[ci skip]`, `[no ci]`, `[skip actions]`, `[actions skip]`, a
  `skip-checks: true` trailer) anywhere in its message, quoted too, and `ci.yml` reads
  `[compile]`, `[test …]`, `[iphone]` and `[ipa]` the same way on branches.
- **Still ask first** before a TestFlight or App Store upload, a change to the app's name or
  icon, and deleting or retiring anything Paul made or named.
- **One merge per `main` run.** Every push to `main` takes 4 of the 5 macOS runners for about
  45 minutes. While main's run is going, queue merges, then merge them together.
- **Model choice.** Taste, design, writing and review stay on Opus. Mechanical work (watching
  CI, reading transcripts, fixtures, renames) goes to Sonnet or Haiku subagents. Only Paul
  lowers a session's model or effort.
- **CI etiquette.** One branch in CI across all sessions while `main` runs, up to three while it's
  idle: look at the CI runs queued and in progress (GitHub's Actions list, by branch) before a
  push. Throwaway branches queue behind anything Paul called a must-have.
  Branch pushes never carry `[iphone]` unless Paul asks for it. Docs-only commits carry
  `[skip ci]`. Hold small tweaks to a branch whose CI is running and push them
  together when it reports: every push cancels the run before it. A slot is freed by a green
  report: merge, and any further push queues again unless it fixes a red run.
- **Paul's word counts once.** His words in your session, or his comment on a page a session made
  for him, are his direct word for anything that can be undone. For what can't, the page's card
  names the exact action, and his comment on that card counts. If auto mode still blocks the
  action, ask Paul to repeat it in your session.
- **Echo before you act** on names, characters, lore, identity or anything that removes
  something. Restate it in one line ("Heard: merge Madeleine into the teacher, keep both") and
  wait for his yes. Phrases like "replace X with Y" are the ones to check.
- **Voices stay distinct** (Paul, October 23: "having agents write in their own voice and not
  mimicking mine is good. So then it can just kind of be clear when it's me writing"). Write as
  yourself: clear, precise and recognizably not Paul. Never imitate his voice or put words in his
  mouth: quote him verbatim and attribute it, as the backlog's *Paul's words* do (in
  painting-company; new text here quotes no one, Three layers). Text he'll send
  as his own (a message, a post) is a draft for him to change, and your report says so; the app's
  copy keeps the app's voice. Nothing already written needs rewriting for this.
- **Propose, don't start.** Any session (and the Lamplit Table, as a round's last question) may
  propose new work it noticed: one short `new` row in the backlog (what, why, size, who
  thought of it), at most one a night, keeping to its own topic, and its next report to Paul names
  the row. Paul signs off on it. Small fixes inside a session's own task aren't proposals.
- **Reports** to Paul carry the row #, branch@sha, pushed or not, the CI state and the one thing
  needed. No "still waiting" pings.
- **Times are Eastern.** Every time a session gives Paul (a report, a page, a notification) is
  America/New_York, labelled ET, never UTC, and so are the dates in reports, commit messages and
  docs; a time he gives ("remind me at 9", a deadline) is ET too, scheduled with
  `CRON_TZ=America/New_York`. Logs and CI keep their own clocks.
- **Audits** fix what they find, unless the file is in another session's open branch (the
  branches in CI and those Paul named); a change to one of Paul's own picks goes on a card before
  it's built.
- **Hand off at about 400k tokens** of context: start a fresh session with a brief of the rows,
  branch@sha, CI state, open questions to Paul, pending check-ins and what's next (the shape of
  painting-company's `.claude/skills/front-desk/SKILL.md` › Hand-offs), and tell Paul its id.
- **Backlog commits.** A session adds and updates its own rows in painting-company's `backlog.md`
  and commits them straight to that repository's `main`, fetching first (several sessions write
  it). It runs no CI, so nothing there waits on a night train.

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
  number is smaller than `LabelSizing.minimumFontSize`; `validate(minLabelRadius:)` checks it. A
  detail area (`Template.detailRegions`, a shape the painter filled) has its own floor, about half
  (`detailMinimumRadius`, `detailMinimumFontSize`): every renderer passes `detail:` for its
  labels, and the pipeline and `validate` judge each region by its own. Print legibility is the
  PDF exporter's job, not a renderer floor: `PDFExporter.sheets` prints a detailed template on
  overlapping sheets so the smallest number is at least 2.6 pt (a detail area's 2 pt).
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
