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
- A `.confirmationDialog` is a popover (iPhone too) anchored to the view that carries the modifier:
  on a screen or a grid it points at the container's middle, not at what asked. Attach it to the
  card, button or menu that asks, keeping one state for what is pending: each gallery card carries
  its Delete and Restart (`GalleryView.isPending`), `DraftRow` its Discard, `PaintView.moreMenu`
  its Restart, `FeedbackBar` its Cancel's. `checkDialog` (`UITestSupport`) measures a dialog
  against its source in `GalleryActionsTests`, `DraftUITests`, `PaintingNavigationTests` and
  `FeedbackUITests`. Alerts (`.alert`) are centered and need none of this.
- `CanvasUniforms`, `RegionState` and `GlyphInstance` are mirrored by hand in `Shaders.metal`:
  change both in the same order, 16-byte vectors only
  (`CanvasRenderTests.shaderStructLayoutsMatchMetal` pins the strides). No shader reads
  `CanvasUniforms.background`: it carries the backdrop to `TimelapseFrameRenderer`'s clear.
- The shaders hold no paper, ink or accent literals (the brush and the paint sheen keep theirs): the
  chrome colors are uniforms (`CanvasUniforms.setChrome`, `select`; `lightInk` is the tone writing
  over dark paint turns to).
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
  `ArtworkFactory` (photo → template), `CreateDraft` (with `DraftStore`) and `Drafts` (`library.drafts`,
  see Create flow), `PaintingSession`, `PaintProgress`, `PaintingAutosaver`,
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
- `Features/`: `Create/`; `Refine/` (`RefineView`, `RefineCanvas`, `RefineGeometry`, `RefineEdits`); `Gallery/` (`AppShellView` the shell, `GalleryView`, `DraftRow`, `ArtworkPaintingView`
  the painting host, `PaintingRecoveryView`, `ImageCaches.swift`, `Toast`); `Paint/` (`PaintView`,
  `PaletteBar`, `PaintChromeState`, `PaintCommands`, `PaintTips`, `PaintSpeech`, `PhotoPeek`,
  `CompletionBar`, DEBUG `PaintDemoView`); `Feedback/` (the painter's feedback on a painting, see
  Giving feedback); `Marginarium/` (how the app is made, in chapters, with Pip, Codex's teapot,
  and Colophon, Claude's moth: `MarginariumView` from the gallery's toolbar once Settings › The
  Marginarium is on (`SettingsKey.showsMarginarium`, off by default; demos open it directly). Debug
  and SideStore builds only for now: the release has neither the switch nor the toolbar entry
  (`#if UNRELEASED`) and leaves out its code, `marginarium.json`, the `pet-*.webp` sheets and `Marginarium.xcassets`
  (Pip's and Colophon's frames) through the target's Release `EXCLUDED_SOURCE_FILE_NAMES`, which
  `ci/check_release.sh` checks; its `marginarium.*` strings stay in the catalog, unused,
  `MarginariumEntry` and the shared `MarginariumSpritePlayer`; `PipSprite` and `ColophonSprite`
  carry the frames in the asset catalog's `Pip/` and `Colophon/`). Paul's shape for it (October
  15): reductive, cute first, complexity only for whoever keeps digging. `MarginariumView` opens
  on its drawings with nothing above them (`MarginariumCompany`: Pip, Colophon and every guardian
  idling as small copies; a tap makes one wave and shows its name, a link to its brief), then one
  way into the story (Chapter 1's opening paragraph, its entry's `passage`, and a link to keep
  reading), then a lean contents: two chapters (1 The Marginarium; 2 The Drawings We Actually
  Made, Codex's), the Who's Who link and Appendices A–F (A and B the book's first chapters, C–F
  the one-passage chapters that followed Chapter 1), each a title and subtitle. Entries open
  `MarginariumReaderView`: native blocks decoded by `MarginariumDocument`, with catalog
  Markdown rendered by AttributedString and `pet:` blocks using the same player. `MarginariumPet`
  resolves imagesets or bundled v2 atlases; a decoded sheet is 14 MiB, so no player keeps one:
  `SpriteAtlasCache.frames` decodes sheets off the main actor, two at a time, redraws the ten cells
  a pet plays into bitmaps of their own (`SpriteAtlas.thumbnails`: a crop would keep its sheet
  alive) and caches those in the gallery's bounded image cache. Authoring, the
  atlas contract and size budget: `docs/marginarium-pets.md`. `tools/marginarium.py` is the import/check manual;
  `Resources/marginarium.json` is bundled, its `docs/marginarium/` sources and tool fixtures are
  not. `MarginariumReaderTests` checks keys, initial content, inline markup and unknown-kind
  skipping. Chapter 1 is imported in full from its approved Docs prose: `tableCell` blocks keep
  row/column/header metadata; numbered `marginNote` blocks keep every signature as `speakers`
  (the last as `speaker`). `Chapter.sections` groups those blocks for
  `MarginariumStructuredViews`: tables align in two columns where the scaled reading measure
  allows, otherwise each row stacks its heading and text; VoiceOver reads a whole row at a time.
  `Chapter.spreads` joins each margin group to the story since the previous one: where the page
  is wide enough (`marginColumnMinimum`, scaled; not at accessibility sizes) and the chapter has
  margins, the reader sets each spread as one row, story column beside margin column, top-aligned;
  otherwise every section is its own lazy row. Each note names the words it is about (the
  source's `<!-- anchor: … -->` line, `anchorBlocks` and the catalog's `<note>.anchor`;
  `tools/marginarium.py`'s docstring), and `MarginariumAnnotations` finds them in the text the
  reader shows; `MarginariumHighlighter` marks them as links (`MarginariumSelection`) the
  reader's `openURL` handles, and `MarginariumWashRenderer` (a `TextRenderer`) washes them in the
  tint, deeper where more voices meet, ending each line's band at its last word (a background
  color on a wrapped space runs on to the margin). Beside a margin column a tap
  picks out the notes (and each note shows its words, quoted); without one it opens
  `MarginariumNoteCard` under the paragraph, and only notes whose words weren't found (a
  translation that moved them; `-NSDoubleLocalizedStrings` finds none) keep a card after their
  story. Opened notes' pets wave (`MarginariumSpritePlayer`'s `greeting`), and every chapter ends
  with its narrator's pet saying goodnight (`MarginariumEntry.narrator`).
  `MarginariumAnnotationsTests` covers anchors and highlights; the `marginarium-chapter1-margin`
  and `-guardians` demos open the first note of their group (on iPhone the card, at the words
  most voices share). Margins use footnote type (beside the story, the contents page's passage rule), and `MarginariumMarginNote`
  shows each signer's pet small beside the note (under it at accessibility sizes), hidden from
  VoiceOver; `MarginariumSpritePlayer` keeps only its pet's frames, never a sheet. `MarginariumSpeakers` is the one table from a signature to a pet (the narrator is
  Colophon, Codex is Pip, the Moon and Bart have none), and a test fails on an unmapped speaker. Chapter 2,
  The Drawings We Actually Made (`petsWeMade`, Codex's chapter), has a pet block for each of the
  nineteen guardians the factory drew, bundled as `Resources/pet-<id>.webp` within the
  budget in `docs/marginarium-pets.md` with Dino's (Paul made it himself in the Codex app; Who's
  Who shows it); the Moon's drawing is withheld. `SpriteAtlasTests` checks a generated
  WebP in the test bundle only, `BundledPetsTests` the shipped sheets, and
  `MarginariumReaderUITests` opens chapters, pets and appendices. Who's Who
  (`MarginariumWhosWhoView`, from the contents and a drawing's name) shows `MarginariumCast`: the
  people (Paul, Chief Architect; Caroline, Chief Designer, making it with him from the start), the
  AI helpers with Pip and Colophon, and the Lamp's guardians in their teams, each card opening
  `MarginariumGuardianView`, its brief (the charter in `factory/GUARDIANS.md` in plain words, ids
  from `factory/panel.json`); a guardian who hasn't hatched shows `MarginariumEgg`. A guardian's drawing
  is the guardian, never its pet (Paul, October 15): its VoiceOver label is its name alone (an
  egg's, "Bart, still an egg"), and no reader-facing text calls it a pet or gives it a name of its
  own; only Pip and Colophon are pets, with their names. A brief shows the name once, as its title
  (the drawing's `caption` is its VoiceOver label there, never shown).
  `MarginariumCastTests` and `MarginariumWhosWhoUITests` (the drawings' names too) cover them. Chief Architect Paul's rule
  for the whole Marginarium: anyone who opens it should have a nice time and roughly follow what's
  going on, so a new page says who people are and what the Lamp's words mean (or links Who's Who),
  in plain words, and is read as a newcomer would before it ships. `Settings/`; `Share/`.
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
  `marginarium` (with `-dark`, `-long-text`) is the contents page, its drawings idling, ready 2 s
  after it appears. `marginarium-chapter`, `marginarium-chapter-dark` and
  `marginarium-chapter-long-text` open the reader on Two More Pets (Appendix F); readiness comes
  when its Pip block appears after the manifest loads.
  `marginarium-chapter1`, `-margin`, `-guardians` and `-table` open Chapter 1 at the top, the
  first margin group (the narrator's notes), the second (five guardians' notes, each guardian
  drawn beside its note) and the guardians table; `marginarium-chapter2` opens Chapter 2 at
  Medea. All have `-dark` and `-long-text` variants. Readiness follows the requested section entering the
  reader's viewport once the sheet has stopped moving, so these scenarios wait up to 30 s;
  `MarginariumReaderUITests` also captures margins and tables at accessibility text sizes.
  `marginarium-whos-who` (with `-dark`, `-long-text`) opens Who's Who at its top,
  `marginarium-whos-who-teams` scrolled to the Workshop, and `marginarium-guardian` (with `-dark`,
  `-long-text`) Dino's brief (`ShellDemo.marginariumPath`).

## Painting screen

- `PaintingSession` (@Observable: painting rules, tap tolerance, drag painting, undo, per-color
  progress, events) drives the canvas through `PaintingCanvas`; `PaintProgress` is what is saved.
  The app is single window: one live session per painting.
- Every fill changes `progress` and `remainingByColor`, so `PaintView`'s body reads neither: it
  reads `isComplete`, `isStarted` and `completedColors`, written only when they flip, and the
  per-fill views read the rest themselves (the badge's `ProgressGroup`, `PaletteBar`). The
  canvas draws on the main thread too: keep per-fill work in small views or off it.
- Events: `PaintingSession.onEvent` has three observers registered when the screen appears:
  `FeedbackEngine.attach` (haptics, sound), `CanvasView` (the shines, the finish) and
  `PaintChromeState.observe` (undo registration, swatch shake, tips, VoiceOver announcements); the
  canvas also gets direct `PaintingCanvas` calls.
- Finishing: the last fill lingers; once it has landed (and the stroke that painted it has
  ended), `CanvasView.finish` eases the camera out to the whole painting, which shines as the
  camera lands (Reduce Motion: a cut after a pause, no shine). A flight to fit follows layout
  changes on the way (`CanvasView.layoutSubviews`): the completion bar taking the palette's place
  changes the canvas insets as the painting finishes. The color that fill finished gets no sound,
  haptic or announcement of its own. The completion bar slides in (`PaintView`'s animation on
  `isComplete`) and its seal bounces once it is up, for a painting finished on screen.
- Palette (iPad first): `PaintView.PaletteLayout` wraps the palette into rows (bottom) or columns
  (trailing edge of wide windows) so every color shows at once, filling across the bar before
  along it (`PaletteBar.lanes`: rows read 1 4 7 / 2 5 8); More › Palette chooses its lines
  (`PaletteRows`) and order (`PaletteOrder`), which the selection follows
  (`PaintingSession.colorOrder`): a painting opens on the palette's first swatch, finishing the
  selected color selects the first color left (`firstIncompleteColor`; the finished swatch
  leaves), and the Pencil's double tap and the Paint menu's `]`/`[` step along it.
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
  hint does, and `zenShinePause` after one that finished a color, whose shine shows first
  (`zenPause` under Reduce Motion, `PaintingSession.reduceMotion`: nothing shines). A tap during
  any camera flight lands it and paints; only a tap on a fling just stops it.
- Drag painting scans the capsule the brush sweeps (`PaintingSession.drag`, radius capped at
  `PaintingSession.maxBrushRadius`); a stroke keeps the color it began with, though finishing
  it moves the selection on.
- Feedback: sounds are synthesized (`ToneSynth`, no audio assets) on the ambient session, one
  `PaintingMelody` note per fill; Core Haptics patterns, none on iPad. `SoundPlayer` and
  `HapticsPlayer` each work on a queue of their own (starting either engine blocks its caller).
  Settings' Sounds and Haptics switches are read live (`SettingsKey.sounds`, `SettingsKey.haptics`);
  Haptics shows only on hardware with haptics (not iPad, not the simulator).
- Color names: each paint goes by a nickname from `ColorNickname.assign`, seeded by the artwork id
  (`ColorNickname.seed(for:)`), using the vocabulary version recorded in `Artwork.nicknameVersion`,
  so a painting's names are the same on every open (derived, never
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
coverage, an RG16F target: the ink's opacity and the share of it in the light tone, then one MSAA
pass), shared by the canvas, `CanvasSnapshot` and `TimelapseFrameRenderer`;
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
- Writing (`TemplateLineArt.writingStrokes`) over a paint under `Template.darkPaintLightness` draws
  in the paper's light tone once its region is painted, so it reads instead of vanishing
  (`docs/writing.md` › Ink on dark paint): `DrawableLineArt.lightWriting` says which strokes,
  `OutlineGeometry.lightWritingMark` rides on their layer to the shader, which crossfades by
  `paintedAmount` (`CanvasUniforms.lightInk`: the lighter of the paper and the ink, so the dark
  sheet's writing stays in its light ink); `TemplateRasterizer.drawBookOutlines` switches where
  the region is painted (never in `.print`) and `LineArtDrawing.paths(within:overPaint:)` splits
  it out over the painting (Refine's). Unpainted and every other line stay in the ink.
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
  artwork off the main actor; deletes are undoable. The create flow's draft lives in
  `Artworks/Drafts/` (not an artwork: `loadAll` skips it).
- `Library.loadForPainting` classifies failures (`Library.OpenError`: `needsNewerApp`,
  `damaged(canRegenerate:)`, or `unreadable`: a passing I/O error that changes nothing and offers no
  regeneration), resets unusable progress with a one-time `OpenNotice` and repairs stale metadata.
  `Library.regenerate(artwork:settings:)` re-runs the pipeline on the stored photo (or the library
  picture its `sampleName` names; for a refined painting with its `refinements.json`: the base,
  then its edits laid on it, as Refine showed them), carries progress over by region overlap
  (`PaintProgress.remapped`) and swaps the folder in atomically (`ArtworkStore.replaceContents`);
  without either photo it can't regenerate (`ArtworkFactory.canRegenerate`). Artworks written by a
  newer app (`Artwork.needsNewerApp`) are listed read-only: delete only.
- `ArtworkPaintingView` hosts `PaintView` and autosaves (`PaintingAutosaver`: debounced, at
  most 10 s apart while painting goes on, on background, on close). Leaving the foreground, it and
  the create flow hold a background task until their writes are on disk (`BackgroundSaving`). `Library.writeFailures` records failed progress or metadata writes (the
  newest unsaved progress is kept for `retrySaving`); the painting screen and the gallery show a
  Retry toast; thumbnail and trash writes only log. Tests make writes fail through
  `ArtworkStore.writeFaults`.
- Favorites and search: `Artwork.isFavorite` (tolerant decoding); the gallery's Show menu
  (`GalleryFilter`, `@SceneStorage("galleryFilter")`) and `.searchable` make a `GalleryQuery`
  (`Library.inProgress`/`finished` list favorites first); `TitleSearch.matches` needs every query
  word to start a title word, ignoring case, diacritics and width. `AppShellView` keeps the open
  painting's id in `@SceneStorage("openArtwork")` and reopens it once on appear (not in demo
  launches, nor while a file is being opened); a launch whose reopen never settled (the app ended
  opening it) shows the gallery at the next one instead (`ReopenGuard`).
- Image caches (`ImageCache`, `ImageCaches.swift`): LRU by decoded bytes, emptied on memory
  warnings; gallery tiles decode thumbnails at their own pixel size.
- Rendering without Metal: `TemplateRasterizer` (CoreGraphics; vector geometry, falls back to the
  region map) backs thumbnails, share PNGs, create-flow previews and `PDFExporter`, on its own white
  paper.

## Create flow

- `PhotoSourceView`: the inline picker fills the page (Gotchas). iPhone doesn't embed it: its grid
  never took a tap on a device, so the Photos pane is Choose Photo, which presents the full system
  picker as Browse All does (`embedsPicker`). Compact windows switch Photos and
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
- Refine (optional, from the preview's toolbar; `RefineView`): the drawing large, on its paper,
  over the photo, or over the painting finished (Painting: every area in its paint,
  `TemplateRasterizer.Style.paintedAreas`, rendered with each template that comes); one finger
  draws lines and takes them out, and the painting has exactly the line drawn: the Pen draws as
  drawn (an end whose ink touches a line moves onto it, so the cell closes as it looks,
  `PenAssist`, `SnapLines`), Shapes draws a straight line, a rectangle, an oval or a curve (two
  drags: its ends, then its bend; `RefineShape`, `ShapePath`); the Eraser rubs out what it
  touches (a tap, a dab), the Smart Eraser rubs too and a tap takes a line from junction to
  junction; Fill's tap makes the closed shape under it an area of its own in the photo's color
  there (a detail area, its number down to half size), and a tap in a filled area takes that fill
  out (`EditFills`). Refine zooms to 12× (`RefineSurfaceView.maximumZoom`). Two fingers zoom and
  move and a two-finger tap undoes (`RefineCanvas`: an invisible scroll view, the canvas's way);
  once an Apple Pencil touches the canvas the Pencil draws and one finger moves, and its double
  tap switches between drawing and the Eraser.
  - **Manual edits, no image processing.** A gesture ends as one PaintCore `TemplateEditor.Edit` in
    canvas units (the Pen's stroke after its smoothing and end assist: `.draw`; a rectangle or an
    oval: `.draw` closed; an eraser rub: `.erase` with the radius it has on screen; a Smart Eraser
    tap: `.eraseLine`; a Fill tap: `.fill` with `LineEdit.photoColor`), which
    `CreateModel.edit(_:)` / `fill(at:color:)` lays on the template on screen off the main actor
    (`EditTrail`: tens of milliseconds): no generation, no draft, no crossfade. The shown template
    is a function of the base (what the generator makes from the photo, the settings and the
    refinements' generator inputs, `TemplateRefinements.generatorInputs`) and `refinements.edits`,
    laid in order, so the same pair is the same template on every device and in every build of one
    `pipelineVersion`; what an edit doesn't reach is bit for bit what it was (`CreateModelTests`).
    Until an edit lands (`CreateModel.settledEdits` reaches its number) it shows over the template
    in the drawing's own ink (`RefineInkLayer`; a fill as a swatch, `RefineFillLayer`, which then
    tints the area in its paint), and `RefineView.land` swaps the new drawing, the painting
    beneath it and the end of the pending ink in together, so nothing flickers.
  - **One queue.** Every change Refine makes (an edit, a brush, a text correction, Undo, Redo,
    Cancel) runs in its turn on `CreateModel`'s queue, from the state the ones before it left, and
    the Undo and Redo stacks live there too (`RefineHistory`, 300 steps; Refine opening clears
    them). Undo and Redo of edits cost no editing: `EditTrail` keeps the templates after the last
    few edits and lays a changed list only from where it parts from the one laid (`move(to:)`);
    deeper steps lay from the nearest kept template or the base. A tap in a filled area removes
    that fill's edit and lays the rest again.
  - **What still regenerates, and why.** Detail Brushes (Settings › Detail Brushes,
    `SettingsKey.detailBrushes`, off: brushes for more or less detail, clearing that brushing,
    and the text corrections, a tap turning a found line off or on, a drag marking one it
    missed), and the sliders, are image settings: they make the base again (`startGeneration`,
    reusing a base made before, `made`) and the edits are laid on the new one, those that no
    longer fit left out of what shows and counted in a toast ("N edits no longer fit the new
    drawing"); they stay in the list, so a brush undone brings them back. A draft (a slider being
    dragged) shows the photo's own drawing, without edits. An edit sent while the base is being
    made again is kept and laid before the new template shows (`generate`).
  - **An edit that can't be made** (`EditTrail.Verdict.declined`: a line that doubles back on
    itself, lines closer than the lattice can tell apart, a fill with no room for its number)
    changes nothing, is not kept and takes no step of the history; a toast says so
    (`RefineNote`, `RefineNoteToast`, announced to VoiceOver by `CreateModel.say`, gone after
    `CreateModel.noteDuration`). A shape a line closed with no room for a number is not cut off but
    its line stays, and the toast says that. An edit with nothing to change (an eraser over bare
    paper) is silent.
  - `TemplateRefinements` are the painter's changes: the `edits`, and the generator's inputs
    (importance, the edge maps' gain, `LineArtInput.writing`, and `lines`, the lines drawn and
    erased by builds that refined through the generator, `LineArtInput.edits`: paintings and
    drafts refined that way regenerate that way, what they mean never changes, and nothing refines
    by it any more; a fill such a build made is part of the base, and a tap there fills again).
    A `refinements.json` without `edits` decodes as it did; an edit it can't read
    is left out; at most `maximumEdits` are kept. Drafts, Start (which saves the template on
    screen, no regeneration) and a refined painting's `refinements.json` carry the edits, and
    `Library.regenerate` makes the base and lays them (`ArtworkFactory.laying`). PaintCore's
    `LineEdits` (root `CLAUDE.md` › Line art) stays the way the generator reads `lines`.
- Draft (`CreateDraft`, kept by `Drafts`, `library.drafts`): the one new painting the painter
  refined and didn't start, so closing the flow, or iOS ending the app, loses nothing. A flow has
  a draft (`CreateModel.draft`) once its photo has refinements, and not while its settings are
  being chosen; `CreateFlowView` hands every change of it (refinements, title, sliders) to
  `Drafts.keep`, which writes it `Drafts.delay` (1 s) after the last, and at once when the flow
  disappears or the scene leaves the foreground, off the main actor and one job after another.
  `Artworks/Drafts/Current/` holds `draft.json` (photo id, titles, settings, the Lines slider,
  sample name), `refinements.json` (an artwork's encoding) and `source.jpg` (the photo as the
  flow holds it, encoded with a photo's first draft and copied after, never encoded twice), built
  in `Drafts/.staging` and swapped in atomically (`DraftStore.write`). It goes when the painting
  starts (`CreateFlowView.start`) or the refinements are undone to nothing (`Drafts.drop`, which
  removes only its own photo's draft) and by Discard on the gallery's `DraftRow` (confirmation).
  A different new painting leaves the draft alone and replaces it only once its own photo is
  refined; so does choosing another photo in the flow. The row tops the gallery (hidden while a
  filter or a search narrows it, like placeholders); Continue Refining reads the draft off the
  main actor (`Drafts.open`) and opens the create flow on its preview (`CreateFlowView.resuming`,
  `CreateModel.load(draft:photo:)`): the photo goes through the usual steps including the
  suggestion (Reset to Suggested, the detents), but the draft's settings are what is generated,
  with its refinements, at full resolution: the base, then its `edits` laid on it in order
  (`DraftTests.resumingADraftLaysItsEditsAgain`). Refine's undo and redo stacks are not kept. A draft
  with any file missing or unreadable, or a photo that won't decode, is no draft: logged and
  removed, never a failure of the gallery (`DraftTests`; `gallery-draft` is its screenshot).
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
  `Preferences`, so `-refineDetailBrushes YES` turns it on in a UI test); Settings › The Marginarium
  puts the book in the gallery's toolbar (off by default). New paintings are
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

Debug launches with `-playHarness` replace the canvas's accessibility children with one
`area-N` button per region (one-based, including filled areas), centered on its primary label
point and valued with its paint number. `play-state` reads the session as the version 1 mailbox
state JSON; `play-settled` reports canvas/animation idleness, and `play-screen-scale` reports
the canvas display scale for screenshot-pixel drags. These readouts stay live as the camera
moves and never paint through accessibility activation. `PaintByNumberUITests/PlayTests`
consumes `PLAY_MAILBOX`, or skips when unset; its temporary-mailbox self-test runs in CI's
`ipad` group. All hooks and tests are guarded by `#if DEBUG`.
