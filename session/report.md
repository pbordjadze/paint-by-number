# Refine from scratch — fish in a fishbowl (iPhone 17 Pro simulator, debug build)

**Verdict**: Yes. I got the picture I wanted, drawn in Refine and painted to 100% on the painting screen. It was still there after I quit through Home and relaunched.

**What I meant to draw**: a round bowl of light-blue water on white, an orange oval fish facing left with a black round eye, a red triangular top fin and red triangular tail, a yellow sand strip at the bottom with two green triangular plants, and three white round bubbles at the upper left.

## What I got

The plan, area for area: a round bowl (an oval drawn close to a circle, 301 × 313 pt on the page) of light blue water, an orange oval body, a black eye, a red triangular fin on top and a red triangular tail on the right, a yellow sand strip whose top line Snap cut exactly at the bowl's edge, two green triangular plants standing on the sand, and three white bubbles. That makes 7 paints and 12 areas: outside, 3 bubbles, water, body, eye, fin, tail, 2 plants, sand. The preview read "7 colors · 12 areas · ~5 min". The red came out a little lighter (coral) than I pictured, but that was my pick from the grid ("red 51"). I chose triangles for the plants and geometric pieces for the fish because of the automation (straight swipes). Ovals covered every curve I needed, so the straight-swipe limit cost me nothing.

- `shots/final-refine`: the finished drawing in Refine, painted, with Numbers on, the whole picture in view.
- `shots/final-template`: the painting screen before painting (numbers, paint 1 hatched, the "Tap to Paint" tip).
- `shots/final-painting`: 100%, the "Finished!" bar.
- Others: `plan-1` (gallery), `plan-2` (bowl + body + tail), `plan-3` (all line work), `plan-4-numbers` (after a tap that did **not** turn Numbers on), `layers-panel`, `newpaint-tap3`, `picker-red`, `after-plants`, `gallery-after`, `repro-zoom`, `relaunch-gallery`.

## The steps

| Step | Tries | Stuck for | What finally worked | What I expected instead |
|---|---|---|---|---|
| Find a blank page | 1 | 0 | + → "From Scratch" (top right of New Painting) opens Refine on an empty white square | as expected |
| Draw the bowl | 1 | 0 | Ink › Shapes (a second tap on the Line tool opens a row: Line, Rectangle, Oval, Curve, Hexagon, Star) › Oval, one corner-to-corner swipe | as expected |
| Fish body + tail | 1 | 0 | Oval body; Line ×3 tail; Snap moved the tail's tip onto the body's edge | as expected |
| Fin, sand line, plants | 1 | 0 | Line ×2 fin; one long Line across the bowl, its overshoot trimmed to the bowl by Snap; Line ×4 plants standing on the sand line | as expected; the trim was a pleasant surprise |
| Eye + bubbles | 1 | 0 | Oval ×4, small (14–20 pt) | as expected |
| Add the first new color | 3 taps | ~3 min (with the Tool Guide) | the rainbow "New Paint" well at the end of the Paint palette; taps 1 and 2 did nothing, tap 3 opened the system picker | the picker on the first tap |
| Color water, body, fin, tail, plants, sand, eye | 1 each | 0 | New Paint → grid cell → close → Bucket tap; the color waits in the palette with "+" and becomes paint n when poured | as expected |
| See the numbers | 2 | ~1 min | Layers › tap the Numbers **switch** itself | a tap on the row to toggle it |
| Done → preview → Start Painting | 1 | 0 | "7 colors · 12 areas" | as expected |
| Paint it | 13 taps (2 lost) | ~2 min | ids `canvas-area-*` for paint 1, points for the rest, Hint to reach a plant off screen | fin and tail to paint on my first taps; instead nothing painted and the canvas zoomed in |
| Quit (Home) + relaunch | 1 | 0 | gallery: "2 ready · 2 finished", both drawings with correct thumbnails | as expected |

**Tool Guide**: I needed it once, to learn how to add a color. I opened the Edit Paint page (the guide opened there, on the current tool), then The Basics, then Bucket. The Bucket page said exactly what to do: "choose any color with the color wheel at the end of the palette … waits in the palette with a + until you pour it". It helped. Each page has a live practice canvas; The Basics' practice area showed a spinner for a while.

## Where I got stuck

1. **The New Paint wheel ignored my first two taps.** I wanted a second color for the water. In the Paint group (Bucket on, palette "1 · White" only), I tapped the rainbow well at the palette's right end (`refine-palette-new`), first by id and then by point (360,707), about a minute apart. Nothing showed, the hierarchy didn't change, and app.log logged nothing. With one white paint and a wheel that does nothing, a newcomer would think colors can't be added. After a visit to the Tool Guide, the third tap opened "New Paint" (`shots/newpaint-tap3`). After that it opened on the first tap 7 times out of 7, including in a fresh Refine session.
2. **Fin and tail didn't paint, and the canvas zoomed in.** I wanted to paint the fin and the tail (paint 4) after the body. One flow did: water tap, `swatch-3`, body tap, `swatch-4`, fin tap (189,363), tail tap (275,410). The water and the body were painted. The fin and the tail weren't, and the canvas was left zoomed about 2.5× on its right half. With no pinch, I painted the tail and the fin at their zoomed positions and used Hint to reach the other plant. The canvas fitted itself again at 100%. There's no saved screenshot of the moment; `shots/after-plants` shows the zoomed state a little later.
3. **The Numbers layer**: a tap on the "Numbers" row (by its id, which taps the row's centre on its label) left the switch off (`shots/plan-4-numbers`). A tap on the switch turned it on (`shots/layers-panel`). This is minor and may be Maestro's tap point.

## What I wanted and couldn't do

- Nothing essential: the picture is the one I planned.
- I wanted the New Paint wheel to respond the first time (see above).
- I wanted to see the whole picture again after the unexpected zoom without finishing it first. With no pinch, I had no way back to the whole picture (the top bar had faded to Back, the ring and Hint).
- I couldn't try freehand curves by a real finger motion (Pen with Smoothing, Bend Line, the Curve shape). I used no curves besides ovals.

## App bugs (reproduced)

None reproduced beyond doubt.

## Suspicions

- **New Paint (`refine-palette-new`) ignored its first two taps in the first Refine session.**
  - Steps: + → From Scratch → draw shapes → Paint group → tap the rainbow well.
  - Expected: the system color picker.
  - Observed: nothing, twice (by id, then by point), and no log line.
  - How often: 2 failures in the first session. Later 7/7 successes, including the first tap in a second From Scratch session, so not reproduced. In the first session I had taken an `inspect_screen` and a screenshot between choosing Paint and tapping; the second time I tapped right away. app.log meanwhile offered the `refineFill` tip many times ("offer in refine: refineFill, wanted" with nothing shown). A tip waiting to present might be what swallowed the taps, but that's a guess.
  - Evidence: `shots/newpaint-tap3`; app.log lines 20–35.
- **Taps lost after a color finishes, plus an unexpected zoom (painting screen).**
  - Steps: as in stuck #2.
  - Expected: the fin and tail fill.
  - Observed: neither filled, and the canvas zoomed in about 2.5×. The two taps were ~90 pt apart and several seconds apart, so a double tap is unlikely. The fin tap was ~9 pt above the just-painted body.
  - How often: once. A mirror sequence on a 4-area drawing (outside → `swatch-2` → left rect → `swatch-3` → two rects) painted everything with no zoom (`shots/repro-zoom`), so not reproduced. Nothing in app.log.
- **Both drawings are named "Drawing, November 5"** in the gallery (`shots/relaunch-gallery`), with nothing to tell them apart but the thumbnail. I left the name field's default in the preview. Minor.
- The Layers panel offers Photo and a Photo-opacity slider on a From Scratch page, where there is no photo. Minor and possibly intended.

## Automation problems

- No pinch or two-finger pan: after the unexpected zoom I couldn't fit the painting again (it fitted by itself at 100%).
- Swipes are straight lines only. My design avoided needing curves (ovals did the round parts), so the result didn't suffer; freehand curves went untested.
- Maestro's tap on a Layers row by id lands on the row's centre (its label) and didn't toggle the switch; tapping the switch by point worked.
- Right after relaunch, two screenshots showed a blank screen while `inspect_screen` already listed the gallery; a third screenshot a few seconds later showed it. I trusted the later screenshot and the hierarchy. It was a slow first draw on this runner, not counted as a bug.

## Not tested

- Pen freehand drawing and Smoothing, Bend Line, the Curve, Hexagon and Star shapes, the Eraser and the Line Eraser. Also the Cells, Numbers and See groups, Looks, the Paint Brush, the Eyedropper, Edit Paint's color change (only opened), and Color from Photo.
- Two-finger undo, three-finger redo, four-finger full screen, pinch, the Pencil, the drag that waits to lift a swatch.
- Drag painting on the painting screen, double-tap zoom on purpose, More › Fit to Screen (More was hidden by the debug quiet bar during painting), Replay (▶) and Share in the Finished bar, and the moon effect on finishing (it may have played and been over before my screenshot).
- Persistence of a half-painted painting (both of mine were finished before I quit).
