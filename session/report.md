# Refine from scratch: a red car (iPhone 17 Pro simulator, debug build)

**Verdict**: Yes. I got the picture I wanted and painted it to 100%. Two catches: the color wheel ignored my first two taps (once, not reproduced), and touching shapes made hair-thin extra areas I couldn't see (reproduced).

**What I meant to draw**: A red car (a long rectangle body with a smaller cabin on top holding a light-blue window) on two round black wheels, standing above a grey road strip along the bottom, with a round yellow sun top-right in a light-blue sky.

## What I got

- `shots/final-refine`: Refine with the whole picture in view, Numbers group. Light-blue sky; yellow circle sun top-right; red body and red cabin frame; light-blue window; two black wheels touching the body's underside; grey road under a full-width line. Numbers shown (very small): 6 sky, 4 sun, 6 window, 2 cabin, 2 body, 3 and 3 wheels, 5 road.
- `shots/plan-6-preview`: the New Painting preview says **"6 colors · 10 areas · ~5 min"**. I had drawn 8 areas with 5 paints.
- `shots/final-template`: the painting screen before painting. Palette 1 (white "Printer Paper") to 6; eight visible numbers; the sky hatched.
- `shots/final-painting`: 100%, "Finished!". It matches my plan exactly: crisp rectangles, true circles, a straight road. It looks the way I wanted.
- The gallery's Finished shelf shows the car thumbnail correctly, also after Home › stopApp › launchApp (`shots/relaunch-gallery`).

The two extra areas are white slivers where each wheel's top meets the body's bottom line. They have no visible number on the template and are invisible once painted (`shots/plan-7-slivers` is the template at that moment; the palette shows paint 1 selected and nothing to see).

## The steps

| Step | Tries | Stuck for | What finally worked | What I expected instead |
|---|---|---|---|---|
| Find a blank page | 1 | ~0 | New Painting › top-right icon (id `from-scratch`, label "From Scratch"). Goes straight to Refine on a white page | Fine. But it's an unlabeled icon; I knew its name only from the accessibility tree. A newcomer has to guess |
| Road line | 1 | 0 | Ink › Shapes (a tool showing "Line") › Line, swipe edge to edge; Snap carried it to both edges | as expected |
| Car body, cabin, window | 3 swipes, 1 each | 0 | Shapes › Rectangle, drag corner to corner | as expected |
| Wheels, sun | 3 swipes, 1 each | 0 | Shapes › Oval, drag corner to corner: true circles | as expected |
| Add a first color (red) | 3 taps + Tool Guide | ~2 min | Color wheel at the palette's end (`refine-palette-new`). The 3rd tap opened the "New Paint" picker (Grid/Spectrum/Sliders, recent colors) | First tap opens it |
| Color body, cabin | 1 each | 0 | Pick in the picker, close with X, Bucket-tap the cell. The pending "New Paint" became paint 2 when poured | as expected |
| Wheels black, sun yellow, road grey, sky and window light blue | 1 each | 0 | Same; the wheel opened on the first tap every time from then on | as expected |
| Check the numbers | 1 | 0 | Numbers group: 8 numbers, nothing hinting at extra cells | Some sign of the 2 slivers it would later count |
| Start Painting | 1 | 0 | Done › preview › Start Painting | Preview counts 10 areas / 6 colors: surprise |
| Paint | 10 taps | 0 | One tap per area (VoiceOver ids `canvas-area-<n>`); finishing a color moved on to the next | as expected; 100% |

Help: I opened the Tool Guide once on purpose (Bucket page, about the color wheel). It confirmed I had the right control but didn't explain why it ignored me. Later I opened it again (Select, Merge pages) while investigating the slivers. The Merge page explained how to use it ("start in the cell whose paint you want to keep, and drag across…"), which was useful.

## Where I got stuck

1. **The color wheel ignored my first two taps.** In Paint, with only "1 · White", I tapped the wheel to add red: nothing, twice (by id, then by point 360,707). No picker, no log line. The Tool Guide's demo wheel opened its picker at once. Back in Refine, a third tap at 359,708 worked, and so did every later one. On a second fresh page later it opened on the first tap, so this is unreproduced.
2. **Invisible extra areas** (`shots/plan-6-preview`, `shots/plan-7-slivers`, `shots/repro-sliver-select`). Where each wheel touched the body, a hair-thin white cell appeared. Refine's Numbers view didn't show it. The preview's "10 areas · 6 colors" was my only clue, and on the painting screen it was a white paint 1 with no visible areas. I found them only through the VoiceOver elements, which a sighted newcomer doesn't have.
3. **No way to fix a sliver by touch** (`shots/repro-sliver-merge3`). Select shows the sliver as a thin purple glow if you tap exactly on it. But Merge needs a drag that starts in the wheel and *ends inside* a cell about 1 pt tall. Ending just short did nothing; going a little past merged the whole wheel into the page.

## What I wanted and couldn't do

- Be warned about, or have the app absorb, tiny accidental cells made by shapes that touch.
- Merge just a sliver into its neighbor.
- Read the wheels' number in Refine's Numbers view: the "3" on the black wheels is dark on black and nearly invisible (`shots/final-refine`).
- See a text label on the From Scratch button.

## App bugs (reproduced)

1. **Shapes that touch make hidden hair-thin cells that count as areas to paint.**
   Steps: + › From Scratch › Shapes › Rectangle drag (90,420)→(310,470) › Oval drag (118,468)→(162,512), so the circle's top meets the rectangle's bottom edge. Then Cells › Select, tap (140,469).
   Expected: two cells (body, wheel), or a visible warning or number for anything smaller.
   Observed: a thin cell on top of the circle lights up; the bar reads "White · Paint 1 · 4 areas" where 3 are visible (page, body, wheel). In the full drawing it gave 10 areas instead of 8 (log "Opened 158D20AB…: 10 regions"). The extra paint 1 stays in the palette and the slivers show no number on Refine's Numbers view or the template; painting them is required for 100%.
   How often: 3 of 3 wheels drawn this way (2 in the car, 1 in the repro).
   Evidence: `shots/plan-6-preview`, `shots/plan-7-slivers`, `shots/repro-sliver-select`.
   After Merge removed the rectangle, a short stub of its line stayed on top of the circle (the sliver's edge), visible in the screenshot after that Merge.

## Suspicions

- **Color wheel (`refine-palette-new`) ignored the first two taps** in my first Refine session (≈20:24:10 and ≈20:24:20; a `refineFill` tip had ended at 20:23:53, none showing). The third tap after a Tool Guide visit worked. Not reproduced on a second fresh page (opened at once, `shots/repro-wheel-1`). Seen 1 time in 2.
- Wheel numbers drawn dark on black paint in Refine's Numbers view: barely legible (`shots/final-refine`). On the painting screen they are grey on unpainted paper, which is fine.
- On relaunch the app showed a plain blank screen for a few seconds before the gallery (`shots/relaunch-gallery` was taken during it). Probably normal start-up on this runner.

## Automation problems

- `assertVisible: "New Paint"` failed while the picker was plainly on screen: the system picker's title isn't in the hierarchy.
- A double tap on the finished painting didn't zoom (known Maestro limitation; the painting was also finished).
- I needed no curves (all rectangles and circles), so straight swipes were enough. The Oval shape gave real circles, which a finger-drawn wheel would not.

## Not tested

Pen freehand, Curve, Hexagon, Star, Bend Line, Eraser, Line Eraser; Cell Edge, Move Edge, Make Cell; Paint Brush, Eyedropper, Edit Paint, Looks; See and Layers; pinch, two-finger pan, multi-finger undo/redo; drag painting on the painting screen; Replay and Share of the finished painting; Give Feedback. What shows only while a finger is down (Merge's highlight) couldn't be seen.
