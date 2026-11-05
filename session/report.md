# Refine from scratch: ladybird on a leaf (iPad Pro 13", debug build)

**Verdict**: Yes. I got the picture I wanted, drew it in Refine and painted it to 100% on the painting screen, in about 10 minutes of app time with no step needing a second try.

**What I meant to draw**: A red round ladybird shell split down the middle, six round black spots, a black round head with two white eye dots, six black ink legs and two ink antennae, on a big green oval leaf, with a pale yellow background around it.

**What I got**: Exactly that. There are 13 areas in 5 paints:
- 1 white: the 2 eyes
- 2 red: the 2 shell halves
- 3 black: the head and the 6 spots
- 4 green: the leaf
- 5 pale yellow ("Banana Pudding"): the background

The legs and antennae are ink lines only, not areas, as I planned. The preview read "5 colors · 13 areas · ~5 min".

Screenshots:
- `shots/final-refine`: the drawing in Refine
- `shots/final-template`: the numbered template before painting
- `shots/final-painting`: 100%, "Finished! Every region is painted."
- `shots/relaunch-gallery`: after Home + relaunch, Ladybird is under Finished with the right thumbnail

The only differences from the plan are matters of taste. The shapes are perfect geometric ovals, so it looks clip-art rather than hand-drawn. The pale yellow I picked from the system grid is slightly greenish.

## The steps

| Step | Tries | Stuck for | What finally worked | What I expected instead |
|---|---|---|---|---|
| Find a blank canvas | 1 | 0 | + › "From Scratch" (top right of New Painting) opens Refine on a blank white page | Same, it was obvious |
| Draw the leaf, shell, head | 1 each | 0 | Shapes › Oval in the bottom bar; a diagonal swipe draws the oval in that box | Same |
| Eyes, 6 spots | 1 each | 0 | Small Oval swipes (22 pt and 35 pt boxes) | Same |
| Midline, 6 legs, 2 antennae | 1 each | 0 | Shapes › Line; Snap was on and the midline met the head and shell cleanly | Same |
| Make each shape its own area | 1 (unnecessary) | ~1 min | Nothing was needed: every closed shape was already a cell. I only saw that after turning on Layers › Numbers | A tip ("Make a Shape Its Own") told me to tap inside with Make Cell. I did, and nothing visibly changed, because numbers are hidden by default |
| Add colors | 1 each (4 paints) | 0 | Bucket shows the palette; the color wheel at its right end opens the system picker "New Paint"; a preset or grid cell adds a swatch; tapping outside closes it | Same |
| Color the areas | 1 tap per area | 0 | Bucket tap in each cell | Same |
| Clean up the head (overlap of head and shell was a separate cell) | 1 | ~10 s (guessing how Merge works) | Merge, swipe from the overlap into the head. The log says "joined 2 areas: 14 ... 13 after" | Merge gave no instruction on screen; I guessed a drag |
| Name it, Start Painting | 1 | 0 | Typed "Ladybird"; the keyboard's return key closed it | Same |
| Paint | 13 taps | 0 | Taps; finishing a color moved to the next one by itself; 100% and "Finished!" | Same |

## Where I got stuck
1. **Did Make Cell do anything?** (shots/plan-3-lines, plan-4-numbers). The tip says "Draw a closed shape, then tap inside it with Make Cell to give it a number of its own." I did, and the screen showed no change and no number. Numbers in Refine are off by default (Layers › Numbers). I had to discover that toggle to learn the shapes were already cells. A newcomer is left unsure whether their shapes are areas at all.
2. **How to use Merge.** Selecting it shows no hint or bottom bar. I guessed a swipe from one cell into the other, and it worked first time. The Tool Guide (?) might have said; I didn't need to open it.
3. **The color picker opened blank.** On the first open, the popover was empty white for a moment (shots: none at that moment, seen in my screenshot about 1 s after the tap); a second screenshot showed the full picker. It was only briefly confusing.

## What I wanted and couldn't do
- Nothing essential. Ovals and lines covered the whole subject, so I never needed a freehand curve. I didn't try Pen or Bend Line.
- I would have liked numbers visible by default in Refine (or visible after Make Cell), to see my areas while drawing.

## App bugs (reproduced)
None found. There were no crashes (crashes.txt is empty) and the log showed no errors.

## Suspicions
- **Make Cell on a shape that is already a cell records an invisible change.** After 20 drawn shapes (11 ovals, 9 lines) and one Make Cell tap inside the leaf, the canvas read "21 changes" with nothing visible changed. It may be an empty undo step. Seen once; not checked with Undo.
- **The tip steers newcomers to an unneeded step.** The "Make a Shape Its Own" tip appears after the first oval, which was already its own cell.
- **The picker's first frame was blank.** On its first open, the "New Paint" color picker popover drew empty for about 1 s. Seen once; later opens were not looked at that early.

## Automation problems
- `hideKeyboard` didn't close the software keyboard on New Painting's name field; the keyboard's return key did.
- I drew straight swipes only. That wasn't a limit here, because ovals and lines sufficed.

## Not tested
- Pen, Bend Line, Eraser, Line Eraser, Select, Cell Edge, Move Edge, Paint Brush, Eyedropper, Edit Paint, Looks, Move Number, Writing, Try Painting, and the Tool Guide (?).
- Undo and Redo in Refine; Cancel with changes.
- Drag painting, pinch and pan, double-tap zoom, Apple Pencil, multi-finger gestures.
- The finished painting's moon effect and Replay. They were over or not tried before my screenshot.
- Leaving mid-painting and returning. I only checked that the finished painting survives Home + relaunch, which it did: it stayed under Finished with the correct thumbnail.
