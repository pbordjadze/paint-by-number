# Paint by Moonlight — Refine exploratory test (iPhone 17 Pro sim, Debug)

## Summary
Refine was opened from the Red Fuji sample's New Painting preview and exercised for about 18 minutes. The new views menu works, and every group tab holds the right tools. Paper's new numbers pile up until they can't be read on large neighbouring cells, and the views symbol jumps sideways in Paper. In Edit Paint, "Similar colors too" recolours clearly dissimilar paints. In an area's card, a sequence of colour picks often doesn't end on the last colour picked. Cancel throws away every Refine edit at one tap, without asking, and the canvas stays shrunk after a taller panel closes.

## Coverage
- (1) Views menu on iPhone: **done**. It opens; Painting, Paper, Photo and Photo Behind can each be picked; the symbol's glyph follows the view, but its position shifts (bug 2). Nothing in the top bar wraps, clips or overlaps (Help, Cancel, views symbol, Undo, Redo, Done all on one line).
- (2) Paper numbers: **done** at the fitted zoom (illegible piles, bug 1) and deep zoom (legible). Pen strokes that close a cell give it numbers in the first screenshot after the stroke (shots/pen4-immediate.png); one earlier stroke looked late (Suspicions).
- (3) Tiny-numbers badge makes way for a note: **done, works**. The Looks › Pastel note "Colors that came out alike share a number now." showed, and "1 tiny number" was gone while it showed (shots/looks-pastel.png); the badge came back afterwards.
- (4) Edit Paint, Looks, area card: **done**. Edit Paint: the last colour sticks, and Undo/Redo step through each pick (3 of 3 steps both ways). Looks: one Undo step per Look. Area card: bugs 4 and 5. Notes for things the app can't do: partly tried. A plain tap with Merge did nothing and showed no note (Suspicions).
- (5) Group tabs: **done, correct**. Ink 5 (Pen, Shapes, Bend Line, Eraser, Line Eraser), Cells 5 (Select, Cell Edge, Merge, Move Edge, Fill Shape), Paint 5 (Bucket, Paint Brush, Eyedropper, Edit Paint, Looks), Numbers 1, See 2 (Writing, Try Painting).
- Free use: Pen strokes, Undo/Redo, Paint group tools, the tiny-number badge (which zooms to the tiny number), Merge tap, Cancel.

## App bugs (reproduced)
### 1. Paper view: numbers of large cells overlap into an illegible pile
Steps: New Painting › Samples › Red Fuji › Refine › views symbol (refine-backdrop) › Paper.
Expected: one legible number per cell, not overlapping.
Observed: at the fitted zoom, a dozen large "2"s on the mountain stack on top of each other into a dark blot; along the bottom, the "19"s run together ("191919"). Zoomed in deep (through the tiny-number badge), the numbers are legible.
Reproduced: 2 of 2 (first visit, and again after Photo › Photo Behind › Paper).
Evidence: shots/paper-view.png, shots/paper-view-2.png; zoomed: shots/tiny-tap.png

### 2. The views symbol changes position in the top bar with the view
Steps: as above; pick each view in turn.
Expected: the symbol stays in one place and only its glyph changes.
Observed: Painting, Photo and Photo Behind put it at x=128–159 pt, beside Cancel. Paper puts it at x=189–213 pt, centred between Cancel and Undo (inspect_screen bounds, matching the screenshots). The control jumps about 60 pt sideways.
Reproduced: 2 of 2 for Paper.
Evidence: shots/views-menu.png, shots/paper-view.png, shots/photo-view.png, shots/photobehind-view.png, shots/paper-view-2.png

### 3. Edit Paint with "Similar colors too" recolours clearly dissimilar paints (the blue sky)
Steps: Refine › Paint group › Edit Paint ("Similar colors too" is on by default) › select paint 2 (Red) › colour well › pick a colour.
Expected: only paint 2 and paints close to it (the oranges and reds) change.
Observed: picking purple for paint 2 also turned the sky's blue to slate-violet and the beige clouds to pink (shots/picker-closed.png). Picking red 51 for paint 3 (Grayish brown) turned the whole blue sky bright red and the clouds pale cyan (shots/looks.png, taken before any Look was applied). Palette names afterwards: "1 · Vivid yellow, 2 · Vivid orange, 3 · Vivid red … 14 · Vivid red, 15 · Vivid orange".
Reproduced: 2 of 2 (paint 2 and paint 3).
Evidence: shots/group-numbers.png (original colours), shots/picker-closed.png, shots/looks.png

### 4. Area card (Only This Area): the last colour picked often doesn't stick
Steps: Refine › Paint group (any tool) › long-press a pale cloud area › card › colour wheel beside "Only This Area" › in the system picker's Grid, tap colour A, then colour B › close (X) › swipe the card down.
Expected: the area ends up in colour B.
Observed:
- Run 1 (bright yellow 69, then green 54, with a screenshot between opening the picker and the picks): green. Correct (shots/card-after-pick.png).
- Run 2 (bright yellow 69, then purple 38, no pause): the area ended **yellow**, so the purple pick was lost (shots/card2-after.png).
- Run 3 (bright yellow 69, then purple 38, no pause): the picker's selected-colour square stayed pale, and neither pick applied. After closing, the card said **"White · Paint 25 · 1 area"**: a new paint was made in roughly the area's old colour (shots/card3-picker-before-close.png, shots/card3-card-after-close.png).
- A single pick made after a pause applied at once (shots/card3-picker2-purple.png).

Each Maestro tap lands 5 s or more after the previous one, so these were not unusually fast picks. No note or log line appeared for the lost picks. Edit Paint's picker kept every pick in the same kind of sequence.
Reproduced: wrong final colour in 2 of 3 runs.

### 5. The area card's colour picks make one Undo step, while Edit Paint's make one each
Steps: as bug 4, picking two colours in one card; then Undo, Redo.
Expected (per the brief): Undo and Redo step through the colour changes one at a time, as Edit Paint does (purple → azure → green → original, and back).
Observed: the change counter rose by 1 for two picks (8 → 9). Undo went straight from green to the original pale colour, skipping yellow, and Redo went straight back to green (shots/card-undo1.png, shots/card-redo1.png). In run 3, Undo went from purple straight to pale, skipping the "White" paint (shots/card3-undo1.png).
Reproduced: 2 of 2 card sessions. (This may be deliberate coalescing, but it is inconsistent with Edit Paint.)

### 6. Cancel discards every Refine edit at once, with no confirmation
Steps: Refine › make edits (run 1: 3 Pen strokes, colour edits and area recolours, "9 changes"; run 2: one Pen stroke) › tap Cancel (the X beside the Help button).
Expected: since this can't be undone, a confirmation ("Discard changes?"), or the edits kept for the next visit.
Observed: Refine closed at once, back to the New Painting preview. Reopening Refine showed the untouched generated painting, with Undo disabled.
Reproduced: 2 of 2.
Evidence: shots/cancel-tap.png, shots/refine-reopen.png, shots/cancel2-before.png, shots/cancel2-after.png
(Cancel sits right beside Help, so a mis-tap can lose a long session.)

### 7. The canvas doesn't grow back after a taller bottom panel closes, leaving a large empty band
Steps: Refine (Ink: canvas frame 116–681 pt) › views › Photo Behind (blend slider appears; canvas shrinks to 116–626) › views › Paper. Or: Paint › Looks (Looks panel; canvas shrinks to 116–509) › Ink or Cells.
Expected: the canvas regains the space once the panel is gone.
Observed: the canvas stayed at 116–626 in Paper, and at 116–509 in Ink and Cells. That leaves about 175 pt of empty grey between the canvas and the Snap row or palette on an iPhone, where space is precious.
Reproduced: 2 of 2 (Photo Behind → Paper; Looks → Ink, then Cells).
Evidence: shots/paper-view-2.png, shots/merge-tap.png, shots/canvas-gap-ink.png, shots/canvas-gap-cells.png (inspect_screen refine-canvas bounds as quoted)

## Suspicions
- **The changes counter isn't consistent.** Each colour pick added one change (3 strokes plus 3 picks = "6 changes"; 2 more picks made 8). Applying Moonlit and then Pastel brought it down to "4 changes", and Undo back to Moonlit still said 4. A second Undo said 8 again. So the counter fell as I made more edits. Seen once.
- **The selected paint jumps after Looks and Undo.** Paint 3 was selected. Pastel selected 13, Undo to Moonlit selected 8, and Undo to before the Looks selected 11 (not 3). The palette scrolls each time. Seen once.
- **The Edit Paint colour well didn't open the picker once.** Right after tapping paint 2's swatch, a tap on the colour well (refine-colors-picker) left no picker (shots/picker-open.png); a second tap opened it. Later (swatch 3, then the well) it opened at the first tap. Seen 1 of 2; no note.
- **The area card opens late.** After the long press, the card wasn't on screen at the next inspect_screen and appeared only by the following screenshot (a few seconds later). Seen once.
- **The area card is missing from the accessibility hierarchy.** While the card was on screen, inspect_screen listed only the Refine screen behind it: no "Only This Area", paint chips or "Show Its Other Areas". The system colour picker it opens is listed. This may mean the card isn't reachable with VoiceOver. Seen on 3 of 3 cards; whether it's the app or Maestro is unconfirmed.
- **A tap with Cells › Merge does nothing and shows no note.** The cell edges show dashed, but a tap neither merges nor explains that Merge needs a drag (shots/merge-tap.png). The counter stayed at 9. Seen once.
- **A Pen stroke showed late once.** After my first stroke, the screenshot showed the line but Undo still disabled and no new numbers (shots/pen-split.png). After the next stroke, the first stroke's new numbers (18, 5) were there. Later strokes showed their numbers in the first screenshot (shots/pen4-immediate.png). Seen once.
- **A new number sits on a line.** A new cell's "18" was drawn on top of a short line at the left edge (shots/pen4-later.png, left, y≈1050 px). Seen once.
- **"Olive" for a bright green.** The card named the area "Olive" after green 54 was picked (shots/card-after-pick.png). Naming only.

## Automation problems
- A double tap (Maestro doubleTapOn) on the Paper canvas with the Pen tool active didn't zoom (tried once). I zoomed through the tiny-number badge instead.
- Maestro's swipe draws only straight Pen strokes, so a closed freehand shape was approximated with a straight stroke from one line to another. One stroke didn't reach the upper line and closed nothing (shots/pen3-later.png): my aim, not the app.
- The area card isn't in Maestro's hierarchy, so its controls were tapped by coordinates (the colour wheel at 361,603 pt).
- A `tapOn: "Cells"` while the card was up, followed by `tapOn: id refine-tool-select`, failed: the card covered the toolbar.
- The app log (app.log) carried only tips lines for this session, so it gave no evidence for the colour or undo issues.

## Not tested
- The card's "Or Use a Paint" chips and "Show Its Other Areas"; the Spectrum and Sliders tabs of the picker; the Looks Strength slider.
- Cells tools other than a Merge tap (Cell Edge, Move Edge, Fill Shape, Select), Writing, Try Painting, Shapes, Bend Line, the Erasers, Bucket, Brush, Eyedropper.
- Pinch zoom and two-finger pan or tap (not available in Maestro); swipe previews while a finger is down; intermediate zoom levels of Paper (only fitted and deep).
- Done (committing Refine) and Start Painting afterwards; the Blank start; iPad layout.
