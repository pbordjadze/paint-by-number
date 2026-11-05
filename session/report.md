# Refine from scratch: owl on a branch (iPad Pro 13", debug build)

**Verdict**: Yes. I got the picture I planned, drawn from geometric shapes, and painted it to 100%. The few rough moments were with the color wheel and with Merge's precision.

**What I meant to draw**: a brown round-bodied owl with a round head, two white eyes with black pupils, an orange triangle beak, two brown ear tufts and darker brown wings, sitting on a brown branch, under a pale yellow moon in a dark navy night sky.

## What I got
- **In Refine** (`shots/final-refine`): exactly the plan, in a deliberately geometric style.
  - Circles for the head, eyes, pupils and moon; an oval for the body.
  - Straight-line triangles for the two tufts and the beak.
  - Each wing is a two-segment angled line across the side of the body (a "<" shape, not a curve).
  - A rectangle for the branch.
  - 14 areas in 8 paints: white, navy, pale yellow, brown, dark brown, red-brown, black and orange. The app named them Printer Paper, Midnight Harbor, Lemon Sorbet, Cocoa Powder, Ancho Chile, Rooibos Tea, Event Horizon and Sweet Potato.
- **The preview** read "8 colors · 14 areas · ~5 min" and the title defaulted to "Drawing, November 5".
- **The painting screen before painting** (`shots/final-template`): clean line art, one number per area, with the sky hatched for paint 2.
- **After painting** (`shots/final-painting`): every area painted, 100%, "Finished! Every region is painted."
- **After quitting through Home and relaunching** (`pressKey: Home`, then `stopApp` + `launchApp`): the app reopened the painting at 100% with every area intact (`shots/relaunch`). `crashes.txt` is empty.
- **Judged against my plan**: every element is there in the colors I chose. The owl is a stylised, snowman-like stack of circles with straight-edged wings. That was my own choice of tools, not a limit: Shapes also offers Curve, and there is Bend Line, but I did not try either.

## The steps
| Step | Tries | Stuck for | What finally worked | What I expected instead |
|---|---|---|---|---|
| Find a blank page | 1 (plus 1 accidental detour) | ~1 min | New Painting › the top-right pen icon ("From Scratch", `from-scratch`) opens Refine on a white page | A labelled "Blank page" or "Draw your own" option. The icon has no text, and I found it from its accessibility label. |
| Pick the Oval shape | 2 | <1 min | Shapes › Oval in the bottom bar | My first tap used pixels instead of points (my mistake) and drew a diagonal line. Undo removed it cleanly. |
| Moon, head, body, eyes, pupils | 1 each | 0 | Oval, dragged from one corner of its box to the other | As expected |
| Branch | 1 | 0 | Rectangle | As expected |
| Beak, ear tufts | 1 per segment | 0 | Line tool, 3 segments per triangle, each starting where the last ended (Snap on). The shapes closed. | As expected |
| Wings | 1 per segment | 0 | Two straight segments per wing, from the body's outline to an inner point and back to the outline | A curve: I chose straight lines and didn't try Curve or Bend Line |
| Make each shape an area | 1 (not needed) | <1 min | Nothing: every closed shape was already its own cell. Make Cell on the moon raised the change count but changed nothing visible. | The tip "Make a Shape Its Own… tap inside it with Make Cell" made me think I had to |
| Add a new color | 3 taps on the first color | ~3 min | The color wheel at the end of the Bucket palette. After taps 1 and 2 no picker showed within ~8 s. After tap 3 it showed, late. After that it opened on every tap (5/5). | The picker opening on the first tap, as it did in the Tool Guide's demo |
| Color all areas | 1 per area | 0 | Bucket: pick a color in the picker, tap outside to close it, tap the area. The new color "waits with +", then becomes a numbered paint. | As expected |
| Join the sliver where the head and body circles overlap | 3 | ~2 min | Merge: a drag from the sliver into the head, kept short of the beak | Try 1 also swallowed the beak (orange left the palette). Try 2 started 1 pt off, on the sky, and merged the whole head into the sky. Undo fixed both. |
| Go to the painting screen | 1 | 0 | Refine › Done › Start Painting | As expected |
| Paint | 14 areas; ~3 tap misses | ~2 min | Tapping by point at first, then the `canvas-area-<n>` ids and Hint | After the first fill the top bar faded and the view shifted, so taps planned on the old layout missed, and one ended as a double-tap zoom. Fit to Screen restored the view. |

## Where I got stuck
1. **The color wheel didn't open the first two times** (`shots/plan-5`, `shots/wheel-retry`: no picker; `shots/picker-navy`: it did open later). On a blank page the palette has only paint 1, white, so coloring anything first needs a new paint. I tapped the wheel (`refine-palette-new`), first by id and then by point. Nothing appeared within the ~8 s each tap waits, in both the screenshot and `inspect_screen`. I opened the Tool Guide (?) for help: its Bucket page confirmed the wheel was the right control, and the wheel in its demo opened at once. That part of the guide helped. Back in Refine, the third tap's picker was not in the flow's own screenshot but was there a few seconds later. After that, the wheel opened on all 5 later taps. A newcomer would think the wheel does nothing.
2. **Merge was unforgiving about where the drag starts and ends** (`shots/merge-lens`, `shots/merge-lens2`). I wanted to join a ~7 pt sliver where the head and body circles overlap. A drag that ended on the beak's tip also merged the beak, and the orange paint left the palette. A drag that started about 1 pt off the sliver merged the whole head into the sky, wiping its outline and turning it navy. Undo fixed both, and the third drag worked. While the finger is down, Merge lights the cells it will join, but I could not see that through Maestro. A person might catch the mistake before lifting.
3. **Taps on the painting screen missed after the first fill**. After the first fill, the debug build's top bar fades and the canvas shifted. My moon tap, planned on the old layout, painted nothing, and the view ended up zoomed in on the moon. I had to tap the progress ring to bring back More, then use Fit to Screen. That menu also brought up the simulator's software keyboard (an automation problem, below). After that, painting by the `canvas-area` ids and Hint went smoothly.

## What I wanted and couldn't do
- Have a new color picker open on the first tap of the color wheel (see bug 1).
- A curved wing outline drawn with my finger: Maestro swipes are straight. I used angled two-segment lines instead, and didn't try the Curve shape or Bend Line.
- See Merge's preview of what it will join before lifting the finger (shows only while the finger is down).

## App bugs (reproduced)
1. **The Refine palette's color wheel ("New Paint") sometimes doesn't open the picker, or opens it seconds late.**
   - Steps: From Scratch › Bucket › tap the color wheel at the right end of the palette.
   - Expected: the "New Paint" picker opens, as it does at once in the Tool Guide's Bucket demo.
   - Observed: after taps 1 and 2 no picker appeared within ~8 s (`shots/plan-5`, `shots/wheel-retry`, and `inspect_screen` listed no picker). After tap 3 it appeared a few seconds late (`shots/picker-navy`). The 5 later taps all opened it normally.
   - How often: 2 of 8 taps failed outright, both in the first minute of using it, and a third was slow.
   - Not ruled out: a slow first presentation of the system picker in the simulator. The log shows nothing at those times: its last line before the delay was 20:25:57, and the taps were at about 20:27.

## Suspicions
- **Make Cell on an already-closed shape counts as a change but does nothing visible.** The "Make a Shape Its Own" tip suggests it is needed after every closed shape, but each closed shape was already its own cell. The tip may mislead newcomers into extra steps, or the tool may not have done what it was meant to. Seen once.
- **A tiny stray "4" at the head-body junction on the painting screen** (`shots/final-template`, centre, where the circles touch). The area counts were right (paint 4 had 4 areas: head, body and two tufts). This looks like a second, tiny number label for the head or body, placed where I merged the sliver. Seen once; not investigated further.
- **The From Scratch button has no visible label.** It is a pen icon next to the photo icon. The accessibility label says "From Scratch", but nothing on screen does. For a newcomer this is the main entry to drawing their own picture.

## Automation problems
- The first "No Photo at Hand" tip had already closed by itself when I tapped its Close button, so the tap landed on the Wheat Field sample and opened its preview. The log shows the tip's "turn over" before my tap. Timing, not an app bug.
- The painting screen's More menu brought up the software keyboard with nothing to type in (simulator).
- Maestro swipes are straight lines: I drew no hand-drawn curves (the wings are angled lines instead).
- Maestro's two quick taps on the canvas (after the layout shifted) turned into a double-tap zoom.
- Screenshots arrive after a gesture ends, so Merge's preview and fill animations were not visible.

## Not tested
- Pen freehand drawing, Bend Line, the Curve/Hexagon/Star shapes, Smoothing, Color from Photo, Eraser/Line Eraser, Cell Edge, Move Edge, Move Number, Edit Paint, Looks, Writing, Try Painting and Layers.
- Pinch zoom and two-finger pan, and Refine's multi-finger undo/redo; Apple Pencil.
- Drag painting on the painting screen; Replay (the "Watch It Again" tip appeared); Share; Give Feedback.
- Leaving Refine with Cancel, and editing the drawing again after painting.
