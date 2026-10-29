# Paint by Moonlight: Tool Guide exploratory test

## Summary
Getting to Refine and its Tool Guide was easy, and the Pen basically works as its page says. Closing a shape makes a cell, and Color from Photo colors new cells from the photo. But the page never tells you how to see that a cell appeared (Layers > Numbers). The new cell's "own number" is the same number as the area around it. And Snap only closes gaps of about 3 pt, so its effect is nearly invisible. The biggest finding is the practice picture: on the Pen, Layers and Coming from Procreate pages, the moon, tree and cottage are outlined but painted the color of the sky or grass (3 paints only). On The Basics the same picture is fully colored (9 paints, cream moon, yellow window), and its Try This depends on that yellow window.

## Coverage
- **Goal 1 (reach Refine + guide): done.** Home > + > Samples tab > Red Fuji > wait about 3 s for "Finding the subject…" > Refine (top right) > "?" (accessibility label "Tool Guide", top left). Easy. The guide opened straight onto the Pen page (the selected tool), not the contents list; the back arrow leads to the contents.
- **Goal 2 (Pen page): done**, except a shaky line for Smoothing (Maestro only draws straight strokes).
- **Goal 3 (practice picture): done.** Compared across Pen, The Basics, Layers and Coming from Procreate.
- **Goal 4 (other pages in order): partly.** Contents order: Start Here (The Basics, Layers, Coming from Procreate), Ink (Pen, Shapes, Bend Line, Eraser, Line Eraser), then more sections below that I didn't scroll to. Done: The Basics, Layers, Coming from Procreate (except the swatch drag). I ran out of time before Shapes, Bend Line, Eraser, Line Eraser and the later sections.

## What I learned, tool by tool
### Pen
- **The page says:** "Draws ink… A line that closes off a shape makes a new cell with its own number. Lines leave the colors alone, unless Color from Photo is on." Step 2: "End a line on another line to close a shape. With Snap on, an end that touches a line joins it." Step 3: Color from Photo gives "each new cell the photo's color there". Step 4: Smoothing "trails your finger a little and evens out wobbles". Try This: draw a cloud ending where you began, then turn on Color from Photo and draw a line across the moon.
- **Closing shapes:** a vertical line ending on the hill line, plus a line out to the picture's left edge, closed off a corner. A 3-stroke triangle "cloud" in the sky also closed. Both became cells, but **nothing visible changed on the picture** until I turned on Layers > Numbers. Then the new area showed its own label "2", the same number as the sky. The canvas's accessibility value counts "N changes". Matches the page's literal words, but not the reading "a new number". Confidence high.
- **Color from Photo:** on, a line across the moon split it into 2 halves that both turned cream, with new number 4: exactly the expected change. Across the tree: dark green halves numbered 5 and 6. Across the cottage wall: cream (7), and the door brown (8). Off, a line across the roof split it into 2 cells that stayed green, number 1. Matches the page. Confidence high.
- **Snap** (all at the same spot: a vertical line ending near the hill line, then a closing line):
  - Snap on, 3 pt short: a cell formed. 5 pt and 7 pt short: no cell.
  - Snap off, 3 pt short: no cell.
  - 10 pt past the line: a cell with Snap on or off. The overshoot tail stays visible either way (Snap doesn't trim it).
  - There's no visual cue when a snap happens.
  - My belief: Snap closes gaps of about 3–4 pt. Confidence medium (1 trial per distance). On a finger that is nearly unnoticeable.
- **Smoothing:** a straight stroke at 0%, about 70% and 100% came out identical and full length, with no visible lag. I couldn't draw a wobble. I can't say what it does; confidence low. The slider value persisted to the next pages (100% on Layers).
- **Good to Know items** (doubling back gives a note; too-small shapes stay lines): not tried.

### The Basics
- **The page says:** ink, cells and paint; pinch to zoom; two- and three-finger taps for undo/redo; touch and hold anywhere for the Eyedropper; Pencil and keyboard notes. Try This: zoom in on the cottage's window, touch and hold a pane "until the loupe shows its yellow", then a quick pinch to come back.
- **Did:** couldn't pinch. A long press on a window pane (unzoomed) picked "9 · Yellow": the palette scrolled to swatch 9 and ringed it. The loupe only shows while the finger is down, so I couldn't see it. Matches as far as I could test.
- **Practice picture here is fully colored** (see App bug 1). Palette: 9 paints, two of them both named "Light beige" (4 and 8).

### Layers
- **The page says:** stack from top: Numbers, Ink, Paint, Photo; "Layers change only what you see". "Refine opens with Ink and Paint showing, the picture as it will look finished." "Photo on, with Paint at half, is good for tracing." The layer your tool works on is marked. Try This: photo shows under Paint at half; turn Photo off to see the paint alone, then on, fade Paint further, and trace the peach glow above the far hills with the Pen.
- **Did:**
  - The popover showed Paint 50%, Photo on, and the Ink row highlighted (the marked layer, as described).
  - Photo off: the paint alone has a moon the color of the sky, and a cottage and tree the color of the grass.
  - Photo on, Paint faded, then a Pen line across the glow from edge to edge. The strip became a cell numbered 2 (sky), not peach.
  - The page doesn't say what tracing should produce, or that Color from Photo would be needed to get the peach.
- Matches the mechanics; the purpose of the Try This is unclear.

### Coming from Procreate
- **The page lists** gestures, including "Drag a swatch onto a cell: ColorDrop". Try This: touch and hold the far hills, lift to pick up their paint, tap the moon to pour it in, then drag any swatch onto the cottage's roof.
- **Did:** a long press on the far hills selected swatch 3 (Grayish blue); tapping the moon filled it grayish blue. Matches. The swatch drag onto the roof changed nothing. Probably an automation limit (Maestro's swipe moves immediately; see Not tested).
- Palette here has only 3 paints (Green, Purple, Grayish blue).
- **Words used but not explained here:** "Reference", "flats", "Continue Filling", "StreamLine", "ColorDrop" (Procreate terms, fair on this page). It also names Cell Edge, Merge, Move Edge and Move Number before you reach their pages.

## Confusions (ranked)
1. **The practice picture changes between pages** (The Basics colored, the others not). The Pen page's picture looks unfinished, and its Try This ("line across the moon") only makes sense because the moon has no color of its own. The Basics' Try This needs a yellow window that the other pages' picture doesn't have. Nothing says the picture differs per page, or why.
2. **Pen: "how would I know a cell appeared?"** With Color from Photo off, closing a shape changes nothing visible. The page should say: "Turn on Numbers in Layers to see the new cell and its number."
3. **Pen / The Basics: "a new cell with its own number"** reads as a new, different number. In fact the new cell gets the number of the color it already has (2 in the sky). The page should say "a new cell, numbered with the color it already has (a new number only if Color from Photo gives it a new color)".
4. **Pen: Snap**: "an end that touches a line joins it" doesn't say how close counts. In practice it's about 3 pt, with no feedback, and overshoots aren't trimmed. The page should give the reach and say what happens to an overshoot.
5. **Reset also resets Layers** (Numbers and Photo off), but not Smoothing (it stayed at 100% across pages). The pages say only "Reset puts the picture back".
6. **Layers: "the picture as it will look finished"**: with the 3-paint practice picture, "finished" would mean a purple moon. That's confusing next to The Basics.
7. **Two palette swatches share the name "Light beige"** (4 and 8) on The Basics. VoiceOver users can't tell them apart.
8. **New Painting preview tip** says "compare the photo and the page" while the labels say "Photo" / "Painting". "Page" isn't explained there.

## App bugs (reproduced)
### 1. Practice picture paint is missing its moon/tree/cottage colors on most pages
- **Steps:** Refine > Tool Guide (opens on Pen); look at the practice picture; Layers > Numbers on. Then the contents > The Basics, then Layers, then Coming from Procreate.
- **Expected:** the same finished picture on every page (The Basics shows it: cream moon, dark green tree, brown trunk, red roof, beige walls, yellow window, brown door).
- **Observed:**
  - Pen, Layers (paint alone, Photo off) and Coming from Procreate: the moon is painted sky purple (number 2), and the tree, trunk, roof, walls, window panes and door are painted grass green (number 1). Only 3 paints exist.
  - The Photo layer underneath (Pen page, Paint at 6%) shows all the real colors.
  - The Basics has 9 paints and the colored picture.
- **Reproduced:** 3 of 3 pages other than The Basics; The Basics colored 1 of 1.
- **Evidence:** shots/pen-practice-initial.png, shots/pen-layers-numbers-photo.png, shots/pen-photo-underneath.png, shots/basics-initial.png, shots/layers-photo-off.png, shots/procreate-page.png, shots/procreate-try2.png.
- **Note:** this may be deliberate, a blank picture to practise Color from Photo and Bucket on. But nothing on the pages says so, and the Layers page calls it "the picture as it will look finished". I'm calling it a bug because it is inconsistent and unexplained.

### 2. Reset turns Layers switches back off
- **Steps:** Pen page > Layers > Numbers on > draw a line > Reset.
- **Observed:** Numbers off again (Photo off too).
- **Reproduced:** 2 of 2.
- **Evidence:** shots/pen-3-triangle-cloud.png, shots/pen-layers-after-reset.png.
- **Note:** may be by design; the page doesn't say. It makes checking for new cells tedious.

## Suspicions
- **Tree halves get different numbers.** After a Color from Photo line across the tree, the two halves look the same dark green but are numbered 5 and 6; the moon's halves both got 4. Seen once. Evidence: shots/pen-6-cfp-tree-cottage.png.
- **Smoothing persists across pages and Reset** (Smoothing 100% on the Layers page). Seen once.

## Automation problems
- Tapping the "Color from Photo" element by id (`refine-pen-colors`) hit its label, not the switch: nothing toggled (value stayed 0). Tapping the switch itself by point (315,479) worked.
- Maestro draws only straight strokes: no shaky line, no curve, no single-stroke cloud (I used a 3-stroke triangle).
- Guide text scrolls only about 200 pt per swipe.
- The Layers popover's controls had to be tapped by point.

## Not tested
- Smoothing on a wobbly line; Pen's "doubles back" note; a shape too small for a number.
- Pinch zoom, two-, three- and four-finger taps, Apple Pencil, keyboard shortcuts.
- The loupe (only visible while holding).
- ColorDrop (dragging a swatch onto a cell): the drag didn't land, likely because it needs a hold before moving.
- Shapes, Bend Line, Eraser, Line Eraser and every page after them: out of time.
- Crashes: crashes.txt is empty, so none.
