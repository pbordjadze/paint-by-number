# Refine from scratch — castle on a hill (iPad Pro 13", debug build)

**Verdict**: Yes, mostly. I got the castle I planned and painted it to 100%. Closing off the hill took about 12 minutes of trial and error and left visible patch-up marks and 4 extra tiny areas.

**What I meant to draw**: A grey stone castle (wide wall with a brown arched gate and dark windows) between two grey towers with red pointed roofs, a red flag on a pole atop the left tower, on a green rounded hill, under a blue sky with a yellow round sun top-right.

## What I got
- `shots/final-refine`: the drawing in Refine. Light-blue sky; yellow round sun top right. Two grey towers, each with a red triangular roof and a dark window. A grey wall between them with two dark windows and a brown arched gate. A red pennant flag on a pole above the left roof. A green hill with smooth rounded shoulders, running from both edges of the page to the towers' feet.
- `shots/final-template`: the painting screen before painting. 8 colors, 18 areas, numbers in every area.
- `shots/final-painting`: fully painted, 100%, "Finished! Every region is painted."
- Flaws, judged against my plan:
  - Where the hill meets each tower there are two short crossing lines (an "X") and a tiny white triangle cell. These are my fix for the leak (see below).
  - There are short stray ticks at the tower/wall seams.
  - The pole is an open line, as intended.
  - 18 areas instead of the 14 I designed: there are 2 tiny white triangles (paint 1, "Printer Paper") and 2 tiny sky triangles.
  - Nothing else is off. Shapes, colors and layout are what I meant.

## The steps
| Step | Tries | Stuck for | What finally worked | What I expected instead |
|---|---|---|---|---|
| Find a blank page | 1 | 0 | + → "From Scratch" (top right of New Painting, after closing a "No Photo at Hand" tip) → Refine with a white page | Same. Easy. |
| Wall, towers | 1 | 0 | Shapes › Rectangle, one drag each | As expected (but see the seam below). |
| Pointed roofs, flag | 1 | 0 | Shapes › Line; Snap joined ends | As expected. |
| Windows, sun | 1 | 0 | Rectangle ×4, Oval | As expected. |
| Gate arch | 1 | 0 | Two Lines + Curve (drag between the ends, then drag to bend it) | Curve worked first time. Nice. |
| Hill curves | 1 to draw, then ~6 to close | ~12 min | See the next row | Drawn from the edge to the tower corners, they looked closed. |
| Separate hill from sky | 6 | ~12 min | Snap OFF, then a short Line crossing each curve end AND the tower wall in an X | That a curve ending on a corner or a line seals the area. |
| Pick colors, Bucket | 8 paints, 1 try each | 0 | Palette's color wheel → system grid → Bucket tap | As expected. |
| Paint it | ~20 taps | 0 | `canvas-area-*` targets + Hint; 100% | One detour: the canvas zoomed in ~2.5× (below). |

Help: I opened the Tool Guide (Select, Shapes, The Basics, Make Cell) while stuck on the hill. It is clear and well written. It told me Snap only moves line/curve ends and that rectangles don't snap. Layers › Numbers showed which cells existed. But nothing in it told me why my hill wasn't closed, or how to find a gap.

## Where I got stuck
1. **The hill wouldn't close, and nothing showed where it leaked** (`shots/plan-5-sky-leak`, `plan-6-select-shows-hill-open`, `plan-8-still-one-area`, `plan-10-curves-still-open`).
   - I drew two Curves from the page edge to the towers' bottom corners. At full-picture scale they look joined.
   - The Bucket's blue flooded sky and hill together. Select showed the curves weren't cell edges ("1 area").
   - These didn't help:
     - Short Lines past the frame.
     - Pen ticks across the frame.
     - Erasing and redrawing the curves starting outside the page and ending on the tower walls.
     - Short lines across the tower/wall seams: Snap pulled their ends onto the seam, so they crossed nothing.
   - These did work as isolated tests: a straight Line edge-to-edge (`plan-9`) and a Curve edge-to-edge (`plan-11`). So the frame and curves were fine; the curve ends at the towers were the problem.
   - The fix (`plan-13-hill-closed`): turn Snap off and draw a Line crossing both the curve end and the tower wall.
   - A newcomer has no way to see the gap: no gap marker, no "this line is open at its ends", and no zoom without a pinch.
2. **Snap working against me.** Snap is on by default. My short sealing lines got shortened onto the nearest line, so they closed nothing (`plan-13` shows the stubs). I had to discover that turning Snap off was the answer.
3. **Coordinates moving under me.** The canvas moved up ~23 pt when Curve's hint line appeared below it, and ~3 pt more later. My next strokes landed off target until I re-measured.

## What I wanted and couldn't do
- See where an area leaks (highlight the open end or the gap) before the Bucket floods.
- Have a curve that ends on a corner of a rectangle close the area, as it visually does.
- Draw a hill outline in one go along the castle base without patch lines. With straight swipes I could only do it with the Curve tool or with many short segments.
- Zoom in to inspect a junction (pinch only, not available to me).
- End up with only the areas I meant to make: 4 extra tiny areas came from the fix, and getting rid of them would have meant Merge, which I didn't try.

## App bugs (reproduced)
- None confirmed as bugs. No crashes (`crashes.txt` empty).

## Suspicions
- **A Curve whose end lands on another shape's line/corner may not join it** (2 of 2 tries, left and right; also with the ends placed on the tower walls above the corner). Edge-to-edge curves and lines do join (1/1 each).
  - Steps: Shapes › Curve, Snap on. Drag from the page's left edge to the bottom-left corner (or side) of a Rectangle; bend it. Then Select the area below.
  - Expected: a separate cell.
  - Observed: one cell with the sky; Select's glow skips the curve.
  - Evidence: `plan-6`, `plan-10`.
  - Possible cause: my tower and wall rectangles share an edge ~0.x pt apart (rectangles don't snap, which the guide says). That could leave a hairline channel. I couldn't zoom in to confirm.
  - Either way, a newcomer gets no feedback on why.
- **Snap pulls a short crossing line onto the line it should cross**, so it closes nothing (seen once at both seams, `plan-13`).
- **The canvas moves when a tool's hint line appears** (Curve): ~23 pt up, then ~3 pt more later (inspect bounds 279 → 256 → 253). This seems to go against the "picture never moves under a finger" design. It happened once per new panel height, so it may be the by-design "tallest panel" rule kicking in for the first time.
- **The painting screen zoomed in ~2.5× during a run of Bucket taps on different spots** (red roofs at 264,429 then 766,429, ~5 s apart). No red got painted. Seen once.
  - Likely the documented double tap. But the taps were ~500 pt apart, so it may also be the auto-zoom when a color finishes (grey had just finished).
  - Evidence: `shots/paint-progress`. The log has nothing.
- The Refine "refineFill" tip was on screen ~5 s (log 23:38:20–23:38:25) and gone before I saw it.
- Undo after adding a paint and pouring took away both the pour and the new swatch in one step. Probably by design, but surprising.

## Automation problems
- No pinch: I couldn't zoom Refine to inspect the junctions, which is exactly what this task needed.
- Straight swipes only: the hill had to be the Curve tool. I could still get the curves I wanted (one bend per curve); an S-shaped or wobbly hill wasn't possible.
- My first tap used screenshot pixels instead of points and missed (my error).
- Quick taps on the painting canvas may have counted as a double tap (see Suspicions).

## Not tested
- Drag painting, Pencil, multi-finger undo/redo, four-finger full screen, the Eyedropper's loupe.
- Bend Line, Cell Edge, Merge (to remove the tiny areas), Move Edge, Move Number, Make Cell, Edit Paint, Looks, Writing, Try Painting.
- Quit/relaunch persistence of the finished painting, and whether the gallery thumbnail is right.
- The debug moon-rise on finishing (it lasts seconds; I didn't watch for it).
- Replay.
