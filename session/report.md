# Refine exploratory session: house and tree (iPhone 17 Pro sim, debug build, 2026-11-03)

**Verdict**: Yes. I got the picture I wanted, and it is painted to 100%. On the way, the trunk leaked into the sky once, and it took two more tries to close it.

**What I meant to draw**: A yellow house (rectangle walls) with a red pointed triangular roof, a brown door and a light-blue square window, and beside it a tree: a brown trunk under a round green top, standing on a green ground strip under a pale-blue sky.

## What I got
A clean, simple picture of 9 areas in 7 paints: pale-blue sky, yellow walls, red triangular roof, brown door, cyan square window, olive round treetop, brown trunk, light-green ground strip. There is also a thin brown sliver (its own area, number 3) between the treetop and the trunk: that is where I patched the trunk's top. It barely shows and reads as part of the trunk. The outlines are crisp, and every shape is its own closed area with a number.
- `shots/final-refine.png`: the drawing in Refine, the whole picture, just before Done.
- `shots/final-template.png`: the painting screen before painting (numbers 1–7 placed sensibly; the sky hatched).
- `shots/final-painting.png`: finished, 100%, "Finished!" bar.
- Along the way: `plan-1` (Samples list), `plan-2` (preview sliders), `plan-3` (line drawing done), `plan-4-trunk-leak` (the brown sky after the trunk leaked), `plan-5-trunk` (trunk fixed).

One mismatch: the painting is still titled **"Bison in Snow"**, the sample I started from, and the gallery and the Finished bar use that name. I didn't rename it on the preview's title field, which offers it, but nothing prompted me to. A drawing from Blank inheriting the photo's name is confusing.

## The steps
| Step | Tries | Stuck for | What finally worked | What I expected instead |
|---|---|---|---|---|
| Find a blank canvas | 3 | ~3 min | + › Samples (no blank sample among ~30) › Bison in Snow › Adjust: Colors 6, Detail lowest (61 areas) › Refine › **Generated / Blank** switch, top left | A "Blank canvas" choice next to Photos/Samples. You have to pick a photo (and wait for it to be processed) before Blank appears, and the minimum sliders still give 61 areas. Blank is easy to miss |
| Walls | 1 | 0 | Ink › Shapes › Rectangle, one swipe corner to corner | as expected; it landed exactly where I swiped |
| Roof | 2 | ~1 min | Shapes › Line, three swipes (two sides plus a base). 1st try: my tap missed the small Line button, so it drew 3 rectangles; I undid them | as expected once Line was selected; Snap joined the ends cleanly |
| Door, window | 1 | 0 | Rectangle ×2 | as expected |
| Treetop | 1 | 0 | Shapes › Ellipse: a clean circle from one straight swipe | as expected. No curve needed, so Maestro's straight swipes were no problem |
| Ground line | 1 | 0 | Line across the full width; it closed the sky off from the bottom strip | as expected |
| Trunk | 3 | ~3 min | 1) two vertical Lines from the circle's bottom to the ground line: **leaked**, so the Bucket filled the whole sky brown. 2) a short horizontal Line under the circle: still leaked (the trunk filled with sky blue). 3) **a closed Rectangle drawn over the trunk lines**: worked | With Snap on, lines drawn to touch the circle and the ground line should close the trunk. Nothing showed where the gap was |
| Colors | 1 each | 0 | Paint › New Paint (color wheel at the palette's right) › system color grid › X › Bucket on the area. A paint joins the palette when first poured; the unused White left by itself | Easy and pleasant. The first tap on New Paint (by id) did nothing |
| Read help | 1 | ~1 min | Tool Guide (?): pages for Select, Make Cell, Cell Edge, each with a practice canvas | It explained the tools clearly. Neither page told me how to find a gap in a shape that won't close, so it didn't solve the trunk; my own idea (a closed rectangle) did |
| Paint it | 1 per area | 0 | Tap each area. After each color is finished, the next is selected by itself. The sliver needed its `canvas-area` element to find it | as expected; 100% and a Finished bar |

## Where I got stuck
1. **The trunk wouldn't close** (worst, ~3 min, 3 tries). I drew two vertical lines from the bottom of the circle to the ground line with Snap on. On screen they look joined at both ends. The Bucket filled the trunk and the whole sky as one area (`shots/plan-4-trunk-leak.png`). A horizontal line across the top didn't fix it either (the trunk then took the sky's blue), so the gap was probably where the lines meet the ground line, but nothing on screen showed it. The fix was to redraw the trunk as a closed rectangle on top of the old lines.
2. **Finding a blank canvas** (~3 min). There is no blank option in New Painting; Samples has only photos and artworks. Blank exists only inside Refine, which you reach after picking a photo. A newcomer told "draw from scratch" might never get there.
3. **Missing the small Line button** (~1 min). The shape buttons sit in a row above Snap. One tap went to the rectangle instead (my coordinate error, but the buttons are close together), and I didn't notice until three rectangles appeared. Undo recovered it.

## What I wanted and couldn't do
- Start a blank drawing directly from + (without a photo first).
- See where an outline has a gap. When the Bucket floods past a line, nothing shows the leak point.
- Have lines snap reliably onto other lines (an ellipse, and the ground line) so a shape closes.
- Have the painting named after what I drew rather than after the sample photo, without having to remember to edit the title.

## App bugs (reproduced)
- None reproduced twice in this session; see Suspicions. (Time went to finishing the task.)

## Suspicions
1. **Snap doesn't close line ends onto an existing ellipse or line.** Steps: Blank › Ink › Shapes › Ellipse (255,325)→(345,420). Line (291,418)→(291,489) and (309,418)→(309,489), with a full-width Line at y=489 drawn after them. Bucket inside the trunk. Expected: only the trunk fills. Observed: the trunk and the whole sky filled together. A further Line at y=421 across the top didn't close it either. Seen once (two attempts at fixing it). Evidence: `plan-4-trunk-leak.png`, `plan-5-trunk.png`.
2. **New Paint didn't open on a `tapOn` by id `refine-palette-new`**, while a tap by point at the same element's centre opened the picker. Once each, so it could be timing (the first tap came right after switching to the Paint tab).
3. **A tap may fill without the screen showing it right away**: after the grass-strip Bucket tap, the next screenshot still showed the strip white. A few seconds later (Cells tab) it was green and the palette had paint 7. Seen once; probably a late redraw.
4. **Accessibility value**: after switching to Blank, `refine-canvas` still read "No changes" while Undo was enabled.
5. **The New Painting title stays the sample's ("Bison in Snow")** after a Blank drawing replaced everything from the photo.
6. Preview sliders: a swipe that starts on the track but not on the thumb didn't move the slider (twice); starting on the thumb works. That may be the standard slider, and Maestro's swipe has no press first.

## Notes (not bugs)
- After Done, the preview read "7 colors · 9 areas" while the Colors slider still said 6 (Refine's added paints; by design in debug).
- The Generated/Blank switch disappears after the first stroke and comes back when everything is undone.
- A rectangle swiped with almost zero height didn't count as an undo step.
- Samples tab: for a moment after the tap it still showed "Choose Photo", then the grid appeared.

## Automation problems
- None that stood in the way: Shapes (rectangle, line, ellipse) made curves unnecessary, so straight swipes were enough. Had I used the Pen for the round treetop, I would have needed many short straight swipes.
- The canvas area for the tiny sliver was too small to find by eye in a scaled screenshot; I used its `canvas-area-7` bounds.

## Not tested
- Pen and Bend Line freehand drawing, Eraser, Line Eraser; Cell Edge, Merge, Move Edge, Make Cell on my own drawing; Numbers and See tabs; Layers; Looks; Edit Paint; the Brush.
- Pinch zoom and two-finger pan in Refine, two/three-finger undo/redo, Pencil.
- Drag painting on the painting screen; Replay; quitting and relaunching to check saving; the gallery thumbnail.
- Renaming the painting.
