# Refine from scratch: snowman with house (iPad Pro 13", debug build)

## Verdict
**Yes.** I got the picture I meant to draw and painted all of it (100%). Two rough spots on the way: the colour wheel that opened nothing at first, and a Merge that turned the whole sky black (Undo fixed it).

## What I meant to draw
A white snowman (two stacked circles) with a black top hat, red scarf and orange triangle carrot nose, standing on white snow under a light-blue sky, with a yellow house (brown triangular roof, brown door, grey chimney) behind it on the right.

## What I got
- `shots/final-refine`: the drawing in Refine, whole page in view. Cyan sky (brighter than the "light blue" I meant; I picked one grid cell and kept it). White snow below a straight ground line from edge to edge. White snowman of two circles. Black top hat: crown plus brim, sitting on the head. Red band scarf at the neck. Orange triangle nose. Pale-yellow house with a brown triangular roof, a golden-brown door and a grey chimney rising out of the right slope. It matches the plan.
- The New Painting preview said **9 colors · 13 areas · ~5 min**.
- `shots/final-template`: the painting screen before painting. Each shape has its own number: 1 white (head, body, snow), 2 sky, 3 hat, 4 scarf, 5 nose, 6 walls, 7 roof, 8 door, 9 chimney. There is also a tiny "3" sliver at the top of the head, under the brim (where the brim rectangle overlaps the head circle).
- `shots/final-painting`: everything painted, "Finished! Every region is painted", 100%.
- Deviations from the plan: the sky is cyan rather than pale blue. The scarf is a flat band, not a draped scarf. The snowman's body circle stops about 10 pt above the ground line, so sky shows under him. In the end he reads as "standing", but he really hovers a little. There are no eyes or buttons (not planned).

## The steps

| Step | Tries | Stuck for | What finally worked | What I expected instead |
|---|---|---|---|---|
| Find a blank page | 1 | 0 | + → top-right icon **From Scratch** (`from-scratch`) opened Refine on an empty white square | as expected. The icon is unlabelled on screen, but it was the obvious one to try |
| House walls, ground, roof, chimney | 1 each | 0 | Shapes › Rectangle, Line (Snap joined the ground line to both edges and the roof/chimney ends to the lines) | as expected |
| Door, body, head | 1 each | 0 | Rectangle, Ellipse (drag corner to corner) | as expected |
| Hat (brim + crown), scarf, nose | 1 each | 0 | Rectangles; nose as 3 Line strokes | as expected |
| Get a second colour | 3 taps + guide | ~3 min | Colour wheel at the end of the palette. Taps 1–2 (by id, by point) showed nothing. Read Tool Guide › Bucket (helpful). Its demo wheel opened a picker. Tap 3 on the real wheel opened an **empty** white popover that filled in a moment later. After that it opened every time (7 more). | the picker on the first tap |
| Colour everything (Bucket) | 1 per area | 0 | Sky, hat (crown + 4 brim pieces), scarf (5 pieces), nose, walls, roof, door, chimney. Each pour filled exactly the closed shape. Closing the picker by tapping the canvas didn't pour, which is nice. | as expected |
| Clean the circle arcs out of the scarf | 2 swipes | 0 | Merge: one horizontal and one vertical swipe across the scarf pieces | as expected |
| Join the hat pieces | 2 swipes + 1 undo | ~2 min | Gave up on this. The brim swipe was declined ("merge stays in one area" in the log). The next swipe, brim → crown, **joined the whole sky into the hat**: the sky went black and paint 2 left the palette. Undo brought it back. | the hat's pieces joined; the sky left alone |
| Paint the template | 1 per area, 1 mis-tap | 0 | Taps by point; swatches by id after finished colours dropped out of the palette and the rest re-centred under my next tap | as expected once I knew the palette shrinks |

## Where I got stuck
1. **Merge on the hat turned the sky black** (`shots/bug-merge-sky-black`). I wanted to join the black brim pieces to the crown. A straight Merge swipe from inside the brim (400,509) up into the crown (400,470) stayed inside black cells the whole way, yet it merged the sky (the largest cell) into the hat. The sky became black and the blue paint vanished from the palette. Undo fixed it in one step.
2. **The colour wheel did nothing on the first two taps** (`shots/plan-5-wheel` is the third tap: an empty popover). As a newcomer, a dead button with no feedback made me open the help.
3. **Mis-tapped swatch while painting**: finished colours leave the palette and the rest slide over, so a swatch position I'd just read was wrong a moment later. I painted with red instead of black once (the taps only shook). Minor.

## What I wanted and couldn't do
- Join the hat's brim pieces and crown into one area. Merge declined or misbehaved, so the hat stayed several areas (fine to paint, but more numbers than needed).
- Draw a real curved/draped scarf or a bumpy snow line. I used straight shapes only. Maestro can't draw a curve in one stroke. I didn't try Bend Line or the Shapes curve tool (no time).
- Pick a precise pale sky blue. The grid's light-blue cell was more saturated than I wanted. Sliders and Spectrum were not tried.

## App bugs (reproduced)
None reproduced twice. See Suspicions.

## Suspicions
1. **Merge inside the hat merged the sky into it.**
   - Steps: Refine, hat drawn as crown rectangle + brim rectangle overlapping the head circle, all pieces poured black, sky cyan. Merge tool: swipe (336,502)→(464,502) along the brim, then (400,509)→(400,470) up into the crown.
   - Observed: the log at 19:46:55 says "An edit was declined: the merge stays in one area" (the brim swipe). After the vertical swipe the whole sky was black and paint 2 was gone. Redo/undo showed the two hat swipes made only one history step between them, so the vertical swipe made the sky merge.
   - Expected: the hat pieces join; the sky is untouched.
   - Seen once; not retried. Evidence: `shots/bug-merge-sky-black`, app.log lines 39.
2. **New Paint (colour wheel) didn't open on the first two taps** in a fresh Refine. Tap 1 was by id, tap 2 by point, minutes apart, with screenshots and an inspect between them. The third tap showed an empty white popover, filled a second later. Later taps (7) all opened. No log line for the taps. Maybe the picker's first load is very slow and the first taps were swallowed. Once.
3. **One area showed two numbers.** On the template the scarf showed "4" twice (centre and top-right corner) though it was one area: one tap filled it, and only one `canvas-area` was offered. A newcomer would think there's a second scarf piece left to paint. Once.
4. **A merge that does nothing gives no visible feedback.** The declined brim merge only appears in the log. On screen nothing said so.
5. The Refine `refineFill` tip showed 19:36:17–19:36:21 while I was drawing. I never saw it (it went away while a swipe was running). Not a bug, just a note on pacing.

## Automation problems
- `assertVisible: "New Paint"` failed while the picker was visibly open: its contents aren't in the hierarchy. I guarded by screenshot instead.
- Straight swipes only: no curved strokes (scarf folds, snow drifts).
- Merge's highlight shows only while the finger is down, so I couldn't see which cells it would join before lifting.

## Not tested
- Pen freehand, Bend Line, Shapes curve/polygon/star, Eraser, Line Eraser, Cell Edge, Move Edge, Make Cell, Paint Brush, Eyedropper, Edit Paint, Looks, Move Number, Writing, Try Painting, Layers.
- Picker Spectrum/Sliders tabs.
- Drag painting, pinch/two-finger pan, Pencil, multi-finger undo/redo.
- Quit/relaunch persistence of the new painting; the gallery thumbnail; Replay.
- Re-running the Merge sky bug a second time.
