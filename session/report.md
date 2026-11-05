# Refine exploratory session: potted flower (iPhone 17 Pro simulator, debug build, 2026-11-05)

**Verdict**: Yes, mostly. I got the picture I planned and painted it to 100%, but only after about 10 minutes stuck on the stem. Lines that join two shapes never close an area, so I had to draw the stem as a separate rectangle that doesn't touch the flower or the pot. That leaves hairline gaps of background showing between them.

**What I meant to draw**: an orange trapezoid pot on a brown table (a line across the page), a green stem and two green leaves, a red five-pointed flower with a yellow round centre, and a light-blue background (6 colours).

## What I got
- `shots/final-refine`: the drawing in Refine. It has a red star flower with a yellow circle centre, a green rectangular stem, two green elliptical leaves, an orange trapezoid pot, a brown table and a pale-blue background. The stem leaves a gap of about 3 pt below the star and above the pot rim. One leftover line stub (≈10 pt) shows by the star's lower notch. The leaves are plain ellipses, not pointed leaves.
- The New Painting preview read "6 colors · 8 areas · ~5 min". That is exactly my 8 shapes.
- `shots/final-template`: the painting screen with 8 numbered areas. It opened on paint 5 (the background, the largest area), as designed.
- `shots/final-painting`: all 8 areas painted, 100%, "Finished!". After Home and a relaunch it shows under Finished in the gallery with the correct thumbnail (`shots/plan-32-relaunch-later`).
- Compared with my plan, the shapes, colours and areas match. The flaws are the stem gaps, the stub, and the stiff oval leaves.

## The steps
| Step | Tries | Stuck for | What finally worked | What I expected instead |
|---|---|---|---|---|
| Find a blank page | 1 | 0 | + → the "From Scratch" icon at the top right of New Painting opens Refine on a white page | — |
| Table | 1 | 0 | Ink › Shapes › Line across the page; Snap carried it to both edges | — |
| Pot | 1 | 0 | 3 Lines, snapped to each other and to the table line | — |
| Flower | 1 | 0 | Shapes › Star, dragged corner to corner | — |
| Flower centre | 1 | 0 | Shapes › Oval | — |
| Leaves | 1 | 0 | 2 Ovals | a leaf or teardrop shape, or a way to bend an oval to a point (I didn't try Bend Line or Curve) |
| First new colour | 3 | ~1 min | the colour wheel at the end of the palette (`refine-palette-new`) opened "New Paint" on the 3rd tap | it opens on the first tap |
| Colour flower, centre, pot, leaves | 1 each | 0 | New Paint → Grid swatch → close → Bucket tap | — |
| **Stem as its own area** | 7 | ~10 min | a Rectangle that touches nothing, ≈3 pt clear of the star and the pot | two lines (or a rectangle) from flower to pot close an area, like the pot's lines did |
| Background and table colours | 1 each | 0 | New Paint + Bucket | — |
| Done → preview → Start Painting | 1 | 0 | — | — |
| Paint 8 areas | 9 taps (1 miss) | 0 | swatch, then tap; Hint flew to the table, which was out of view | — |

Help: I read the Tool Guide twice. The **Bucket** page told me the colour wheel makes new paints, which helped. The **Make Cell** page ("the fill spreads out to the ink around your tap") described what should have happened to my stem, but that isn't what the app did.

## Where I got stuck (worst first)
1. **The stem wouldn't become its own area** (~10 min, 7 tries). I wanted a green strip between the flower and the pot. I tried:
   - 2 snapped Lines (`shots/plan-10-green-orange`: the pour turned the whole background green);
   - overshooting segments with Snap off, which left visible ink stubs inside the star and pot (`plan-12-stemfix`, `plan-13-blue`);
   - Make Cell, which flooded the whole background (`plan-14-makecell`);
   - a closed Rectangle touching both shapes (`plan-20-stemgreen`, `plan-22-select-rectstem`, `plan-23-makecell-rect`).

   Only a Rectangle clear of both shapes worked (`plan-27-gapped-stem`).
2. **Cleaning up with the Line Eraser.** A tap aimed at a short stub next to the star erased the whole star outline instead. The red paint left the palette and the numbers renumbered (`plan-25-isolated-stem`). Undo brought it back (`plan-26-undo2`). This was my mistake, partly: the stub was within about 3 pt of the star's edge. But nothing shows which line the eraser will take.
3. **The first new colour.** The colour wheel did nothing on two taps (`plan-8-newpaint` was taken after the 3rd tap, which worked).

## What I wanted and couldn't do
- Join two shapes with lines and get a closed area (the stem). The stem had to float with gaps instead.
- Draw a pointed leaf shape directly. I settled for ovals; I didn't explore Curve or Bend Line for lack of time.
- See which stroke the Line Eraser will remove before it removes it.
- Zoom Refine's canvas to check whether two strokes really meet (no double-tap zoom there, and no pinch in Maestro).

## App bugs (reproduced)
1. **Ink that joins existing ink doesn't split cells, so an area bounded by lines that run between two shapes never becomes a cell.**
   - Steps (minimal repro): + → From Scratch → Ink › Shapes › Rectangle, draw two rectangles one above the other, about 130 pt apart. Then draw two vertical Lines from the bottom edge of the top rectangle to the top edge of the bottom one, about 40 pt apart. Open Numbers.
   - Expected: the strip between the lines is a cell with its own number.
   - Observed: each rectangle and the background get a number, and the 40×130-pt strip gets none (`shots/repro-1-bridge`). In my drawing, a Bucket pour into such a strip paints the whole background. Cells › Select outlines the background and ignores the strip's ink (`plan-15-select-stem`, `plan-22-select-rectstem`). Make Cell inside it floods the background too (`plan-14-makecell`, `plan-23-makecell-rect`), against the guide's "spreads out to the ink around your tap".
   - Frequency: 1/1 in the minimal repro. In the drawing it failed 4 of 4 ways: snapped lines, overshooting lines with Snap off, a closed rectangle touching both shapes, and Make Cell.
   - Contrast: a rectangle that touches no other ink becomes a cell at once, even 11 pt wide (`plan-16-thin-test`, `plan-27-gapped-stem`). Oddly, the pot (3 lines meeting the table line) did close. The difference may be that the table line ran to the page's edge.

## Suspicions
- **The colour wheel / New Paint button ignored its first two taps** (one by id, one by point, about 30 s apart, Paint tab, Bucket selected). Inspect showed no sheet opening. After a visit to the Tool Guide it opened every time (5 of 5). Seen once; I didn't reproduce it.
- **The leaves looked unfilled (white) right after a pour** in the Paint view (`plan-20-stemgreen`), while Numbers a few seconds later showed them green (`plan-21-after-stem-pour`). This may be a render or animation timing issue; I trust the later Numbers view. Seen once.
- **The painting canvas zoomed in on its own** during a run of 6 single taps on different spots (fills of background, star, centre, a leaf and the stem, with swatch taps between). One later tap, meant for the right leaf, then missed it (`plan-29-painting-mid`). No two taps were on the same spot, though the star (200,282) and centre (200,315) taps were 33 pt apart within a few seconds. The log says nothing about it. Seen once.
- **Snap couldn't be toggled through its accessible element.** `tapOn id: refine-snap` (centre of the labelled row) left it on; a tap on the switch itself turned it off. This may be Maestro hitting the label.
- **A refineFill tip ran 15:24:47–15:25:32** (per app.log) while I drew, but no screenshot or inspect in that window showed it.
- **The Line Eraser picks a neighbouring long stroke** over a short stub under the finger (see stuck #2). This may be by design (nearest stroke by some measure), but it is surprising.

## Automation problems
- Swipes are straight, so I drew no freehand curves. I used Oval and Star instead, which suited this subject. A curved, pointed leaf was out of reach in the time (I didn't try Curve or Bend Line).
- No pinch: I couldn't zoom Refine's canvas to check whether strokes met.
- Taps can miss by a few points. The Line Eraser hazard above came from this.

## Not tested
- Drag painting on the painting screen (press then drag), two-finger pan and pinch, Apple Pencil, and multi-finger undo or redo in Refine.
- The Pen (freehand), Curve, Hexagon, Bend Line, Eraser (area), Split, Merge and Move Edge tools; Looks, Edit Paint and the See tab; Layers.
- Replay and Share on the finished painting.
- Whether the app's behaviour on the stem gap differs on iPad.
