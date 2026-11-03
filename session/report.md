# Refine exploratory session: sailboat (in progress)

**Verdict**: in progress.

**What I meant to draw**: A sailboat on the sea: light-blue sky, yellow round sun top-left, two white triangle sails on a mast, red trapezoid hull, dark-blue sea below a straight horizon (6 areas, 6 colors).

## Log so far
1. + → tip "No Photo at Hand" (closed) → Samples → Red Fuji → preview → Refine (top-right). 1 try each.
2. Refine opened with a tip "Draw Your Own Lines" (closed). There's a Generated / Blank switch above the canvas: Blank gave one grey-olive area. 1 try, found it right away (shots/plan-1 is the generated one before Blank).
3. Horizon: Pen, one straight swipe across from 1 pt inside the left edge to 1 pt inside the right edge. Ink appeared.
4. Ink › Shapes offers Line, Rectangle, Ellipse, a path, Polygon, Star. Ellipse: one drag drew the sun circle (the drag sets its bounding box). 1 try.
5. Line shape, Snap on: mast, main sail diagonal, hull top, two hull sides, jib diagonal. Six swipes, and every end looked joined on screen (shots/plan-2).
6. New Paint: a tap by id `refine-palette-new` did nothing. A tap at its centre by point opened the "New Paint" picker (Grid/Spectrum/Sliders). Picked light cyan, closed it, and a swatch "2" appeared.
7. Bucket on the sky filled **the whole picture except the sun**: sails, hull and sea too. Undo. Numbers showed only 2 numbers. Cells › Select on the sail lit one cell = everything but the sun, "Paint 1 · 2 areas" (shots/plan-3).
   → **None of my lines made areas**, though on screen they meet the edges and each other.
8. Read the Tool Guide › The Basics ("Cells are the areas the lines and edges make"). It told me the idea but not why mine failed.
9. Test: a Line from off-picture (x=3) to off-picture (x=399) made a real cell ("3 areas"). So lines must **cross** the edge or line they end on. Ending exactly there, as Snap puts them, leaves a gap.
10. Undid the boat, Line Eraser on the old horizon (one tap, worked), redrew everything with ~5 pt overshoot (shots/plan-5). Numbers: sun, sky, jib, main sail, sea, but **no hull**. Select on the hull: it was still part of the sky. Snap had pulled the side lines' ends exactly onto the hull top/horizon again.
11. Line Eraser on both hull sides, Snap **off**, redrew the sides crossing both lines. They cross, but they leave visible ink stubs past the corners.
