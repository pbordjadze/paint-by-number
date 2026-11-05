# Refine from scratch: cupcake (iPad Pro 13", debug build)

**Verdict**: Yes. I got the picture I meant, drawn in Refine and then painted to 100% on the painting screen. Two small differences: the cherry came out orange-red (my pick in the color grid), and the striped case is yellow and white.

**What I meant to draw**: A pink-iced cupcake (an oval dome of icing) with a red cherry on top and a yellow-and-white striped paper case (a trapezoid, 5 stripes), standing on a brown table in front of a cream wall with a four-pane light-blue window.

## What I got

- **Window**: one rectangle split into 4 panes by a cross, all light blue ("Ice Pond").
- **Wall**: cream ("Butter Cream").
- **Table**: a horizontal edge across the page; the table is dark orange-brown ("Rust Bucket").
- **Icing**: an oval dome in pink ("Flamingo").
- **Cherry**: a small upright oval on top of the icing, in orange-red ("Campfire", described as "vivid red").
- **Case**: a trapezoid with 4 slightly slanted stripe lines, making 3 yellow ("Canary") and 2 white stripes.
- **Totals**: 7 colors and 13 areas, the count I planned. Every shape is closed and is its own area.
- **The cherry is an oval, not round.** I dragged a 40×50 pt box. It is not a defect of the app.
- **The picture is flat**: no cupcake top, no window sill, no shading. That was my choice, to keep the areas simple.
- **Screenshots**:
  - `shots/final-refine.png`: the drawing in Refine, whole page in view.
  - `shots/final-template.png`: the painting screen before painting, numbers 1–7 in the right areas.
  - `shots/final-painting.png`: 100%, "Finished! Every region is painted."
  - `shots/relaunch.png`: right after relaunching. It came out blank; a second screenshot moments later showed the painting at 100%.
  - Progress shots: `plan-1` to `plan-8`, `wheel-*`, `paint-*`.

## The steps

| Step | Tries | Stuck for | What finally worked | What I expected instead |
|---|---|---|---|---|
| Find a blank canvas | 1 | 0 | + › "From Scratch" (top right of New Painting) opened Refine on a white page | Same. Very clear. |
| Window frame | 1 | 0 | Shapes › rectangle, one drag corner to corner | Same |
| Window cross | 2 lines, 1 try each | 0 | Shapes › line. Snap joined the ends to the frame. | Same |
| Icing and cherry | 1 each | 0 | Shapes › ellipse, drag the bounding box | Same |
| Case sides, bottom, 4 stripes | 7 lines, 1 try each | 0 | Shapes › line. Snap attached the ends to the ellipse. | Same |
| Table edge | 2 lines | 0 | Two line segments, page edge to case edge, so the case stays whole | Same |
| Pick a new color | 3 taps the first time | ~1 min | Bucket › color wheel at the end of the palette. The first 2 taps showed no picker; the 3rd opened it. Later it opened on the first tap 5 times out of 5. | It opens on the first tap |
| Pour the colors | 1 per area, plus 1 tap per color to close the picker | 0 | Pick a color in the grid, tap outside (that only closes the picker), then tap the area | Same. The extra tap is normal iOS behaviour. |
| Remove the icing arc crossing the cherry | 2 (1 failed, undone) | ~2 min, including reading the guide | Line Eraser: a **tap** on the stretch. My first try, a short **drag**, erased a band (see stuck #1). | A short drag along the line removes just that line |
| Name it | 2 | 0 | Typed "Cupcake". Maestro's hideKeyboard did nothing; the keyboard's return key closed it. | Same |
| Paint | 13 areas, about 18 taps | ~1 min | Tapping by point worked until the canvas zoomed in on its own; then I tapped the `canvas-area-<n>` elements | The view stays put while I tap |
| Leave and relaunch (Home, then stopApp and launchApp) | 1 | 0 | Reopened Cupcake at 100% | Same |

## Where I got stuck

1. **The Line Eraser's drag wiped out half my cupcake** (`shots/plan-7-cherry-erase.png`).
   - I wanted to remove the short piece of the icing outline that crosses the cherry. With Line Eraser selected, I dragged 18 pt along that piece.
   - It rubbed out a band at the default Size. That took the cherry's lower outline and opened the icing outline as well.
   - The icing and the cherry merged into the wall and turned cream. Pink and red left the palette.
   - Undo brought everything back in one step. A **tap** on the line, as the guide says, removed exactly that stretch (`plan-8-cherry-tap.png`).
   - The guide explained it ("Dragging rubs out ink as the Eraser does, at its Size"), but nothing on the screen did. The tool's name says "line", and the drag preview can't be seen.
2. **The color wheel didn't open the first two times** (no screenshot; the screen looked unchanged).
   - I tapped "New Paint" by point, then by its id; neither showed a picker.
   - The third tap, made after closing the Tool Guide, opened it. Every later tap opened it at once (5/5).
   - I lost about a minute wondering whether the wheel was a picker at all.
3. **The painting screen zoomed and shifted the canvas while I was tapping areas** (`shots/paint-1.png`).
   - After filling the wall and selecting swatch 7, my next four quick taps on the panes left the canvas zoomed about 1.4× and shifted.
   - Two of those taps painted nothing, so I fell back on the `canvas-area` elements.
   - After color 1 was finished the view moved again (`paint-2.png`), and my tap on the icing missed.
   - It was not stuck for long, but a person tapping by sight would hit the wrong place.

## What I wanted and couldn't do

- **Round the top of the icing like a swirl.** I didn't try: the ellipse was good enough, and I skipped Bend Line for time.
- **A cherry stem.** A single line isn't an area, so it would only be decoration; I left it out.
- **See where my drag would erase before it erased.** The Line Eraser's drag shows nothing in advance (at least nothing I could see after the drag).

## App bugs (reproduced)

None reproduced. Nothing crashed: `crashes.txt` is empty.

## Suspicions

1. **The color wheel ("New Paint", `refine-palette-new`) sometimes doesn't open.**
   - Steps: in Refine, with Bucket selected, tap the color wheel.
   - Expected: the "New Paint" picker opens.
   - Observed: twice in a row nothing showed; then it opened on every tap (6 of 8 taps worked).
   - Each failed tap was followed by a screenshot several seconds later. The log has nothing for the wheel.
   - Possibly the "refineFill" tip (shown 21:31:43–21:31:47 per `app.log`, which I never saw) or its pacing interfered. Not reproduced afterwards.
2. **The painting screen moves the canvas on its own.**
   - Steps: on the new painting, tap the wall area, tap swatch 7, then tap the four panes quickly.
   - Expected: the canvas stays put and all four panes get painted.
   - Observed: the canvas ended up zoomed (about 1.4×) and shifted, and only two panes were painted (`paint-1.png`).
   - After the last white stripe the view moved again (`paint-2.png`).
   - Possibly two of my taps, or a fill tap plus the next one, were taken as a double tap. Or the app pans toward the next color's areas. The log has no line for either. Seen twice in one run, not repeated deliberately.
3. **The Line Eraser's drag Size reaches too far for a short line.**
   - It follows the guide, so it is not a bug. But a newcomer who drags along a short line inside a small shape loses neighbouring outlines and whole colors.
   - A preview, or a smaller default Size, would help.
4. **The table's "5" sits far from the middle of its area.**
   - It is placed low left, near the palette, in `final-template.png` and `paint-1.png`.
   - In the zoomed view, the palette nearly covered it.
5. **Blank screen right after relaunch** (`relaunch.png`).
   - The screen was empty for a moment before the painting appeared.
   - Probably just loading; only a note.

## Automation problems

- Maestro's `hideKeyboard` didn't close the software keyboard after typing the name; I tapped its return key.
- The `refineFill` tip came and went during my swipes, so I never saw it.
- What shows only while a finger is down (the Line Eraser's drag, Snap's live preview) can't be seen.
- I needed no curves beyond what Shapes › ellipse gave, so straight swipes were not a limit this time.

## Not tested

- Bend Line, Pen freehand, Smoothing, Cell Edge, Merge, Move Edge, Make Cell, Paint Brush, Eyedropper, Edit Paint, Looks, Move Number, Writing, Try Painting, Layers.
- Drag painting on the painting screen, pinch and two-finger pan, Pencil, multi-finger undo.
- Replay of the finished painting, and the gallery thumbnail after finishing (I relaunched straight into the painting and didn't go back to the gallery).
