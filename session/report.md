# Refine session report (in progress)

**Verdict**: in progress.

**What I meant to draw**: A yellow-walled square house with a red triangular pointed roof, a brown door and a light-blue square window, and beside it a tree with a brown rectangular trunk and a round green leafy top, on a pale blue sky over green grass.

## Steps log
1. Gallery → + → tip "No Photo at Hand" closed → Samples → Earthrise (mostly black photo, chosen as the emptiest). Preview → Refine. 1 try.
2. Refine shows a "Draw Your Own Lines" tip (closed) and a Generated/Blank switch. Blank = solid black canvas (one cell, paint "1 · Black"). Found in 1 try. shots/plan-1.
3. Ink › Shapes offers Line, Rectangle, Oval, Curve, Hexagon, Star. Drew walls, door, window, trunk (Rectangle), tree top (Oval), roof (2 Lines), roof base and ground (Lines). All 9 strokes landed where I aimed, 1 try each. shots/plan-2. But: ink is near-black on the black blank canvas — barely visible. The Generated/Blank switch disappears after the first stroke. A "1 tiny number" badge appeared.
4. Paint › palette New Paint (color wheel): tapped twice (by id, by point) — nothing opened. Read Tool Guide (Bucket page says tap the wheel); the wheel inside the guide's demo opened the picker. Back in Refine the 3rd tap opened the "New Paint" picker (and it opened first time on every later try). Picked light teal; it became pending swatch 2.
5. Bucket on the sky: sky filled — but so did the roof triangle and the whole ground below the ground line (shots/plan-3-leak). The roof base line (40→200 at y=340) did not show outside the walls; the ground line stopped a few points short of the right edge.
6. Fixes: redrew roof base 36→204 (left eave appeared, right eave still missing: the end seemingly snapped to the walls' corner, not the roof's); drew 184→206 (tried to switch Snap off first; the switch still looked on). Extended ground line past the right edge. Ground then became its own cell: Bucket green on it worked (1 try).
7. Bucket red on the roof: the sky turned red too, and pale blue vanished from the palette (shots/plan-4-roof). Undo restored it. Cells › Select on the roof highlights the sky cell, whose outline goes round walls, tree and ground but NOT the roof: the roof's three lines, though they look closed, make no cell edge.
8. Cells › Make Cell tapped inside the roof: the whole sky+roof became black, pale blue gone (shots/plan-5-makecell-black). Undo.

## Suspicions so far
- New Paint color wheel in the Refine palette did not open the picker on the first two taps; opened on the third after visiting the Tool Guide. No log line.
- A triangle made of three Line strokes whose ends meet (as far as the eye can tell) is not a closed cell; rectangles and ovals are.
- Snap pulled a line's end to the wrong nearby corner (walls' 190,340 instead of roof's 200,340).
- Black ink on Blank-from-a-dark-photo canvas is near invisible.
