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
- The inline picker's second pick of a photo it gave before in the flow (its selection is reset
  after each pick so the same photo can be picked again) is an item with the photo's identifier and
  no content types: `loadTransferable` answers nil, however often it is asked, and the preview
  said "Couldn’t Open Photo" (CI, Oct 17). `CreateModel.load(item:)` keeps the data of the last
  three library photos by identifier and uses the kept copy then. The preview opens either way, so
  `CreateFlowTests` waits for Start Painting to enable after the second pick, and for the settings'
  chip (`previewLoads`, `waitForSuggestion`: in SideStore and Debug builds Start works from the first draft).
- `ArtworkPaintingView` is pushed with a zoom transition whose swipe-down and pinch dismissal it
  turns off: they stole canvas gestures (`PaintingNavigationTests` guards this). It shows the
  painting only once the push has landed: the transition lays the screen out every frame, and
  the painting screen rendered at each frame (hundreds of renders) stopped CI's simulator
  answering UI tests for up to half a minute. The painting Start Painting makes is pushed with no
  animation, under the create flow's cover, and shows without fading (`StartHandoff`).
- The create flow's preview turns off iOS 26's swipe back from anywhere on a pushed screen
  (`ContentSwipeBackOff` in `TemplatePreviewView`): it took the sliders' and the comparison's
  drags and left for the photo step. The edge swipe and Back still go back.
- A presentation's content only sees state its presenter's body read: `AppShellView.body` reads the
  create flow's photo, title and identity up front, or the flow opens without its photo.
- The create flow's cover has a clear background (`.presentationBackground(.clear)` in
  `AppShellView`) and `CreateFlowView` draws its own paper behind its screens: Start Painting pushes
  the painting under the cover and the flow dissolves into it (Create flow › Start Painting into
  the painting). Anything new that sits in that cover needs a background of its own, or the
  gallery shows through it.
- A `.confirmationDialog` is a popover (iPhone too) anchored to the view that carries the modifier:
  on a screen or a grid it points at the container's middle, not at what asked. Attach it to the
  card, button or menu that asks, keeping one state for what is pending: each gallery card carries
  its Delete and Restart (`GalleryView.isPending`), `DraftRow` its Discard, `PaintView.moreMenu`
  its Restart, `FeedbackBar` its Cancel's, `PaintingRecoveryView` its Delete Painting (what both
  Deletes say: `DeleteConfirmation`). `checkDialog` (`UITestSupport`) measures a dialog
  against its source in `GalleryActionsTests`, `DraftUITests`, `PaintingNavigationTests`,
  `FeedbackUITests` and `RecoveryTests`. Alerts (`.alert`) are centered and need none of this.
- `CanvasUniforms`, `RegionState` and `GlyphInstance` are mirrored by hand in `Shaders.metal`:
  change both in the same order, 16-byte vectors only
  (`CanvasRenderTests.shaderStructLayoutsMatchMetal` pins the strides). A frame's constants are
  packed in one place, `CanvasUniforms(_:)` from a `CanvasFrame` (no defaults), for the canvas
  and `CanvasSnapshot` alike: a new uniform is a `CanvasFrame` field, set by both. No shader reads
  `CanvasUniforms.background`: it carries the backdrop to `TimelapseFrameRenderer`'s clear.
- The shaders hold no paper, ink or accent literals (the brush and the paint sheen keep theirs): the
  chrome colors are uniforms (`CanvasUniforms.setChrome`, `select`; `lightInk` is the tone writing
  over dark paint turns to).
- Exhaustive switches: `PaintTips.signal(for:isStroking:)` and `FeedbackEngine.handle` over
  `PaintEvent`.
- Strokes report paint many times a second, so each tip is invalidated at most once per launch and
  donations are capped per event and launch (`PaintTips.donate`).
- The modifiers that point a tip (`.gentleTip`, `.barTips`, `.cardTip`'s popover) hold their ids
  as a `TipSet` (bits), never an array: they are plain data, which SwiftUI compares bit for bit,
  skipping their bodies when their screen renders again unchanged.
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
  `PreviewStyle`, `Sky`; DEBUG `DemoMode`, `ShellDemo`, `MainThreadWatchdog`.
- `Model/`: `Library` (@Observable, in the environment), `ArtworkStore` (file IO), `Artwork`,
  `ArtworkFactory` (photo → template), `CreateDraft` (with `DraftStore`) and `Drafts` (`library.drafts`,
  see Create flow), `PaintingSession`, `PaintProgress`, `PaintingAutosaver`,
  `Sample`, `GalleryQuery`, `GalleryCounts`, `IncomingFile`, `SharedPaintingCodec`, `ColorNameText`, `PaintingTimeText`, `TemplateCounts`,
  `Background`, `Log` (every logger; CI's `*-app.log`), `UnlimitedPaintings` and `FreePaintings`
  (see Unlimited Paintings); DEBUG `DemoTemplateCache`, `UnlockStoreStub`.
- `Generation/`: `PhotoLoader`, `SubjectVision` (one Vision pass a photo, shared by the three after
  it while it runs), `SubjectImportance`, `EdgeDetector`, `EyeFinder`,
  `ObjectFinder`, `TextFinder`, `LineArtInputs`, `TemplateRefinements`; DEBUG `LineArtMapsCache`.
- `Canvas/`: `CanvasView`, `CanvasRenderer`, `CanvasScene`, `RenderContext`, `Shaders.metal`,
  `CanvasTypes.swift`, `LineStyle.swift` (`ClassicLook`, `ColoringBookLook`, `DrawableLineArt`),
  `CanvasSnapshot`, `TimelapseFrameRenderer`, `CanvasAccessibility`, `DigitAtlas`; DEBUG
  `SyntheticTemplate`.
- `Export/`: `TemplateRasterizer`, `PDFExporter`, `TimelapseExporter`, `ArtworkExporter`
  (`ArtworkExports.swift`), `ImageCodec`.
- `Features/`: `Create/`; `Refine/` (`RefineView`, `RefineCanvas`, `RefineEdits`, `RefineColorsPanel`, the Toolbox's `RefineStudio` and `RefineToolbox`; its gestures and
  geometry are PaintCore's `Refine/`, which `pbn refine` replays on Linux, `RefineGeometry+Drawing`
  the app's part); `Gallery/` (`AppShellView` the shell, `GalleryView`, `EmptyGalleryView` (its sketch paints
  itself once a launch in SideStore and Debug builds: `SelfPaintingSketch`), `DraftRow`, `ArtworkPaintingView`
  the painting host, `PaintingRecoveryView`, `ImageCaches.swift`, `Toast`); `Paint/` (`PaintView`,
  `PaletteBar`, `PaintChromeState`, `PaintCommands`, `PaintTips`, `PaintSpeech`, `PhotoPeek`,
  `CompletionBar`, DEBUG `PaintDemoView`); `Feedback/` (the painter's feedback on a painting, see
  Giving feedback); `Settings/`; `Share/`; `Tips/`
  (the gentle tips, see Tips); `Unlock/` (`UnlockSheet`, see Unlimited Paintings).
  The Marginarium, the storybook that was `Features/Marginarium/`, is in no build: Paul's decision
  (October 23): the Marginarium is private for now; it leaves every build and this repository. Its
  archive is in the private painting-company repository. `Preferences.retiredKeys` clears its
  Settings switch at launch.
- `Features/MakingOf/`: the making-of show in the app (F32; the show itself is `Sources/MakingOf`,
  linked as the package's `MakingOf` product). It has no crew: the app plays `FieldShow`, each step
  growing from seeds over the picture itself, and draws no sprites (it ships in Release;
  `ci/check_release.sh` checks that `making-of.json` is bundled and that no `SpriteAtlas` or
  `MakingOfSprites` is). It stays behind
  Settings › The Making-of (`SettingsKey.playsMakingOf`, off by default; the switch and the screen
  have no `#if`, only `MakingOfDemoView` is DEBUG). With the switch on, `CreateFlowView.start` saves
  the painting as ever, then lays `MakingOfView` over the flow, its picture coming from where the
  preview's was to where the painting's page will be, and playing there (`MakingOfLayout`: the card
  in the roomiest band beside the page, under it on most screens); the painting opens beneath, and
  Skip, a tap or the show's end hands over to it once its picture has become the page (Create flow
  › Start Painting into the painting), and so does a show that can't be made. `MakingOfPlayer`
  makes the show off the main actor (`MakingOfShow.build`: the base generated again with a
  `PipelineSnapshot` observer from `CreateModel.makingOfSource`, the saved template, the bundled
  `making-of.json`, seeded by the artwork id), composites the picture on the CPU with
  `FieldShow.composite` at most 30 times a second on a background task, and announces each card to
  VoiceOver; `MakingOfCanvas` draws the rest of each `ShowFrame` (the real template, numbers, seed
  rings, then the field show's sparks at the burning tips of the ink step and its stars round the
  numbers coming out, in ink at the picture-to-view scale the rings use), `MakingOfCardView` the
  card in New York (captions in the catalog, which `MakingOfShowTests` keeps the spec's; credits
  from `Acknowledgements.methods` letter for letter). Reduce Motion plays stills, one per step
  with its card, cross-faded, with no rings, sparks or stars. No replay from the painting yet.
- `Feedback/` (haptics and sound, not the painter's feedback): `FeedbackEngine`, `ToneSynth`,
  `PaintingMelody`, `HapticsPlayer`, `SoundPlayer`; the sky they play in is `App/Sky.swift`.
- `Resources/`: asset catalog, `Localizable.xcstrings`, `InfoPlist.xcstrings`, `Models/` (the two
  `.mlpackage`s), `Samples/` (`library.json` and the pictures), `PrivacyInfo.xcprivacy`.
- `App/Config/Info.plist` holds what the generated plist can't express: the image document type, the
  scene manifest, ProMotion on iPhone, and the launch screen's `Paper` color (a white launch screen
  flashed before the gallery's paper; `ci/check_release.sh` checks it).

## Tests and demos

- `PaintByNumberTests`: Swift Testing, hosted in the app, which keeps a throwaway library
  (`DemoMode.isTestHost`). Shared helpers in `Fixtures.swift` (`waitUntil`, `record`, `mosaic`,
  `rasterize`, `PixelReader`, `repositoryRoot`, `sample`: a template of a library picture).
- `PaintByNumberUITests`: XCTest launching demo scenarios (`-demo`) with `-demoFixedPictures`,
  `-tracePaper`, `-tracePhotoPeek`, `-openFile` (with `-openFileOnQuestion`: once the gallery asks a question), `-slowFullResolution <seconds>` (each
  full-resolution generation of the create flow waits: a phone's tens of seconds, on a simulator),
  `-NSDoubleLocalizedStrings`,
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
  (`gallery-damaged`, `gallery-timelapse`, `paint-unavailable`), `gallery-send` (with `-dark`,
  `-long-text`) is Send Template's sheet, `gallery-received` (with `-dark`) opens a refined painting
  sent with its photo as a `.moonlight` file (`ShellDemo.sentPaintingFile`), and `gallery-first-run` is the
  gallery as the first launch leaves it (the two starters, none painted on); `gallery-preparing` holds
  it before they are made, their placeholders showing the sample sharp in SideStore and Debug builds
  (`PlaceholderCard.showsPicture`; a placeholder takes no tap). Demo launches and the test host
  reset TipKit and hide every tip except in the tip scenarios (Tips). The scenarios a viewer judges the app by
  show the library by position; the rest use `ShellDemo.fixedPictures`.
  `making-of`, `-ink`, `-stars`, `-dark`, `-long-text`, `-end` and `-reduce-motion` (DEBUG
  `MakingOfDemoView`) make the show of a portrait photograph and hold it at a moment (the paints
  step's rings, the ink step's sparks, the template step's stars); `MakingOfUITests` turns the
  setting on with `-playsMakingOf YES`, starts a painting, and skips the show into it.
  `paint-nightfall` (with `-dark`) is `paint-finish` by Moon, ready at the night's fullest; with
  `gallery-empty` (ready once its sketch has painted itself) it is in `NightfallUITests`, whose
  frames (stretched by Debug's `-introSlowdown <factor>`) are the two animations to look at; the
  sketch waits there for a tap (`-introWaitsForTap YES`), since it paints by the clock from when
  it appears and a slow simulator let it finish before the test's first frame.

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
  camera lands (Reduce Motion: a cut after a pause, no shine). In SideStore and Debug builds
  (`#if UNRELEASED`, until Paul has seen it) night then falls over the painting, about 3 s once
  the shine has swept (`Nightfall`, `CanvasView.finale`; the Lamplit Table's round
  `pieces/intro-animation` on `claude/vibe-factory`, which put it here rather than at launch): dusk
  settles, a gold crescent is inked into its top corner and two stars come out, then it lifts; by
  Sun only a warm evening light; no sound; Reduce Motion fades one still; VoiceOver hears "The moon
  rises over your painting." Its layers follow the camera and go with an undo or a replay. A flight to fit follows layout
  changes on the way (`CanvasView.layoutSubviews`): the completion bar taking the palette's place
  changes the canvas insets as the painting finishes. The color that fill finished gets no sound,
  haptic or announcement of its own. The completion bar slides in (`PaintView`'s animation on
  `isComplete`) and its seal bounces once it is up, for a painting finished on screen. The
  progress badge then names no color (nothing is on the brush), the top bar has no Hint, and the
  completion bar names the painting only when the badge doesn't (`badgeShowsTitle`, from the top
  bar's row that fits); during a replay its ring and
  percentage follow the canvas, not the finished painting (`CanvasView.replay` tells the session
  how many areas are on screen, `PaintingSession.replayed`, by `ReplayProgress`; `isComplete` and
  the saved progress stay whole). While it plays (`PaintingSession.isReplaying`) Undo is off (the
  canvas offers no `undoManager`, so ⌘Z and three-finger undo wait too) and Replay's slot, in the
  bar and More, holds Stop (`CanvasView.stopReplay`).
- Palette (iPad first): `PaintView.PaletteLayout` wraps the palette into rows (bottom) or columns
  (trailing edge of wide windows) so every color shows at once, filling across the bar before
  along it (`PaletteBar.lanes`: rows read 1 4 7 / 2 5 8); More › Palette chooses its lines
  (`PaletteRows`) and order (`PaletteOrder`), which the selection follows
  (`PaintingSession.colorOrder`): a begun painting opens on the palette's first swatch
  (`firstIncompleteColor`; a fresh one, in SideStore and Debug builds, on its largest area's color:
  `OpeningColor`), finishing the selected color selects the next color left after it
  (`nextIncompleteColor`, coming round; the finished swatch leaves, and the first swatch left
  sent a painter in the middle of a long palette back to 1), but the first swatch left in an
  order by areas left, which re-sorts as the painting goes (Nearly Done, Most Left:
  `PaletteOrder.followsProgress`, `PaintingSession.advancesToFirstLeft`), and the Pencil's
  double tap and the Paint menu's `]`/`[` step along it. A tap on an
  area of another color selects nothing and shakes that color's swatch, which the bar scrolls into
  view as little as it can (`PaletteBar.shaken`, `reveal`), so the shake is seen.
- `PaintCommands` is the Paint menu (iPadOS menu bar, single-key shortcuts) fed by the focused
  `PaintingFocus`; fills are registered with the window's `UndoManager` (⌘Z/⇧⌘Z, Edit menu,
  three-finger undo); the Pencil paints while fingers navigate (and only navigates them under "Only
  Draw with Apple Pencil").
- Photo peek (`PhotoPeek`: hold to peek, tap to latch, `p` in the Paint menu) drives
  `CanvasView.showsPhoto`; the canvas draws the photo in its own pass, so it tracks zoom and pan;
  canvas touches hide a latched photo instead of painting.
- Paper: Settings › Paper (`PaperAppearance`) reaches `CanvasView.paperAppearance`, which resolves a
  `CanvasPalette` from it and the trait collection every frame. `CanvasPalette.accent(for:)` is the
  selected paint lifted until it reads on the paper. Dark paper makes the bars, their popovers
  and the painting's toasts dark on a light system too (`PaintView.chromeScheme`: light glass
  slabs sat on it); the canvas, outside them, keeps its own trait collection.
  `paint-book-night-paper` (and its `--tip-benchFind`) is that case's screenshot: a scenario
  named `dark` is captured in dark appearance.
- Quiet painting (`QuietPainting`, Debug and SideStore builds only: `#if UNRELEASED`): once an
  area is painted (`PaintChromeState.wantsQuiet`) the top bar fades to Back, the progress ring
  and Hint; a tap on the ring (`quiet-ring`) brings the rest back until the next fill. The canvas
  insets don't change, so the painting never moves. A painting not begun or finished, feedback
  mode, VoiceOver, Switch Control and a tip at Photo or More keep the whole bar. On regular widths
  the bar's buttons (`glassButtonDiameter`) and the swatches (`PaletteMetrics.scaled`) are a
  quarter bigger, always. `paint-quiet` (with `-dark`) is its screenshot.
- Tips: the bench's moments are in `PaintChromeState` (see Tips below). Zoom, Drag and Pencil
  lie on the page as a card with no arrow, just inside its top as it first fits
  (`TipDesk.pageTip`, `PaintView.pageTipInset`; Paul, October 18: "No arrow").
- Zen Mode (More menu, `SettingsKey.zenMode`): `PaintingSession.flowsToNextArea` sends the
  canvas to the next area of the selected color `zenPause` after each fill or stroke, as the
  hint does, and `zenShinePause` after one that finished a color, whose shine shows first
  (`zenPause` under Reduce Motion, `PaintingSession.reduceMotion`: nothing shines). A tap during
  any camera flight lands it and paints; only a tap on a fling just stops it.
- Drag painting scans the capsule the brush sweeps (`PaintingSession.drag`, radius capped at
  `PaintingSession.maxBrushRadius`); a stroke keeps the color it began with, though finishing
  it moves the selection on.
- Feedback: sounds are synthesized (`ToneSynth`, no audio assets) on the ambient session, one
  `PaintingMelody` note per fill, in the sky of the moment (`Sky`, Settings › Sound's Music,
  one row like Paper's: Sun, Moon, or Auto, the default, Sun from 6 a.m. to 7 p.m. by the device's clock and
  time zone and Moon the rest; Paul's calls; a theme, never tied to the dark appearance or the
  paper; decided with the Lamplit Table, root `CLAUDE.md` › App rules): by Sun a brighter kalimba, by
  Moon a celesta-like bell on the same five notes, lower and minor, twinkling where a phrase
  rests, each sky with its own flourish and finale. The sky turns only where a phrase begins,
  and the fill's stars with it: `FeedbackEngine` keeps the tune on the main actor (its
  `skyOfComingFill` is what `CanvasView.popSparkles` asks, before the sounds hear of the fill)
  and hands `SoundPlayer` each note. `paint-book-moon-dark` holds two stars for a screenshot.
  Core Haptics patterns, none on iPad. `SoundPlayer` and `HapticsPlayer` each work on a queue of
  their own (starting either engine blocks its caller). Settings' Sounds, Haptics and Music are read
  live (`SettingsKey.sounds`, `SettingsKey.haptics`, `SettingsKey.sky`); Haptics shows only on
  hardware with haptics (not iPad, not the simulator).
- Color names: each paint goes by a nickname from `ColorNickname.assign`, seeded by the artwork id
  (`ColorNickname.seed(for:)`), using the vocabulary version recorded in `Artwork.nicknameVersion`,
  so a painting's names are the same on every open (derived, never
  stored: root Saved data). `PaintingSession.colorNicknames`/`nickname(of:)` (nil outside English)
  feed the palette caption, current color, VoiceOver, the swatch's long-press popover and the PDF
  key; `pbn names` prints a template's.

## Tips

The gentle tips are the app's design panel's design of October 17 (its words, ids, triggers, pacing
and Never list are the spec; its notes are the record, not UI): 22 tips, and Refine's Draw Your
Own Lines (`RefineDrawTip`, the line that sat under Refine's tools until Paul's calmer menus,
October 18; like Tap to Paint it waits for neither the gap nor something done, `TipID.isHowTo`),
each said once, on for everyone from the first launch. Paul's change (October 17): no invitation and no Show Tips or No Thanks,
and no Turn Off Tips on a tip: Settings › Tips is the only way to turn them off. The shelf is the
gallery, the bench the painting screen, the drawer Settings; `TipID` names the tips and `TipPlace`
where they live.

- **Where they live.** `Features/Tips/`: `GentleTips` (18 of the tips as TipKit tips, `nonisolated`,
  in the design's words; the other five, the bench's first, are in `Features/Paint/PaintTips.swift`
  with the ids of the first version, so what was closed stays closed), `TipDesk` (turns), `TipPacing`
  (limits, with `TipHistory` and `TipStore`), `TipMoments` (`TipPreference`, the switch's value, and
  `TipMoments`, which tips a moment may offer) and `PaintTips+Moments`. `PaintTips` is the facade
  (configure, the switch, donations, `used`), set up in `PaintByNumberApp.init`; the bench's moments
  are `PaintChromeState`'s. Counts the rules need are TipKit events (`TipEvents`:
  `donations.count`); every tip's rules also read `TipSwitch.tipsOn`. A tip has no button but TipKit's
  close button, which closes just that tip for good.
- **Turns, not TipKit's say-so.** A view points a tip only while `TipDesk.turn` is its id
  (`.gentleTip(…)`, a popover tip; `GentleTipView`, inline, for Ready to Paint; `TipDesk.pageTip`,
  a card on the page, for Zoom, Drag and Pencil; a card with no arrow for the three about the
  bar's buttons (a popover from the button covered it on iOS 26; Paul, October 18: a card, as on
  the page): Refine's at the top of the preview, under the bar (`.barTips(…)`), the gear's and
  the +'s atop the gallery's pages, which make room (`GentleTipView`, anchored by
  `.barTipsInline(…)` while that top is in view: laid over the pages, the card hid the first
  section's title); and
  `.cardTip(…)` for the two on the shelf's cards, Hold and the time-lapse, where TipKit's popover
  tip found nothing to anchor to on CI: SwiftUI's own popover with the tip's `TipView` inside;
  these, the bar's and the page's have no
  TipKit display limit, which would retire a tip from under its view: `TipDesk` says it once, when
  it is closed, used, left 45 s or its screen goes (`TipID.isDrawnByTheApp`); a card
  anchors its tip only while it is mostly in view). A screen reports the
  moment its tips may come at (`TipDesk.offer`: the shelf appeared, the preview is final, the painter
  stopped for a minute); the desk waits for TipKit to find one eligible (`TipID.progress`, polled) and
  for the painter's hand to rest, then asks `TipPacing`, which a refusal leaves untouched: a refused
  hint is not queued, it waits for its moment to come again. A tip's turn ends when it is closed (TipKit
  invalidates it), used (`PaintTips.used` → `invalidate(reason: .actionPerformed)`), its screen goes
  (`TipDesk.leave`) or 45 s pass. `TipPacing`: one at a time, 3 minutes and something done between
  hints (a fill, a slider, a screen), 3 a session (a stretch without a 30-minute break), 5 a day, 3 on
  the first painting (counted from its opening, in place of the session's), silence while a finger or
  the Pencil is on the page, a fill lands, The Making-of, Replay, the shine, Zen drifts or Give
  Feedback is on, and after a finish only Replay Painting. Tap to Paint and Draw Your Own Lines alone wait for
  neither the gap nor something done (`TipID.isHowTo`). State: UserDefaults, `TipStore` (`tipsPacing`, `tipsHistory`);
  `TipPacingTests` and `TipMomentsTests` run on Linux too (the files are Foundation-only).
- **The switch.** `SettingsKey.tipsEnabled` is Settings › Tips' switch and the one thing that turns
  tips off: unset means on (`TipPreference`), so whoever updates from an earlier build has tips too.
  The first shelf visit, once the starter pages show, gives A Page Is Waiting with no question asked
  (`TipMoments.shelf`). Show Tips Again turns tips on, bumps the generation (`PaintTips.scoped` ids and
  events) and starts the pacing and history over. Day one is the first launch with tips on
  (`TipHistory.tipsOnSince`, set when the desk is made).
- **Tests keep them hidden.** Demo launches and the test host clear TipKit and the pacing, put the
  switch back to on, hide every tip (`Tips.hideAllTipsForTesting`) and mute the desk, except in the
  scenarios `PaintTips.demoScenarios` lists (each says which tip it waits for and
  `DemoMode.markReady()` follows it, `PaintTips.awaitDemoTip`): `paint-tip`, `paint-tip-fill` (UI
  tests), `gallery-tip` (with `-dark`, `-long-text`), `gallery-tip-gear` (the tip about a navigation
  bar button, atop the pages), `gallery-tips-off` (UI tests: the switch off and the desk not muted, so the real gate
  is tested), `create-tip`, `settings-tips`, `settings-tip`. A UI test that needs a tip names one of
  them; `GentleTipsUITests` and `PaintingTipsTests` do. Any scenario's name with `--tip-<id>` after it
  (`paint-dark--tip-benchZen`) is that scenario with the tip forced onto its view once its screen
  is in view, whatever the moment and the pacing (`DemoMode.forcedTip`, `TipDesk.force`; every
  rule's count donated), ready once it is up: `ci/scenarios.txt` screenshots each tip so.

## Giving feedback

- Give Feedback (`PaintView`: More, never the top bar; the Paint menu) captures the
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
- Send writes the bundle (`FeedbackPackage`; its contents are `FeedbackReport`'s doc comment: the
  painting-with-marks PNG, the zip and `feedback.md` beside it) and `FeedbackUploader` posts the
  three to the relay (`feedback-relay/`, root `CLAUDE.md` › Map; `FeedbackUploader.endpoint` is the
  one place its address is written). Sent, the export folder goes and feedback ends with a toast
  that says it was sent. A failed send (offline, a timeout, any non-2xx) shows an alert: Try Again
  sends the same files, Share Instead hands the PNG and the zip to `ActivityShareSheet` (the old
  path: the painter picks Mail, Messages, AirDrop or Files; sharing ends feedback with the plain
  thank-you), Cancel keeps the draft. The review sheet says Send goes straight to the people who
  make the app; `PRIVACY.md` and the privacy manifest say what is uploaded (`AboutTests` pins it).
- Tests and CI never upload: `FeedbackUploads.current` is the real uploader only in Release builds;
  in Debug it is `FeedbackUploadStub` unless the launch says `-feedback-upload live`
  (`fail` and `fail-once` make the stub fail, for `FeedbackUITests`' alert and Try Again). The stub
  sits in `#if DEBUG` and `ci/check_release.sh` looks for its name and the argument in the Release
  binary.

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
  (Vision face landmarks of `SubjectVision`'s faces → eye contours and irises) and `ObjectFinder`
  (its foreground instance mask traced by PaintCore's `MaskContours`) find the eyes and subjects, `TextFinder` (Vision's text
  recognition, down to 1/128 of the photo's height; none on the simulator) the lines of text PaintCore's `Writing` keeps
  legible (`docs/writing.md`).
- `LineArtInputs.Maps.input(for:)` builds the generator's `LineArtInput` by the rule pbn uses too
  (`LineArtInput(drawing:contours:detector:)`): by default the drawing over the contours
  (`EdgeMap.combined`), the contours deciding the outlines; `LineArtSettings.detector` picks one map
  alone.
- Entry point: `LineArtInputs.forGeneration(of:settings:cached:)`: nil for classic settings, and on
  a model failure, so the template comes out classic. Cached per `CGImage` instance (two photos; a
  computation shared by its waiters, cancelled when all are); `CreateModel` computes the inputs once
  per photo beside Vision, `ArtworkFactory.template` (regeneration, starters) uncached; both share
  the Vision pass (`SubjectVision`) with the importance map they compute alongside. Demo and
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
  (`GalleryFilter`, `@SceneStorage("galleryFilter")`; there once a favorite exists, or while it
  filters) and `.searchable` make a `GalleryQuery`
  (`Library.inProgress`/`readyToPaint`/`finished` list favorites first; the gallery's sections are
  these three, a painting nobody has painted on being ready to paint, not in progress, and
  `GalleryCounts` is the subtitle that counts them); `TitleSearch.matches` needs every query
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
  albums and search; "Browse All…" (the toolbar, iPad only) presents the full system picker, the way in when the embedded
  one doesn't take taps.
- Samples: Paintings then Photographs (`Sample.all(of:)`), in `library.json`'s order, titled from
  the catalog (`sample.<id>`); `Sample.starters` (a painting and a photograph) are prepared on first
  launch. Adding a picture: `docs/picture-library.md`.
- Suggested settings (`CreateModel`): every photo (picker, camera, sample, drop, opened file) goes
  loading → analyzing (`SubjectImportance.analyze`: importance map plus `SubjectHints`, faces and
  animals, from `SubjectVision`'s pass, which the line-art inputs' eyes and subjects share) → suggesting (`AutoSettings.choose` on
  the draft, `CreateModel.maxCandidates`; its first candidate shows as a draft at once, unless the
  preview is line art, sliders and Start wait; in SideStore and Debug builds Start is on from that draft,
  and tapped before the painting is made waits for it, `CreateModel.askForStart`, called off as a
  waiting Refine is) → the winner's draft (unless it is that candidate
  and the line art is classic) and its full resolution. A new photo or closing the flow cancels it
  (a `withTaskCancellationHandler` flag reaches every candidate's thread).
- `settingsOrigin` is `.suggested` until the painter moves a slider (`.custom`, reported through
  `settingsChanged()`; back on every suggested value, the sliders' detents, it is `.suggested`
  again); `TemplatePreviewView`'s chip offers Reset to Suggested, which restores the kept
  `AutoDecision` without choosing again. Decisions are never stored: `meta.json` records only
  `settingsOrigin` and `paintingLength`, and regeneration reuses an artwork's recorded settings.
- Tuning: a drag renders drafts from the reduced photo, their line lengths scaled to the draft's
  canvas (`CreateModel.draftSettings`) so short strokes like eyes show as they will; a thumb
  resting `CreateModel.restDelay` renders the full resolution under the finger, and letting go
  makes the settings' unless it is under way or there (`setAdjusting`: a touch on a slider cancels
  nothing, only a setting that changes does; a draft never replaces a final preview). The Lines slider
  moves the book's thresholds and shortest line (`CreateModel.lineArt(_:lines:)`; the middle is
  the book's defaults), the line art recorded with the painting like any setting. `CompareView` zooms both layers alike (pinch, double tap, VoiceOver), the zoom held
  across slider changes.
- Settings › Preview (`PreviewStyle`) picks the comparison's other layer (`CreateModel.Picture`):
  the painting (`TemplateRasterizer`'s `.painting`), or its line art: `LineArtDrawing`, the lines
  `TemplateRasterizer` draws for a book (a classic template's every edge), which `CompareView`
  strokes as vectors on the sheet's paper, crisp at every zoom and as heavy as the canvas draws
  them for the picture's size against the window's. A suggestion's first candidate has no
  drawing, so with line art the photo waits for the winner's draft.
- Refine is in SideStore and Debug builds only for now (`#if UNRELEASED`; Paul, October 21: "Let’s
  just take refine out of the release for now—there will be a good one soon"): the release has no
  Refine button or tip on the preview, no Refine note over it and no draft row (`Drafts` reads
  no draft there, leaving the one on disk for a build with Refine), and Release's
  `EXCLUDED_SOURCE_FILE_NAMES` leaves out every `Refine*.swift` and `DraftRow.swift`, which
  `ci/check_release.sh` checks (its types, read from the files the setting names): a new file of
  Refine's screen named so is left out and checked too, and
  anything outside them that names its types needs `#if UNRELEASED`. `RefineEdits.swift` (the
  edits' model, back in by `INCLUDED_SOURCE_FILE_NAMES`) and `CreateModel`'s refining stay, so
  paintings refined before regenerate as they were.
- Refine (optional, from the preview's toolbar; `RefineView`; it draws on the final template alone,
  which a full resolution takes tens of seconds to make again on a phone after a slider moved, so
  the button stays on meanwhile: a tap shows Preparing… and Refine opens by itself once the
  template is made, `CreateModel.askForRefine` / `opensRefine`, called off by touching a slider,
  Start or another photo; it is off only without line art, while the settings
  are chosen and after a failed generation, the status saying why): the drawing large, on its paper,
  over the photo, or over the painting finished (Painting: every area in its paint,
  `TemplateRasterizer.Style.paintedAreas`, rendered with each template that comes); one finger
  draws lines and takes them out, and the painting has exactly the line drawn: the Pen draws as
  drawn (an end whose ink touches a line moves onto it, so the cell closes as it looks, never
  bent back into a hook: `PenAssist`, `SnapLines`), Shapes draws a straight line, a rectangle, an oval, a curve (two
  drags: its ends, then its bend), a hexagon or a star (`RefineShape`, `ShapePath`); the Eraser
  rubs out what it touches (a tap, a dab), the Line Eraser rubs too and a tap takes a line from
  junction to junction (no line under the tools says how they work: each button's
  VoiceOver hint does, and a tip once, `RefineDrawTip`; only a curve waiting to be bent says
  what comes next); Fill's tap makes the closed shape under it an area of its own in the photo's color
  there (a detail area, its number down to half size), and a tap in a filled area takes that fill
  out (`EditFills`). Looks and Edit Paint (backlog row 38) show the painting and `RefineColorsPanel`: a row of looks (Photo, then the
  five of PaintCore's `TemplateEditor.Look`s it `offered`s, night to day, then a painter's; the
  Lamplit Table's `factory/pieces/recolor`, and Paul's five of eight, the rest kept) with a Strength slider once one is chosen, and the paints, one picked
  there or by a tap on its area taking a new color from the system `ColorPicker` (its family
  along while Similar Colors Too is on); the picked paint's areas glow (`RefinePaintGlow`).
  `CreateModel.recolor(_:)` makes them edits
  (`RefineColors`): a look or Photo takes every look and repaint out first, so looks never stack;
  a repaint of the color the last one repainted replaces it (the picker still moving is one step
  of the history); paints made alike merge and a note says so. New colors cross-fade in (none
  under Reduce Motion). `create-refine-colors` (with `-dark`) is its screenshot. Refine zooms to
  12× (`RefineSurfaceView.maximumZoom`). Two fingers zoom and
  move and a two-finger tap undoes (`RefineCanvas`: an invisible scroll view, the canvas's way);
  once an Apple Pencil touches the canvas the Pencil draws and one finger moves, and its double
  tap switches between drawing and the Eraser.
  - **The Toolbox** (Paul, October 21: "a drawing app
    with the tools to make a paint by number", the design claude.ai/artifact/1RuRF7GYbjagg8AJHrVhUH,
    grown from the Studio, claude.ai/artifact/X2d1aeYEUYHHRxdMQZFXPE, `factory/pieces/refine-studio`):
    each tool does one visible thing, and ink, cells and paint are separate. The tools are in groups
    (`RefineGroup`: Ink, Cells, Paint, Numbers, See): on iPad a rail along the leading edge holds every tool
    in labelled sections (`RefineView.toolRail`), on iPhone the groups are tabs over a row of the
    group's tools. Ink: the Pen (ink alone, `RefineView.inked`: a draw with no paints to give; its
    options Snap, `PenAssist`'s end join, on by default, and Color from Photo, off,
    `SettingsKey.refineSnaps`/`refinePenColors`), Shapes (its figures and Snap above the tools), the
    Eraser, the Line Eraser, Bend Line (`.reshape`: a drag moves the line under it, bending it near
    the grab, previewed as it will lie, `TemplateEditor.reshapedChain`; `RefineBendPreview`). Cells: Select (a tap selects a cell, outlined, its paint, area count and
    share of the picture in `RefineSelectionBar`, whose Change Color opens its card), Cell Edge
    (PaintCore's `.cellEdge`: an undrawn boundary, both sides keeping the paint), Merge (`.merge`: a
    drag joins the cells it crosses into the first, boundaries and ink between them gone; the cells
    it will join glow while the finger is down, found off the main actor as the editor finds them,
    `TemplateEditor.MergeProbe`; one that stays in one area says it is one area already), Move Edge
    (`.reshape` on a cell's boundary, inked or not), Fill Shape; while
    a Cells tool is picked the undrawn edges show dashed (`RefineCellEdges`). Paint: the palette
    (`RefinePaletteBar`, in Cells and Paint) holds the current paint (`RefinePalette`: a color as on
    screen, following its paint through edits; the system color picker at its end picks any color,
    which the first Bucket tap adds as a paint), the Bucket (`.paintArea` with the current paint), the
    Paint Brush (`.brush`: the stroke's footprint in the current paint, joining that paint's cells
    it meets; a tap a dab; its Size, `SettingsKey.refineBrushSize`, a radius on screen),
    the Eyedropper (a cell's paint, or over the photo the photo's color), Edit Paint and Looks
    (`RefineColorsPanel`'s two modes; in Edit Paint a swatch dragged onto another becomes it, a
    repaint whose paints made alike merge). Numbers: Move Number (`.moveLabel`, the number held under
    the finger, `RefineHeldNumber`). See: Writing (the Text tool) and Try Painting (the painting
    screen on the template as it stands, `RefineTrial`, saving nothing). The views (Painting, Paper,
    Photo, Photo Behind, whose slider sets how faint the painting lies over the photo) are in the
    navigation bar (a menu on compact widths), opening on the painting. Until the first edit a
    Start From control at the canvas's top picks the base (`CreateModel.start(from:)`,
    `TemplateRefinements.start`: Generated, or Blank, the photo as one area on the generator's
    canvas, `ArtworkFactory.blank`, to draw and paint everything on; a refinement kept in drafts and
    `refinements.json`, a step of the history, and no making-of show). A long press
    (`RefineSurfaceView.pressDuration`, any tool) opens an area's card
    (`RefineAreaCard`, a popover beside it, a sheet on iPhone): its paint and how many areas
    share it, glowing; Only This Area (`CreateModel.paintArea(at:color:)`, PaintCore's
    `.paintArea`, the picker still moving one step) or another paint for it; its other areas in
    Edit Paint. A line or a cell edge that cuts off an area pops two gold sparkles where its ends
    met (`CreateModel.closedShape`, `RefineSparkles`; stars by Moon, a soft tap, none under Reduce
    Motion), and a badge counts the numbers near their floor (`RefineTinyAreas`), zooming to
    each (`RefineFocus`). `create-refine-card` (with `-dark`) opens the largest area's card,
    `create-refine-select` (with `-dark`) selects it. Refine's files compile only where
    `UNRELEASED` is (above), so nothing in them is gated again: the first release's one row of
    buttons went on October 23, with the Color Splitter's button and Tool Guide page (Paul's yes,
    backlog row 100).
  - **The Tool Guide** (`RefineGuide.swift`; Paul, October 21:
    "each tool with a scenario that you can play with and reset easily", built for painters who
    will use Refine seriously, with tweaks, new tools and retired ones to come). Refine's toolbar
    opens it (`refine-guide`) on the tool in hand: The Basics (ink, cells, paint; moving around) and
    Views, then a page per tool the Toolbox offers, listed from `RefineGroup`, so a tool the Toolbox
    stops offering leaves the guide with it. A page's words are `RefineGuidePage.of(_:)`, one
    exhaustive switch over `RefineTool` (a new tool doesn't compile without its page): what it does,
    How to Use It, Try This (on the practice picture), Good to Know and Goes Well With (links to
    other pages); `RefineGuideTests` checks every listed tool has one. Beside the words (above them
    on narrow widths) is the practice canvas: `RefineView` in practice mode
    (`RefinePracticeSetup`: the tool alone, its options and palette, Undo, Redo, the views and
    Reset; no rail, no Start From, no tips, nothing saved; the tool stays the page's, and Snap,
    Color from Photo and Size live in `RefinePracticeSetup.settings`, seeded from the painter's as
    the guide opens, so a page leaves Refine's as they were) on a `CreateModel` of its own
    (`CreateModel.practice(_:scene:)`: the photo and base given, final at once, never generated, so
    no text corrections or sliders are offered). The picture is PaintCore's `RefinePractice`, a
    drawn moonlit evening made a template by the editor's own draws (`painted`: every shape in the
    photo's colors; `inked`: outlines over the hills' paints, for Fill, the Bucket and Color from
    Photo), made once a launch off the main actor (`RefinePracticePicture`). Reset is Cancel's
    way back (`cancelRefining`) and the canvas made again (`.id`). Writing has no practice (the
    picture has no text). `create-refine-guide` (with `-dark`, `-long-text`) opens it on Merge;
    `RefineUITests.testToolGuidePracticesAndResets` merges, resets and follows a link.
  - **Manual edits, no image processing.** A gesture ends as one PaintCore `TemplateEditor.Edit` in
    canvas units (the Pen's stroke after its smoothing and end assist: `.draw`; a rectangle or an
    oval: `.draw` closed; an eraser rub: `.erase` with the radius it has on screen; a Line Eraser
    tap: `.eraseLine`; a Fill tap: `.fill` with `LineEdit.photoColor`; the retired Color Splitter's
    stroke was `.split`, the Pen's line as an undrawn boundary whose sides end with different
    paints, `docs/coloring-book.md` › Split, and splits made before still lay), which
    `CreateModel.edit(_:)` / `fill(at:color:)` lays on the template on screen off the main actor
    (`EditTrail`: tens of milliseconds): no generation, no draft, no crossfade. A drawn line
    first takes the photo's colors for the pieces it cuts (`TemplateEditor.painted` on the
    template shown and `source.image`, kept in the edit's `paints`; `docs/coloring-book.md` › A
    drawn line's colors), and so does a split; a line sent while the base is being made again is
    kept as drawn, a split with the paints of the template on screen (it can't be made without). The
    shown template is a function of the base (what the generator makes from the photo, the
    settings and the refinements' generator inputs, `TemplateRefinements.generatorInputs`) and
    `refinements.edits`,
    laid in order, so the same pair is the same template on every device and in every build of one
    `pipelineVersion`; what an edit doesn't reach is bit for bit what it was (`CreateModelTests`).
    Until an edit lands (`CreateModel.settledEdits` reaches its number) it shows over the template
    in the drawing's own ink (`RefineInkLayer`; a fill as a swatch, `RefineFillLayer`, which then
    tints the area in its paint), and `RefineView.land` swaps the new drawing, the painting
    beneath it and the end of the pending ink in together, so nothing flickers.
  - **One queue.** Every change Refine makes (an edit, a text correction, Undo, Redo,
    Cancel) runs in its turn on `CreateModel`'s queue, from the state the ones before it left, and
    the Undo and Redo stacks live there too (`RefineHistory`, 300 steps; Refine opening clears
    them). Undo and Redo of edits cost no editing: `EditTrail` keeps the templates after the last
    few edits and lays a changed list only from where it parts from the one laid (`move(to:)`);
    deeper steps lay from the nearest kept template or the base. A tap in a filled area removes
    that fill's edit and lays the rest again.
  - **What still regenerates, and why.** The text corrections (the Text tool, always offered:
    a tap turning a found line off or on, a drag marking one it missed), and the sliders, are image settings: they make the base again (`startGeneration`,
    reusing a base made before, `made`) and the edits are laid on the new one, those that no
    longer fit left out of what shows and counted in a toast ("N edits no longer fit the new
    drawing"); they stay in the list, so a correction undone brings them back. Refine's detail
    brushes are gone (Paul, October 18, for the Color Splitter, itself retired October 23); areas a build
    with them brushed stay in `TemplateRefinements.strokes` and still shape the base, so those
    paintings and drafts regenerate as they were. A draft (a slider being
    dragged) shows the photo's own drawing, without edits. An edit sent while the base is being
    made again is kept and laid before the new template shows (`generate`).
  - **An edit that can't be made** (`EditTrail.Verdict.declined`: a line that doubles back on
    itself, lines closer than the lattice can tell apart, a fill with no room for its number)
    changes nothing, is not kept and takes no step of the history; a toast says so
    (`RefineNote`, `RefineNoteToast`, announced to VoiceOver by `CreateModel.say`, gone after
    `CreateModel.noteDuration`). A shape a line closed with no room for a number is not cut off but
    its line stays, and the toast says that, only when the line cut nothing off (the slivers a
    line closes crossing ink beside a junction are silent: `EditTrail.Verdict.made`). An edit
    with nothing to change (an eraser over bare paper) is silent.
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
  flow holds it, encoded with a photo's first draft and copied after, never encoded twice), and,
  once the edits are all laid, the trail they made (`DraftStore.KeptFile`: `base.pbnt`,
  `laid.pbnt`, `made.json`; `EditTrail.Kept`), built in `Drafts/.staging` and swapped in
  atomically (`DraftStore.write`), so the trail is always that of the `refinements.json` beside it. It goes when the painting
  starts (`CreateFlowView.start`) or the refinements are undone to nothing (`Drafts.drop`, which
  removes only its own photo's draft) and by Discard on the gallery's `DraftRow` (confirmation).
  A different new painting leaves the draft alone and replaces it only once its own photo is
  refined; so does choosing another photo in the flow. The row tops the gallery (hidden while a
  filter or a search narrows it, like placeholders); Continue Refining reads the draft off the
  main actor (`Drafts.open`) and opens the create flow on its preview (`CreateFlowView.resuming`,
  `CreateModel.load(draft:photo:)`): the photo goes through the usual steps including the
  suggestion (Reset to Suggested, the detents), but the draft's settings are what is generated,
  with its refinements, at full resolution: the base, then its `edits` laid on it in order
  (`DraftTests.resumingADraftLaysItsEditsAgain`), unless the draft kept the trail they made
  (`CreateModel.keptTrail`, `DraftStore.KeptFile`): then the draft's own settings show its kept
  base and template, nothing made or laid (`EditTrail(base:edits:resuming:)`), since the draft
  keeps a JPEG of the photo, which would make another base; other settings make theirs from it.
  A kept trail missing or damaged is laid again, never the draft's loss. Refine's undo and
  redo stacks are not kept. A draft
  with any file missing or damaged, or a photo that won't decode, is no draft: logged and
  removed, never a failure of the gallery; one that can't be read just now (an I/O or data
  protection error) is kept, at launch and on Continue (`DraftTests`; `gallery-draft` is its
  screenshot).
- Start Painting into the painting (`StartHandoff`, `StartHandoffPlan`,
  `Features/Create/StartHandoff.swift`; backlog row 142, Paul's "one move, then still"): the
  journey from the settings to the canvas is one picture moving once. On Start the flow's controls
  fade around its picture (`clear`; the show's photo fades in over the preview's, or the preview's
  picture whole, `DepartingPicture`), the status bar goes (the painting has none, and an iPad's
  safe area changes with it), and the picture glides once (`glide`, no bounce) to where the
  painting's page will be: `PaintingLayout.page`, the painting screen's own layout (palette, bars,
  `CanvasView.fittedPage`), which `PaintView` lays itself out by, so the two can't drift
  (`PaintingLayoutTests` pins the places CI's canvases put the page). The making-of show plays
  there; the preview's picture becomes the page as the canvas draws it on the way (`HandoffPage`:
  the canvas's `CanvasLook`, nothing selected), the show's once it is over (`settle`). Once the
  picture is still, the shell `begin`s the hand-off and pushes the painting *under* the cover
  (`startPainting`: the usual push and its zoom, unseen behind the opaque cover; a push with
  animations off left the edge swipe back dead), and `ArtworkPaintingView` mounts without its fades
  (`isUnderCover`). The canvas notes when its first frame is on screen
  (`CanvasView.hasShownFirstFrame`: a tenth of a second after the GPU finished it), and
  `PaintView.reportTemplate` then tells the hand-off where the page is, in the window's coordinates
  as UIKit has the canvas (`CanvasController.templateFrameInWindow`; SwiftUI's global frame of the
  pushed canvas put it a safe area's height too low, October 25), and again should it move (a
  rotation). The preview's picture is measured the same way (`PreviewPictureProbe`). The flow then
  fades its paper away around the picture (`reveal`), which stays over the canvas's identical page,
  and `complete`s; the shell takes the cover away with animations off (`endCreateFlow`), and the
  canvas, which opened with the selected color hidden (`watchesFirstFrame`, hatch strength 0 draws
  as no selection), eases its hatch and its numbers' emphasis in (`revealSelection`). A page more
  than a point from where it was expected is moved to first (`StartHandoffPlan.correction`, logged
  as an error: it means the layouts drifted). A painting that has not drawn in
  `StartHandoffPlan.fallback` (2.5 s: a slow open, the recovery screen) `timeOut`s: the cover fades
  out alone and the painting stays pushed. Reduce Motion moves nothing: the picture fades in at the
  page's place. The painting's tips wait for the cover to go (a popover can't present under it).
  `StartHandoffLogic` holds the rules for `StartHandoffTests`; `StartHandoffUITests` attach the
  frames of the screen around the hand-off (`ScreenFrames.swift`), `-handoffSlowdown N` (Debug)
  stretches every duration N times for their `Slowed` runs, and `-handoffFallback S` sets the
  seconds a painting has to draw: CI's simulators take several to open one, and stall their main
  thread for seconds meanwhile, so a motion of half a second is a frame or two there.
- Compact windows (iPhone) show one slider at a time in the card, Colors first, under a
  segmented chooser (`TemplatePreviewView.settingChooser`; Paul's calmer menus, October 18); the
  iPad's card shows all four. In SideStore and Debug builds (`#if UNRELEASED`) the card folds them away until
  Adjust shows them, and keeps them shown for whoever opened it (`TemplatePreviewView.foldsSettings`,
  `SettingsKey.previewShowsSettings`; Adjust alone folds them, the chip keeping Reset to Suggested);
  UI tests open them with `openPreviewSettings`, and find them as an earlier test left them. They enlarge the preview from the toolbar (Shrink Preview, in Enlarge
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
  Share Extension (a hand-written `.appex` target that can't open its app). A painting someone
  sent (a `.moonlight` file, the type `Config/Info.plist` exports, Owner rank) is told from a photo
  by its first bytes (`SharedPaintingCodec.isSharedPainting`): `Library.receive` adds it as a new,
  blank painting with the sender's title and nicknames of its own, and with the sender's photo
  (decoded like any opened image, stored as `source.jpg`) and library picture when they came, so
  it has the photo peek and a damaged template is made again from the photo, without the sender's
  edits, which never travel. It opens in place of any painting or create flow; one that can't be
  read adds nothing and says why in an alert (`Library.ReceiveError`).

## Sharing and exports

The time-lapse renders under `TimelapseExportSheet`/`TimelapseExportModel` (progress, Cancel, Try
Again; `TimelapseSchedule` eases the strokes in and out) and goes to `ActivityShareSheet`, which
reports when the share sheet closes so the movie is deleted. Every export lives in
`tmp/Exports/<uuid>/` (`ArtworkExporter`); picture and template `ShareLink`s can't report
completion, so they rely on the launch purge and the sweep of stale exports each new export runs
(`ArtworkExporter.staleExportAge`). The completion share picture and the time-lapse stay on light
paper (`CanvasSnapshot.Options`). Send Template… (a gallery card's menu › Share) opens `SendTemplateSheet`: the
blank page and the Original Photo switch, on unless the painter turns it off (Paul, October 18),
then Send… shares "<Title> Template.moonlight" (`ArtworkExporter.sharedPainting`): PaintCore's
`SharedPainting`, the template as it is (the painter's refinements are in it) with its title and
settings, LZFSE inside (`SharedPaintingCodec`), and with the switch on the photo and library
picture; never progress or refinements. The sheet deletes the file once the share sheet closes,
and stays up when the painter backs out of it. Whoever hasn't the app gets Print Template…'s PDF
instead. `PRIVACY.md` says what the file holds (no change to the privacy manifest: the painter
sends it, the developers collect nothing).

## Unlimited Paintings

- The app's one purchase (Paul, October 22: "3 free at first, then one per day", $4.99 once,
  $9.99 when Refine joins it): `UnlimitedPaintings` (`Model/`, in the environment from
  `PaintByNumberApp`) holds whether it is bought, its price and the painter's `FreePaintings`
  (three, one back at each midnight, never more than three; UserDefaults `freePaintings`).
  Library pictures, paintings someone sent and paintings made again never take one: only Start
  Painting on the painter's own photo does (`TemplatePreviewView.start`: `mayStart` before,
  `started` once the painting is saved), and with none left it opens `UnlockSheet`
  (`Features/Unlock/`), whose purchase starts the painting. A line under Start Painting counts
  what is left (`free-paintings`); Settings › Unlimited Paintings shows it, or Unlocked, and opens
  the same sheet, which has Restore Purchases (App Review requires one). Its mark is the design
  system's crescent and two of the Moon's stars, drawn as `Nightfall` draws them (the Lamplit
  Table's `factory/pieces/unlimited-paintings` on `claude/vibe-factory`).
- StoreKit 2 on the device (`StoreKitUnlock`: the product
  `com.pbordjadze.paintbynumber.unlimited`, a non-consumable with Family Sharing on, bought with
  SwiftUI's `\.purchase`; `Transaction.updates` followed from launch for Ask to Buy, other
  devices, the family and refunds). Nothing reaches us (`PRIVACY.md` › Unlimited Paintings; no
  change to the privacy manifest). `App/UnlimitedPaintings.storekit` sells it in Xcode runs (Edit
  Scheme › Run › Options › StoreKit Configuration); App Store Connect must hold the product before
  a TestFlight or App Store build that carries it.
- SideStore builds (`UNRELEASED` without `DEBUG`) sell nothing: a sideloaded app can't buy from
  the App Store, so everything is unlocked there and none of it shows. Demo and test launches use
  `UnlockStoreStub` (DEBUG): `-demoFreePaintings <n>`, `-demoUnlocked YES`, `-demoPurchase
  fail|pending|cancel`, the count kept in memory. `create-unlock` (with `-dark`, `-long-text`) is
  the sheet over a photo's preview; `UnlimitedPaintingsTests`, `UnlockUITests` and
  `SettingsTests.testUnlimitedPaintingsShowsTheFreeOnesAndUnlocks` cover it.

## Settings

- `Preferences` is the snapshot that code outside views reads (the create flow); views bind the
  other `SettingsKey`s with `@AppStorage`, and `PaintView` hands a painting's session the
  painting settings (Advance to Next Color, Zen Mode, the palette's order) whoever presents it. Settings › Painting Length
  (`PaintingLength`, Relaxed by default) is what suggestions aim for; Settings › Preview
  (`PreviewStyle`, Painting by default) is how the create flow shows a new painting; Settings › The Making-of plays the
  making-of show after Start Painting (off by default; `Features/MakingOf`); Settings › Music
  (`SkySetting`: Sun, Moon or Auto, the default) picks the sounds and whether the fill's
  sparkles are stars (Painting screen › Feedback). New paintings are coloring books at the book's defaults
  (`LineArtSettings()`), with no pipeline tuning: nothing in Settings changes how a template is
  made.
- Printed templates are laid out for the region's paper (`PDFExporter.Paper.default(for:)`).
- Settings the app retired (Settings › Advanced's line art, tuning, line appearance and preview
  picture, and its switch per sound, haptic and flourish; the time-lapse's pace; Settings' paper
  size, Color Names and Detail Brushes,
  later Text Corrections, whose Text tool Refine now always offers (Paul, October 18), and The
  Marginarium; the Custom palette order with every painting's arrangement) are removed at launch by
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
canvas (`CanvasView.popSparkles`); by Moon they are stars (`Sparkle.starPath`, the sparkle with
shorter, uneven arms on its diagonals). The app icon PNGs are rendered from the design system's
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
`ipad` group. All hooks and tests are guarded by `#if DEBUG`, but for
`PaintingNavigationTests`' tap on another color, which only passes `-playHarness` to find an area
of a paint whose swatch is out of view.
