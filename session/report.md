# Refine session report: lighthouse at sunset (iPad Pro 13", debug build)

**Verdict**: Yes. I got the picture I wanted and painted it to 100%. Two things cost me time: the horizon looked closed but wasn't, and the palette's "New Paint" button did nothing.

**What I meant to draw**: a white lighthouse tower with a red lamp room and a dark roof, on a grey rock, with a blue sea below the horizon and an orange sunset sky holding a yellow sun.

**What I got**:
- `shots/final-refine.png`: the drawing in Refine. Orange sky, round yellow sun, blue sea in two areas (left and right of the rock), grey trapezoid rock, white tower, red lamp room, grey triangular roof. 6 paints, 8 areas. The preview said "6 colors · 8 areas · ~5 min".
- `shots/final-template.png`: the painting screen before painting. The numbers are correct, with the sky (2) hatched.
- `shots/final-painting.png`: all 8 areas painted, "Finished! Every region is painted.", 100%.
- Progress shots: `shots/plan-1` to `plan-6`.
- It matches the plan. The roof is the same grey as the rock; I reused paint 5 on purpose. The shapes are straight and a bit stiff, and the top edge of the tower is slightly tilted (Snap pulled the ends).

## The steps
| Step | Tries | Stuck for | What finally worked | What I expected instead |
|---|---|---|---|---|
| Find a blank canvas | 1 | 0 | + → "From Scratch" icon button, top right of New Painting (I found it through its label in the hierarchy) | It's an icon with no text, next to "Browse All…". A newcomer may not spot it. |
| Horizon | 3 | ~3 min | Shapes › line edge to edge, then a short second line to the right edge | The first line ended about 10 pt short of the right edge. Snap didn't close it, so sky and sea on the right were one area. Nothing showed this until Edit Paint's purple outline left that piece out. |
| Sun | 1 | 0 | Shapes › ellipse | — |
| Rock | 1 | 0 | 3 straight lines; Snap joined the corners and the bottom edge | — |
| Tower | 2 | ~1 min | 3 lines ending on the rock top | The rectangle's bottom stopped about 3 pt above the rock line instead of snapping to it, so I undid it. |
| Lamp room and roof | 1 | 0 | 5 lines | — |
| Remove the horizon inside the tower | 2 | ~1 min | Eraser, short stroke | The first stroke erased about 15 pt around the finger and cut both tower walls; there's no size preview. I undid it. |
| Check the areas | 3 | ~2 min | Edit Paint and Select outline areas; Select's bar counts them ("Paint 1 · 8 areas") | "Writing" (SEE) changed nothing visible. Refine never shows the numbers. |
| Add a new color | 3 | ~3 min | Select an area → Change Color → card → color wheel → system picker grid | The palette's rainbow "New Paint" button did nothing (2 taps, by point and by id; nothing in the log). |
| Color the 8 areas | 8 rounds | — | Card picker for new colors; Bucket plus a swatch, or the card's "Or Use a Paint", for an existing paint | Each new color takes about 5 taps. While a card is open, a tap on another area only closes the card. |
| Paint | 7 taps | 0 | Tap each area; finished paints leave the palette and the next one is selected | — |

## Where I got stuck
1. **The horizon looked closed but wasn't** (`shots/plan-6` is the same canvas after the move). I drew it edge to edge. On screen it ended about 14 px short of the right edge, which is easy to miss against the canvas's rounded corner. Snap didn't extend it to the edge, so the whole right side of the sky and sea was one area. Nothing warned me. I found it only by opening Edit Paint, which outlines in purple the borders of the paint's areas and left that piece out. A newcomer would see it only at painting time, as one huge area.
2. **No way to add a paint from the palette.** The rainbow circle at the end of the palette ("New Paint, New Paint", value "white") did nothing on 2 taps. I found new colors only through Select → Change Color → area card → color wheel. That's 5 steps per color, and I needed the area card to get there.
3. **The Eraser had no preview of its size.** My first stroke, a small horizontal one inside the tower, took out both tower walls. Undo fixed it. The second, shorter stroke removed exactly the horizon segment, although the Size slider looked unchanged.

## What I wanted and couldn't do
- See the numbers while drawing in Refine. "Writing" showed nothing visible, and I found no "show numbers" view.
- A warning or highlight for a line that doesn't close an area: a loose end near an edge or near another line.
- Add a new paint straight from the palette.
- Have Snap join a rectangle's edge onto an existing line, as it does for line endpoints.
- See the eraser's size before erasing.

## App bugs (reproduced)
1. **Palette "New Paint" button does nothing** (Refine, Bucket tool selected).
   - Steps: From Scratch → Bucket → tap the rainbow circle at the right end of the palette (`refine-palette-new`).
   - Expected: a color picker or a new paint.
   - Observed: no picker, no change, nothing in app.log.
   - How often: 2 of 2 taps, once by point (943,1322) and once by id. Evidence: compare `shots/plan-5` with the screen after the taps (unchanged).
   - Not tried: tapping it again later, once more paints existed.
2. **"Writing" (SEE) shows nothing.**
   - Steps: tap Writing in Refine with the drawn outline on the canvas.
   - Expected: some view of the writing or the numbers.
   - Observed: only the tool's highlight changed; the canvas looked identical.
   - How often: 1 of 1. Evidence: `shots/plan-5`. Possibly it applies only to photo-based paintings, but nothing says so.

## Suspicions
- **Snap is inconsistent.** Line endpoints snapped to the left edge, the bottom edge and to other lines. The horizon's right end (drawn to 1017 pt, edge at 1020) and the rectangle's bottom (about 3 pt from the rock line) did not. Seen once each.
- **Tower labelled twice.** On the painting screen the white tower (one area: one tap filled all of it) showed two "1" labels, above and below where the erased horizon used to cross it. Possibly by design for tall areas, or a leftover of the erased line. Evidence: `shots/final-template`.
- **The canvas moved up about 38 pt** the first time Edit Paint opened, and stayed there. This is the documented "tallest panel" behaviour, but I had to recompute every coordinate.
- **The area card's highlight is misleading.** While the card for one area (the sky) was open, the purple outline showed all of paint 1's areas, not just the one being recolored.

## Automation problems
- Maestro's swipes are straight lines. I needed no curve: the ellipse tool gave the sun. Bend Line and the curve tool are untried.
- Tapping outside the system color picker dismisses it. One of my taps landed outside it because of my own wrong coordinate conversion, not the app's fault.
- A tip ("refineFill", 14:48:41 to 14:48:45 in the log) came and went between screenshots, so I never saw it.

## Not tested
- Pen (freehand), Bend Line, Line Eraser, the curve, polygon and star shapes, Cell Edge, Merge, Move Edge, Make Cell, Paint Brush, Eyedropper, Looks, Move Number, Try Painting, Layers, Tool Guide (help: I didn't need it).
- Naming the painting (the title field), Replay, Share, quitting and relaunching to check the painting was saved, and the gallery's thumbnail.
- Pinch zoom, two-finger gestures, Apple Pencil, drag painting.
- No crashes: crashes.txt is empty.
