# Refine from scratch: a red kite over a park (iPhone 17 Pro, debug build)

**Verdict**: Partly. The kite, sky, park, tree, child, string and clouds came out as I meant, but only one of the three bows is whole: two are half-open, with stray crossing lines, and half of each is left sky-blue.

**What I meant to draw**: A red diamond kite in a pale-blue sky, top right, with a curved tail of three yellow bow-ties, a curved string down to a small child (peach round head, purple triangle body) on green grass below a straight horizon, a tree on the left (brown trunk, green round crown), and two white clouds.

## What I got
A clean, simple picture that matches the plan except for the bows (see `shots/final-refine`, `shots/final-template`, `shots/final-painting`):
- red diamond kite; a smooth curved tail; a smooth curved string that ends at the child's body
- pale-blue sky, green grass, a tree with a green round crown and a brown rectangular trunk standing on the horizon
- a child with a peach round head and a purple triangle body; two white oval clouds (plain ovals, not puffy)
- **bows**: bow 1 is a proper yellow bow-tie, though the tail cuts through its right half and leaves a tiny white sliver. Bows 2 and 3 have only a yellow left half. Their right halves never closed, and the two extra lines I drew to close them overshoot as visible stray ink strokes (`shots/plan-26-bows-zoomed` shows it best).
- The painting screen made it 8 colors · 21 areas. I painted all 21, reaching 100% and "Finished!" (`shots/final-painting`).

## The steps
| Step | Tries | Stuck for | What finally worked | What I expected instead |
|---|---|---|---|---|
| Find a blank canvas | 1 | 0 | + › close the "No Photo at Hand" tip › **From Scratch** (top right of New Painting) opens Refine on a white page | as expected; easy to find |
| Horizon | 1 | 0 | Ink › Shapes › Line, one swipe; Snap carried it to both edges | as expected |
| Kite diamond | 1 | 0 | 4 Line swipes; Snap joined the corners | as expected |
| Curved tail | 2 | ~1 min | Shapes › Curve: drag end to end, then drag the middle to bend it (the on-screen hint says so) | 1st try landed 23 pt below the kite because the canvas moved up when I picked Curve (Suspicion 1) |
| Bows (3 bow-ties, 4 lines each) | 1 to draw, 3 to try to fix | ~6 min | Bow 1 closed. Bows 2 and 3 never closed on the right; extra lines with Snap off didn't close them either | tiny closed shapes from 4 lines, as the kite was |
| Clouds, crown, head | 1 | 0 | Oval shape, drag corner to corner | as expected |
| Trunk, child's body | 1 | 0 | Rectangle (snapped to the crown and the horizon); 3 Lines for the triangle | as expected |
| String | 1 | 0 | Curve from the kite's bottom corner to the child's body, bent | as expected |
| Colors | 1 per paint | ~10 s each | Paint › colour-wheel "New Paint" › system picker Grid › swipe the sheet down › Bucket tap | picker opened **blank for ~5 s** the first time (Suspicion 3) |
| Color the bows | 6 bucket taps, then 3 retries | ~5 min | 4 of 6 halves are yellow. Three times a tap meant for a bow half turned the **whole sky yellow**; Undo fixed it each time | a tap on a tiny open shape to warn me or do nothing, not flood the sky |
| Understand the bow problem | 1 | 0 | **Numbers** tab showed which bow halves had no number, i.e. were part of the sky | it would be good to see open shapes while drawing |
| Help | 1 | 1 min | Tool Guide (?) › Make Cell page: clear and well written, but no tool for "close this gap" | a "close gaps" tool or a visible gap marker |
| Done › preview › Start Painting | 1 | 0 | "8 colors · 21 areas · ~5 min" | as expected |
| Paint | 1 | ~2 min | Tapped big areas by point, tiny ones by `canvas-area-<n>` ids, Hint to find the yellow bows; reached 100% | the canvas zoomed in unexpectedly once (probably two of my taps read as a double tap) |

## Where I got stuck
1. **Tiny bow-ties wouldn't close, and I couldn't see why** (`shots/plan-15-bows-yellow`, `shots/plan-19-numbers`, `shots/plan-26-bows-zoomed`). I wanted three small closed bow-ties. With Snap on, the ends of my short lines seem to have snapped to the nearby tail curve rather than to each other, so the right halves stayed open. Nothing on the Ink tab shows an open gap. I found out only by flooding the sky with yellow, and later through the Numbers tab. My overshoot lines (with Snap off) still didn't close them; they only left stray strokes. On iPhone the bows are about 20×14 pt, and without pinch (automation) I couldn't zoom Refine to fix them.
2. **A bucket tap on a tiny shape flooded the sky** (`shots/plan-15-bows-yellow`, `shots/plan-18-bow2-retry`, `shots/plan-23-bow2-fill`), three times. Undo always put it back, but the blue paint vanished from the palette and the numbers shifted (yellow 6 → 5). That is alarming the first time.
3. **The canvas moved between strokes** (`shots/plan-2`, `shots/plan-3-after-undo`). I aimed my first tail at the kite's corner and it landed 23 pt lower, because the picture had moved up when I picked the Curve tool.

## What I wanted and couldn't do
- Close tiny shapes reliably, or see where a shape is open while drawing (a gap marker, or a "close gaps" option).
- Zoom Refine's canvas to draw small details (pinch isn't available through Maestro, and Refine doesn't zoom on double tap).
- Puffy, scalloped clouds: only plain ovals, or many curve strokes.
- Draw freehand curves with the Pen: Maestro's swipes are straight lines. The Curve shape covered the tail and the string well.

## App bugs (reproduced)
None confirmed as bugs. No crashes (`crashes.txt` is empty).

## Suspicions
1. **Refine's canvas moves when the tool panel changes.** Steps: From Scratch › Pen (picture at y 190–568 pt per `inspect_screen`) › Shapes (picture at 185–563) › Curve (its hint line appears; picture at 162–540). Expected: the picture stays put ("the canvas keeps the room of the tallest panel… the picture never moves as tools change"). Observed: two moves, the second by 23 pt, and my next stroke landed off target. Seen once per session, since after that the picture stayed at 162. I trusted `inspect_screen`'s bounds; screenshots agree. Evidence: `shots/plan-2`, `shots/plan-3-after-undo`.
2. **Snap joins short strokes to the wrong line.** The right halves of bow-ties 2 and 3 (lines about 14–20 pt long, about 2–10 pt from the tail curve) stayed open. Bow 1, drawn the same way, closed. Seen 2 times out of 3. Not proven to be Snap; it could be my strokes being a few points off. Evidence: `shots/plan-19-numbers`, `shots/plan-26-bows-zoomed`.
3. **The color picker sheet opened blank** (a white sheet with only the grabber) for about 5 s the first time, then filled in. Later opens were quick. Probably a slow simulator. Evidence: `shots/plan-11-colorpicker-blank`.
4. **Yellow bow halves looked white in Refine's Paint view while the sky was yellow**, yet showed yellow in the Numbers view and after Undo. I'm unsure: it was read from scaled-down screenshots (`shots/plan-15-bows-yellow` vs `shots/undo2`).
5. **The painting canvas zoomed in about 2.5× during a run of taps** (white swatch, cloud, cloud, red swatch, kite, …) with no deliberate double tap. Most likely two of my taps landed close enough in time and place to count as one double tap. Not reproduced.

## Automation problems
- Maestro has no pinch or two-finger pan, so I couldn't zoom Refine to draw or fix the 20-pt bows. That is the main reason the bows stayed broken.
- Swipes are straight lines, so freehand curves with the Pen were impossible. I used the Curve shape instead.
- `tapOn: id: refine-snap` didn't toggle Snap; a tap on the switch itself (166,716) did. Most likely the element's centre lies between the label and the switch.

## Not tested
- Drag painting (press then drag), Pencil, multi-finger undo and redo in Refine, Bend Line, Eraser, Line Eraser, Merge, Move Edge, Make Cell (only read about), Looks, Layers.
- Leaving and relaunching to check that the finished painting and the gallery thumbnail are kept.
- The "moon rising" finish animation: the final screenshot showed the normal finished state with a "Finished!" bar. Any animation was over or never showed; I can't tell which.
