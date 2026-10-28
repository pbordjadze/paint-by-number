# Paint by Moonlight: exploratory test, Refine session (2026-10-28, 04:12–04:31)

## Summary
This session tested Refine's new controls, opened from a photo preview (the parrots photo), then carried the refined painting through Start Painting, one fill, and a quit and relaunch. Layers, Select › Change Color, the Size slider, the Line Eraser tap, Make Cell, Cancel's confirmation and the Tool Guide mostly worked as described, and every Refine change carried into the painting. Three problems reproduced:
- A held touch (the Eyedropper) while the Photo layer is showing picks a colour from the photo, not the cell's paint.
- A paint emptied by Make Cell leaves a gap in the painting's numbers (no 11), and the preview's colour count (40) disagrees with the palette (39).
- A freshly made painting opens on swatch 15, not swatch 1.

No crashes (crashes.txt is empty).

## Coverage
1. Create a painting: done. Photo › preview › Refine › Done › Start Painting. 177 areas opened (log 04:27:46). The "painting never drew" hand-off line appeared (by design).
2. Paint: partly. I filled one large area of paint 15 at the fitted zoom by tapping the centre of `canvas-area-5`. It was painted in the swatch's olive and progress went 0% → 1%. Zoomed-in painting and drag painting were not tried (time).
3. Zoom navigation: not tried (time).
4. Gallery round trip: done, lightly. After the fill and the relaunch, Back to the gallery shows the painting under In Progress, "1% painted", with the fill in its thumbnail (shots/gallery-after-paint.png); the painting also showed 1%.
5. Quit and relaunch: done. Home, screenshot, then stopApp + launchApp (not a bare stopApp). The app reopened the painting with the fill kept and 1% shown (shots/relaunch.png).
6. Refine, the session's focus:
   - Layers button: done. The Numbers, Ink, Paint and Photo switches, the Paint and Photo opacity sliders and "Your tool's layer" (Ink for Pen, Paint for Bucket) all match the picture. Drawing with the Pen while Ink was hidden turned Ink back on (sensible).
   - Held touch picks the cell's paint: done. Correct with Photo off; wrong with Photo on (bug 1). The tool stayed the same and nothing was drawn, as expected.
   - Select › Change Color › area card: done. "Or Use a Paint" recolours the cell; Undo restores it.
   - Eraser and Line Eraser Size slider: done. Size changes the width; the value ("11 points") is shared by both tools.
   - Line Eraser: done. A tap removed my stray line out to the next junction; a drag rubs out like the Eraser, as the Guide says.
   - Pen Smoothing: slider seen (0% by default). Not tried with a wobbly line, because Maestro swipes are straight.
   - Make Cell: done on the main picture (the chest became a new paint 40 in the photo's yellow) and in the Guide's practice (the moon).
   - Cancel with changes: done. It asks "Discard Your Changes? Refine goes back to how it was when you opened it." with Discard Changes. Dismissing the popover kept all 3 changes. I did not tap Discard Changes.
   - Tool Guide: done. It opens on the current tool (log 04:23:50, "smartEraser"). The Layers, Coming from Procreate and Make Cell pages (Good to Know, In Procreate, Goes Well With) read correctly and match the app.

## App bugs (reproduced)

### 1. Held touch with the Photo layer showing picks the photo's colour, not the cell's paint
- Steps: + › Your Photos › parrots photo › Refine. Layers: Photo on (100%), Paint 44%. Pick Bucket. Long-press the yellow chest of the left parrot (paint 11, Vivid yellow), at point 427,888 and again at 413,812.
- Expected: the palette ring moves to swatch 11 (the cell's paint); nothing is drawn; the tool stays Bucket.
- Observed: no swatch is selected (no ring; `inspect_screen` shows no swatch `selected`). The current-colour well (`refine-palette-new`) becomes a yellow that isn't in the palette, with a different name each time: "light vibrant amber", then "bright amber". So the colour comes from the photo pixel under the finger, not from the cell. Nothing was drawn (canvas still "1 change") and Bucket stayed selected.
- Control: with Photo off (Paint 81%), the same long-press at 413,812 rings swatch 11 correctly (`selected` on the swatch). With Photo on, a hold on the red parrot (826,661) did ring swatch 4, perhaps because that photo pixel happened to match paint 4.
- Reproduced: 2 of 2 with Photo on (yellow cell); with Photo off, 1 of 1 correct.
- Evidence: shots/hold-bucket-yellow.png, shots/hold-bucket-yellow-2.png, shots/hold-bucket-red.png, shots/layers-photo-off-paint100.png, shots/hold-bucket-yellow-photo-off.png. app.log has no lines for holds.

### 2. A paint emptied by Make Cell leaves a gap in the painting's numbers, and the preview's colour count is off
- Steps: in Refine, with Make Cell, tap the yellow chest (the only area of paint 11, Vivid yellow) › Done › preview › Start Painting.
- Observed in Refine: the chest becomes new paint 40 (the photo's yellow), but swatch 11 (Vivid yellow) stays in Refine's palette with no areas. The preview then reads "40 colors · 177 areas" (it read 39 colors before Refine). The painting's palette has 39 swatches numbered 1–10 and 12–40: there is no 11.
- Expected: either the emptied paint is dropped and numbers are compacted, as Change Color does (there paint 11 vanished and 12→11 etc. immediately), or it isn't counted. In any case the preview's count should match the palette, and the numbers shouldn't skip.
- Reproduced: the gap and the missing swatch were seen on 3 of 3 opens of the painting (first open after Start Painting, reopen from the gallery, and after relaunch); the inspect tree lists swatch-10 then swatch-12. The Refine step itself was done once.
- Evidence: shots/makecell-chest.png, shots/after-refine-done.png, shots/painting-opened.png, shots/painting-palette.png, shots/painting-reopened.png, shots/relaunch.png.

### 3. A new painting opens on swatch 15, not the first swatch
- Steps: Start Painting from the preview above (no area painted yet); then Back and reopen it from the gallery.
- Expected (by design): a painting opens on the palette's first swatch (1).
- Observed: both times it opened on "15 · Flint" (`current-color` "15, Flint, olive"; swatch-15 `selected`). After one area was painted and the app was quit and relaunched, it opened on "1 · Faded Rose", as designed. So this may concern only untouched paintings, perhaps ones made through Refine.
- Reproduced: 2 of 2 before any painting. Evidence: shots/painting-opened.png, shots/painting-reopened.png, shots/relaunch.png; log 04:27:46 and 04:28:27 "Opened B3A16150… 177 regions".

## Suspicions

### After Change Color empties a paint, the current paint silently becomes a different one
- Steps: Select › tap the yellow chest (paint 11, ringed) › Change Color › Or Use a Paint › 2.
- Observed: the chest becomes paint 2; paint 11 is dropped and every later paint is renumbered across the picture. The ring stays at position 11, which is now Dark yellow, so the current paint changed without the user choosing it. After Undo the old numbering returns and the ring follows Dark yellow to 12; it doesn't return to Vivid yellow.
- Seen once. Evidence: shots/select-yellow.png, shots/change-color-card.png, shots/change-color-use-paint2-again.png, shots/change-color-undo-2.png.

### Area summary is ambiguous after a change
- After the change the Select bar reads "Vivid red · Paint 2 · 2 areas · 5.4% of the picture". 5.4% is the chest alone, but paint 2's two areas include the large head, so it reads as if paint 2 covers 5.4%. Seen once (shots/change-color-use-paint2-again.png).

### One eraser stroke across an outline recolours a whole neighbouring cell
- Eraser at a large size, one vertical stroke across the red parrot's head outline: the head merged with the background and the whole head became paint 15 (olive-brown). Undo restored it. Probably the designed "cells the line kept apart become one", but a user rubbing out a stray line may not expect to lose the head's red. Seen once (shots/eraser-small-then-large.png, shots/eraser-undo1.png).

### Make Cell shows the palette though it doesn't use it
- With Make Cell selected, the paint palette shows (ring on 12), yet Make Cell always takes the photo's colour (Guide: "To pour a paint you chose, use the Bucket"). It could suggest the chosen paint will be used. Seen once (shots/makecell-selected.png).

### Tool Guide text shows through under the practice panel
- Make Cell page, scrolled: the line "Tap a cell you made to take it out again." shows clipped in a strip between the practice palette and the panel's edge. Cosmetic; seen once (shots/guide-makecell-scrolled.png).

### Canvas moves as panels appear
- The picture moved up when the palette first appeared (Bucket) and again when Select's card appeared: top edge at 609, 603, then 559 px in screenshots. This is the by-design "room of the tallest panel"; listed only because the user isn't touching it then. shots/layers-pen.png, shots/layers-bucket.png, shots/select-yellow.png.

## Automation problems
- A tap on the Paint Opacity slider track didn't move it (standard iOS slider); dragging the thumb did.
- The first tap on swatch 2 in the area card (286,757) did nothing; a second tap at 291,758 worked. The first Undo tap by point (829,54), right after closing the card, also didn't undo; Undo by id did. Each seen once; probably taps that landed during an animation.
- While the area card is open, `inspect_screen` doesn't list the top bar, so `tapOn: id: refine-undo` failed (about 17 s wait) until the card was closed.

## Not tested
- Pen Smoothing on a wobbly line (Maestro draws only straight swipes).
- The Eyedropper's loupe and the cell highlight during a drag (they show only while a finger is down); dropping a swatch on a cell; two-, three- and four-finger gestures; Pencil.
- The card's system colour picker (Color); Discard Changes actually discarding; Edit Paint, Looks, Merge, Move Edge, Cell Edge, Shapes, Bend Line, Move Number.
- In the painting: zoomed-in fills, double-tap zoom, Hint, undo, a wrong-colour tap, drag painting.
