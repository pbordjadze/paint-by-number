# Paint by Moonlight — exploratory test report (iPad Pro 13" simulator, release build 1.0 (1))

## Summary
The core loop works well on iPad. Two paintings were made: one from the Red Fuji sample, and one from the parrots photo with the fewest colors the slider allows (6). Taps painted the right areas in the swatch's color at the fitted zoom and zoomed in. Progress and fills survived going back to the gallery and a quit-and-relaunch, and the 6-color painting was finished to 100% with no crash (`crashes.txt` is empty).

Three defects reproduced:
- **Every time the More (…) menu opens, an empty on-screen keyboard comes up as well** and covers the palette (3 of 3).
- **Finishing a color jumps the selection back to color 1** instead of advancing to the next color (2 of 2).
- **Replay on the finished painting shows nothing** (2 of 2).

Several polish and copy issues are listed under Suspicions. The most notable is that the New Painting preview frames the photo much tighter than the painting it produces.

## Coverage
1. **Create painting**: done, twice.
   - Samples › Red Fuji with the default sliders: 22 colors, 248 areas. Draft at 21:50:21, painting screen at 21:50:41.
   - The parrots photo from Your Photos, with Colors at the minimum (6) and Detail at the minimum: 73 areas, painting screen at 22:08:13.
2. **Paint**: done (except drag).
   - Tapped areas at the fitted zoom and zoomed in, using the `canvas-area-*` ids and coordinates.
   - Red Fuji: colors 1, 2, 16 and 20. Parrots: all 6 colors, to 100%.
   - Each fill matched the tapped area and the swatch's color, and progress moved (Red Fuji 0 → 6%; parrots 0 → 4 → 45 → 61 → 75 → 98 → 100%).
   - Undo removed exactly the last fill.
   - Drag painting: not tested.
3. **Zoom levels**: partly. Hint zoomed in about 2.5× and I painted 3 areas there. Fit to Screen zoomed back out. The canvas, numbers and fills were consistent at both levels. Double-tap zoom: see Automation problems.
4. **Back to gallery and reopen**: done. The gallery showed 3% with the fills in the thumbnail. On reopening, every fill was there at 3%.
5. **Quit and relaunch**: done. Home, then `stopApp`, then `launchApp`. The app reopened onto the painting with every fill and 3%. The gallery still showed 3%.
6. **Explore**:
   - Gallery context menu (Favorite / Rename / Share › Share Progress, Print Template, Send Template / Restart / Delete).
   - Send Template sheet (cancelled), Rename, search and its no-results state.
   - Settings: Paper, Line Weight, Music, Painting Length, Preview, Acknowledgements.
   - Dark paper with Bold lines.
   - Give Feedback: pen stroke, review sheet, then Discard. Send was never tapped.
   - Finish moment, completion bar, Replay, Done, and the gallery's Finished section.
   - **Not done:** Show filter (I didn't find it), Print, Favorite, Restart and Delete confirmations, a palette long enough to scroll, Show Tips Again, Zen Mode, The Making-of.

## App bugs (reproduced)

### 1. Opening More (…) on the painting screen also brings up an empty keyboard
- **Steps:** open any painting, then tap More (…).
- **Expected:** only the menu appears.
- **Observed:** a full on-screen keyboard appears with the menu, although there is no text field. It covers the bottom ~27% of the screen: the palette and part of the canvas. The hierarchy lists `inputView` and `UIKeyboardLayoutStar`. The keyboard goes away when the menu closes.
- **Reproduced:** 3 of 3, at 21:53 and 21:54 on light paper and 22:03 on dark paper. This matches the iPhone report.
- **Evidence:** `shots/12-more-menu.png`, `shots/14-more-menu-2.png`, `shots/42-more-menu-3-dark.png`.

### 2. Finishing a color selects color 1, not the next color ("Advance to Next Color" is on)
- **Steps:** with Settings › Advance to Next Color on (the default), on Red Fuji, select a swatch in the middle of the palette and paint all its areas.
- **Expected:** the next color (17 after 16, 21 after 20) is selected.
- **Observed:** the finished swatch leaves the palette, the remaining swatches reflow, and the selection jumps back to "1 · Cappuccino", far from where the user was working.
  - The reflow moves every later swatch, and once it moved swatches between rows (21 went from the bottom row to the top), which undoes muscle memory.
  - On the parrots painting, colors were finished in order 1 → 6, so there "next" and "first unfinished" were the same color.
- **Reproduced:** 2 of 2 (color 16 at ~21:52; color 20 at ~22:05).
- **Evidence:** `shots/07-swatch16.png` → `shots/08-painted-16.png`; `shots/41-dark-painted2.png` → `shots/48-color20-done.png`.

### 3. Replay on a finished painting shows nothing
- **Steps:** finish a painting. In the "Finished! Every region is painted." bar, tap the ▶ (Replay) button.
- **Expected:** the painting replays.
- **Observed:** nothing visible changes. Screenshots taken right after the tap and about 1.5 s later are identical to before. Nothing about replay appears in the app log (the last line is a tips offer for `benchReplay` at 22:13:30).
- **Reproduced:** 2 of 2: once by its label, once by coordinates on the button.
- **Evidence:** `shots/58-replay-start.png`, `shots/59-replay-mid.png`, `shots/60-replay-end.png`, `shots/61-replay2-a.png`.
- **Caveat:** if the replay runs in a way screenshots can't capture, this is an automation limit. Nothing in the hierarchy or log suggested it ran.

## Suspicions (seen once, or unsure whether they are bugs)

1. **The New Painting preview frames the photo far tighter than the painting it makes.**
   - For the parrots photo, the preview showed only the blue-and-yellow macaw's head and chest filling the frame. The preview looked the same on a second visit (`shots/50-photo-preview.png`, `shots/65-photo-preview-2.png`).
   - The painting it produced shows the whole photo: both macaws, the red one on the right, plus the background (`shots/53-parrot-start.png`).
   - Painting made once.
   - Red Fuji's preview and painting matched in framing.
2. **No lines between some areas of different colors.**
   - On Red Fuji, the sky's 16, 15 and 14 areas and the color-1 patches on the mountain have no outline. A first-time user can't see where one area ends until that color is selected and hatched (`shots/04-making.png`).
   - The Line Art preview of the parrots is similarly sparse.
3. **Copy that doesn't match the situation:**
   - The tip "No Photo at Hand" appears beside a Photos grid with 7 photos (`shots/02-new-painting-tip.png`).
   - "Suggested for this photo" is shown for a Hokusai print (`shots/03-preview.png`).
   - Send Template says "your changes to the drawing included" (the release build has no Refine) and "your photo …" for a sample painting (`shots/24-send-template.png`, `shots/25-send-template-off.png`).
   - The Settings footer "about half an hour of painting" sits beside Relaxed, while the Relaxed preview estimated "~10 min".
   - "Auto plays Sun from 6 AM and Moon from 7 PM" stays when Music is set to Moon (`shots/34-lineweight-menu.png`).
4. **Music has no Off.** The choices are Sun, Moon and Auto (`shots/32-music-menu.png`). I couldn't listen to audio on the runner.
5. **Dark paper polish:**
   - The palette tray and the completion bar stay light grey slabs on the near-black screen.
   - The title-pill progress ring is dark-on-dark.
   - Evidence: `shots/39-dark-paper.png`, `shots/57-finish-settled.png`.
6. **Restart is styled differently in two places:** red in the painting's More menu, black in the gallery's context menu (`shots/12-more-menu.png` vs `shots/22-context-menu.png`).
7. **Progress shows 0% after 2 of 248 areas.** It looks floored, so a first tap shows no progress (`shots/05-painted-1.png`).
8. **Possible stutter.** The log shows "Waited 0.27–0.36 seconds for a drawable" around fills (21:51:14 – 21:53:08). No hitch was visible in screenshots, and it may be the simulator.
9. **Gallery title switches between large and compact.** It was large on first launch, compact after returning from a painting, and large after search, always at the top of the scroll (`shots/01-new-painting.png`, `shots/18-gallery-after-back.png`).
10. **Two colors in the 6-color palette share the description "olive".** They are "3, Chimney Smoke, olive" and "4, Cattail, olive". VoiceOver users hear the same color twice.

## Automation problems
- `doubleTapOn` did not zoom the canvas (1 try, `shots/09-doubletap.png`). I zoomed with Hint and Fit to Screen instead.
- The first `tapOn: "New Painting"` by label reported success but didn't open the screen. Coordinates worked.
- `tapOn: "Close"` aimed at a tip that had already gone, so it closed the New Painting sheet instead.
- `tapOn: "Painting"` in Settings hit the section header, not the Preview value.
- The Photos picker grid (a remote view) is not in the hierarchy. I tapped photos by coordinates.
- Maestro `swipe` worked for sliders and for a Feedback pen stroke. It can't press-then-drag to paint.

## Not tested
- Drag painting, pinch and two-finger pan.
- The gallery's Show filter (not found).
- Print Template, Share Progress, Favorite, Delete and Restart confirmations.
- A palette long enough to scroll.
- Show Tips Again, Zen Mode, The Making-of, Sounds on/off by ear.
