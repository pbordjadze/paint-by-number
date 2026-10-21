# Paint by Moonlight – exploratory test report

## Summary
I made a painting from the parrots photo (39 colors, 180 areas) and painted areas of colors 2, 1, 5 and 16, both at the fitted zoom and zoomed in with Hint. Every tap filled the area I tapped, in the right color, and progress went 0% → 3%. Leaving and reopening, and quitting and relaunching, kept every fill and the same percentage. One-finger drags never painted (4 of 4); I can't tell whether that is the app or Maestro. Once, right after a relaunch, Undo updated the progress but left the fill on the canvas until I picked another swatch. A second try didn't reproduce it.

## Coverage
1. Create a painting: **done**. + → parrots photo → preview (waited ~1 min while it said "Finding the subject…") → Start Painting → painting screen.
2. Paint: **partly**. Taps work at the fitted zoom, by id (`canvas-area-36`, `-128`, `-22`) and by coordinates, and zoomed in after Hint. A finished color (2) leaves the palette. Drags didn't paint (see Suspicions).
3. Zoom navigation: **partly**. Fit → Hint zoom → panning (by accident, from drags) → More › Fit to Screen. Fills and numbers stayed in the right places at every level. Double-tap zoom couldn't be tested (Automation).
4. Back and reopen: **done**. 3% in the gallery card, the thumbnail and the painting header; all fills kept.
5. Quit, relaunch, reopen: **done, twice**. Fills and percentage kept both times.
6. Extras: **partly**. Tried Undo 4 times (see Suspicions) and Hint once. I didn't open Settings, gallery menus, search, Give Feedback or the Photo toggle.

## App bugs (reproduced)
None confirmed. Nothing below happened twice in a way that clearly rules out automation as the cause.

## Suspicions

### 1. Canvas still shows a fill after Undo, until it redraws (seen 1 of 2 tries after a relaunch; 0 of 2 within one session)
- **Steps:** Paint area 16 (the olive blob, `canvas-area-22`, about 583,363 pt) with swatch 16 selected → Back → reopen (selected swatch resets to 1) → stopApp/launchApp → open the painting → tap Undo.
- **Expected:** The olive blob turns back into a hatched/unpainted area and progress drops.
- **Observed:** Progress dropped 3% → 2% and swatch 16's progress ring cleared. The accessibility tree reported swatch 16 at "0 percent painted" and `canvas-area-22` as "not painted". But the canvas still drew the blob filled in olive. Only after I tapped swatch 16 did the canvas redraw it as hatched/unpainted.
- **Not reproduced:**
  - Undo in the same session, with swatch 16 selected: redrew correctly.
  - Undo in the same session, after switching to swatch 1: redrew correctly.
  - Paint → Back → relaunch → reopen → Undo: redrew correctly.
  - In the one failing run, the app had been relaunched and the painting reopened twice before Undo, and Undo was the first action after opening.
- **Evidence:** `shots/relaunch-reopen.png` (before), `shots/undo-1.png` (2% shown, blob still drawn), `shots/undo-1-select16.png` (blob hatched after picking swatch 16). Non-repros: `shots/repro2-undo.png`, `shots/repro3-after-undo.png`, `shots/repro4-reopened.png` → `shots/repro4-after-undo.png`.

### 2. A one-finger drag pans instead of painting (4 of 4 tries; might be automation)
- **Steps:**
  - Zoomed in via Hint, color 5 selected:
    - Maestro `swipe` starting on a "4" area.
    - Maestro `swipe` starting at the edge of a hatched "5" area.
  - Color 16 selected:
    - A `swipe` starting well inside a hatched "16" area.
    - At the fitted zoom, a `swipe` along the hatched "16" band at the bottom left, (160,810) → (145,900), 1000 ms.
- **Expected:** The drag paints matching areas along its path.
- **Observed:** Zoomed in, the canvas panned by about 58–62 pt each time and nothing was painted. At the fitted zoom, nothing happened at all. A plain tap on the same "16" area painted it at once.
- **Log:** At 17:01:26.814 the app logged `offer in bench: benchDrag, wanted benchDrag`, then `nothing was eligible in time: benchDrag pending`. Nothing is logged for gestures themselves. At 16:59:14.018 the painting screen's recognizer list showed only `UIKitHoverGestureRecognizer, _UIParallaxTransitionPanGestureRecognizer, _UIContentSwipeDismissGestureRecognizer (disabled), _UITransformGestureRecognizer (disabled)`. I can't tell if that list is complete.
- **Evidence:** `shots/zoomed-paint-5.png`, `shots/drag-5.png`, `shots/drag-16.png`, `shots/tap-16.png`, `shots/drag-fit-16.png`.
- **Caveat:** Maestro's swipe may not look like a human drag (no initial hold), so this could be an automation limit.

### 3. The preview's color count disagrees (seen once)
The Colors slider showed "40", but the summary under it said "39 colors · 180 areas · ~10 min". The log says `Draft #1 started for 40 colors` (16:58:57.819). The painting has 39 swatches. The tool may have merged colors, but the label is confusing. Evidence: `shots/preview-40-vs-39.png`.

### 4. Minor or unclear (seen once each)
- **Selected swatch isn't remembered.** It reset from 16 to 1 on reopen. Happened on both reopens, so it is probably by design.
- **Undo history survives a relaunch.** Undo was enabled right after relaunching and undid the last fill. That may be intended, but it combines with Suspicion 1.
- **"Never drew" log line.** At 16:59:17.438 the log says `Hand-off: the painting never drew; the cover fades away`, yet the painting displayed fine.
- **Progress shows 0% after the first fill.** It stayed at 0% after filling one whole color (color 2, its one area). Probably rounding: one area out of 180 is under 1%.
- **Blank screen on launch.** Right after the relaunch there was a blank white screen for a few seconds before the gallery appeared (`shots/relaunch-gallery.png`).

## Automation problems
- **Double tap didn't zoom.** `doubleTapOn` at (640,385) pt on the fitted canvas did nothing (1 try), matching the earlier session. I zoomed with Hint and returned with Fit to Screen.
- **Drags may be unreliable.** Maestro `swipe` may not produce a paint drag (Suspicion 2).
- **One flow failed on my own mistake.** I added `index` to a text `tapOn` with the wrong syntax ("Invalid Command Format"). Coordinates worked instead.
- **One tap missed because of scaling.** Early on I tapped using screenshot pixels instead of points (screenshot 1500 px wide = 1032 pt) and missed. Corrected afterwards.
- **No crashes.** I didn't look in `crashes/`, and no flow suggested a crash.

## Not tested
- Two-finger pan and pinch (not available in Maestro).
- Double-tap zoom in and out.
- Settings, the gallery's menus (long press), search, deleting or renaming paintings.
- Give Feedback (opened none; never tapped Send), the Photo reference toggle, the Refine button and sliders in the preview.
- Finishing a whole painting.
- The two starter paintings, and samples as a source.
- iPhone layout.
