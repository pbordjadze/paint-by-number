# Paint by Moonlight — exploratory test report (Refine / glass-mosaic session)

Device: iPad Pro 13-inch (M5) simulator, debug build. Session 00:17–00:45 (app.log times). Coordinates are points (screen 1032×1376). I trusted screenshots plus inspect_screen together; where they differ, it's noted.

## Summary
I made a glass-mosaic painting from The Great Wave: Refine, Start From › Blank, a 6×4 grid over the crest (1 rectangle + 8 straight Pen lines = 9 gestures for 24 intended tiles), paints from New Paint, Bucket fills, Edit Paint, Merge, Undo/Redo, a hexagon, Try Painting, Done, Start Painting. I then painted, went back to the gallery, quit and relaunched. Shapes and lines landed within ~1–2 pt of where I drew them, and progress survived the gallery and a relaunch. Two serious Refine problems spoiled the mosaic. **(1) Snap joins a Pen stroke's start to a nearby line but not its end, so tiles silently leak into each other: 24 intended tiles became 17 areas, with no warning. The painter still sees the drawn lines, but one number covers several "tiles".** **(2) Tapping a Refine palette swatch's centre doesn't select it, because the tap targets are shifted left. The Bucket keeps laying the previous paint.**

## Coverage
1. Create from a sample, through to painting: **done**. The Great Wave › preview › Refine › Blank › … › Done › "3 colors · 19 areas · ~5 min" › Start Painting.
2. Paint: **partly**. Bucket fills in Refine; in the finished painting, 2 areas filled (beige tile via `canvas-area-4`, then navy on the leaked L region: one tap filled 8 tiles). Progress showed 10% (2 of 19, rounded down: correct). No zoomed painting, no drag.
3. Zoom levels: **not tried** (no pinch in Maestro; the Refine canvas has no Fit/zoom buttons, and I didn't use double tap/Hint in the painting).
4. Gallery round trip: **done**. Back to the gallery showed "10% painted" and a correct thumbnail (shots/52-gallery).
5. Quit and relaunch: **done** (Home, screenshot, then stopApp + launchApp). The gallery still showed 10% and the same thumbnail; reopening showed both fills and 10% (shots/53-relaunch, 54-reopen-after-relaunch).
6. Session goals (Refine): Blank ✔, Rectangle ✔, Hexagon ✔, straight Pen lines ✔, Bucket ✔, New Paint ✔ (2 paints added), Edit Paint ✔, Merge ✔, Undo ✔, Redo ✔, Try Painting ✔ (Back from it returns to Refine with all edits kept ✔).

### Answers to the session's questions
- **Placement:** yes, within a few points. The rectangle dragged (420,440)→(660,600) landed at (420,439)–(658,599). The Pen verticals at x=460/500/540/580/620 landed at 459.6/499.5/540/580/620. The hexagon dragged (740,470)→(820,550) filled the box (740,470)–(819,549). The gaps of bug 1 are the exception.
- **Refusals / toasts:** none. No line, shape or fill was refused, and no toast appeared all session. That is part of the problem: the open strokes (bug 1) produced no message either.
- **Which paint the Bucket lays:** often unclear (bug 2). New Paint adds a swatch with a "+" and no number until it is used. The Bucket tool shows no paint other than the palette ring, which often didn't move to the swatch I tapped.
- **Speed as tiles accumulated:** no slowdown visible up to ~30 edits; every edit rendered before the next screenshot. app.log has **no timing lines for Refine edits**, only tips lines, so I can't give numbers. The painting screen logged "Waited 0.26–0.47 seconds for a drawable".
- **Gestures per tile:** the grid took 9 gestures for 24 intended tiles (~0.4 per tile), but the end gaps cost 7 of them: 24 → 17 areas. Colouring needs 1 tap per clean tile, plus 1–3 taps to choose a paint because of bug 2 (a left-edge tap, or the Eyedropper on a filled tile). The hexagon was 1 gesture for 1 tile.
- **What I wanted and couldn't find:**
  - a grid/array or "repeat shape" tool for tiles;
  - a view of the area count, or of which areas are joined (a gap marker or "open stroke" warning);
  - a snap-distance setting;
  - a way back to Start From › Generated after the first stroke (the control disappears);
  - Edit Paint changing only the chosen paint by default;
  - a hint for how Merge works.
- **Kept from me by Maestro:** pinch zoom (I couldn't zoom in to check the 2 pt gaps or draw tiles smaller than ~40 pt), curves/Bend Line, the two-finger tap undo from the tip, and press-and-drag painting.

## App bugs (reproduced)

### 1. Snap closes a Pen stroke's start but not its end, so tiles leak into each other silently
- **Steps:** Refine › Start From › Blank. Shapes › Rectangle (420,440)→(660,600). Pen, Snap on (default). Draw vertical strokes top→bottom from y=441 to y=597 (2 pt inside the frame at each end), and horizontal strokes left→right from x=422 to x=656. Bucket with a new paint; tap a tile in the right column or bottom row.
- **Expected:** with Snap on, a stroke ending 2 pt from a line joins it, as its start does, so each tile is its own area. Failing that, a warning that the stroke is open.
- **Observed:** strokes visibly reach the frame at their start (top/left) and stop ~2 pt short at their end (bottom/right). One Bucket tap fills the whole right column plus the bottom row's other tiles: 8 tiles in an L, so 24 intended → 17 areas. Left and top tiles fill one by one. In Try Painting and in the saved painting, the L carries one number "2" and one tap paints all 8 tiles, while the drawn (open) lines still split it visually. In the separate test rectangle, the single "2" sits right on top of the open dividing line. No toast or marker at any point.
- **Reproduced:** 3 of 3. Grid tap at (639,459) at 00:26; tap at (560,579) after Undo at 00:27; a fresh rectangle (700,620)–(800,700) with one Pen stroke from (750,622) to (750,698), where one tap at (725,660) filled both halves, 00:40.
- **Evidence:** shots/07-grid, 12-edge-fills, 15-leak-repro, 16-left-top (left/top tiles separate), 43-trypainting, 44-try-fill-navy, 46-snap-repro3, 48-start-painting (one "2" on the rectangle's line), 51-navy-L.

### 2. Refine palette swatch tap targets are offset to the left: tapping a swatch's centre doesn't select it
- **Steps:** Refine › Bucket. Add paints with New Paint (2 · Navy, 3 · Light vivid blue). Tap the centre of swatch 1 (287,1322) or swatch 2 (331,1322).
- **Expected:** the tapped swatch becomes the selected paint.
- **Observed:** the selection doesn't change. inspect_screen keeps the old swatch `selected`, and the next Bucket tap lays the old paint (00:30: after tapping swatch 2's centre, the tile at (520,539) got paint 3). It fails the same way with the label selector ("1 · Light beige", "2 · Navy"), by id, and with longPress. Tapping a swatch's **left edge** works: x=309 selected swatch 2 (00:33), x=273 selected swatch 1 (00:34), x=357 selected swatch 3 (00:34). The target sits roughly 20–25 pt left of the drawn swatch, so a centre tap lands on the previous swatch's target. The last swatch's centre works because it lies inside its own target. Seen with Bucket, Eyedropper and Edit Paint.
- **Reproduced:** about 8 failed centre taps over swatches 1 and 2 (00:27–00:33); 3 of 3 left-edge taps selected.
- **Evidence:** shots/18-repair-test2, 20-lightblue-then-navy, 24-bucket-swatch2, 25-eyedropper-swatch2, 26-swatch1-after-sample (all unchanged); 28-swatch1-left-edge, 30-editpaint-sel3 (selected). Swatch bounds from inspect: paint-1 [266..307], paint-2 [315..347], paint-3 [354..395] × y [1301..1342].
- Workaround: the Eyedropper on a filled tile selects that paint (shots/22-eyedropper). The painting screen's palette (`swatch-1..3`) did not show this problem: swatch-2 by id selected fine at 00:42.

### 3. The same paint has three different names
- Paint 1 is "1 · Light beige" in Refine's palette (inspect), "1 · Fresh Linen" in Try Painting's header (shots/43), and "1 · Candle Wax" in the saved painting's header and swatch label (shots/48, inspect "1, Candle Wax, light beige"). Paint 2: "Navy" in Refine, "Navy Peacoat" in the painting. Paint 3: "Vivid green" in Refine, "Glowworm" in the painting.
- Reproduced: seen on each of the 3 screens, and Candle Wax again after relaunch (shots/54).

## Suspicions
- **Edit Paint's "Similar colors too" is on by default and drags other paints along.** Changing paint 3 (light vivid blue) to green also turned paint 2 (navy) dark green (00:36, shots/34-editpaint-green). With the toggle off, only paint 3 changed (shots/36). It's a toggle, so maybe intended, but on by default it's surprising when choosing deliberate tile colours, and navy counting as "similar" to light vivid blue is a stretch. One Undo restored both paints (shots/35). Seen once each way.
- **Taps on the Edit Paint picker's colour grid didn't register** (2 of 2: (185,984) and (413,956)), while its preset circles did (green (386,1142), 2 of 2). In the New Paint picker, grid taps worked (2 of 2). It's the system UIColorPicker, so it may be automation; listed because the two pickers behaved differently.
- **Merge gives no feedback on a tap.** A single tap on a tile did nothing visible (shots/38); dragging from one tile into its neighbour merged them (shots/39). No hint about the gesture. Undo/Redo of the merge worked (shots/40, 41).
- **Two gallery paintings are both titled "The Great Wave"** (the seeded one and mine). Nothing tells them apart but the thumbnail and progress; no prompt to rename when starting.
- **The Refine canvas moves under you:** it shifted 11 pt up when Edit Paint opened (bounds [208,385] → [208,374]) and stayed there, so taps planned on the old layout land 11 pt off. Seen once.
- **First taps after opening the new painting were ignored:** right after Start Painting (00:41), a tap on swatch 2's centre (516,1308) didn't select it. A later id tap on swatch-2 worked. Possibly the hand-off cover still swallowing touches, or automation. Seen once.
- **Pen overshoot leaves a stub:** the first vertical, started 4 pt above the frame, left a dangling tick above it, visible in every grid shot and in the final painting.
- **"New Paint" by id didn't open the picker** (`tapOn id: refine-palette-new`, 00:24), while a tap at its centre did (3 of 3). Unsure whether app or automation.
- **Accessibility value:** the Refine canvas said "No changes" after choosing Blank, though Undo was enabled.
- **Tips log:** with Refine open, app.log repeatedly logged "offer in preview: newPaintingDivider, newPaintingSuggested, newPaintingSliders, newPaintingRefine, wanted" (00:26–00:38), as if the preview behind still asked for tips.

## Automation problems
- inspect_screen exposes nothing inside the system colour picker (only `UIColorPicker` bounds), so grid cells had to be tapped by coordinates.
- No pinch: I couldn't zoom the Refine canvas to inspect the ~2 pt gaps up close. The gap is judged from fill behaviour plus scaled screenshots (strokes end ~5 screenshot px short of the frame).
- Maestro `swipe` can't press-and-hold, so Paint Brush, drag painting and curves weren't tried.
- One of my own mistakes: a tap at (301,419) in the painting was meant for the background but landed on a "2" tile (I mixed screenshot pixels and points); it isn't counted as a finding.

## Not tested
- Zoomed painting (double tap, Hint), More › Fit to Screen, Give Feedback, Settings, the gallery's menus.
- Bend Line, Cell Edge, Move Edge, Fill Shape, Looks, Writing, Move Number, the Star/Oval/Curve shapes, Eraser and Line Eraser, the picker's Spectrum/Sliders tabs.
- Finishing the painting (and the debug moonrise).
