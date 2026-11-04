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
- a drawn line's segments are at most 16 units (`RefineGestures.longestSegment`), so a big
  Blank's validation doesn't run out of work and decline a plain line.

`tools/refine_from_scratch.py` (simulated fingers whose ends miss by 0–4, 3–9 or 7–15 points,
drawing a cat, a house and a face): a casual finger closed 98 of 120 shapes and 4 of 18 whole
pictures before, 112 and 13 after; a careful one 120 and 18 both times.

## What's next

In the critic's order, each smallest change, none started:

1. A pour that runs out through a gap shows nowhere where the gap is: flash the outline of the
   area the pour spread into, or mark the gap.
2. New Paint (the palette's color wheel) ignored its first tap in 6 of 8 sessions; and several
   new colors picked in a row keep only the last. Device-confirm the first, then keep each new
   paint until undone or Refine closes.
3. The Blank switch sits under Refine's first tip, and a drawing keeps the sample photo's title.
   From Scratch on the New Painting screen (painting-company row 231) now opens Refine on a
   blank page with no photo behind it, no Start From and a name of its own ("Drawing, <date>");
   the switch on a photo's Refine is as it was.
4. The template validator charges a long segment's whole box (`GeometryValidator`'s bucket
   stage); drawn lines are densified, but an edge made otherwise across a big Blank (a Bend Line
   of a long line) could still meet the limit.

Maestro draws only straight swipes, so the sessions never drew a freehand curve: the simulated
fingers above stand in for that, and a person on a device is the check still owed.
