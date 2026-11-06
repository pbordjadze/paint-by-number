# Paint by Moonlight: newcomer's first hour (iPhone 17 Pro simulator, debug build, 05:28–05:58)

## Summary
All six journey goals worked: the gallery, painting a starter, making paintings from a sample, a photo and an empty page, Refine on a preview, and printing (found in about 3 minutes, via long-press on a gallery card › Share › Print Template…). Five tips showed on screen: "Tap to Paint" (twice, once per tip reset), "No Photo at Hand" and "Draw Your Own Lines". All were readable, stayed put and closed cleanly. The tip problems are elsewhere:
- In the first session the log gave the Zen tip a 30 s turn while nothing was on screen, and the session then counted as full.
- The preview's Sliders and Refine tips were "wanted" 3 of 3 times but never became eligible.
- In Refine, the Generated/Blank switch (and the tiny-numbers badge) sit over the top of portrait pictures (2 of 2).
No crashes (`crashes.txt` empty).

## Coverage
1. Gallery + paint a starter: done (The Great Wave, 5 areas, back; gallery shows "1% painted" and a coloured thumbnail).
2. Sample painting: done (Red Fuji: preview, Start Painting, fills, Hint, Fit to Screen).
3. Photo painting: done (parrots photo from Photos, 3 fills).
4. Empty page: done (New Painting › From Scratch › Ink › Shapes › ellipse; Done; Start Painting; painted the circle).
5. Line tool on a preview: done (Irises preview › Refine › Pen, one line; X › "Discard Your Changes?" › Discard Changes; back on the unchanged preview).
6. Printing: done (≈3 min, 3 looks).
- Persistence: (a) from the gallery: Home, then stopApp + launchApp at 05:41. All 4 paintings kept the same progress (50%, 1%, 1%, 1%) and thumbnails. (b) from inside Delicate Arch at 7%: Home, then stopApp + launchApp at 05:54. The app reopened Delicate Arch at 7% with every fill. Both were Home-first quits, not crash-style kills.
- Tip sessions: session 1 (fresh install, 05:28–05:40); session 2 after relaunch + Settings › Show Tips Again (05:42–05:54); session 3 after the 05:54 relaunch (05:54–05:58).

## Tips
0. (Before I started) `shelfStarter`: per app.log, turn 05:25:26 to "turn over" 05:26:11, while the app was still preparing. Not seen by me.
1. **Tap to Paint**: `shots/tip-1-tap-to-paint.png`
   - When: right as The Great Wave opened for the first time (log `turn: benchTap` 05:28:54, ~3 s after I tapped its card).
   - Where: a card across the bottom of the screen (points y 658–761), just above the palette, with an arrow pointing down at the selected swatch (4).
   - Covers: the "4 · Salt Flat" current-color label (y 744–759, under the card) and the top edge of the palette tray. Not the canvas.
   - Points at: swatch 4, the selected color, which fits its words.
   - Words: "Pick a color, then tap an area marked with its number to fill it." Clear and useful right then.
   - Looked again a few seconds later: it stayed, unmoved. Closed with its X (log `turn over` 05:29:12). Then I painted.
2. **benchZen: had a turn but never visible** (no screenshot possible; evidence is the log plus `shots/redfuji-hint.png`, taken in that window)
   - Log `turn: benchZen` 05:31:57 → `turn over: benchZen` 05:32:26, in Red Fuji, right after I tapped Hint (the canvas zoomed).
   - In that window two screenshots and one `inspect_screen` showed no tip, and the hierarchy had no TipView or popover. A showing tip makes `inspect_screen` list only the popover, as it did for every other tip.
   - The top bar was in its quiet state (Back, ring, Hint; More hidden). Zen Mode lives in the More menu, so its anchor was probably hidden. The turn ended at about the time I opened More.
   - Effect: 05:35:37 `benchShowPhoto refused: sessionFull`. No more tips that session: none in New Painting, the preview, Refine or the From Scratch editor.
3. **Tap to Paint (again, after Settings › Show Tips Again)**: `shots/tip-3-tap-to-paint-again.png`
   - When: opening Delicate Arch for the first time, ~1 s after the tap (log `turn: benchTap` 05:42:47).
   - Where/covers: the same card above the palette. It covers the "5 · Autumn Pumpkin" current-color label and the top of the palette. Its arrow points at swatch 5, the selected color, which is right.
   - Stayed for several seconds; closed with X (05:43:12). So the card hiding the current-color label happened 2 of 2. It is harmless while you read it.
4. **No Photo at Hand**: `shots/tip-4-no-photo-at-hand.png`
   - When: tapping + (New Painting), which opens on the Photos tab (log `turn: newPaintingSamples` 05:46:52, ~3 min 40 s after tip 3 closed).
   - Where: a bubble just under the Photos/Samples control (points y 151–266), full width. It covers only empty space; Choose Photo stays visible.
   - Points at: the middle of the Photos/Samples control (arrow x≈201 pt, the seam between the segments), not at "Samples", which it talks about.
   - Words: "Samples has paintings and photographs ready to use." Clear. The title "No Photo at Hand" assumes I have none, while the library has 7 photos. Harmless.
   - Stayed for several seconds; closed with X (05:47:21); I then went to Samples.
5. **Draw Your Own Lines**: `shots/tip-5-draw-your-own-lines.png`
   - When: right after tapping Refine on the Sudden Shower preview (log `turn: refineDraw` 05:52:46, ~1.5 s after Refine opened, ~5 min after tip 4).
   - Where: a card at the bottom (points y 672–775), with an arrow pointing down at the Pen tool (selected).
   - Covers: the Snap / Color from Photo / Smoothing panel and the Ink/Cells/Paint/Numbers/See tabs. The Pen row stays visible.
   - Points at: the Pen, which matches the title.
   - Words: "Two fingers zoom and move. Tap with two to undo." The title promises drawing, but the body only explains zoom and undo. It never says to drag one finger to draw, which is what a newcomer needs first. Half made sense.
   - Stayed for several seconds; closed with X (05:53:22).
- **Tips that wanted to come but never did (log only)**:
  - Preview `newPaintingSliders` and `newPaintingRefine`: "wanted" at 05:50:54, 05:51:38 and 05:52:20 (Cranes, Plum Garden, Sudden Shower; Adjust open the first time, closed the other two). Each time the log then says `nothing was eligible in time: … newPaintingSliders pending, newPaintingRefine pending`.
  - `newPaintingReset` (05:50:54) and `newPaintingSuggested` (05:51:41) were marked `invalidated(actionPerformed)` although I never tapped Reset to Suggested or the Suggested chip (I had only moved sliders and the divider).
  - Session 2 and 3 Zen: offered with nothing wanted at 05:45:01, 05:45:43, 05:54:43, 05:55:15 and 05:55:52. Wanted at 05:46:03 but `nothing was eligible in time: benchZen pending`. Never shown.

## Printing
- **Expected** (written before looking): in a painting's More (…) menu as Print/Share/Export, or in the long-press menu of a gallery card.
- Before the search (while painting Red Fuji, 05:32) I had already seen the painting's More menu: Show Numbers, Zen Mode, Fit to Screen, Palette ›, Give Feedback…, Restart. No Print or Share. A newcomer looking there first finds nothing. Settings, seen later, has no print option either.
- **Where I looked, in order** (started ≈05:37:40):
  1. Gallery, long-press on the Red Fuji card: Favorite, Rename, Share ›, Restart, Delete (`shots/print-1-gallery-card-menu.png`).
  2. Share › submenu: Share Progress, **Print Template…**, Send Template… (`shots/print-2-share-submenu.png`). Found at ≈05:38:30.
  3. Print Template… opens the system share sheet titled "Red Fuji Template" (Preview, More; Copy, Markup, **Print**, Save to Files) (`shots/print-3-share-sheet.png`).
  4. Print opens the system print Options: No Printer Selected, Pages 1–6, US Letter. The preview is a clean numbered line template: page 1 is an overview split into 4 numbered sheets, header "22 colors · 248 areas · 4 sheets" (`shots/print-4-print-options.png`). I did not print.
- **How long**: about 1 minute and 3 turns to see "Print Template…", about 3 minutes to the print options (one extra try because of an automation miss, below).
- Would I have given up? No. But I found it only because long-press menus are a habit. Someone who never long-presses would look in the painting's More menu, find nothing, and could give up.
- Oddities: "Print Template…" opens a share sheet, not the print dialog, so one more step. The share sheet's thumbnail shows the painting *with my red paint* although the printed template is blank (thumbnail only; the pages are clean).
- **Where I would put it**: also in the painting's More menu ("Print or Share Template…"), next to Give Feedback, since that is where I am when I decide I'd rather paint on paper. And make "Print Template…" go straight to the print dialog.

## App bugs (reproduced)
1. **Refine: the Generated/Blank switch and the tiny-numbers badge cover the top of portrait pictures.**
   - Steps: New Painting › Samples › Sudden Shower over Shin-Ōhashi (or Plum Garden at Kameido) › Refine.
   - Expected: the controls above the picture, as with landscape Irises (`shots/refine-line.png`, where they sit above it).
   - Observed: `refine-start` (Generated/Blank) at points [210,128]–[390,171] lies over the picture [39,128]–[362,630] on Sudden Shower. On Plum Garden both Generated/Blank and "1 tiny number" sit over the picture's top edge, hiding part of it (the red cartouche, branches). The controls are semi-transparent, but the picture under them can't be seen or drawn on comfortably.
   - Reproduced 2 of 2 portrait pictures. Evidence: `shots/refine-portrait-generated-blank-overlap.png`, `shots/refine-plum-generated-blank-overlap.png`, `shots/tip-5-draw-your-own-lines.png`.
2. **Preview tips for Sliders and Refine never become eligible.**
   - Steps: after Settings › Show Tips Again and more than 3 min since the last tip, open a sample's preview (with Adjust open or closed).
   - Expected: one of the wanted tips shows.
   - Observed: log `offer in preview: … wanted newPaintingDivider, newPaintingSuggested, newPaintingSliders, newPaintingRefine` → `nothing was eligible in time: … newPaintingSliders pending, newPaintingRefine pending`. No tip on screen.
   - Reproduced 3 of 3 (05:50:54, 05:51:38, 05:52:20). The Refine button's purpose (changing lines yourself) is exactly what a newcomer can't guess, so this tip matters. ("Pending" may be a TipKit rule not yet met; if so it was never met in ~10 min of use.)

## Suspicions
1. **A tip (benchZen) had a turn while invisible and used up the session's tip budget.**
   - Steps: fresh install; open Red Fuji (new), paint one area (top bar goes quiet, More hidden), tap Hint, paint 2 areas.
   - Expected: a visible Zen Mode tip, or none until More is visible.
   - Observed: log `turn: benchZen` 05:31:57 → `turn over` 05:32:26; nothing on screen in screenshots or hierarchy; 05:35:37 the next tip was refused with `sessionFull`.
   - Seen 1 time. Two later sessions in a similar state held it back (`benchZen pending` 05:46:06; nothing wanted 05:54–05:56), so not reproduced.
2. **`newPaintingReset` and `newPaintingSuggested` tips marked "actionPerformed" without the action.** I only moved sliders and the divider (log 05:50:54 and 05:51:41). If moving a slider counts as performing the reset, the Reset tip can never be seen. 1 time each.
3. **From Scratch drawing has a Photo button that shows a blank page, and the app offered a "show photo" tip for it.**
   - Steps: From Scratch, draw a circle, Done, Start Painting, tap the ring, tap Photo.
   - Observed: the canvas becomes a plain white square (`shots/scratch-photo-button.png`); log 05:35:36 `offer in bench: benchShowPhoto` (refused only because the session was full).
   - Expected: no Photo button or tip when there is no photo. 1 of 1.
4. **From Scratch painting has one paint, "Printer Paper" (white).** The drawing gives "1 color · 2 areas", so painting means filling white with white (`shots/scratch-preview.png`, `shots/scratch-painted-circle.png`). Nothing told me how to give my areas colours (the editor's Paint tab, which I didn't find before Done). Confusing for a newcomer. 1 of 1.
5. **Print Template share-sheet thumbnail shows painted progress** while the template itself is blank. Seen in one flow.
6. **"No Photo at Hand" arrow points at the seam of the Photos/Samples control**, not at Samples (tip 4). 1 of 1.
7. **"Draw Your Own Lines" body doesn't say how to draw** (tip 5). Wording, 1 of 1.
8. **Finished colors leave the palette.** After I finished paint 5 and then paint 1 in Delicate Arch, their swatches vanished, so the palette read 4, 6, 7… and then 2, 3, 4, 6… (`inspect_screen` 05:47 and 05:57). It may be intended. To a newcomer the missing numbers look like a gap, and there is no way to see a finished paint. 2 of 2 finished colors.

## Automation problems
- Opening the painting's More menu brought up the software keyboard (simulator artefact). Also, the first screenshot after tapping More showed no menu, while `inspect_screen` listed it; a second screenshot moments later showed it. I trusted the hierarchy and the second screenshot.
- In the system share sheet the hierarchy gives bounds relative to the sheet's container (x 0–384, y 0–364, container at 9,501). `tapOn: "Print"` therefore tapped about (236,324) on screen, outside the sheet, and dismissed it. A tap at the absolute point (245,780) worked.
- `doubleTapOn` on the zoomed Delicate Arch canvas (on a "16" area) did not zoom. The app took it as a tap on another color, and the palette scrolled to swatch 16 (by design). I zoomed with Hint and unzoomed with Fit to Screen.
- Right after Start Painting, the first screenshot showed the new painting without the selected color's hatch; a second one a moment later showed it. Slow first draw on this runner; not counted as a bug.
- `tapOn: optional` and `extendedWaitUntil … optional` did not actually wait (to pace tips), so I passed the time with real actions instead.
- A `tapOn: id swatch-16` failed (17 s wait) because the palette had scrolled and finished swatches had left it. My selector's fault.

## Not tested
- Drag painting (press-then-drag), pinch and two-finger pan, and Refine's two-finger undo, which the tip mentions.
- Double-tap zoom on the canvas (Maestro's double tap didn't zoom).
- Actually printing (no printer; not wanted).
- Send Template, Share Progress and Give Feedback (they send content outward).
- Finishing a painting (the moon).
- The benchDrag and benchShowPhoto tips (never eligible / refused), and the preview Divider, Sliders, Refine, Suggested and Reset tips (never shown).
