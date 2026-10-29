# Paint by Moonlight: exploratory test of Refine's Tool Guide

## Summary
Reaching Refine's Tool Guide was easy (+ → a sample → Refine → the ? button). The guide's practice picture is not the same on every page:
- **The Basics, Bend Line, Eraser, Line Eraser and Select** show it painted: cream moon (paint 4), dark tree, red roof, cream cottage, yellow window.
- **Pen and Shapes** show the same drawing with the moon painted the sky's purple (2) and the whole tree and cottage painted grass-green (1), as if their paint were missing.

The Pen mostly does what its page says. But the page never says how you can tell a cell was made, what "its own number" means, how close "touches" has to be for Snap, or when Color from Photo adds a new color. The Eraser's Try This can't be done at the default Size without destroying the window.

## Coverage
- **Goal 1 (reach the guide):** done, easily.
- **Goal 2 (Pen):** mostly done.
  - Done: a line ending on another line; Snap off and on, with ends short of and past a line; Color from Photo off and on, across the moon, tree and cottage.
  - Partly done: Smoothing. Maestro only draws straight lines, so I couldn't draw a shaky line.
  - Not done: the cloud (a closed freehand shape), which needs a curved stroke.
- **Goal 3 (practice picture):** done. Compared with five other pages (bug B1).
- **Goal 4 (other pages):** partly done.
  - Pages tried: The Basics (read only), Shapes, Bend Line, Eraser, Line Eraser, Select.
  - Pages not reached (time): Layers, Coming from Procreate, Cell Edge onward.

## What I learned, tool by tool

### Pen
**What the page says:** "The Pen draws ink: lines that show in the finished picture. A line that closes off a shape makes a new cell with its own number. Lines leave the colors alone, unless Color from Photo is on." The steps say:
- "End a line on another line to close a shape. With Snap on, an end that touches a line joins it."
- "Turn on Color from Photo to give each new cell the photo's color there."
- "Set Smoothing to steady your line: it trails your finger a little and evens out wobbles. All the way down, the Pen draws exactly as you draw."

**What I did and what happened** (Numbers layer on via the practice Layers button, so I could see the numbers):
1. **Line across the moon, Snap on, Color off** (shots/pen-2b-moon-colorOff.png): the moon split into two cells, both labelled **2**, the same number as the sky. I expected "its own number" to be a new number; it's the color number of the cell it came from. Colors didn't change, which matches the page.
2. **Color from Photo on, another line across the moon** (pen-4-moon-colorOn.png): the two pieces on either side of the new line turned cream and became a new number **4**. The pieces it didn't touch stayed purple 2. This matches the page.
3. **Lines across the tree and the cottage, Color on** (pen-5-tree-cottage-colorOn.png): the tree's halves became dark green, labelled **6 and 5**, though they look the same. The cottage walls became cream (7) and the door brown (8). The window panes and roof, which no line touched, stayed grass-green 1.
4. **Line from the picture's top border to the sky/river line, Color on** (pen-12, pen-13): the sky split, with a "2" in each half, so the border counts as a line. But Color from Photo kept the existing color 2, with no new number.
5. **Snap** (moon chord, Color on, so a new cell shows up as cream):
   - Snap on, ends about 4–6 pt short of the outline: no cell (pen-7).
   - Snap on, ends about 2 pt short: cell made, and the line ends sit cleanly on the outline (pen-8).
   - Snap off, the same 2 pt-short stroke: **no cell**, though on screen the line looks like it touches the outline (pen-9).
   - Snap off, ending past the outline: cell made, tails stick out (pen-10).
   - Snap on, ending about 3 pt past: cell made, and a small tail still shows (pen-11).
6. **Smoothing near the top, a straight line across the tree** (pen-14-smoothHigh.png): the line ran from where I touched down to where I lifted, with no visible trailing. I couldn't draw a wobbly line.

**My understanding now:**
- **Snap:** pulls a line end onto a nearby line when it lands within about 2–3 pt of it; further away, nothing happens. With Snap off, an end must actually cross a line. It doesn't trim ends that overshoot. *Fairly sure* (one try at each distance). The page should say how close counts as "touches", and that with Snap off a line that only looks like it touches may not close the shape.
- **Color from Photo:** when a line makes new cells, they're repainted with the photo's color under them, sometimes as a new palette color (moon 4, tree 5 and 6, walls 7, door 8) and sometimes as an existing one (sky 2). *Fairly sure* about the repainting, *unsure* about when a new number appears. The page should say that new colors are added to the palette, and when similar ones are merged.
- **Smoothing:** *not understood.* I couldn't test the wobble claim.
- **How you know a cell was made:** the page never says. With Numbers and Color off, a line that closed a shape looks exactly like one that didn't. (Shapes, by contrast, shows a note: "That shape is too small for a number.")

### Shapes
**What the page says:** "Shapes draws a clean figure across a drag… a closed figure becomes a cell of its own." Step 1 says "Pick a figure above the tools." Try This: "Draw a star in the sky. Then pick the curve and give the cottage a path to its door."

**What happened:**
- **Star:** a star corner to corner worked, and its inside became a slightly darker purple than the sky (shapes-1-star.png). The page doesn't explain the new color.
- **Curve:** dragging the ends worked, and a hint appeared: "Drag to bend the curve, or tap to keep it straight." When it appeared, the whole picture jumped up about 14 pt (shapes-2). Dragging the middle down about 20 pt bowed the curve much further, off the bottom edge, and a note said "That shape is too small for a number." (shapes-3)
- **Matches the page?** Mostly.

**Confusing:**
- "Above the tools": the figures are in a bar *below* the picture.
- The picture is unpainted (B1).

### Bend Line
**What the page says:** "Grab a line and drag… Its ends stay where they meet other lines, and the cells on either side keep their paint." Try This: "Pull the far hills' line up into a mountain."

**What happened:** dragging the top of the blue band up made a smooth mountain, and the blue cell followed (bend-1-mountain.png). This matches the page.

**Confusing:** nothing says which band is "the far hills". I guessed the blue band, which could also be water.

**Confidence:** sure.

### Eraser
**What the page says:** "Where it breaks a line between two cells, they become one, in the paint of the larger." Step 2: "Tap to take out a small dab." Try This: "Rub out the cross in the cottage's window, so its four panes become one."

**What happened:**
- **Default Size, short strokes:** the whole window vanished, frame and yellow panes, and merged into the cream wall (eraser-1).
- **Default Size, one tap at the cross's centre:** this "small dab" removed the whole cross *and* the middle of all four frame sides. The window again became cream wall (eraser-4).
- **Size at minimum, one tap:** only the centre of the cross went. The panes joined and stayed yellow (eraser-5), which is what the page promised.

**Confusing:** the page should tell you to set Size small or zoom in first.

**Confidence in the tool:** sure.

### Line Eraser
**What the page says:** "Tap a line and the Line Eraser takes it out from one junction to the next… The cells the line kept apart become one." Try This: tap the line around the moon, then the cottage's door.

**What happened:**
- One tap on the moon's outline removed the whole circle. The moon merged into the sky and disappeared (lineeraser-1).
- One tap on the door's side removed the door's three sides; the door merged into the wall (lineeraser-2).

**Matches the page?** Yes. But this page doesn't say whose paint the merged cell keeps (here the larger one's, as the Eraser page says).

**Also:** its Size slider was already at the minimum I'd set on the Eraser page, so the two tools seem to share one Size. The page doesn't say so.

### Select
**What the page says:** "Tap a cell to select it. It glows, and the bar below shows its paint and how many cells use it." Try This: select the sky, then the moon.

**What happened:**
- **Sky:** it glowed, and the bar showed "Purple · Paint 2 · 1 area" (select-1).
- **Moon:** "Light beige · Paint 4 · 1 area" (select-2).
- **Matches the page?** Yes.

**Confusing:**
- The page says "how many cells use it" but the bar says "area". "Area" is never explained on this page.
- The palette row below kept its ring on swatch 1 whatever I selected.
- When the bar appeared, the picture jumped up about 26 pt, as on Shapes (S4).

### The Basics (read only)
**What the page says:** "Cells are the areas the lines and edges make, each with its own number."

**Note:** in practice, numbers are color numbers that many cells share (on the Pen page, all of the grass, tree and cottage are "1").

## Confusions (ranked)
1. **Pen page: you can't tell whether a line made a cell.** With Snap off, a line ending about 2 pt short looks joined but isn't. The page should say: "Turn on Numbers in Layers to see new cells" (or the app should show a note, as Shapes does).
2. **Eraser page: the Try This fails at the default Size.** The "small dab" also removes the window frame, and the window loses its yellow. The page should say to lower Size or zoom in first.
3. **Pen and Basics pages: "its own number."** Numbers are color numbers shared by many cells (moon halves 2/2, sky halves 2/2). The page should say "a new cell, numbered with its color". And "area" (Select's bar) vs "cell" (the pages) is never reconciled.
4. **Pen page: Color from Photo.** It sometimes adds new numbers (tree halves 5 and 6, which look identical) and sometimes reuses one (sky 2). The page doesn't explain this.
5. **Pen page: Snap's "touches".** No distance is given, and overshooting tails stay either way.
6. **Shapes page: "Pick a figure above the tools".** The figures are below the picture.
7. **Bend Line page: "the far hills".** Which band that is isn't shown.
8. **Eraser and Line Eraser: shared Size.** The setting carries between the two tools without saying so.

## App bugs (reproduced)
### B1: The Pen and Shapes practice pictures are missing the paint of the moon, tree and cottage, while the other pages' pictures have it
- **Steps:** Refine → ? (Tool Guide) → Pen; then The Basics; Pen again; Shapes; Bend Line; Eraser; Shapes again; Line Eraser; Select.
- **Expected:** the same finished practice picture on each page, as on The Basics: cream moon, dark-green crown, brown trunk, red roof, cream walls, yellow window panes, brown door.
- **Observed on Pen and Shapes:**
  - The moon is just an outline on sky purple, labelled 2, the sky's paint. (On Select, the same moon is "Light beige · Paint 4".)
  - The crown, trunk, roof, walls, door and 4 window panes are all grass green, labelled 1.
  - The Pen page's own Photo layer shows the colored scene underneath, so only the paint is wrong.
- **Observed elsewhere:** The Basics, Bend Line, Eraser, Line Eraser and Select show the same drawing fully painted.
- **Reproduced:**
  - Pen: 3 of 3 (first open, after Reset, after going away and back).
  - Shapes: 2 of 2.
  - Painted pages: 5 of 5, each once.
- **Evidence:**
  - shots/pen-baseline-numbers.png, pen-numbers-on.png, pen-photo-only.png, pen-6-after-reset.png, pen-revisit.png, shapes-page.png, shapes-revisit.png
  - versus basics-page.png, bend-page.png, eraser-page.png, lineeraser-page.png, select-page.png, select-2-moon.png
  - Log: `05:44:23.380 … Tool Guide page shown: pen` (nothing else is logged about it).
- **Impact:** on the Pen page, Color from Photo's effect looks like the moon and cottage "getting their real colors". A learner can't tell whether that's the tool or a fix for a broken picture.

### B2: The practice picture jumps when a bar or hint appears under it
- **Seen:**
  - Shapes: after dragging a curve's ends, the hint "Drag to bend the curve…" appeared and the picture moved up about 14 pt (shapes-2, shapes-3).
  - Select: when the selection bar appeared, the picture moved up about 26 pt (select-1).
- **Reproduced:** 2 of 2 (on two different pages).
- **Expected:** the picture stays put, so the spot you aim for next (the curve's middle, the next cell) is where you saw it.

## Suspicions
- **S1: tree halves get two different numbers** (Pen, Color from Photo on). Seen 2 of 2 (pen-5, pen-14): labelled 6 and 5, both the same-looking dark green. The moon's halves both got 4.
- **S2: a strip of grass cut off by a line showed no number.** Seen once (pen-1-split-grass.png); the strip may be too narrow to label.
- **S3: Reset also turns off the Numbers layer.** Seen once, on Pen. It may be by design.
- **S4: leaving a guide page throws away your practice changes.** Seen once (Pen → Basics → Pen: fresh, Reset disabled). It may be by design, but nothing says so.
- **S5: Select's palette ring stays on swatch 1** whatever cell is selected (sky = 2, moon = 4). Seen on 2 selections in one session.

## Automation problems
- My first taps used screenshot-pixel coordinates instead of points (the screen is 1032×1376 pt and screenshots are about 1.45× that); they missed.
- Some strokes didn't register at all:
  - An exactly horizontal swipe across the moon (Pen).
  - A short (12 pt) near-vertical eraser swipe.
  - Longer sloped swipes always worked.
  - I count these as automation, not app bugs: a finger can't draw a perfectly straight 12 pt line in a 1.5 s swipe.
- `tapOn id: refine-pen-colors` didn't flip the switch (the element's centre is on its label); tapping the switch's own point worked.
- The Smoothing slider swipe stopped just short of 100%.
- Maestro swipes are straight lines only: no curved or shaky strokes, so no cloud and no real Smoothing test.
- The app log records no drawing events, so I judged everything from screenshots and the canvas's "N changes" accessibility value.

## Not tested
- The Smoothing wobble claim; a freehand cloud; Pencil hover.
- Pinch zoom, two-finger pan, two- and three-finger tap undo and redo, four-finger full screen, keyboard shortcuts (The Basics page lists them).
- Select's Change Color card.
- Guide pages not reached: Layers, Coming from Procreate, Cell Edge, Merge, Move Edge, Make Cell, Bucket, Paint Brush, Eyedropper, Edit Paint, Looks, Move Number, Writing, Try Painting.
- Whether the real Refine canvas has anything like B1. I only looked at the guide's practice pictures.
