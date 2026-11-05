# Paint by Moonlight: Refine from scratch, hot-air balloon (iPhone 17 Pro simulator, debug build, 2026-11-05)

**Verdict**: Yes. I got the picture I meant to draw, a red balloon on two ropes with a brown basket over two green hills under a blue sky, and painted it to 100%. Two moments were rough: the color wheel twice did nothing, and the canvas jumped when I first used Curve.

**What I meant to draw**: A red oval balloon at the top centre with a small brown square basket hanging below on two straight ropes, a blue sky, and two overlapping green hills (light green behind, dark green in front) across the bottom.

## What I got
- `shots/final-refine.png`: the drawing in Refine (Numbers tab, whole picture in view). It has 6 areas: the sky, the sky between the ropes, the red balloon (oval), the brown basket (rectangle), the light-green back hill and the dark-green front hill. All are closed shapes with black lines, and each has its own number.
- The preview line read "5 colors · 6 areas · ~5 min".
- `shots/final-template.png`: the painting screen before painting. The sky is hatched for color 1, the other areas are paper with numbers 1–5, and the palette shows blue, red, brown, light green and dark green.
- `shots/final-painting.png`: all 6 areas painted, 100%, "Finished!". It matches my plan.
- Weak points in the picture:
  - The basket nearly sits on the back hill (about 15 pt above it).
  - The numbers in Refine's Numbers view are very small, though they are a fair size on the painting screen.
- The finished painting stayed in the gallery after Done (`shots/gallery-after.png`) and after quitting through Home and relaunching (`shots/after-relaunch.png`; the thumbnails were still fading in at that moment).

## The steps
| Step | Tries | Stuck for | What finally worked | Expected instead |
|---|---|---|---|---|
| Find a blank page | 1 | ~0 | New Painting › the pen-squiggle button at the top right (labeled "From Scratch" for accessibility only). It opened Refine on a white page (`plan-1`, `plan-2`). | A visible text label. I knew what the icon meant only from `inspect_screen`; a newcomer has to guess. |
| Draw the balloon | 1 | 0 | Ink › Shapes › Oval, one corner-to-corner drag (`plan-3`) | As expected |
| Basket + two ropes | 1 each | 0 | Shapes › Rectangle, then two Lines. Snap joined the rope ends to the oval and the basket, so the areas closed (`plan-4`). | As expected |
| Back hill (a curve) | 1 | 0 | Shapes › Curve: drag a straight line, then drag once more to bend it. The curve passes through where you drag. Before the bend, the canvas jumped up about 23 pt (see Bugs). | The canvas staying still |
| Front hill | 1 | 0 | The same two-step Curve (`plan-5`, `plan-6`) | As expected |
| Find how to add colors | 4 taps + help | ~3 min | Paint tab › the color wheel at the end of the palette. My first two taps on it did nothing. The Tool Guide (Bucket page) told me the wheel is the way, and its demo wheel opened a "New Paint" picker. Back in Refine, the third tap opened it. | The first tap opening the picker |
| Color the areas | 1 each | 0 | Pick a grid color in the picker › close (X) › Bucket-tap the area. The unused White left the palette by itself (`plan-8`, `plan-9`). | Picking a grid color didn't close the picker; one more tap each time. Fine. |
| Done › Start Painting | 1 | 0 | Done → preview → Start Painting. The painting opened in about 2 s. | As expected |
| Paint | 6 taps | 0 | `canvas-area-0` + a tap between the ropes for blue. The app moved on to the next color by itself after each one (`paint-1`, `paint-2`). | As expected |

Help: I opened the Tool Guide once, after the color wheel failed. It explained the wheel clearly, so yes, it helped. Its demo also showed the wheel does work, which made me retry.

## Where I got stuck
1. **The color wheel ignored my first two taps** (by id `refine-palette-new`, then by point 360,707). The palette showed only "1 · White", and I didn't know whether the wheel was the right control. I opened the help, came back, and the third tap worked. Evidence: the screenshot after those taps showed no change (not saved as a file; `inspect_screen` showed no picker either); `wheel-tap-3.png` shows the third, working tap.
2. **The canvas jumped up about 23 pt** the first time I used Curve, between drawing the line and bending it. If I had aimed the bend from the old position, it would have missed the line. Evidence: `plan-4.png` (before) vs `plan-5.png` (after).
3. **"From Scratch" is an unlabeled squiggle icon**, so a newcomer can't tell it means "blank page". Evidence: `plan-1.png`.

## What I wanted and couldn't do
- A gentle wavy horizon with more than one hump in a single line. A Curve bends in one place only, so I used two curves. That was fine for this picture.
- A clear on-screen name for "From Scratch".

## App bugs (reproduced)
- **The canvas moves when the Curve hint first appears.**
  - Steps: + → From Scratch → Ink › Shapes › Curve → drag a line across the page.
  - Expected: the picture stays where it is. (The design says the canvas keeps its room so the picture never moves under a finger.)
  - Observed: the hint "Drag to bend the curve, or tap to keep it straight." appears, and the canvas moves up from y=185–563 to y=162–540 (inspect_screen bounds). It then stays there for later curves.
  - How often: 2 of 2, on two separate blank pages. The second page is in the `wheel-repro-2` / Discard sequence, where the canvas top went from 434 px to 372 px in the screenshot.
  - Evidence: `plan-4.png` vs `plan-5.png`.

## Suspicions
- **The color wheel sometimes ignores a tap.** It happened twice in a row in the first session (19:28–19:29). There was no log line, and `inspect_screen` afterwards showed no picker. I couldn't reproduce it on a fresh page, or after drawing a curve and switching to Paint (`wheel-repro-1`, `wheel-repro-2`: both opened on the first tap). The log does show a "refineFill" tip having its turn at 19:26:51–19:27:36, which I never saw on screen, and further refineFill offers at 19:27:55 and 19:28:30. Maybe a tip being prepared swallowed the taps. Not proven.
- **An unseen tip.** `app.log` says the refineFill tip had its turn for about 45 s while I was drawing, yet no screenshot or hierarchy showed a popover. It may be linked to the canvas jump above, which happened at the same time.
- **Discard returns to the wrong screen.** Cancel → "Discard Changes" on a new blank page leads to the New Painting preview of an empty page ("1 color · 1 area · ~5 min", Start Painting enabled), not back to New Painting. I expected to land back where I started (`after-discard.png`).
- **Odd estimate.** "~5 min" for a blank 1-area page, the same as for my 6-area drawing.
- **Color names.** Paint 1, a light blue, is called "Lavender Fields". The blue I picked was announced as "azure" in Refine but named "Lavender Fields, light vivid blue" on the painting screen.

## Automation problems
- `tapOn` waits for the screen to settle, so short effects (fill shine, the finish moon) were over before my screenshots.
- No curve-shaped swipes. I didn't need them, because Shapes › Curve made the curves.

## Not tested
- Freehand Pen drawing, Bend Line, Eraser, Line Eraser, Cells tools, Edit Paint, Looks, Layers, See.
- Pinch/pan zoom in Refine and on the painting screen.
- Drag painting, Replay, Share.
- The debug build's moon on finishing (too short to catch).
- Renaming the painting (I kept "Drawing, November 5").
