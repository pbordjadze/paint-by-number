# App notes

The `PaintByNumber` app target. The root `CLAUDE.md`'s App rules apply (platform and isolation,
identity, localization, demo mode, done means); this file is the app's map and gotchas, and a type's
doc comment is the reference for its feature. It sits outside `App/PaintByNumber/`, whose
synchronized folder would bundle it into the app.

## Gotchas

- The inline `PhotosPicker` runs out of process: never put it inside a ScrollView (UIKit can't
  arbitrate their pans across the process boundary: neither scrolls). It stays flush with the page's
  left edge, the window's unless a safe area insets it (edge to edge on compact widths, its card
  docked there on wide ones): inset from both the left and the top, its photo grid ignores taps on
  iPhone for its first ten seconds or so, and a painter's iPad ignored them too, though the iPad
  simulator doesn't (`PhotoSourceView`; `CreateFlowTests` picks an inline photo on both devices
  and checks the left edge).
- `ArtworkPaintingView` is pushed with a zoom transition whose swipe-down and pinch dismissal it
  turns off: they stole canvas gestures (`PaintingNavigationTests` guards this). It shows the
  painting only once the push has landed: the transition lays the screen out every frame, and
  the painting screen rendered at each frame (hundreds of renders) stopped CI's simulator
  answering UI tests for up to half a minute.
- The create flow's preview turns off iOS 26's swipe back from anywhere on a pushed screen
  (`ContentSwipeBackOff` in `TemplatePreviewView`): it took the sliders' and the comparison's
  drags and left for the photo step. The edge swipe and Back still go back.
- A presentation's content only sees state its presenter's body read: `AppShellView.body` reads the
  create flow's photo, title and identity up front, or the flow opens without its photo.
- `CanvasUniforms`, `RegionState` and `GlyphInstance` are mirrored by hand in `Shaders.metal`:
  change both in the same order, 16-byte vectors only
  (`CanvasRenderTests.shaderStructLayoutsMatchMetal` pins the strides). No shader reads
  `CanvasUniforms.background`: it carries the backdrop to `TimelapseFrameRenderer`'s clear.
- The shaders hold no paper, ink or accent literals (the brush and the paint sheen keep theirs): the
  chrome colors are uniforms (`CanvasUniforms.setChrome`, `select`).
- Exhaustive switches: `PaintTips.signal(for:isStroking:)` and `FeedbackEngine.handle` over
  `PaintEvent`.
- Strokes report paint many times a second, so each tip is invalidated at most once per launch and
  donations are capped per event and launch (`PaintTips.donate`).
- `AboutTests` and `LocalizationTests` read repository files through `Fixtures.repositoryRoot`
  (`#filePath`): `ACKNOWLEDGEMENTS.md`, the string catalogs, `tools/models/convert_*.py`,
  `Sources/PaintCore`; moving those breaks them.
- Nicknames reach the UI as variables shown verbatim, never as literals, so the string checker needs
  no exceptions; they are English data, shown only when the app runs in English
  (`ColorNameText.nicknamesAvailable`).
- Core ML models run `.cpuOnly` (the Neural Engine and GPU round differently per chip); the target
  has `COREML_CODEGEN_LANGUAGE = None` and loads the `.mlmodelc`s by URL.
- Every template the app makes (new paintings, the first-launch starters, the gallery demos' seeds)
  is a coloring book, so `ArtworkFactory.template` runs the edge detector for each; only the classic
  `paint*` demos ask for classic lines.
- Synchronous file IO, decoding and rendering go through `Background.run`, off the main actor.
- Vision finds no subjects or eyes on CI's simulators: `ObjectFinderTests` and `EyeFinderTests` bite
  only on a device.

## Layout (`App/PaintByNumber/`)

- `App/`: `PaintByNumberApp`, `RootView`, `Preferences`/`SettingsKey`, `Theme`, `LineWeight`,
  `PreviewStyle`; DEBUG `DemoMode`, `ShellDemo`, `MainThreadWatchdog`.
- `Model/`: `Library` (@Observable, in the environment), `ArtworkStore` (file IO), `Artwork`,
  `ArtworkFactory` (photo → template), `PaintingSession`, `PaintProgress`, `PaintingAutosaver`,
  `Sample`, `GalleryQuery`, `IncomingFile`, `ColorNameText`, `PaintingTimeText`, `TemplateCounts`,
  `Background`, `Log` (every logger; CI's `*-app.log`); DEBUG `DemoTemplateCache`.
- `Generation/`: `PhotoLoader`, `SubjectImportance` (Vision), `EdgeDetector`, `EyeFinder`,
  `ObjectFinder`, `TextFinder`, `LineArtInputs`, `TemplateRefinements`; DEBUG `LineArtMapsCache`.
- `Canvas/`: `CanvasView`, `CanvasRenderer`, `CanvasScene`, `RenderContext`, `Shaders.metal`,
  `CanvasTypes.swift`, `LineStyle.swift` (`ClassicLook`, `ColoringBookLook`, `DrawableLineArt`),
  `CanvasSnapshot`, `TimelapseFrameRenderer`, `CanvasAccessibility`, `DigitAtlas`; DEBUG
  `SyntheticTemplate`.
- `Export/`: `TemplateRasterizer`, `PDFExporter`, `TimelapseExporter`, `ArtworkExporter`
  (`ArtworkExports.swift`), `ImageCodec`.
- `Features/`: `Create/`; `Refine/` (`RefineView`, `RefineCanvas`, `RefineGeometry`); `Gallery/` (`AppShellView` the shell, `GalleryView`, `ArtworkPaintingView`
  the painting host, `PaintingRecoveryView`, `ImageCaches.swift`, `Toast`); `Paint/` (`PaintView`,
  `PaletteBar`, `PaintChromeState`, `PaintCommands`, `PaintTips`, `PaintSpeech`, `PhotoPeek`,
  `CompletionBar`, DEBUG `PaintDemoView`); `Feedback/` (the painter's feedback on a painting, see
  Giving feedback); `Settings/`; `Share/`.
- `Feedback/` (haptics and sound, not the painter's feedback): `FeedbackEngine`, `ToneSynth`,
  `PaintingMelody`, `HapticsPlayer`, `SoundPlayer`.
- `Resources/`: asset catalog, `Localizable.xcstrings`, `InfoPlist.xcstrings`, `Models/` (the two
  `.mlpackage`s), `Samples/` (`library.json` and the pictures), `PrivacyInfo.xcprivacy`.
- `App/Config/Info.plist` holds what the generated plist can't express: the image document type, the
  scene manifest, ProMotion on iPhone.

## Tests and demos

- `PaintByNumberTests`: Swift Testing, hosted in the app, which keeps a throwaway library
  (`DemoMode.isTestHost`). Shared helpers in `Fixtures.swift` (`waitUntil`, `record`, `mosaic`,
  `rasterize`, `PixelReader`, `repositoryRoot`, `sample`: a template of a library picture).
- `PaintByNumberUITests`: XCTest launching demo scenarios (`-demo`) with `-demoFixedPictures`,
  `-tracePaper`, `-tracePhotoPeek`, `-openFile`, `-NSDoubleLocalizedStrings`,
  `-UIPreferredContentSizeCategoryName`; shared helpers in `UITestSupport.swift`. iPad-only tests
  (menu-bar keys, landscape) skip on iPhone, and the system-picker tests skip where synthesized taps
  can't reach the picker. `LongTextTests` keeps each screen's controls, the color name and the toast
  on screen under doubled strings.
- On CI's iPad simulator the screenshots take about 8 minutes, the unit and Settings UI tests about
  8 (job `ipad`), the other UI tests about 22 (job `ipad-ui`: a slow new UI test lengthens every
  push's wait). Demo and test launches seed their pictures from templates kept on disk (DEBUG
  `DemoTemplateCache`, beside `LineArtMapsCache`'s maps; CI keeps both between runs, so a test
  that needs a photo no cache has seen makes one, as `LineArtInputsTests` does): the line-art
  models take 10 to 40 s a picture there, and a UI test waits for its seed.
- Demo launches (screenshots, UI tests) run `MainThreadWatchdog`: a main thread that stops
  answering for 2 s has its stack logged every 5 s until it answers (category `demo`, in
  `test-app.log` and the screenshots' `*-app.log`), and STATUS.md lists each stall's length.
- Demo scenarios (catalogs: `ShellDemo`, `PaintDemoView`, `RootView`): names containing `dark` are
  captured in dark appearance, `long-text` ones with doubled strings; failure states have scenarios
  (`gallery-damaged`, `gallery-timelapse`, `paint-unavailable`). Demo launches and the test host
  reset TipKit and hide every tip except in `paint-tip`. The scenarios a viewer judges the app by
  show the library by position; the rest use `ShellDemo.fixedPictures`.

## Painting screen

- `PaintingSession` (@Observable: painting rules, tap tolerance, drag painting, undo, per-color
  progress, events) drives the canvas through `PaintingCanvas`; `PaintProgress` is what is saved.
  The app is single window: one live session per painting.
- Every fill changes `progress` and `remainingByColor`, so `PaintView`'s body reads neither: it
  reads `isComplete`, `isStarted` and `completedColors`, written only when they flip, and the
  per-fill views read the rest themselves (the badge's `ProgressGroup`, `PaletteBar`). The
  canvas draws on the main thread too: keep per-fill work in small views or off it.
- Events: `PaintingSession.onEvent` has three observers registered when the screen appears:
  `FeedbackEngine.attach` (haptics, sound), `CanvasView` (the finishing shine) and
  `PaintChromeState.observe` (undo registration, swatch shake, tips, VoiceOver announcements); the
  canvas also gets direct `PaintingCanvas` calls.
- Palette (iPad first): `PaintView.PaletteLayout` wraps the palette into rows (bottom) or columns
  (trailing edge of wide windows) so every color shows at once, filling across the bar before
  along it (`PaletteBar.lanes`: rows read 1 4 7 / 2 5 8); More › Palette chooses its lines
  (`PaletteRows`) and order (`PaletteOrder`); picking the next color, and the Paint menu's `]`/`[`,
  follow that order (`PaintingSession.colorOrder`).
- `PaintCommands` is the Paint menu (iPadOS menu bar, single-key shortcuts) fed by the focused
  `PaintingFocus`; fills are registered with the window's `UndoManager` (⌘Z/⇧⌘Z, Edit menu,
  three-finger undo); the Pencil paints while fingers navigate (and only navigates them under "Only
  Draw with Apple Pencil").
- Photo peek (`PhotoPeek`: hold to peek, tap to latch, `p` in the Paint menu) drives
  `CanvasView.showsPhoto`; the canvas draws the photo in its own pass, so it tracks zoom and pan;
  canvas touches hide a latched photo instead of painting.
- Paper: Settings › Paper (`PaperAppearance`) reaches `CanvasView.paperAppearance`, which resolves a
  `CanvasPalette` from it and the trait collection every frame. `CanvasPalette.accent(for:)` is the
  selected paint lifted until it reads on the paper.
- Tips: `PaintTips` (TipKit), configured in `PaintByNumberApp.init`; donations and invalidations
  come from session events in `PaintChromeState` (plus double-tap zoom and Pencil strokes from the
  canvas); one tip at a time through a `TipGroup`. Settings › Show Tips Again bumps the tips' id
  generation.
- Zen Mode (More menu, `SettingsKey.zenMode`): `PaintingSession.flowsToNextArea` sends the
  canvas to the next area of the selected color `zenPause` after each fill or stroke, as the
  hint does. A tap during any camera flight lands it and paints; only a tap on a fling just
  stops it.
- Drag painting scans the capsule the brush sweeps (`PaintingSession.drag`, radius capped at
  `PaintingSession.maxBrushRadius`).
- Feedback: sounds are synthesized (`ToneSynth`, no audio assets) on the ambient session, one
  `PaintingMelody` note per fill; Core Haptics patterns, none on iPad. `SoundPlayer` and
  `HapticsPlayer` each work on a queue of their own (starting either engine blocks its caller).
  Settings' Sounds and Haptics switches are read live (`SettingsKey.sounds`, `SettingsKey.haptics`).
- Color names: each paint goes by a nickname from `ColorNickname.assign`, seeded by the artwork id
  (`ColorNickname.seed(for:)`), so a painting's names are the same on every open (derived, never
  stored: root Saved data). `PaintingSession.colorNicknames`/`nickname(of:)` (nil outside English)
  feed the palette caption, current color, VoiceOver, the swatch's long-press popover and the PDF
  key; `pbn names` prints a template's.

## Giving feedback

- Give Feedback (`PaintView`: the top bar where it fits, else More; the Paint menu) captures the
  painting (`FeedbackCapture`: progress, selection, what is on screen, app and device; where it
  came from is `feedbackSource`, put in the environment by `ArtworkPaintingView`) into a
  `FeedbackDraft` and switches to feedback mode: painting, the Paint menu and the Pencil's double
  tap and squeeze are off, `CanvasView` lets go of first responder (no undoing fills), the palette
  gives way to `FeedbackTools` and `FeedbackBar` replaces the top bar.
- `MarkupCanvas` is a PencilKit canvas over `CanvasView` that takes every touch. Its scroll view
  leads the camera (started from `CanvasView.ScrollCamera`, mirrored by `CanvasController.follow`),
  so drawing units are canvas units and the Metal canvas stays sharp at every zoom; its delegate is
  a separate object (a `PKCanvasView` subclass must not stand in for PencilKit's own scroll view
  callbacks). Marks have their own `UndoManager` (never the window's, which holds the fills), ink
  is drawn in the light style so it keeps its colors, and a finger draws unless "Only Draw with
  Apple Pencil" is on (its `drawingPolicy`). The tools are the app's own (`FeedbackTools`: the pen
  in red, blue or green, the highlighter, the vector eraser), never PencilKit's tool picker: the
  picker needs the canvas as first responder, and moving first responder to or from the canvas
  while the review sheet came or went, just after a finger stroke, hung the app on CI's simulators
  (iOS 26.5). `CanvasView.isAnnotating` hides the areas VoiceOver would offer to paint.
- `FeedbackSheet` (Next) groups the ink into marks (`FeedbackMarks.group`: strokes within 36 points
  on screen at the zoom they were drawn at), gives each a comment beside its close-up (anything
  written on the painting reads there; there is no handwriting recognition: Vision's text
  recognition was tried and dropped, unproven on finger writing over a painting), and lists what
  goes along; the painter's own photo only when they switch Original Photo on (a library picture
  is named instead).
- Send writes the bundle (`FeedbackPackage`; its contents are `FeedbackReport`'s doc comment) and
  hands the painting-with-marks PNG and the zip to `ActivityShareSheet`: there is no fixed address,
  the painter picks Mail, Messages, AirDrop or Files. The export folder goes once the sheet closes;
  sharing ends feedback with a thank-you toast.

## Canvas

`CanvasView` is a `CAMetalLayer` under an invisible `UIScrollView` overlay (the system's pan, pinch
and deceleration), rendering through a display link only while something changes.
`RenderContext.shared` holds the device, queue and a pipeline per pass built from `Shaders.metal`
functions looked up by name; nil means no Metal (`CanvasView.isRenderable` false, the
`paint-unavailable` stand-in). `CanvasScene` holds a template's GPU buffers, `CanvasRenderer` the
region states and three frame slots. `RenderContext.encode` is the one frame recipe (outline
coverage, then one MSAA pass), shared by the canvas, `CanvasSnapshot` and `TimelapseFrameRenderer`;
colors are linear Display P3 into sRGB-curved targets; fills animate on the GPU from timestamps.
Render tests compare pixels (`CanvasRenderTests`). Canvas units are the template's (root
Conventions).

## Line art rendering

- A template with line art draws as a coloring book, alike everywhere (`ColoringBookLook`;
  `docs/coloring-book.md`), whatever its `lineArt.style` (a template of the retired layered style
  too): every drawn layer in the paper's full ink, color edges never, the drawing never dissolving
  under paint and nothing outlined for being selected (the fill's hatch shows the selected color's
  cells). Renderers read line data through `DrawableLineArt` (bad strokes are dropped, counts that
  don't match the edges draw as classic) and `OutlineGeometry`. `CanvasSnapshot` and the
  time-lapse draw the drawing even with outlines off, and `TemplateRasterizer` draws it in every
  style (`drawBookOutlines`, after dotted color-edge guides in `.print`, since paper has no hatch).
  Classic templates draw every edge alike (`ClassicLook` on the canvas), the selected color's
  unpainted cells outlined.
- Settings › Line Weight (`LineWeight`: Fine, Regular, Bold) is the one thing about a book's lines
  the painter sets: an open canvas follows a change at once (`PaintView`'s `@AppStorage`), and
  pictures, the time-lapse and print read it (`LineWeight.stored`). Constants live in
  `ClassicLook`, `ColoringBookLook` and `Shaders.metal`.

## Line art inputs

- `EdgeDetector` runs the two bundled models (provenance in its doc comment and
  `tools/models/convert_*.py`): `edgeMap` the HED contours, `lineDrawing` the drawing;
  `EdgeDetector.maps(for:)` returns both (the drawing resampled to the contours' size). `EyeFinder`
  (Vision face landmarks → eye contours and irises) and `ObjectFinder` (Vision's foreground instance
  mask traced by PaintCore's `MaskContours`) find the eyes and subjects, `TextFinder` (Vision's text
  recognition, down to 1/128 of the photo's height; none on the simulator) the lines of text PaintCore's `Writing` keeps
  legible (`docs/writing.md`).
- `LineArtInputs.Maps.input(for:)` builds the generator's `LineArtInput` by the rule pbn uses too
  (`LineArtInput(drawing:contours:detector:)`): by default the drawing over the contours
  (`EdgeMap.combined`), the contours deciding the outlines; `LineArtSettings.detector` picks one map
  alone.
- Entry point: `LineArtInputs.forGeneration(of:settings:cached:)`: nil for classic settings, and on
  a model failure, so the template comes out classic. Cached per `CGImage` instance (two photos; a
  computation shared by its waiters, cancelled when all are); `CreateModel` computes the inputs once
  per photo beside Vision, `ArtworkFactory.template` (regeneration, starters) uncached. Demo and
  test launches keep each photo's maps on disk (DEBUG `LineArtMapsCache`).
- Tests compare each model with a PyTorch-made map (`HEDFixture.ppm` → `HEDFixture.pgm`,
  `LineArtFixture.pgm`, written by the conversion scripts; at most 2 levels apart), eyes on
  `FaceFixture.jpg`.

## Library and saving

- `Library` (@Observable) keeps `Artwork` metadata in memory; `ArtworkStore` does the file IO
  (`Application Support/Artworks/<uuid>/`: `meta.json`, LZFSE `template.pbnt`, `progress.bin`,
  `source.jpg`, `thumbnail.png`, and `refinements.json` for a refined painting; atomic writes,
  staging and trash folders). Writes are queued per
  artwork off the main actor; deletes are undoable.
- `Library.loadForPainting` classifies failures (`Library.OpenError`: `needsNewerApp`,
  `damaged(canRegenerate:)`, or `unreadable`: a passing I/O error that changes nothing and offers no
  regeneration), resets unusable progress with a one-time `OpenNotice` and repairs stale metadata.
  `Library.regenerate(artwork:settings:)` re-runs the pipeline on the stored photo (or the library
  picture its `sampleName` names), carries progress over by region overlap
  (`PaintProgress.remapped`) and swaps the folder in atomically (`ArtworkStore.replaceContents`);
  without either photo it can't regenerate (`ArtworkFactory.canRegenerate`). Artworks written by a
  newer app (`Artwork.needsNewerApp`) are listed read-only: delete only.
- `ArtworkPaintingView` hosts `PaintView` and autosaves (`PaintingAutosaver`: debounced, on
  background, on close). `Library.writeFailures` records failed progress or metadata writes (the
  newest unsaved progress is kept for `retrySaving`); the painting screen and the gallery show a
  Retry toast; thumbnail and trash writes only log. Tests make writes fail through
  `ArtworkStore.writeFaults`.
- Favorites and search: `Artwork.isFavorite` (tolerant decoding); the gallery's Show menu
  (`GalleryFilter`, `@SceneStorage("galleryFilter")`) and `.searchable` make a `GalleryQuery`
  (`Library.inProgress`/`finished` list favorites first); `TitleSearch.matches` needs every query
  word to start a title word, ignoring case, diacritics and width. `AppShellView` keeps the open
  painting's id in `@SceneStorage("openArtwork")` and reopens it once on appear (not in demo
  launches, nor while a file is being opened).
- Image caches (`ImageCache`, `ImageCaches.swift`): LRU by decoded bytes, emptied on memory
  warnings; gallery tiles decode thumbnails at their own pixel size.
- Rendering without Metal: `TemplateRasterizer` (CoreGraphics; vector geometry, falls back to the
  region map) backs thumbnails, share PNGs, create-flow previews and `PDFExporter`, on its own white
  paper.

## Create flow

- `PhotoSourceView`: the inline picker fills the page (Gotchas). Compact windows switch Photos and
  Samples with a segmented control; windows at least 600 pt wide (`PhotoSourceView.isWide`) keep the
  picker in a card with a scrolling samples column beside it. The picker's own top bar reaches the
  albums and search; "Browse All…" presents the full system picker, the way in when the embedded
  one doesn't take taps.
- Samples: Paintings then Photographs (`Sample.all(of:)`), in `library.json`'s order, titled from
  the catalog (`sample.<id>`); `Sample.starters` (a painting and a photograph) are prepared on first
  launch. Adding a picture: `docs/picture-library.md`.
- Suggested settings (`CreateModel`): every photo (picker, camera, sample, drop, opened file) goes
  loading → analyzing (`SubjectImportance.analyze`: importance map plus `SubjectHints`, faces and
  animals, in one Vision pass, beside the line-art inputs) → suggesting (`AutoSettings.choose` on
  the draft, `CreateModel.maxCandidates`; its first candidate shows as a draft at once, unless the
  preview is line art, sliders and Start wait) → the winner's draft (unless it is that candidate
  and the line art is classic) and its full resolution. A new photo or closing the flow cancels it
  (a `withTaskCancellationHandler` flag reaches every candidate's thread).
- `settingsOrigin` is `.suggested` until the painter moves a slider (`.custom`, reported through
  `settingsChanged()`; back on every suggested value, the sliders' detents, it is `.suggested`
  again); `TemplatePreviewView`'s chip offers Reset to Suggested, which restores the kept
  `AutoDecision` without choosing again. Decisions are never stored: `meta.json` records only
  `settingsOrigin` and `paintingLength`, and regeneration reuses an artwork's recorded settings.
- Tuning: a drag renders drafts from the reduced photo, their line lengths scaled to the draft's
  canvas (`CreateModel.draftSettings`) so short strokes like eyes show as they will; a thumb
  resting `CreateModel.restDelay` renders the full resolution under the finger. The Lines slider
  moves the book's thresholds and shortest line (`CreateModel.lineArt(_:lines:)`; the middle is
  the book's defaults), the line art recorded with the painting like any setting. `CompareView` zooms both layers alike (pinch, double tap, VoiceOver), the zoom held
  across slider changes.
- Settings › Preview (`PreviewStyle`) picks the comparison's other layer (`CreateModel.Picture`):
  the painting (`TemplateRasterizer`'s `.painting`), or its line art: `LineArtDrawing`, the lines
  `TemplateRasterizer` draws for a book (a classic template's every edge), which `CompareView`
  strokes as vectors on the sheet's paper, crisp at every zoom and as heavy as the canvas draws
  them for the picture's size against the window's. A suggestion's first candidate has no
  drawing, so with line art the photo waits for the winner's draft.
- Refine (optional, from the preview's toolbar; `RefineView`): the drawing large, on its paper
  or over the photo; one finger draws lines with the pen and takes them out with the eraser
  (rubbing, or a tap on a line takes it from junction to junction, `LineChains`), two fingers
  zoom and move and a two-finger tap undoes (`RefineCanvas`: an invisible scroll view, the
  canvas's way). Each change regenerates at full resolution, no draft (`CreateModel.refine`);
  meanwhile the changes the template on screen lacks draw over it in its own ink
  (`RefineInkLayer`), and Undo brings back a template already made at once (`CreateModel`'s
  `made`). Settings › Detail Brushes (`SettingsKey.detailBrushes`, off) adds the brushes for
  more or less detail, clearing that brushing, and the text corrections (a tap turns a found
  line off or on, a drag marks one it missed). `TemplateRefinements` change only the
  generator's inputs (the line art's edits, `LineArtInput.edits`; importance, the edge maps'
  gain, `LineArtInput.writing`), so drafts, sliders and Start carry them, and a refined
  painting's `refinements.json` lets regeneration reproduce them. Nothing else reads them: a
  painting nobody refined is made as before. PaintCore's `LineEdits` (root `CLAUDE.md` › Line
  art) is where drawn lines join the drawing and erased ones leave it.
- Compact windows (iPhone) enlarge the preview from the toolbar (Shrink Preview, in Enlarge
  Preview's place, goes back; a checkmark there read as accepting the painting): the comparison
  fills the page (`CompareView.fillsSpace`: the picture fitted in the space, and zoomed in, all
  of it) above the slider of one setting at a time, Lines first (`TemplatePreviewView`'s
  `tuningTray`). Side by side, the preview is as large as it gets already.
- Open in Paint by Moonlight: images from the share sheet and Files arrive through an image document
  type (`CFBundleDocumentTypes` in `Config/Info.plist`, Alternate rank, copied into
  `Documents/Inbox`) and `.onOpenURL` → `AppShellView.openFile`. `IncomingFile` reads the file off
  the main actor (deleting it only from the app's inbox) and titles the painting after its name; the
  create flow opens like a drop (`droppedPhoto`, which the gallery's
  `.dropDestination(for: DroppedPhoto.self)` also sets) once the first-launch samples are done and
  any sheet or open painting is closed; the gaps are on `AppShellView.presentIncomingImage`. No
  Share Extension (a hand-written `.appex` target that can't open its app).

## Sharing and exports

The time-lapse renders under `TimelapseExportSheet`/`TimelapseExportModel` (progress, Cancel, Try
Again; `TimelapseSchedule` eases the strokes in and out) and goes to `ActivityShareSheet`, which
reports when the share sheet closes so the movie is deleted. Every export lives in
`tmp/Exports/<uuid>/` (`ArtworkExporter`); picture and template `ShareLink`s can't report
completion, so they rely on the launch purge and the sweep of stale exports each new export runs
(`ArtworkExporter.staleExportAge`). The completion share picture and the time-lapse stay on light
paper (`CanvasSnapshot.Options`).

## Settings

- `Preferences` is the snapshot that code outside views reads (the create flow, a painting's
  session); views bind the other `SettingsKey`s with `@AppStorage`. Settings › Painting Length
  (`PaintingLength`, Relaxed by default) is what suggestions aim for; Settings › Preview
  (`PreviewStyle`, Painting by default) is how the create flow shows a new painting; Settings ›
  Detail Brushes adds Refine's detail brushes and text corrections (the create flow reads it from
  `Preferences`, so `-refineDetailBrushes YES` turns it on in a UI test). New paintings are
  coloring books at the book's defaults (`LineArtSettings()`), with no pipeline tuning: nothing in
  Settings changes how a template is made.
- Printed templates are laid out for the region's paper (`PDFExporter.Paper.default(for:)`).
- Settings the app retired (Settings › Advanced's line art, tuning and line appearance, and its
  switch per sound, haptic and flourish; Settings' paper size and Color Names; the Custom palette
  order with every painting's arrangement) are removed at launch by
  `Preferences.removeRetiredSettings`, Advanced's book Line Weight carried over to Settings ›
  Line Weight first; a setting retired later joins `Preferences.retiredKeys`.

## Design

The design system is claude.ai/artifact/HRz1Lc9bkLACNvPKhctojF (README, tokens, icon, motifs).
`Theme` and the asset catalog carry its tokens (`Theme.swift` names each: `paper` is `surface-base`,
the screen background; `signature` the Nightshade under prominent buttons' labels and tinted badges;
`gold`; the `Sparkle` shape). New York comes through `Font.display(_:weight:)`,
`Theme.styleNavigationTitles`, the swatch numerals and the canvas digits (`DigitAtlas`). The canvas
sheet is its own paper and ink in both appearances (`CanvasPalette.sheetPaperSRGB`/`sheetInkSRGB`;
Settings › Paper can make it dark). The fill moment's two gold sparkles are `CAShapeLayer`s over the
canvas (`CanvasView.popSparkles`). The app icon PNGs are rendered from the design system's
`pipo-app-icon-v2.svg` at 1024 px (dark: the same art; tinted: its grayscale); no generator script
lives in the repo.

## Accessibility

`CanvasView` is a VoiceOver container (`CanvasAccessibility`): up to 40 `canvas-area-<region>`
buttons for the selected color's unpainted areas in view, a `canvas-placeholder` when there are
none, custom actions, an "Unpainted areas" rotor and `accessibilityScroll`; it posts `layoutChanged`
on selection, progress and camera settle. Swatches are `swatch-N`, labelled "N, <color name>";
`current-color` shows the selected color's name. `PaintSpeech` holds the labels, values, hints and
announcements of swatches, areas, the canvas and progress; the action and rotor names are in
`CanvasView`, the spoken positions in `CanvasPosition`, the current-color label in `PaletteBar`, and
`ColorNameText` holds the localizable color names. `PaletteMetrics` scales swatches with Dynamic
Type up to 1.4×; the fixed-height bars clamp at `.xxLarge` and use the Large Content Viewer.
Reduce Motion reaches the
canvas through `CanvasView.reduceMotion` (instant fills and undos, no shine, stepped replay). UI
tests query these identifiers.
