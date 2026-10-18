# Refine's Color Splitter: what was decided

The Lamplit Table's look at the Color Splitter as built (October 18, 2026), before it merges.
Paul, October 18: "Take the 'increase' and 'add detail' brushes out of the app entirely. Replace
with a new brush to separate a color cell WITHOUT a line ... So line pen, and then a color splitter
pen" (he confirmed the echo with "Yes"); then, of Settings › Detail Brushes, later Text
Corrections: "take away that setting completely, and just focus on refine UX", and of the Text
tool: "Stays always on".

As built at 27ef7f8 (CI green): a scissors button right after the Pen; picking it shows the
Painting beneath the drawing; the stroke shows dashed while the finger is down; it divides an
area from line to line with no line, each side in the photo's color, one side a shade apart where
the photo is one color; "That area couldn't be split there." when it divides nothing. The three
detail brushes and the Settings switch are gone; Text is always in the row. Six seats, low-effort
Opus subagents, blind, each from its own view of CI's iPad screenshots (`views/`, described in
`prompts/<seat>.md`); every reply is in `replies/`.

| Seat | Verdict | Ask |
| --- | --- | --- |
| The Astrologer | ship | none |
| Rikyū | ship | none: "One new button takes the place of three removed" |
| The Child at Bedtime | ship | none |
| The Hedge Witch | change | "Let the split follow the finger's own wobble, not a ruler-straight seam; it should look cut by hand like the soft cloud edges beside it." |
| Madeleine, the Bible School Teacher | ship | none: the failure line "explains without telling anyone off" |
| Originality | (abstains by charter) | none; no veto |

**Decided**: ship as built, 4 to 1, no veto.

**The Hedge Witch's ask** is already how the tool works: the split's boundary is the finger's own
path, smoothed as the Pen's is (`RefineGestures.splitter`), nothing straightened. Her view showed
a ruler-straight seam because the UI test that took the screenshot drags in a straight line. Her
finding stands as a caution for the screenshots: a demo of the splitter should draw a hand's line.
Told to Paul with the merge.

**Claude's calls in building it**: the scissors symbol and the name Color Splitter (Paul's words,
"color splitter pen"); the switch to Painting on picking it (a split shows nowhere else); the
dashed trace (a line that won't be drawn); the shade rule (1.5 just-noticeable differences toward
the photo, stepping out twice more where a neighbour has that paint or the number has no room).
