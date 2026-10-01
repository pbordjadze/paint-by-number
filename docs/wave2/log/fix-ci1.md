# CI fixes after the first integration run (Opus 5.5)

Branch `wt/fix-ci1`, head `7adf3f2`; merged as `bdaf814`. Run 87 (179873d): 245 passed, 4 failed.

1. `CanvasRenderTests.canvasResolvesPaperFromPreferenceAndTraits` — test bug. The canvas wasn't in
   a window, so `overrideUserInterfaceStyle` never reached its `traitCollection`; the app path works
   (`DarkPaperTests.testAutomaticPaperFollowsTheSystemAppearance` passed). Fixed `601583a`: hosted
   in a `UIWindow`, style flipped with `updateTraitsIfNeeded()`.
2–4. `OpenFileTests` ×3 — app bug in `AppShellView`: `body` read `droppedPhoto`, `droppedTitle`,
   `flowID` only inside the `.fullScreenCover` content closure (and `isCreating` only as a binding),
   so setting them never re-ran `body`; the cover built its content from the previous pass's closure
   (photo nil → picker step; `.id(flowID)` never restarted a flow; empty data never showed "Couldn't
   Open Photo"). The gallery drop has the same pattern and likely only worked because
   `isDropTargeted` changes around a drop. Fixed `7adf3f2`: `body` reads the values up front.
   Also: the time-lapse export sheet moved from `GalleryView` to `AppShellView`
   (`.sheet(item:onDismiss: presentIncomingImage)`, `GalleryView` takes `@Binding timelapse`), so a
   file arriving while it is up closes it and opens the create flow (W5's open item).

Open: `PaintView`'s own sheets/dialogs and the gallery's rename/delete dialogs may block the cover
when a file arrives (not handled); the `*-long-text` screenshots show raw placeholders, which is by
design (wave 1 `4cf3fe0`). Other wave 2 screenshots (favorites, search, dark paper, time-lapse Pace,
settings) look correct.
