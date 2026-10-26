# Paint by Moonlight — Refine exploratory test (iPad Pro 13" sim, Debug build), 2026-10-26

## Summary
Refine opens from the New Painting preview (sample "Jūmantsubo Plain at Fukagawa Susaki", 23 colors, 192 areas). Several things work:
- The tool rail is complete and in order.
- The Tool Guide opens on the tool in hand.
- A Pen line that closes a new cell gives it a number at once.
- Zoomed-in Paper numbers are legible.

Two serious problems:
- In Edit Paint, the open system color picker silently switches to a different paint after a pick (Paint 1 → 18, Paint 9 → 6), so the next pick recolors paints the user never chose. With "Similar colors too" on, that spreads across the picture.
- At the fitted zoom, Paper draws many overlapping copies of a big cell's number, so it can't be read.

No crashes (crashes.txt empty).

## Coverage
- (1) Paper numbers: done as far as reachable.
  - Fitted zoom: numbers show but overlap (bug 2).
  - Deep zoom (reached through the tiny-number badge): numbers are crisp and legible (shots/41-paper-zoomed.png).
  - A closed cell made with the Pen got its number at once (shots/08, 09).
  - In-between zoom levels and zooming as a motion were not reachable (no pinch; double tap doesn't zoom Refine).
- (2) Tiny-number badge making way for a note: not tested. I never got a note to appear. The badge itself works: a tap zooms to the tiny number (shots/40-tiny-tap.png).
- (3) Colors:
  - Done: the area card ("Only This Area") with the system picker, the Edit Paint color well, and Looks.
  - The last color picked sticks after quickly closing the picker and card.
  - Undo/Redo step per picker session, not per color (bug 3).
  - Not seen: a note for something the app can't do.
- (4) Tool rail: done. It matches exactly (Ink: Pen, Shapes, Bend Line, Eraser, Line Eraser; Cells: Select, Cell Edge, Merge, Move Edge, Fill Shape; Paint: Bucket, Paint Brush, Eyedropper, Edit Paint, Looks; Numbers: Move Number; See: Writing, Try Painting). The Tool Guide opened on "Writing" with Writing in hand (log 20:30:10 "Tool Guide page shown: text"; shots/44-guide-writing.png).
- Free use: one Pen line across the red cartouche (the writing) split it cleanly into two cells. Not tried: the Writing view's detection on this picture (I was stuck zoomed in), other drawing tools, Done/Cancel.

## App bugs (reproduced)
### 1. Edit Paint: while the system color picker is open, a pick can switch it to another paint, and the next pick recolors that paint
- Steps: Refine › Edit Paint tool ("Similar colors too" on, its default) › select a paint in the palette › tap the color well next to "Paint N" › pick colors from the picker's swatch row, one at a time.
- Expected: every pick in this picker changes the paint it was opened for; paint numbers stay put.
- Observed:
  - Run 1, opened on Paint 1 (Red). Picking green turned Paint 1 green, as expected. But at the same moment:
    - the bar's label became "Paint 18";
    - the picker's current color became Paint 18's gray-brown, and the eagle (Paint 18) was outlined;
    - the palette was renumbered: swatch 3 "Beige" → "Pale gray", 7 "Grayish orange" → "Vivid blue", 18 "Dark blue" → the gray-brown.

    The next pick (blue) recolored Paint 18, and through "Similar colors too" the whole sky and paint 7 too.
  - Run 2, opened on Paint 9 (light grayish green). Picking red recolored Paint 9 (and similar paints 4, 5, 11), and the picker stayed on Paint 9. Picking yellow next turned Paint 9 yellow, but the bar then read "Paint 6" and the picker showed Paint 6's gray, outlining Paint 6's areas. A further pick would have recolored Paint 6.
- Nothing in the log.
- Reproduced: 2 of 2 picker sessions (the jump came on the 1st pick in one, the 2nd in the other).
- Evidence: shots/24-editpaint-well-3.png, 25-editpaint-green.png, 26-editpaint-blue.png, 27-editpaint-closed.png; 29-paint9-picker.png, 30-paint9-red.png, 31-paint9-yellow.png, 32-closed-paint6.png.
- Related: Looks also moves the selected swatch on every preset (4 → 14 → 8; Undo → 13; shots/33–39).

### 2. Paper view at the fitted zoom stacks many overlapping copies of a cell's number
- Steps: Gallery › + › Samples › Jūmantsubo Plain at Fukagawa Susaki › wait for the preview › Refine › close the tip › tap "Paper".
- Expected: each cell shows its number once (or a few copies, spaced apart), legible.
- Observed: the sky cell carries about 20 "15" labels of different sizes piled on top of each other ("151515…"). Select calls it one cell ("Grayish teal · Paint 15 · 3 areas · 20% of the picture"), and there are no dashed borders inside it. The same happens at the bottom right ("10 10 1010" overlapping) and in the "2" water area. Unreadable. Deeply zoomed in, single numbers look fine.
- Reproduced: 3 of 3 (opening Paper; switching Painting › Paper again; after the Pen edit).
- Evidence: shots/03-paper.png, 05-select-sky.png, 07-paper-again.png, 08-pen-split-cartouche.png.

### 3. Picks in the system color picker don't each get an Undo step (area card)
- Steps: Edit Paint tool › long press an area › tap the "Only This Area" color well › pick blue, then green, then yellow › close the picker and card › Undo.
- Expected (per this branch's brief): Undo/Redo step through the color changes one at a time.
- Observed: one Undo went from yellow straight back to the color before the session (light beige), skipping green and blue. A second Undo went back to red. Redo replayed beige, then yellow. Each picker session is a single step: the first session (blue + an accidental peach) was also one, and the canvas value read "2 changes" after line + session. This may be intended coalescing; flagged because the brief asks for one-at-a-time.
- Reproduced: 2 of 2 sessions.
- Evidence: shots/19-after-green-yellow-close.png, 20-undo1.png, 21-undo2.png, 22-redo1.png, 23-redo2.png.
- What did work: after picking and then closing the picker and card quickly, the last color picked (yellow) stuck. Looks: each preset is one Undo step and Undo restores earlier manual colors (shots/37–39).

### 4. Every Undo/Redo in Refine makes the preview behind it offer its tips again (log only)
- The log shows "offer in preview: newPaintingDivider, newPaintingSliders, newPaintingRefine, wanted" at these times, each matching an Undo/Redo tap while Refine covered the preview:
  - 20:19:43, 20:20:06, 20:20:27, 20:20:38;
  - 20:27:34, 20:27:49, 20:28:01.
- No tip appeared on screen. It suggests the hidden preview re-runs on every Refine change.
- Reproduced: 7 of 7 Undo/Redo taps.

## Suspicions
### A. Area card: the picker moves after the first pick
- The first pick in "Only This Area" turns the area into a new paint (Paint 24). The card then re-lays out (title "Only This Area" → "Color"), and the system picker popover moved about 37 pt lower.
- My second quick tap at the same spot landed on the grid's pale peach instead of the green swatch, so the area ended "Light beige". Seen once (shots/13-card-picker.png vs 17-picker2.png; 14-after-card-colors.png). A painter making quick successive picks would hit a wrong color.
- Paint 24 (one area, the lower half of the cartouche) reported "0.57% of the picture". That is the same share Paint 1 reported for all 4 of its areas just before, which looks wrong (shots/09, 15).

### B. Lines out of register with fills while the Looks panel grows
- On the first tap of "Moonlit", the screenshot taken after the animation settled showed the line art offset right and down from the fills: the cartouche outlines sat beside their pink fills, and the eagle's lines were shifted (shots/34-looks-moonlit.png). This happened as the Strength slider appeared and the canvas shrank.
- Tapping Moonlit again later showed everything aligned (shots/36-looks-moonlit-2.png). Seen once; possibly a frame caught mid-resize, but it was still there after `waitForAnimationToEnd`.

### C. Looks replaces manual paint edits
- Applying Golden Hour or Moonlit after Edit Paint recolors discarded them: the green and yellow cartouche halves went back to red-orange and cream (shots/35).
- Undo restores them, so nothing is lost. But a painter may not expect a Look to wipe hand-picked colors without a note.

### D. Edit Paint color well sometimes ignores taps
- The first two taps on the color well (by id, then by point), right after choosing the Edit Paint tool, opened nothing, and nothing appeared in the log. Later taps (by point and by id) opened it. Seen 2 of 4; may be Maestro timing.

### E. No way back from the tiny-number zoom without a pinch
- Tapping "1 tiny number" zooms about 10× (canvas bounds about 7900 pt wide). Refine offers no Fit/zoom-out control, and a double tap doesn't zoom out. On a device a pinch works, so this mostly blocks automation. Still, a button-only route out (e.g. tapping the badge again, or a Fit control) would help.

## Automation problems
- On the New Painting sheet, `tapOn: "Close"` meant for the "No Photo at Hand" tip closed the whole sheet: the tip had already gone, and the sheet's X is also labelled "Close". Tips' close buttons are safer tapped by point.
- `doubleTapOn` on the Refine canvas did not zoom in or out (2 tries, Select and Writing tools). There is no pinch, so I ended the session stuck at the tiny-number zoom.
- Maestro `swipe` draws only straight lines; freehand shapes, and anything visible only while a finger is down, were not tried.
- While the system color picker is open, `inspect_screen` shows only the picker (no palette or bar).
- Palette swatches scrolled out of view (e.g. `refine-paint-2`) can't be tapped by id; the tap silently did nothing.

## Not tested
- The tiny-number badge making way for a note: I didn't manage to trigger a note.
- Paper numbers at intermediate zooms.
- The Writing tool's detected lines on this picture.
- Shapes, Bend Line, Eraser, Line Eraser, Cell Edge, Merge, Move Edge, Fill Shape, Bucket, Paint Brush, Eyedropper, Move Number, Try Painting.
- Done/Cancel, and the painting that Refine produces.
- Painting, gallery, and relaunch persistence (outside this session's Refine focus).
