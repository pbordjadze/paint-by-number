# Paint by Moonlight — exploratory test, Refine on iPhone 17 Pro (debug build), 2026-10-28

## Summary
I opened Refine from the New Painting preview of the "Red Fuji" sample (22 colors, 248 areas). On iPhone, Select › Change Color behaves as described: the card replaces the palette inside Select's bar, nothing covers the picture, and the button reads Close. "Or Use a Paint", "Only This Area" and "Show Its Other Areas" all worked. The Eraser and the Line Eraser removed a paint whose only area they took ("Navy"), and the numbers after it closed up. Edit Paint, Move Number and the Eraser were each taken back by Undo. After Done, the preview read "24 colors · 248 areas", and the painting's palette (1–24, with the two new paints 23 and 24 last) matched Refine; painting them worked. No crashes; no app bug was reproduced twice. The main suspicions: the card's colour well failed to open the picker 3 times early in the session, colour wells report wrong accessibility colour names, and a Bend Line drag (via Maestro) made no change.

## Coverage
- 1. Select › Change Color on iPhone: **done**.
  - The card opens in Select's bar, in the palette's place, with nothing over the picture. Change Color becomes Close (shots/change-color-card.png).
  - "Or Use a Paint" 4 recoloured the mountain cell. The header updated to "Grayish red, Paint 4 · 2 areas" (shots/card-use-paint4.png).
  - "Only This Area" (yellow) made a new paint 23 with 1 area; the paint's other area was unchanged (shots/only-this-area-yellow.png).
  - Close returns to the palette.
  - "Show Its Other Areas" switches to Paint › Edit Paint on that paint and outlines its areas (shots/show-other-areas.png).
- 2. Eraser and Line Eraser: **done, 1 case each, same line**.
  - I erased the right border of the inscription box (top left) at about (36,220–250 pt).
  - Both tools made the paint "Navy" (number 16) leave the palette. 17 Teal … 24 Vivid blue became 16 … 23. Undo and Redo toggled it correctly (shots/eraser-cartouche.png, shots/eraser-undone.png, shots/eraser-redone.png, shots/line-eraser-palette.png).
  - I couldn't identify the Navy area itself; it was presumably a small cell inside the box.
  - The purple paint I had given the box's inside kept its own cell: erasing ink doesn't merge cells.
- 3. One change each, then Undo:
  - Edit Paint: **OK**. Picking green with "Similar colors too" on recoloured paint 4 and similar paints; one Undo restored all (shots/edit-paint-green.png, shots/edit-paint-undo.png).
  - Move Number: **OK**. The "24" moved and shrank to fit; Undo put it back (shots/move-number.png, shots/move-number-undo.png).
  - Bend Line: **no change from a Maestro drag** (see Suspicions).
  - Move Edge, Looks: **not tried** (time).
- 4. Tool Guide: **partly**.
  - On the Move Number page, I scrolled the words under the practice panel; none showed over it (shots/guide-scrolled.png).
  - The list shows a description line under each page's name (shots/guide-list.png; the Start Here and Ink sections seen, the rest not scrolled).
- 5. Done, then Start Painting: **done**.
  - The preview read "24 colors · 248 areas" (22 original + 2 new paints).
  - The painting's palette ran 1–24, with 23 "Pitaya, vivid purple" and 24 "Hyacinth Bloom, vivid blue", matching Refine.
  - The canvas numbers matched (mountain 4, patch 24). The painting opened on paint 4, its largest area (debug build, by design).
  - I filled the mountain (4) and the patch (24) in the right colours. Progress showed 1%, and after 24 was finished the selection moved to paint 1 (shots/painted-24.png).
  - Leaving and relaunching: not tried (out of scope and time).

## App bugs (reproduced)
None reproduced twice.

## Suspicions
### The card's "Only This Area" colour well didn't open the picker (3 failures, then 3 successes)
- Steps: New Painting › Samples › Red Fuji › Refine › Cells › Select › tap the mountain (300,420 pt) › Change Color › "Or Use a Paint" 4 › tap the colour well at the right of "Only This Area".
- Expected: the system colour picker opens.
- Observed: nothing happened and nothing was logged in app.log, 3 of 3 tries (20:53–20:54): by id `refine-card-color`, and by point at (356,615) and (362,612).
- Later the same well opened at (358,615) on 3 freshly opened cards (20:57–21:01): the hill, the hill after "Or Use a Paint" (so using a paint first is not the trigger), and the inscription box. Edit Paint's well opened first time.
- This may be a first-use issue in the session, or an automation fluke; I couldn't reproduce it.
- Evidence: shots/only-this-area-tap3.png (failed), shots/only-this-area-tap4.png and shots/well-after-use-paint.png (opened).

### Colour wells' accessibility value doesn't describe the shown colour
- `refine-card-color`, `refine-colors-picker` and `refine-palette-new` all reported "vermilion" while showing Paint 4's dark grayish red, in several hierarchies.
- Before any change `refine-palette-new` read "red orange". After a vivid-yellow pick `refine-card-color` read "very light yellow".
- VoiceOver would announce the wrong colour.

### Bend Line: a Maestro drag across an ink line made no change (1 try)
- Steps: Ink › Bend Line, then swipe (203,349)→(185,322) pt over 1.2 s across the mountain's left slope line.
- Observed: no visible change, the change count stayed at 3, and Redo stayed enabled.
- The guide says "Drag a line to reshape it", so this may be an automation limit (Maestro's swipe touch) rather than the app.
- Evidence: shots/bend-before.png, shots/bend-after.png

### Line Eraser: one swipe made two history steps, and the first Undo showed no visible change
- One vertical swipe (36,222→36,248) raised the count from 3 to 5. The first Undo went 5→4 with no visible change; the second restored the line and the Navy paint.
- A single tap at (36,235) made exactly one step (3→4). The guide says "Takes out a whole line with one tap", so the swipe probably took two lines, one of them too small to see. Likely fine.
- Evidence: shots/line-eraser-after.png, shots/line-eraser-undo1.png, shots/line-eraser-undo2.png

### One card session is one Undo step, including "Or Use a Paint"
- One card session recoloured the hill yellow ("Only This Area"), then used paint 4. A single Undo returned it to the original grayish blue (shots/card-undo1.png).
- The brief says the card's picker is one step. That this also covers "Or Use a Paint" picks may or may not be intended.

### Minor UI observations
- On the first Select, the palette's ring stayed on paint 1 while the bar said "Red, Paint 2" (shots/change-color-card.png).
- After "Only This Area", "Show Its Other Areas" is disabled and leaves an empty row in the card (shots/only-this-area-yellow.png).

## Automation problems
- Opening the painting's More menu brings up the software keyboard (simulator, not the app).
- Maestro's swipe can't press and hold, which may explain Bend Line.
- refine-cell-<n> elements are absent (VoiceOver is off), so I tapped by point.
- The colour picker failures above may be automation-related.

## Not tested
- Move Edge (on a Cell Edge line) and Looks, each with Undo (time).
- The Tool Guide's later list sections and other pages.
- Pinch, multi-finger undo/redo, held undo, the Pencil, dragging a swatch onto a cell.
- Previews shown only while a finger is down.
- Back to the gallery and relaunching after the refined painting was started.
