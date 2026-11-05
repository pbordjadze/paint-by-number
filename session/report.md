# Refine from scratch: lighthouse (iPhone 17 Pro, debug build)

**Verdict**: Yes. I drew, colored and painted to 100% the picture I wanted, in about 9 minutes, with no redos. One real problem turned up next to the task: Back on the New Painting preview throws a from-scratch drawing away without asking.

**What I meant to draw**: A red-and-white striped lighthouse tower (red top, alternating bands) with a yellow lantern and dark roof, on a grey oval rock island, in a dark-blue sea with a lighter wavy band and a darker band below, and two white seagulls in a light-blue sky.

**What I got**: That picture, in 16 areas and 9 paints:
- a light-blue sky with two gulls, each made of two white crescent wings;
- the lighthouse: a dark-grey triangle roof, a yellow lantern and five bands (red, white, red, white, red);
- a grey oval island in a dark-blue sea that wraps around it;
- a scalloped wave line (three arcs) with a lighter-blue band under it, and a navy band at the bottom (one gentle arc).

The waves are stylised scallops, not realistic ones, and the gulls are crescent "M" shapes. Both fit a simple paint-by-numbers picture. The bottom red band is shorter than the others because the island's top edge bulges up into it, so its number sits off-centre to the right. That is cosmetic.

Screenshots:
- `shots/plan-1`: New Painting
- `plan-2`: blank Refine
- `plan-3`: tower outline
- `plan-4-lineart`: all the lines
- `plan-5-numbers`: colored, with the Numbers layer on
- `final-refine`, `final-template`, `final-painting`
- `gallery-after`: "Lighthouse · Finished · 1 min", with a correct thumbnail

## The steps

| Step | Tries | Stuck for | What finally worked | What I expected instead |
|---|---|---|---|---|
| Find a blank canvas | 1 | 0 | + → "From Scratch" (top right of New Painting) | As expected; the label is clear |
| Learn the tools | 1 | ~1 min reading | Tool Guide (?) → Pen page. It explains Snap (about 10 pt) and that a closed line makes a cell. Helpful, though I only needed that one page. | — |
| Island | 1 | 0 | Ink › Shapes › Oval, one corner-to-corner drag | — |
| Sea line | 1 | 0 | Shapes › Line from each edge to the oval; Snap joined all ends | — |
| Tower, 4 stripes, lantern, roof | 1 (12 swipes) | 0 | Shapes › Line; every end snapped onto walls or the oval | — |
| Waves (curves) | 1 | 0 | Shapes › Curve: drag the chord, then drag to bend it (the hint says so). One bend per curve, so the wave line is 3 chained arcs and the lower band 1 arc | One stroke for an S-shaped curve; chaining arcs worked |
| Gulls | 1 each | 0 | For each wing: a bent Curve plus a straight Line under it, making a crescent cell | — |
| Colors | 1 per paint | 0 | Paint › Bucket. The palette's colour wheel opens the system picker; tap a Grid colour, tap outside to close, then bucket the areas | — |
| Check the areas | 2 | ~1 min | Layers › Numbers. A tap on the row's middle didn't flip it; a tap on the switch itself did | That the row tap would toggle |
| Name it and start | 1 | 0 | Typed "Lighthouse" in the name field; Maestro's `hideKeyboard` then landed in painting (see Automation problems) | — |
| Paint | 16 taps, 1 per area | 0 | Every tap filled its area; finishing a colour moved on to the next | — |

## Where I got stuck
I was never stuck for long. The three roughest moments, worst first:
1. **Lost a drawing with one tap on Back** (after the task, see Bug 1). My test drawings were trivial, but this would have thrown away the 9-minute lighthouse with no warning. Screenshots: `discard-1-preview`, `discard-2-after-back`, `discard-3-blank-again`.
2. **The canvas jumped 23 pt when I picked Curve.** My first curve landed 23 pt lower in the picture than I meant, because my swipe used the old position. It still worked for my picture. Compare `plan-3` (canvas top at 185 pt) with `plan-4-lineart` (162 pt).
3. **The Numbers switch in Layers** didn't toggle from a tap on its row. It's minor and may be Maestro tapping the label area.

## What I wanted and couldn't do
- Draw a wavy, S-shaped curve in one stroke. Curve gives a single bend, so I chained three. (Maestro swipes are straight, so freehand Pen curves weren't an option either.)
- Go back from the preview to Refine to tweak the drawing without risking it. Back discards it; the "Refine" button at the top of the preview is the safe way, but nothing tells you that.

## App bugs (reproduced)
1. **Back on the New Painting preview discards a from-scratch drawing without asking.**
   - Steps: + → From Scratch → draw something (a line; in the second run an oval) → Done (the preview shows the drawing, "1 color · 2 areas") → tap Back (‹, top left) → you land on New Painting (Photos/Samples) → tap From Scratch again.
   - Expected: Back asks "Discard your drawing?", as Refine's own Cancel does ("Discard Your Changes?"), or From Scratch reopens the drawing.
   - Observed: no question; From Scratch opens a blank page, and the drawing (and its typed name, "Line test", in run 1) is gone.
   - How often: 2 of 2.
   - Evidence: `discard-1-preview`, `discard-2-after-back`, `discard-3-blank-again`, `from-scratch-again`.

## Suspicions
1. **The canvas jumps when a Shapes hint appears.** Choosing Curve shows a hint above the shape bar ("Drag from one end of the curve to the other, then drag to bend it. Two fingers zoom and move."). The canvas then moves up 23 pt (from y 185–563 to 162–540) and stays there, even after the hint fades.
   - It happens on selecting the tool, not mid-stroke. In my first run, choosing Curve and swiping were in one flow, so it looked as if the picture moved under the finger. The repro showed it moves before any touch.
   - That fits the design note that the canvas keeps the room of the tallest panel. But a person who has lined up a stroke and then picks a tool sees the picture jump.
   - How often: 2 of 2 (once per fresh Refine).
2. **Tips in the log I never saw.** Between 22:43 and 22:45 the log has "offer in refine: refineFill, wanted" about 25 times. It also has "turn: refineFill" at 22:42:28 and "turn over: refineFill" at 22:43:13, but none of my screenshots in that window show a tip, so I may have missed it. Then "refineFill refused: nothingDone", though I had drawn plenty by then. The tip's pacing and its "nothing done" check may be off.

## Automation problems
- Swipes are straight lines. For curves I used the app's Curve shape, so this cost nothing here.
- **`hideKeyboard` started the painting.** After I typed a name on the preview, Maestro's `hideKeyboard` put me on the painting screen without my tapping Start Painting. A retest with the keyboard's own ✓ key just closed the keyboard and stayed on the preview (`name-return`), so this was Maestro's touch (most likely landing on Start Painting as the layout moved back), not the app. It spent one free painting (5 → 4 left).
- Layers › Numbers: tapping the row by id (the row's centre) didn't flip the switch; a tap on the switch did. Possibly Maestro hitting the label.

## Not tested
- Pen freehand with Smoothing, Bend Line, Eraser, Line Eraser, the Cells/Numbers/See groups, Looks, Edit Paint, Paint Brush, Eyedropper, Color from Photo.
- Rectangle, Hexagon and Star shapes.
- Pinch, two-finger pan and multi-finger undo; Apple Pencil.
- Drag painting on the painting screen.
- Quitting and relaunching mid-drawing (whether Refine keeps an unfinished drawing).
- The Replay of the finished painting.

No crashes (`crashes.txt` is empty).
