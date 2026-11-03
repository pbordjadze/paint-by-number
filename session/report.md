# Refine — draw-your-own session report (iPhone 17 Pro simulator, debug build, 2026-11-03)

**Verdict**: Yes: I got the sailboat I planned, drawn from a blank canvas in Refine, painted to 100%, and still there after a quit and relaunch. On the way, one plain straight line was refused three times for an internal reason, and the colour wheel didn't respond at first.

**What I meant to draw**: a sailboat: blue sea below a straight horizon, a brown trapezoid hull on it, two white triangular sails either side of a mast, a small red flag at the mast top, and a yellow round sun in a light-blue sky.

## What I got
A clean coloring-book sailboat. It has 7 areas and 6 paints: 1 light-blue sky, 2 yellow sun (circle), 3 red pennant flag, 4 white sails (two triangles either side of the mast), 5 brown trapezoid hull, 6 deep-blue sea. All are closed shapes, each its own area, in the colours I chose. The preview said "6 colors · 7 areas · ~5 min". It matches my plan line exactly. The sails are straight-edged triangles: I tried a curved, billowing sail with Bend Line and undid it (see below).
- `shots/final-refine`: the drawing in Refine, whole picture in view.
- `shots/final-template`: the painting screen before painting (numbers 1–6, sky hatched).
- `shots/final-painting` (taken during the finish effect, colours dimmed) and `shots/final-painting-later` (a moment later, true colours): finished, 100%.
- `shots/relaunch`: taken right after launch, shows a blank loading screen. A screenshot seconds later (not saved) showed the finished Sailboat at 100%.
- Along the way: `plan-1` (Samples), `plan-2-blank`, `plan-3-hull`, `plan-4-sails` (left sail missing), `plan-5-refused`, `plan-6-lines-done`, `plan-7-wheel` (a tap meant for the wheel opened a guide page, see step log), `plan-8-picker-late`, `plan-9-sun`, `plan-10-sails`, `plan-11-colored`, `plan-12-bend-wavy`.

## The steps
| Step | Tries | Stuck for | What finally worked | What I expected instead |
|---|---|---|---|---|
| Find a blank canvas | 1 | 0 | + › Samples › Red Fuji › **Refine** (top right of the preview) › "Generated / Blank" switch above the canvas › **Blank**: one area filled with a grey-olive (presumably the picture's average colour) | Easy to find. A white/paper start might be more natural than olive, but it didn't matter once painted |
| Close the first tip ("Draw Your Own Lines") | 1 | 0 | Close | – |
| Horizon | 1 | 0 | Ink › Shapes (2nd tool) › Line; one swipe edge to edge | as expected |
| Hull (3 lines) | 1 | 0 | three Line swipes; Snap joined the ends to the horizon and each other | as expected |
| Mast, right sail, flag (2 lines) | 1 | 0 | Line swipes | as expected |
| Left sail (one line from mast to hull top) | 4 | ~1.5 min | moving the start on the mast from y≈305–310 to y≈320 | the first try to work: it's the mirror of the right sail (**bug 1**) |
| Sun | 1 | 0 | Shapes › Ellipse; one diagonal swipe gave a circle | as expected |
| Find how to add colours | 3 taps on the wheel + Tool Guide | ~2 min | the colour wheel at the palette's right end opens a "New Paint" sheet (Grid / Spectrum / Sliders); pick, close with X; the new paint is selected | the wheel to open on the first tap (**suspicion 2**). I needed the Tool Guide (?): it confirmed this was the right control. Its back arrow then took me to the guide's list, where my next tap opened "Bend Line" by mistake |
| Colour sky, sun, flag, sails, hull, sea | 1 each | 0 | Paint › Bucket: tap each cell after picking its paint. The original grey paint left the palette by itself once unused | as expected; very smooth |
| A billowing sail (curve) | 1 | 0 | Ink › Bend Line, a short drag on the right sail's edge bent it, but into a wavy S (bulge high, kink near the foot), not one smooth arc; Undo restored it | a gentle single curve from a small drag (**suspicion 3**) |
| Name it | 1 | 0 | the title field held the sample's name "Red Fuji" (placeholder); I typed "Sailboat" | a drawing made on Blank still carries the sample's name as its default (**suspicion 4**) |
| Paint it | 7 areas, ~3 extra taps | 0 | swatch, then tap area; finished at 100% with "Finished! Sailboat" | see suspicion 5 on the shifting palette |
| Quit (Home) and relaunch | 1 | 0 | reopened on the finished Sailboat, 100%, all areas painted | as expected |

## Where I got stuck (worst first)
1. **The left sail line was refused 3 times** (`shots/plan-4-sails`, `shots/plan-5-refused`). I wanted a single straight line from the mast down to the hull's top edge, the mirror of the right sail that had just worked. First nothing happened; then "That line couldn't be drawn there." The log said it was an internal "validation work limit exceeded". A newcomer gets no hint what is wrong or what to change. I only got through by nudging the start point down the mast.
2. **The colour wheel didn't respond** (`shots/plan-8-picker-late`). I wanted to add paints. Two taps on the wheel showed nothing; I went to the Tool Guide to check I had the right control. The sheet then appeared only seconds after a third tap.
3. **A curve didn't come out as a smooth curve** (`shots/plan-12-bend-wavy`). I wanted a slightly billowing sail. Bend Line gave an S-shaped wobble, so I kept straight sails.

## What I wanted and couldn't do
- Draw a gentle single-arc curve (a filled sail) with Bend Line from one short drag. Maestro's swipe is straight, so freehand Pen curves weren't an option either (see Automation problems).
- Draw the left sail's line where I first put it (mast at y≈305).
- Get the colour picker on the first tap.

## App bugs (reproduced)
1. **A simple straight line is refused: "That line couldn't be drawn there." (internal work limit).**
   Steps: + › Samples › Red Fuji › Refine › Blank. Ink › Shapes › Line, Snap on (default). Draw the horizon (14,430)→(388,430); hull (120,400)→(300,400), (120,400)→(150,430), (300,400)→(270,430); mast (210,400)→(210,278); right sail (210,292)→(285,400); flag (210,278)→(242,286)→(210,294) (points; canvas spans (12,246)–(390,503)). Then Line (210,305)→(150,400).
   Expected: a line closing the left sail.
   Observed: no line, 3 of 3 times at that spot: twice (210,305)→(150,400), once reversed (150,400)→(210,310). Try 1 showed nothing by my next screenshot; tries 2 and 3 showed the toast "That line couldn't be drawn there." Log each time: `An edit was declined: the result is not valid: edges 0 rings 0 mesh 0 labels 0 canvasAreaError 0.0 cramped 0 validation work limit exceeded: geometry bucket entries (limit 10624)` (later `limit 12160`). All the geometry counters are 0. Only a work limit failed, on a picture of about 9 straight lines. Moving the start to (209,320)→(160,399) worked on try 4. Other edits right after (an ellipse) worked.
   Evidence: `shots/plan-4-sails`, `shots/plan-5-refused`, app.log lines at 12:25:14, 12:25:39, 12:26:00.

## Suspicions
2. **The New Paint colour wheel ignored the first taps or opened very late.** Paint › Bucket, the wheel (`refine-palette-new`, label "New Paint, New Paint") at the palette's end. Tap by id: screenshot after Maestro's settle showed no sheet. Tap by point (360,707): same. No log line for either. After a visit to the Tool Guide, a tap by label: `inspect_screen` right after showed no sheet, but a screenshot a few seconds later showed the "New Paint" sheet (`plan-8-picker-late`). The next four times it opened promptly. Seen once (the first use in the session); not re-tested from a fresh Refine. Possibly a slow first presentation of the system picker in the simulator.
3. **Bend Line gives a wavy S rather than a smooth bulge.** A ~16-point outward drag from the middle of a ~130-point straight sail edge (248,346)→(262,338) produced a bulge near the top and an inward kink near the bottom (`plan-12-bend-wavy`). The guide says the line "bends smoothly around it, less the farther along"; the result didn't look smooth to me. Seen once; Undo restored the line correctly.
4. **A blank-canvas drawing keeps the sample's name.** After drawing on Blank, the title field's placeholder still read "Red Fuji", so a person who doesn't type a name gets a sailboat called "Red Fuji". Minor.
5. **The painting palette shifts under the finger as colours finish.** Finishing colour 1 removed its swatch and re-centred the rest. My next swatch taps, aimed where 2 and 3 had just been, landed between swatches. The ring then sat on 4 (white). A tap on the small flag (3) painted the nearby right sail instead (the 14-point rule, by design). A person tapping from memory would hit the wrong swatch. Seen once; this may be intended design, so I'm noting it, not calling it a bug.

No crashes (crashes.txt empty).

## Automation problems
- Maestro's `swipe` is a straight line, so freehand Pen curves weren't possible. I used Line and Ellipse (fine for this subject) and Bend Line for the one curve I tried. This also belongs under what I wanted.
- `hideKeyboard` failed on the title field ("Couldn't hide the keyboard"); I pressed the keyboard's ✓ by point instead.
- Taps are judged only after the screen settles. Short effects (the shine of a fill, a swatch shake) couldn't be seen.

## Not tested
- Pinch zoom, two-finger pan, two-finger undo / three-finger redo in Refine; Apple Pencil; dragging a swatch onto a cell; press-and-drag painting on the painting screen.
- Pen (freehand) tool, Eraser, Line Eraser, Cells / Numbers / See groups, Looks, Edit Paint, Layers.
- The gallery thumbnail of the finished Sailboat (relaunch reopened the painting, not the gallery).
