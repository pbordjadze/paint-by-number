# Refine exploratory test: draw a face

**Verdict**: Partly. In Refine I got the face I planned, quickly, except that the hair and lips are angular polygons rather than curves and the nose came out amber. On the painting screen I painted 3 of 8 areas before time ran out.

**What I meant to draw**: a front-facing oval face in peach on a white background, with two blue eyes, a brown nose, a red upper lip and a pink lower lip, and dark-brown hair over the top of the head.

## What I got
- `shots/final-refine`: on white, a tall peach oval head, two blue oval eyes and an amber/orange oval nose. The mouth is an angular red upper lip (two peaks) over an angular pink lower lip. The hair is a dark-brown polygonal cap that comes down both sides of the head to the hairline.
- New Painting preview after Done: "7 colors · 8 areas · ~5 min". That matches the drawing (background, face, hair, 2 eyes, nose, 2 lips).
- `shots/final-template`: the numbered template. The areas and numbers are correct, but the hair shows two "2" labels.
- `shots/paint-mid`, `shots/final-painting`: the background, face and hair are painted. The eyes (3), upper lip (4), lower lip (5) and nose (6) are still unpainted (6 is hatched as selected). Progress is about 37%.

## The steps
| Step | Tries | Stuck | What finally worked | Expected instead |
|---|---|---|---|---|
| Find a blank canvas | 1 | 0 | + > closed the "No Photo at Hand" tip > sample The Great Wave > Refine > the **Generated / Blank** switch above the canvas > Blank (one plain beige area) | as expected, and obvious |
| Head outline | 1 | 0 | Shapes > the oval in the bottom bar > one corner-to-corner swipe | as expected |
| Eyes, nose | 1 | 0 | 3 more oval swipes | as expected |
| Mouth (upper and lower lip) | 1 | 0 | Pen with Snap on: 4 strokes for the top of the upper lip (cupid's bow), 1 for the lip line, 3 for the lower lip, all meeting at the corners. Both lips came out as closed areas. | wanted curved lips; a straight swipe can't give them |
| Hair | 1 | 0 | Pen: 8 straight segments for the outer outline and 4 for the hairline, ends on the head oval. Then **Line Eraser**, one tap on the head's top arc, which removed only the arc between the two crossings, so the hair became one area. | the hair is polygonal; I didn't get to try Bend Line to curve it |
| Add paints, colour | 2 tries for the first New Paint | ~1 min | The palette has one paint and a colour wheel ("New Paint"). My first tap on the wheel by point did nothing; a tap by id opened a popover picker (Grid / Spectrum / Sliders). Picking a grid cell adds and selects a new paint; a tap outside closes the picker; the Bucket fills the area. 6 paints added, every fill right first time. | as expected after the first try |
| Nose colour | 1 | 0 | got amber, not brown: I picked the wrong grid cell (my mistake) and didn't fix it with Edit Paint | |
| Leave Refine | 1 | 0 | Done (check mark) > back to the preview with the new picture | the title is still "The Great Wave", which is confusing for a picture I drew myself |
| Paint | 3 of 8 areas | out of time | the background, face and hair, by tap and by `canvas-area-7` | after painting, the canvas zoomed or moved on its own, so my coordinate taps for the eyes, lips and nose missed |

## Where I got stuck
1. **Painting screen: the view moved under me** (`shots/paint-mid`, `shots/final-painting`). After I painted the background and face, the canvas was suddenly zoomed in. After I painted the hair it moved again, and my next five taps (eyes, lips, nose) landed off target. I didn't have time to tell whether this was an automatic zoom when a colour is finished or a double tap read from two of my quick taps (the background tap, then the swatch tap, then the face tap). Unconfirmed.
2. **The first tap on New Paint (colour wheel) did nothing.** The tap at (943,1322) was inside its bounds ([926,1304]–[962,1340]); the second try, by id, opened the picker. Seen once.
3. **No curves** for the hair and lips. With straight swipes the hair and lips are polygons. Bend Line probably exists for this, but I didn't try it.

## What I wanted and couldn't do
- Curved hair and lip outlines (straight swipes only, and Bend Line not tried).
- To name the painting after my drawing before painting; it kept "The Great Wave". I didn't look for a rename.
- To finish painting the eyes, lips and nose (out of time).

## App bugs (reproduced)
- None reproduced: I had no time to repeat anything.

## Suspicions
- **The hair area shows two number labels ("2" twice)** on the painting screen (`shots/final-template`), though the preview says 8 areas and VoiceOver lists a single hair area (`canvas-area-7`). Maybe the area got two labels because of its shape (a crown plus side bands, after the Line Eraser joined two areas). Seen once.
- **The canvas zoomed or moved by itself while painting** (see stuck #1). Seen twice in one session, cause unconfirmed.
- **The first tap on the New Paint colour wheel was ignored** (stuck #2). Seen once.
- **A user-drawn painting keeps the sample's title** "The Great Wave" (it is shown on the painting screen too). This may be expected, but it's confusing.

## What worked well
- The Blank start is easy to find.
- The Shapes oval works well.
- Pen strokes join each other with Snap on.
- The Line Eraser removed exactly the segment between two crossings, which a newcomer would hope for.
- Each Bucket pour filled exactly the closed area.
- The preview's area count matched the drawing.
- When I finished a colour (background, face), its swatch left the palette.

## Automation problems
- A straight-line `swipe` can't draw curves, so the hair and lips are polygons (this also belongs under what I wanted).
- No pinch or two-finger pan, so I couldn't zoom back out on the painting screen once it had zoomed in.
- Quick consecutive taps may be read as a double tap (the possible cause of the zoom).

## Not tested
Bend Line, Cell Edge, Merge, Move Edge, Make Cell, Paint Brush, Eyedropper, Edit Paint, Looks, Move Number, Writing, Try Painting, Layers, Undo and Redo in Refine, the Tool Guide (?) help (I didn't need it), Smoothing, two- and three-finger gestures, the Pencil, drag painting, finishing the painting (moon rise), saving across a relaunch.
