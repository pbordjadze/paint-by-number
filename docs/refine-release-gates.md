# Refine's release gates

Refine (with its Tool Guide) and From Scratch reach only Debug and SideStore builds for now: the
release leaves them out with `#if UNRELEASED` and the Release configuration's
`EXCLUDED_SOURCE_FILE_NAMES` (root `CLAUDE.md` › App rules). This is the list of what takes them
out, for the change that ships them (painting-company row 236, on a release branch; `main` keeps
the gates until then). Main at the time of writing: November 5, 2026 (painting-company row 235).

Other features sit behind `UNRELEASED` too and are **not** Refine's: leave them as they are unless
their own row ships them. They are listed at the end so nothing is taken out by mistake.


**Done for 1.1** (November 10, 2026, Paul's word: all of them, the five free paintings too) on the
release branch `claude/pbm-1.1-candidate`; `main` keeps its gates. Beyond this list it also took
out the era door's (`App/EraDoor.swift`, `RootView`, `SettingsView`'s Year row), Release's
exclusion of `Era*.swift`, `Ravenna.framework` and `RavennaResources.bundle`, and Paint Now's ✎
Change (`PaintingChange.swift`, `ArtworkPaintingView`) and Blank Page (`PhotoSourceView`, split
from Start from a Drawing's block). The `Ravenna` target no longer defines `UNRELEASED` in
Release, so its `UnlimitedPaintings.forLaunch` sells there (CI's SideStore build passes
`UNRELEASED` to every target, which still sells nothing); its own looks keep the side it was
always built with, and its Nightfall stays gated. `ci/check_release.sh` requires Paint by
Mosaic's resources and door in Release instead of forbidding them.
## The build settings

1. `App/PaintByNumber.xcodeproj/project.pbxproj`, the app target's Release configuration:
   `EXCLUDED_SOURCE_FILE_NAMES = "Refine*.swift DraftRow.swift";` and
   `INCLUDED_SOURCE_FILE_NAMES = RefineEdits.swift;`. Remove both lines. Every `Refine*.swift`
   (`Features/Refine/`: the screen, its canvas, toolbox, layers, colors panel, cell elements,
   studio, guide, edits and `RefineUnlock.swift`) and the gallery's `DraftRow.swift` then compile
   in Release. Nothing in those files is gated again.
2. `ci/check_release.sh`: its Python exits with "found no excluded or no Debug-only files" when
   no file is excluded. Keep the Debug-only half and drop the requirement that something is
   excluded (`if not left_out or …` becomes a check on the Debug-only files alone), and update
   its header comment, which names Refine's screen and the draft row.
3. `.github/workflows/ci.yml` (the SideStore build in the `compile` and `ipa` jobs) clears
   `EXCLUDED_SOURCE_FILE_NAMES` and adds `UNRELEASED`: with the gates out it stays as is, since
   the other features below still need `UNRELEASED` there.

## The `#if UNRELEASED` blocks that are Refine's or From Scratch's

Take each block's `#if UNRELEASED` / `#endif` out and keep its code (where there is an `#else`,
keep the `UNRELEASED` side and drop the other).

`Features/Create/TemplatePreviewView.swift`
- `isRefining`, `hasSettled`, `hasRefined`, `offersRefineUnlock` (state, near the top).
- `.barTips(.newPaintingRefine, …)`: Refine's tip on the preview.
- `.fullScreenCover(isPresented: $isRefining) { RefineView … }`, `RefineUnlockOffer`, the
  `opensRefine` change and the `.task` that opens Refine once the push lands.
- `.onChange(of: isRefining)` in `observingTheModel` (Refine's tips, `hasRefined`).
- `#if DEBUG && UNRELEASED` `create-refine`'s opening: becomes `#if DEBUG`.
- `waitsForRefine`'s body (keep the `UNRELEASED` side), `pushSettles`, `scratchSettles`,
  `openRefine()`.
- The toolbar's Refine button.
- `previewFinal()`: `let canRefine = model.canRefine` (drop the `false` side), and the
  `create-refine-unlock` demo line (stays inside `#if DEBUG`).
- The comparison's top overlay: `RefineNoteToast` and `DraftSaveToast`.

`Features/Create/CreateModel.swift`
- `defaultTitle`'s Blank name and `blankTitle` (and its setting in `begin`).
- `loadScratch()`, `blankPage()`, `blankPageSide`, `scratchTitle()`.
- `practice(_:scene:)`: the Tool Guide's practice pictures.

`Features/Create/PhotoSourceView.swift`
- The From Scratch toolbar button, `startFromScratch()`, and `RefineUnlockOffer` on the body.
- `offersRefineUnlock` and the `UnlimitedPaintings` environment sit in the same block as Start
  from a Drawing's `picksDrawing` (below): split the block, keeping `picksDrawing` gated if the
  drawing doesn't ship.

`Features/Gallery/GalleryView.swift`
- The draft row (`DraftRow`), drafts being Refine's.

`Model/Drafts.swift`
- Reading the draft on disk: without `UNRELEASED` the release reads none, leaving it for a
  build with Refine.

`Features/Unlock/UnlockSheet.swift`
- The sheet's message: keep the `UNRELEASED` side, which says the purchase unlocks Refine.

## Paint Now's drawing-tool parts (painting-company row 239)

The Paint page, the wait in place of the preview and the length chip ship ungated. These wait
for the drawing tools:

- `Features/Paint/PaintingChange.swift` (`PaintingChangeView`, ✎ Change's cover): wholly in
  `#if UNRELEASED`; drop the `#if`.
- `Features/Gallery/ArtworkPaintingView.swift`: `change`, `offersChangeUnlock` and the
  `UnlimitedPaintings` environment; the cover and `RefineUnlockOffer`; `changeAction`'s
  `UNRELEASED` side; `openChange()`, `changeEnded()`, `showChangeFailed()`; `PaintingChange`.
- `Features/Create/PhotoSourceView.swift`: A Drawing on Paper and Blank Page in Your Own, and
  `startFromScratch()`.
- `Features/Create/CreateModel.swift`: `load(artwork:photo:template:refinements:)`.
- `Features/Create/TemplatePreviewView.swift`: the drawing tools' Done on a blank page starting
  the painting (in `observingTheModel`'s `isRefining` block).

## With the gates out, also

- **Unlimited Paintings with Refine** (`UnlimitedPaintings.includesRefine`, painting-company
  row 143): in a build that sells it, Refine's button and From Scratch open the unlock sheet
  until it is bought, worded for Refine, with Try It in the Tool Guide (its practice pictures are
  free). Refine's paintings count as any other: only Start Painting on the painter's own photo
  (and a page from scratch is one) takes a free painting. `includesRefine = false` gives Refine
  to everyone. The price, the product's display name and description in App Store Connect, and
  `App/UnlimitedPaintings.storekit`'s `displayPrice` (pinned at 4.99 by
  `UnlimitedPaintingsTests`, and the stub's `price()`), are the owner's to change.
- **1.1's free paintings** (painting-company row 235, the owner's decision of November 5): under
  `UNRELEASED`, `FreePaintings.most` is five and `UnlimitedPaintings.countsEveryPainting` true,
  kept under `freePaintings.v2`; `UnlockSheet` and Settings' footer have 1.1 wording. These are
  not Refine's gates but ship with them: take each `#if UNRELEASED` there out keeping its 1.1
  side, and change `PRIVACY.md` › Unlimited Paintings, `ci/store-listing.json`'s free-paintings
  lines and the root `CLAUDE.md`'s Monetization line to five, every new painting.
- `ACCESSIBILITY.md` (the App Store's accessibility page) gains Refine's line, left out until it
  ships: "Refine: with VoiceOver, the cells in view are buttons while a cell tool is picked; Merge
  and Move Number offer actions in place of their drags."
- `PRIVACY.md` and the privacy manifest: no change (Refine sends nothing anywhere).
- The store listing (`ci/store-listing.json`): Procreate is named nowhere in it or in tool names,
  only in the Tool Guide, whose trademark line (`refine.guide.procreate.note5`, on Coming from
  Procreate, and the Bucket's) is a legal line.
- `App/CLAUDE.md` › Create flow and the root `CLAUDE.md` › App rules: drop the "SideStore and
  Debug builds only" wording for Refine and From Scratch, and the `EXCLUDED_SOURCE_FILE_NAMES`
  sentence.
- The CI screenshots of Refine (`create-refine*`, `create-refine-unlock*`) are the store's
  screenshot source for later; the store's slides are made from the painter's own photos
  (`store-screenshots.yml`).

## Not Refine's (leave gated)

- Kit paint (`CreateModel.newPaintMix`, `newTuning`, `newTaste`).
- Start from a Drawing (`PhotoSourceView`'s `picksDrawing`, `drawingItems`, its camera and
  library branches; `TemplatePreviewView`'s drawing palette).
- Nightfall (`Canvas/Nightfall.swift`, `CanvasView`'s nightfall calls, `PaintDemoView`'s
  `paint-nightfall`).
- `QuietPainting.isAvailable`, `PaintingSession.isLargestArea`, `ArtworkCard.showsPicture`,
  `EmptyGalleryView`'s self-painting sketch, `SendTemplateSheet`'s photo explanation,
  `TemplatePreviewView.foldsSettings` and `startsEarly`.
- `UnlimitedPaintings.forLaunch`'s `UNRELEASED && !DEBUG` (SideStore sells nothing).
