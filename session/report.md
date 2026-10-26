# QA report: Refine recheck (debug build), Jūmantsubo Plain at Fukagawa Susaki

Session 2026-10-26, 22:58–23:15. Path: gallery › New Painting › sample "Jūmantsubo Plain at Fukagawa Susaki" › preview › Refine. All screenshots are in `shots/`. There were no crashes: crashes.txt is empty.

## Summary
I rechecked the four fixes from the last QA run:
- **(3) Paper at the fitted zoom holds**: numbers legible, no piles (3 of 3 looks).
- **(4) Pen line ending on the cartouche writing holds**: no visible jump onto a letter (3 of 3, at screenshot resolution).
- **(1) Edit Paint fails**: only the first color picked in a picker session applies; the 2nd and 3rd picks are ignored (3 of 3).
- **(2) The area card fails on the moving popover**: after the first pick the card changes size and the picker popover moves 18–36 pt, so a quick second pick lands on the wrong color or none (3 of 3).

## Coverage
- **(1) Edit Paint, Similar colors too on, 3 picks in a row**: done, 3 tries (Paint 1, Paint 9, Paint 15). Fails, see Bug 1. The bar did keep naming the paint just recolored, and no other paint was recolored by the ignored picks.
- **(2) Area card, pick A then B**: done, 3 tries (plain = Paint 2 · 20 areas, water = Paint 10 · 3 areas, sky = Paint 15 · 3 areas). Fails on "popover doesn't move", see Bug 2. The card kept saying Only This Area every time. The area ended in what my B tap actually hit, or stayed A when it hit nothing.
- **(3) Paper at the fitted zoom**: done, 3 looks. Two before any edit (shots/paper-fitted-1, -2) and one after three Pen lines (shots/paper-fitted-3). Every area's numbers are legible. The sky (15) and plain (2) have many copies, but they are spread apart, not stacked; I saw no pile anywhere. A few numbers sit across a drawn line (e.g. "21" right of the eagle's chest, "10" on the water line lower right), which is minor. I didn't zoom in, to avoid the tiny-numbers badge.
- **(4) Pen line from open water ending on the red cartouche's writing**: done, 3 lines with Snap on (shots/pen-before, pen1, pen2, pen3, paper-fitted-3). Each line's end stayed where my swipe lifted: near the middle "L" stroke (twice) and next to the top stroke. None visibly jumped onto a letter. Caveat: the cartouche is about 50 × 170 pt and screenshots reach me scaled down; I didn't zoom in, so a jump under about 3 pt would not show.

## App bugs (reproduced)

### Bug 1. Edit Paint: only the first pick in a picker session takes effect (3 of 3)
- **Steps:** Refine › Edit Paint. Select a paint, leave Similar colors too on, tap the color well (`refine-colors-picker`), and in the system picker tap 3 colors in a row (about 5–8 s apart, the pace of Maestro's tapOn). Then close the picker.
- **Expected:** each pick recolors the selected paint, so it ends in the 3rd color.
- **Observed:** the 1st pick recolors the paint (and its "similar" paints). The 2nd and 3rd picks show as selected in the picker (selection square, sample swatch), but the paint and canvas don't change. The canvas value counts one change per session ("No changes" → "1 change" → "2 changes"). The bar keeps naming the right paint.
  - **Try 1:** Paint 1 (red), grid. Blue applied; yellow and purple ignored. Ends "1 · Vivid blue", well value "dark azure". Evidence: ep1-pick1, ep1-pick2, ep1-pick3, ep1-closed.
  - **Try 2:** Paint 9 (light olive), grid. Red applied; orange and pink ignored. Ends "9 · Vivid red". Evidence: ep2-open, ep2-pick1, ep2-pick2, ep2-pick3, ep2-closed.
  - **Try 3:** Paint 15 (sky), preset circles. Green applied; yellow and black ignored (black shows selected in ep3-pick3 while the sky stays green). Evidence: ep3-open, ep3-pick1, ep3-pick2, ep3-pick3, ep3-closed.
- **Log:** app.log has no line for any of these picks (its last line is "turn over: refineDraw" at 23:01:05.357).

### Bug 2. Area card: the picker popover moves after the first pick (3 of 3)
- **Steps:** Refine › Select. Long-press an area whose paint has several areas, tap the color well beside Only This Area, tap color A, then tap where color B is.
- **Expected:** the popover stays put, the area ends in B, and the card says Only This Area.
- **Observed:** the first pick turns the area into its own new paint ("Paint 24 · 1 area", "Paint 25 · 1 area"). The card drops its "Show Its Other Areas" row and changes size. The well, with the popover attached to it, moves down, and the B tap hits whatever is now under the finger.
  - **Try 1** (plain): the popover moved about 36 pt. The red tap hit a pale-yellow grid cell, and the area ended "Grayish yellow". Evidence: card1-open, card1-picker, card1-pickA, card1-pickB, card1-afterclose.
  - **Try 2** (water): moved about 18 pt. The red tap hit a pale cell. Evidence: card2-open, card2-picker, card2-pickA, card2-pickB, card2-afterclose.
  - **Try 3** (sky, card beside the area): moved about 18 pt. The red tap fell between the grid and the presets, so nothing was picked and the sky stayed blue. Evidence: card3-open, card3-picker, card3-pickA, card3-pickB, card3-afterclose.
- The Only This Area label itself held in all three tries.

## Suspicions

### An area recolored to another paint's color joined its neighbour (seen once)
In card try 2, the stray B pick gave the water area the same pale yellow as the plain area recolored in try 1. The card then read "Grayish yellow, Paint 24 · 1 area", with plain and water outlined as one region, so two areas became one (card2-pickB, card2-afterclose). This may be intended (same paint, no line between them), but it is surprising from a picker labelled Only This Area. It also produced a huge pale area that wiped out the water's colors.

### Similar colors too recolors paints that don't look similar (all 3 Edit Paint tries)
- Light olive (9) → red also turned the plain's "Light beige" (2) pink, "Beige" (4) vivid pink, the water (10) beige, and "Light grayish teal" (12) dark yellow (ep2-closed).
- The grayish-teal sky (15) → green also turned the eagle's browns (6, 7, 8) green (ep3-closed).
- Red (1) → blue turned beiges/browns (3, 5, 7) pinkish-mauve (ep1-pick1).

This may be a deliberately broad family, but beige plains and brown feathers don't look similar to an olive or a teal.

### The Generated/Blank control covers the canvas's top-left corner
On a fresh Refine (no edits) this control sits over the picture's top-left corner and hides a "22" there. It shows once the control is gone after edits (compare paper-fitted-1 with paper-fitted-3).

### Three Pen lines raised the tiny-numbers count from 1 to 4
This is expected, since slivers between close lines are tiny (pen3). I note it only because the badge's zoom has no way back without a pinch.

## Automation problems
- The first two taps on Edit Paint's color well (point 339,1252, then id `refine-colors-picker`) left no picker on screen; the third (336,1248) opened it. Later taps by id opened it at once.
- `tapOn id: refine-paint-14` selected Paint 15, the swatch to its right (the known Maestro offset).
- While an area card is open, the hierarchy hides the top bar (`refine-cancel` was not found, about a 17 s wait). A tap in the top bar (800,60) closed the system picker but not the card; a tap on the canvas closed the card.
- At first I tapped New Painting at a screenshot-pixel position, which missed (points ≠ pixels). Then `tapOn: "Close"` closed the New Painting sheet instead of the tip.

## Not tested
- Bug 1's picks with Similar colors too off, or with picks made faster than about 5 s apart (Maestro's pace).
- The Pen end at higher zoom (I avoided zooming in Refine), and anything shown only while a finger is down.
- Pinch and two-finger gestures.
- Done (applying Refine), and the rest of Refine (Looks, Merge, Move Edge, Writing, Try Painting).
