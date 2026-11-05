# Refine: drawing from scratch

Where Refine stands for a newcomer who draws their own picture on Blank and paints it, as the
exploratory QA of November 3, 2026 measured it (painting-company row 205), and how to measure it
again.

## The QA

Eight sessions of `qa-explore` (agent mode, debug build), each a newcomer told only the goal:
"draw something of your own from scratch in Refine and make it look the way you want". The brief
is `ci/qa/explore.md` with its Goals and report replaced, on the branch `claude/refine-scratch-qa`
(rebase it on `main` before a run; never merge it: `ci/qa/` is generated). Reports:
`git fetch origin refs/qa-runs/<id>:refs/qa-runs/<id>`, then `session/report.md`,
`session/shots/final-*.png` and `agent/transcript.md` (the swipes, when a report stops early).

| Round | Subject, device | Run | Got what they wanted |
| --- | --- | --- | --- |
| 0 (before) | cat, iPad | 41577110703 | yes (Shapes only) |
| 0 | house and tree, iPhone | 41579909695 | no: the roof never closed |
| 0 | face, iPad | 41584230981 | no: the mouth and hair never closed |
| 0 | sailboat, iPhone | 41588232599 | partly: nothing closed until lines crossed |
| 1 (after 4e2f1ba) | house and tree, iPhone | 41618590832 | yes, painted to 100%; the trunk took three tries |
| 1 | face, iPad | 41627468839 | yes, every part its own area |
| 1 | sailboat, iPhone | 41632352641 | yes, painted to 100%; one line declined three times |
| 1 (after 51e1868) | cat, iPad | 41658370278 | yes, ears and tail by Pen, every shape closed first try |
| 2 (November 5, row 235) | lighthouse, iPad | 42045770277 | yes, painted to 100%; the horizon stopped short of the edge |
| 2 | potted flower, iPhone | 42045777195 | mostly: the stem between flower and pot never closed |
| 2 (after 9ef2111) | hot-air balloon, iPhone | 42090190226 | yes, painted to 100%; the ropes closed the sky between them |
| 2 | snowman and house, iPad | 42090194956 | yes, painted to 100%; one Merge took the sky into the hat |
| 3 (after 3cb1c12) | owl on a branch, iPad | 42099016133 | yes, painted to 100%; a Merge begun a point off the shape, on the sky, took the head |
| 3 | red car, iPhone | 42099020758 | yes, painted to 100%; each wheel left an unseen sliver to paint |

Verdict of the round 1 critic: mostly yes. Round 0's: partly.

## What was fixed

Every cause of a shape that looked closed and wasn't, replayed off the device from the testers'
own swipes (`tools/refine_from_scratch.py --qa`; each leaks on the main of that morning and closes
now):

- an end heading at a line joins it within a fingertip, not half of one (`PenAssist.joined`);
- a tail past a crossing that lands on another line is kept (a roof's base along a wall's top);
- the picture's edge is a line an end heading at it meets (`SnapLines.frame`);
- a line meets every stroke a chain it touches runs to, not only those in its box (editor 3);
- a line passing just beside a free tip heading at it bends through it (`PenAssist.throughTips`);
- two lines drawn from one shape to another close the strip between them, though they never
  meet (editor 4: a line meets the strokes of its regions that touch their outlines; November 5);
- an end heading straight at the picture's edge meets it from two fingertips, not one
  (`PenAssist.joined`; November 5);
- a closed figure's sliver beside the ink it overlaps (a wheel's circle poking a point into the
  car's body) stays with the shape beside it instead of being an area nobody sees (editor 5;
  November 5);
- a drawn line's segments are at most 16 units (`RefineGestures.longestSegment`), so a big
  Blank's validation doesn't run out of work and decline a plain line.

`tools/refine_from_scratch.py` (simulated fingers whose ends miss by 0–4, 3–9 or 7–15 points,
drawing a cat, a house and a face): a casual finger closed 98 of 120 shapes and 4 of 18 whole
pictures before, 112 and 13 after; a careful one 120 and 18 both times.

## What's next

In the critic's order, each smallest change, none started:

1. A pour that runs out through a gap shows nowhere where the gap is: flash the outline of the
   area the pour spread into, or mark the gap.
2. New Paint (the palette's color wheel) ignored its first taps in 6 of 8 sessions of November 3
   and in both of November 5. Several new colors picked in a row now wait in the palette until
   poured (November 5). The first taps: on CI (runs 42066725760 to 42085773960, November 5) a
   fresh simulator's first launch showed no picker within 40 s of the tap while the main thread
   stalled, again and again for about two minutes, in UIKit loading the system picker's images;
   every later launch opened it within 3 s, with a tip shown or not, from scratch or on a photo,
   and a picker made in advance as Refine opened changed nothing. It looks like the cold
   simulator's, not Refine's: a device's first New Paint is the check still owed.
3. The Blank switch sits under Refine's first tip, and a drawing keeps the sample photo's title.
   From Scratch on the New Painting screen (painting-company row 231) now opens Refine on a
   blank page with no photo behind it, no Start From and a name of its own ("Drawing, <date>");
   the switch on a photo's Refine is as it was.
4. Merge keeps the paint of the cell the drag starts in, so a drag begun a point off the shape, on
   the sky, takes the shape into the sky (round 3's owl, its log saying so; round 2's snowman
   most likely the same). Undo puts it back, and the cells glow while the finger is down; a
   person on a device is the check still owed.
5. The template validator charges a long segment's whole box (`GeometryValidator`'s bucket
   stage); drawn lines are densified, but an edge made otherwise across a big Blank (a Bend Line
   of a long line) could still meet the limit.

Maestro draws only straight swipes, so the sessions never drew a freehand curve: the simulated
fingers above stand in for that, and a person on a device is the check still owed.
