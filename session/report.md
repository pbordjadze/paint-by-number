# Paint by Moonlight: exploratory test report (iPhone 17 Pro simulator, release build, 2026-10-21 19:44–20:08)

## Summary
The core loop works. I created a painting from a sample and filled areas at two zoom levels. Every fill and the progress survived going back, reopening and three relaunches. Undo right after reopening and after relaunching redrew at once. Four problems reproduced:
- Tapping another color's number on the canvas does nothing (8 of 8, on two paintings).
- Opening the More menu brings up an empty keyboard over the palette (3 of 3).
- After quitting from the painting screen, the gallery thumbnail stays out of date (2 of 2).
- Every relaunch starts on a blank white screen (3 of 3).

The New Painting preview also has polish issues: the Colors value disagrees with the summary count, Enlarge Preview doesn't enlarge, and the preview gets squeezed while the title is edited.

## Coverage
- Goal 1 (create painting): done. Sample "Red Fuji" → preview (all four sliders, Reset to Suggested, Enlarge/Shrink, title field) → Start Painting. The painting opened within about 2 s.
- Goal 2 (paint): done except drag. Filled colors 1, 2 and 19 at the fitted zoom and zoomed in (via Hint). Each fill matched the tapped area and the swatch color; progress went 0% → 1% → 2%, and the swatch rings moved. Drag painting: not tested.
- Goal 3 (zoom levels): partly done. Hint zoom-in and Fit to Screen keep fills, hatching and numbers right. Double-tap zoom didn't work through Maestro, and pinch can't be done.
- Goal 4 (back and reopen): done. Gallery "2% painted" = painting 2%, all fills there.
- Goal 5 (relaunch): done, three relaunches. All fills and the % kept in the gallery and in the painting; the thumbnail didn't keep up (bug 3).
- Goal 6: done in part.
  - Tried: Undo after reopening and after relaunching, Hint, palette scrolling, Palette → Rows (All at Once / Auto), the More menu, Give Feedback (opened and closed without sending), Settings (Show Tips Again), and the gallery card menu (Favorite).
  - Not tried: Order, Zen Mode, Show Numbers, Restart, Delete, Rename, Share, search.
- Focus (a) gallery tip cards: not seen.
  - The first-run shelfStarter tip ran 19:39:36–19:40:21, before my session.
  - After Settings → Show Tips Again and a relaunch, the log says "offer in shelf: shelfNewPainting, wanted shelfNewPainting" (20:03:35.726), then "nothing was eligible in time: shelfNewPainting pending" (20:03:39.683), and no tip appeared.
  - So I couldn't judge whether tips cover titles, cards or buttons, or how the page makes room for them.
- Focus (b) preview on iPhone: done (bug 5 and the Suspicions). No Refine button, as intended.
- Focus (c) the swatch comes into view: blocked. Tapping another color's number never selects it (bug 1), so the palette never scrolls.
- Focus (d) Undo right after reopening / relaunching: done. It redrew at once both times (see Checked and fine).
- Focus (e) first seconds after a relaunch: done. White screen 3 of 3 (bug 2).

## App bugs (reproduced)

### 1. Tapping another color's number on the canvas doesn't select that color (or scroll the palette to it)
- Steps: open a painting; with some color selected, tap a number of a different color on the canvas.
- Expected (per the brief): that color gets selected and its swatch scrolls fully into view in the palette.
- Observed: nothing at all happens. Selection, palette scroll and canvas stay the same, and nothing is logged. Matching-color taps paint in the same places, so taps do reach the canvas. Tried:
  - Red Fuji (2 or 19 selected):
    - "19" at the fitted zoom (37,530 pt)
    - "16" at the fitted zoom (46,307)
    - "19" zoomed in (195,663)
    - "18" zoomed in (230,302)
    - "5" zoomed in with the palette scrolled to its end (160,211)
    - a long press on "19"
  - Delicate Arch (fresh, 1 selected):
    - "15" (257,324)
    - "24" (372,494)
    - "15" with the palette set to All at Once (257,240)
- Reproduced: 8 of 8 taps (plus 1 long press), on two paintings. Settings has no option that looks related.
- Evidence: shots/29-tap-19, 30-tap-16, 33-zoomed-tap-19, 34-zoomed-tap-18, 35-longpress-19, 40-tap-5, 79-arch-tap-15, 80-arch-tap-24, 85-allatonce-tap-15; for contrast, 36-zoomed-paint-2 and 39-painted-19.

### 2. Blank white screen for the first seconds after a relaunch
- Steps: with the app running, `stopApp` then `launchApp`.
- Expected: a launch screen that matches the app (the gallery background is light grey), going smoothly to the gallery.
- Observed: plain white with only the status bar in every screenshot taken right after launch (4 in a row, then 3, then 2), about 2 s or more. Then the complete gallery appears at once.
- Reproduced: 3 of 3.
- Evidence: shots/50–53 then 54-relaunch-settled; 62–64 then 65-relaunch2-settled; 72–73 then 74-relaunch3-settled. The new process's first log lines: 19:58:07.248, 20:01:10.402, 20:03:35.726. The log can't time the white screen.

### 3. Gallery thumbnail stays out of date after quitting from the painting screen
- Steps: open the painting, change it (Undo a fill, or paint one), wait a few seconds, quit the app while still on the painting screen, relaunch.
- Expected: the gallery thumbnail matches the painting and its "% painted".
- Observed:
  - Run 1: I undid the Flint sea (2% → 1%) and quit. After the relaunch the card said "1% painted" but the thumbnail still showed the sea (shots/48-undo-immediate vs 54-relaunch-settled). Opening the painting, making another Undo and leaving with Back refreshed it (60-gallery-after-undos).
  - Run 2: I painted the sea again, waited about 8 s and quit. After the relaunch the thumbnail had no sea (61-sea-repainted vs 65-relaunch2-settled), yet the painting has it saved (66-reopen-after-relaunch2). Opening the painting and leaving with Back without changing anything did not fix it (70-gallery-tips-1); it was still wrong after another relaunch (74-relaunch3-settled).
- Reproduced: 2 of 2. Progress and fills are saved; only the thumbnail is wrong, and it stays wrong until the painting is changed again.

### 4. Opening the More menu on the painting screen brings up the keyboard
- Steps: painting screen → tap More (…).
- Expected: only the menu (Show Numbers, Zen Mode, Fit to Screen, Palette, Give Feedback…, Restart).
- Observed: a full software keyboard slides up with the menu and covers the palette and the lower canvas. No text field is visible or in the hierarchy (only `inputView` and the keys). It goes away when the menu closes. It also stays up inside the Palette submenu.
- Reproduced: 3 of 3 (Red Fuji zoomed in and fitted; Delicate Arch).
- Evidence: shots/41-more-menu, 43-more-menu-2, 81-arch-more / 82-arch-palette-submenu, 44-menu-dismissed.

### 5. Colors slider value disagrees with the summary's color count
- Steps: + → Samples → Red Fuji → preview, Colors tab.
- Expected: Colors N → summary "N colors" (or a label that explains the difference).
- Observed (inspect_screen):

  | Colors slider | Summary line |
  |---|---|
  | 24 | "22 colors · 248 areas · ~10 min" |
  | 53 | "40 colors · 269 areas" |
  | 150 | "97 colors · 423 areas" |
  | 8 | "8 colors" |
  | 6 | "6 colors" |

  The log shows the slider value is what gets requested ("Full #2 started for 24 colors" 19:46:13.777; "Full #6 started for 150 colors" 19:46:54.833). With Colors still 24, the other sliders change the summary count too: Detail max gives "24 colors", Detail min "16 colors", Smoothness max "18 colors". The painting made with Colors 24 has 22 swatches.
- Reproduced: 4 of 4 slider positions ≥ 24 differed. Reset to Suggested brings back 24 / 22.
- Evidence: shots/05-preview, 06-colors-slider-up, 07-colors-max, 08-colors-min, 09-colors-min-again, 12-detail-max, 13-detail-min, 15-smooth-max.

## Suspicions

### Enlarge Preview doesn't enlarge on iPhone
- Observed: the comparison image stays 370×252 pt (inspect_screen before: [16,176][386,428]; after: [16,266][386,518]). It just moves down. The Back button, title field, Suggested chip and Start Painting are hidden, leaving large empty bands. Shrink Preview restores them. Seen 1 time.
- Evidence: shots/05-preview, 18-enlarged, 19-shrunk.

### Preview squeezed to an unreadable thumbnail while the title is edited
- Observed: with the keyboard up, the preview becomes about 90 pt wide. Its "Photo"/"Painting" badges are cut to "…" and "P…", and the divider handle covers most of it. Seen 1 time.
- Evidence: shots/21-title-typed.

### "Compare Photo and Page" tip appears mid-interaction and covers the preview
- It popped up while I was dragging the Detail slider and covered the lower half of the preview (shots/12-detail-max; log 19:48:25.569 "turn: newPaintingDivider"). Seen 1 time.

### "Show Tips Again" brought no gallery tips back
- See Coverage (a). The log shows the shelf tip wanted but "not eligible in time". Seen 1 time (after one relaunch).

### The selected color isn't remembered
- I left Red Fuji with 19 selected. After reopening and after a relaunch it came back with 1 selected and the palette scrolled to the start (shots/47-reopened, 55-reopened-after-relaunch). This may be intended. Seen 2 times.

### Progress percentage counts areas, not surface
- Filling the whole mountain (about a third of the picture) moved progress 0% → 1%, and the big sea moved it to 2%. A first-time user may find this discouraging. It's a design question.

### Thin unpainted areas don't show hatching at the fitted zoom
- With swatch 2 selected, four unpainted color-2 strips (canvas-area-237/238/241/242) show no hatching at the fitted zoom (shots/58-relaunch-undo-swatch2). Zoomed in, they are clearly hatched (59-relaunch-undo-hint).

### Log: "Hand-off: the painting never drew; the cover fades away"
- 19:51:16.998, when the new painting opened after Start Painting. On screen it looked normal (shots/24-paint-screen-tip).

### Other small things
- Opening New Painting: after tapping +, the button was greyed and the gallery stayed for about a second before the sheet appeared (shots/02-new-painting).
- The time estimate goes up with fewer colors: 24 colors → "~10 min"; 6 colors → "~15 min".
- Accessibility labels: the preview's Back button is labelled "New Painting" (id BackButton), and the "Suggested for this photo" chip is labelled "Settings".
- The painting screen never shows the painting's title (only the progress pill's accessibility label has it). The long title is cut to "…Lon…" on the gallery card, which is fine.

## Checked and fine
- Undo right after reopening: the undone sea was already gone in the screenshot taken right after the tap; progress 2% → 1% (shots/48-undo-immediate).
- Undo right after a relaunch: the swatch-2 ring shrank at once. Zoomed in, the undone strip is hatched exactly as before it was painted (56, 59 vs 32).
- Fills match the tapped area and the swatch color. Fit to Screen keeps everything. The palette scrolls cleanly to its last swatch.
- Palette → Rows → All at Once shows a tidy 6×4 grid, and the canvas moves up to make room (84). Rows → Auto restores it.
- Gallery card menu (Favorite, Rename, Share, Restart, Delete). Favorite adds a heart badge and a filter button (77).
- Give Feedback opens a markup screen; X closes it without sending (87, 88).

## Automation problems
- A fast slider swipe to the far left once stopped at 8 rather than the minimum 6. A slower swipe reached 6.
- `doubleTapOn` on the canvas (80,515) didn't zoom (shots/31-doubletap-zoom), as in the earlier session. I zoomed with Hint instead.
- The first-run gallery tip ran before my session.
- I used a zero-length 3 s `swipe` at (50%,10%) as a wait before the second relaunch. It may have pressed the Photo button; I saw no effect.
- I can't list the `crashes/` folder with my tools. The app never quit unexpectedly.

## Not tested
- Drag painting (Maestro's swipe can't press first). Two-finger pan and pinch. Double-tap zoom in and out.
- Photo from the Photos library (I used a sample).
- Zen Mode, Show Numbers, Palette → Order, Restart, Delete, Rename, Share, search, Paper/Line Weight/Sound settings.
- Gallery tip-card layout (no gallery tip appeared while I watched).
