# Refine exploratory session — drawing a cat (iPad Pro 13", debug build)

**Verdict**: in progress — drawing and coloring done in Refine; painting not yet done.

**What I meant to draw**: an orange cat sitting, seen from the front: round head with two pointed ears, an oval body below it, a curling tail on the right, green eyes and a pink nose, on a light-blue background.

## What I got (so far)
Orange cat on light blue: round head, two triangular ears (Pen), oval body, a tail (Pen polyline, then Bend Line to round two of its corners), lime-yellow eyes (I mis-picked lime instead of green in the grid), pink nose. Every shape closed: one Bucket tap filled each. Screenshots: shots/plan-1…plan-6.

## The steps
| Step | Tries | Stuck | What worked | Expected instead |
|---|---|---|---|---|
| Get to Refine | 1 | 0 | + → sample Red Fuji → Refine (top right) | — |
| Find a blank canvas | 1 (needed luck) | ~1 min | "Generated / Blank" switch top-left of canvas; it was hidden under the first tip "Draw Your Own Lines" | Blank offered visibly at entry |
| Head & body | 1 each | 0 | Shapes › Oval, drag corner to corner | — |
| Ears (Pen) | 1 each (2 strokes each) | 0 | Stroke ends snapped onto head line | — |
| Tail (Pen) | 1 (10 short strokes) | 0 | Polyline closed onto body; angular | A curve: straight swipes only (automation) |
| Round the tail | 2 bends | 0 | Bend Line: drag a segment's middle — it curved smoothly | — |
| Eyes, nose | 1 each | 0 | Shapes › Oval, small | — |
| Change background color | 3 | ~2 min | Edit Paint › color well › system picker | Tap a swatch to change its color |
| Add new colors | 5+ | ~3 min | Palette's colour-wheel "New Paint" button; then Bucket an area | Picker to open on first tap; several new paints to stay in palette |
| Color areas | 1 tap each | 0 | Bucket | — |

## Where I got stuck
1. **New Paint button did nothing** (twice, first time with Bucket selected and only paint 1 in the palette: by point and by id `refine-palette-new`); later the same button opened the "New Paint" picker every time. Unclear why.
2. **Only one new paint at a time**: I added orange, then green, then pink in a row; the palette kept only the last (one "+" swatch, its color replaced). A newcomer building a palette first loses colors without warning.
3. **Blank canvas hidden** under the first tip.

## App bugs (reproduced) / Suspicions
- Suspicion: New Paint (`refine-palette-new`) unresponsive on first two taps (15:28, Bucket tool, palette with only the original paint). Not yet reproduced. app.log shows nothing for it.
- Finding (design?): unused new paint is replaced by the next New Paint pick instead of adding a swatch (seen 3×).

## Automation problems
- Swipes are straight lines: the tail had to be a 10-segment polyline, then rounded with Bend Line.

## Not tested (yet)
- Two-finger zoom/undo, Pencil, painting screen.
