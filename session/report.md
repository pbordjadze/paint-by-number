# Refine: drawing a face from scratch (exploratory session, 2026-11-03)

**Verdict**: Partly. The line drawing looks like the face I planned, but as a paint-by-numbers picture it isn't one: the mouth and the hair, both drawn with separate Pen strokes, never became areas. I didn't finish coloring and didn't get to paint it on the painting screen.

**What I meant to draw**: A front-facing oval face in peach on a light-blue background, two white eyes with dark pupils, a small brown nose, a red upper lip and a pink lower lip, and a dark-brown cap of hair on top.

## What I got
- `shots/final-refine`: a light-blue background and a peach oval head. Two eyes with round pupils and a triangle nose are all still light blue (I didn't get to color them). The lips and the hair are drawn as lines, but they are **not areas**: the lips are part of the peach face, the hair cap inside the head is peach (part of the face), and the hair band outside the head is part of the blue background.
- Back on the New Painting preview after Done, the line under it reads **"2 colors · 7 areas"**: background, face, 2 eyes, 2 pupils, nose. So no lip areas and no hair area.
- `shots/final-template` / `shots/final-painting`: **not taken**. I ran out of time at the preview after Refine, before Start Painting.

## The steps
| Step | Tries | Stuck for | What finally worked | What I expected instead |
|---|---|---|---|---|
| Open New Painting | 2 | ~30 s | Tap on "New Painting" (label). The sheet appeared a screenshot later | The first tap on + to open it at once |
| Find an empty canvas | 2 | ~1 min | Dark sample + Colors 6 / Detail Simple, then Refine › **Blank** (hidden under the first tip until I closed it) | A white blank page. Blank is a single **black** cell |
| Make a background color | 2 | ~1 min | New Paint (rainbow swatch, 2nd tap) › Grid › light blue, then Bucket | The first tap to open the picker |
| Head | 1 | – | Shapes › Ellipse, corner to corner | – |
| Eyes, pupils | 1 each | – | Shapes › Ellipse | – |
| Nose | 1 | – | Shapes › Line ×3 with Snap on: closed triangle, its own area | – |
| Mouth (upper + lower lip) | 1 drawing, then 1 Make Cell try | ~3 min | **Nothing**: 8 Pen strokes look closed but aren't areas | Strokes that meet close an area, as the Line tool's did |
| Hair | 1 drawing, then 2 Merge tries | ~4 min | **Nothing**: 13 Pen strokes look closed but leak into the face/background | The same |
| Color face | 1 | – | Bucket with a new peach paint (it also filled the hair cap, which revealed the leak) | Only the face below the hairline |
| Paint on the painting screen | 0 | – | Not reached (time) | – |

## Where I got stuck
1. **Pen strokes that visibly meet don't close an area** (`shots/pen-strokes-not-cells`, `shots/plan-4`, `shots/plan-5`). I drew the mouth (upper lip outline, middle line, lower lip outline) and the hair (hairline + outer outline) as separate Pen strokes, each starting exactly where the last ended (same point coordinates), with Snap on. On screen they join. With Numbers on (Layers), the lips have no numbers. Bucket on the face also filled the hair cap above the hairline, and the hair band outside the head has no number of its own (it shares the background's "1"). The preview then counted 7 areas. The nose, made of 3 separate **Shapes › Line** strokes, did close. So the newcomer's natural way (Pen, stroke by stroke) silently fails, and nothing on screen says the shape is open or where the gap is.
2. **Merge erased the whole head outline** (`shots/merge-erased-head`, `shots/merge-erased-head-2`). I wanted to join the two hair parts (inside and outside the head line), so I used Merge and dragged from the cap to the band. The entire head ellipse vanished, not just the arc between the two hair parts, and the face became one with the background. It happened 2 out of 2 times, and Undo restored it. In hindsight the "cap" was already part of the face (point 1), so Merge joined face and background. But a newcomer sees a tool that deleted the head.
3. **Make Cell turned the face black** (`shots/make-cell-black`). Hoping it would make an area from the lines I tapped inside, I picked Make Cell and tapped inside the lower lip. The whole face cell filled with black ink, the palette disappeared, and no lip area was made. Undo restored it. Make Cell gives no hint of what it does before you tap.

## What I wanted and couldn't do
- Close an area with freehand Pen strokes drawn one after another (the lips, the hair).
- See where an outline is open (a gap marker, or the area lighting up before Bucket).
- Draw a curved lip or hairline: I only had straight swipes, so the lips and hair are polylines. Bend Line exists but I had no time to learn it.
- Start from white paper: Blank is black.
- Turn a region enclosed by ink into an area (Make Cell did something else).
- Paint the finished picture (no time).

## App bugs (reproduced)
- **Merge removes the entire stroke, not only the shared edge.** Steps: Refine › Blank › Bucket a new paint › Shapes › Ellipse (big) › Pen: an outline crossing the ellipse's top › Merge, drag from inside the ellipse top to outside it. Expected: only the border between the two dragged-across areas goes. Observed: the whole ellipse goes. 2/2. Evidence: `shots/merge-erased-head`, `shots/merge-erased-head-2`. (Caveat: in my drawing the inner area was, unknown to me, already the whole face, see Suspicions.)

## Suspicions
- **Separate Pen strokes don't make closed areas even when their ends coincide (Snap on)**, while separate Line-shape strokes do. Seen for the mouth (8 strokes) and the hair (13 strokes), confirmed three ways: Numbers, Bucket spill, and "7 areas" on the preview. Evidence: `shots/pen-strokes-not-cells`, `shots/final-refine`. Maestro swipes end exactly on the next start, so it isn't finger wobble. It may be how Pen strokes end, or how Snap treats Pen.
- **Blank is a black page with only "1 · Black" in its palette.** For a coloring book I expected white paper. Black lines on it are invisible until you repaint it.
- **The first tap on New Paint (`refine-palette-new`) and the first tap on the gallery's + did nothing visible.** The second tap worked, and later a single tap on New Paint worked. Possibly slow presentation, possibly a lost tap: seen once each.
- Refine's canvas reported "No changes" right after switching to Blank, although Undo was enabled.
- The Generated/Blank switch was hidden behind the first tip ("Draw Your Own Lines"). It vanishes after the first edit, so a newcomer who edits first can't go back to Blank except by Undo.

## Automation problems
- Swipes are straight lines: the lips and hair came out as polylines, not curves (also listed under what I wanted).
- No pinch: I couldn't zoom into the joints of the mouth to look for gaps.

## Not tested
- Bend Line, Cell Edge, Move Edge, Select, Paint Brush, Eyedropper, Edit Paint, Looks, Move Number, Writing, Try Painting. Also the Tool Guide (?) help: I didn't open it.
- Start Painting, the painting screen, saving and relaunch.
- Two-finger undo, pinch, Apple Pencil.
