# Refine Studio: brief

The Lamplit Table's round of October 20, 2026, on the visual pass Paul asked for before any code ("Beauty first", relayed by the front desk at about 20:40 UTC with his "Yes. Let's go ahead"). The design and plan: https://claude.ai/artifact/X2d1aeYEUYHHRxdMQZFXPE. Each seat sees its own view in `views/`; the mock-ups are drawn in SVG by Claude (no CI screenshot exists yet), rendered light and dark.

## The piece: Refine Studio, three moments

Paul, October 20, 2026: "I want that screen to feel as beautiful and as powerful as the main
painting screen itself. We want the tooling there to be sufficient for someone on that screen to
make a wonderful, amazing, beautiful paint by numbers template. It should be as fun as the main
experience, but more involved. There can be way more tools, if that's what's necessary. This will
be more of a hobbyist experience. Most users won't go there — those who do have implicitly
consented to a more involved experience with a learning curve. The vision is that it would be fun
to use, but also very powerful—a studio."

Today Refine (the screen after a new painting is made, before painting starts) has one row of
round buttons: Pen, Shapes, Erasers, Fill, Colors, Show, Text. Claude proposes the Studio, still
called Refine: the tools in four groups (Lines, Areas, Paints, Numbers), and only the picked
group's tools on screen at once, in two glass rows at the bottom (the groups above, the group's
tools below), the same on iPad and iPhone. A tool's options show only when the picked tool is
tapped again. On top: Done, a view switcher (Painting, Paper, Photo, X-ray), Undo and Redo, and
Try Painting (paint it for a minute, nothing saved). A small badge under it says how long the
painting will take, and turns into a warning when something would be hard to paint.

The mock-ups are drawn, not screenshots (a made-up husky template; glass and shadows
approximate). Four of them:

1. **At rest** (iPad). The painting in its paints, the Lines group open, the Pen picked.
   Arriving: the photo cross-fades into the painting (0.4 s), the glass rows rise into place and
   the top bar settles; nothing bounces. Tapping a group slides its tools in under it (0.25 s).
2. **A shape closes** (iPhone, at night, zoomed in on the meadow). The painter drew a loop with
   the Pen. As the finger lifts, the line settles into the template's ink (0.12 s); the new area
   floods with its color from where the ends met, a ripple of light crossing it (0.35 s); its
   number fades up with a small lift; two gold sparkles twinkle at the join for about a second
   (by Moon, the app's small stars); one soft haptic tap and a quieter version of the painting
   screen's fill chime. Reduce Motion: color and number at once, no sparkle; the tap stays.
   VoiceOver: "New area, paint 19."
3. **The area card** (iPad). A long press on any area, with any tool: a light tap; the area gets
   a breathing ring; every other area sharing its paint glows gold with one slow sweep of light
   (here the sky and the other eye: the generator gave the husky's eyes the sky's blue); a glass
   card grows out of the area (a soft spring, 0.3 s): its paint and number, then Only This Area
   (the area gets a paint of its own and the color picker opens on it; its number turns over to
   the new one like a page; the sky stays still), Join a Neighbour (tap a neighbour: the line
   between them thins and melts away, 0.3 s, as their colors run together), Keep as Detail, Move
   Number. The inset shows the eyes after Only This Area, in a paler blue of their own.
4. **Shade Bands** (iPad, the Areas group). Picked, then a drag across an area from its light
   side to its dark side: a dashed guide follows the finger, translucent bands preview behind it,
   a soft tick at each step. On lift the bands ink in one after another from light to dark, 60 ms
   apart, each with its number and a tiny tap; no sparkle (sparkles are kept for a shape closing).
   Here the sky becomes four blues, numbered 19, 1, 20 and 21, as a paint-by-numbers sky is
   shaded. A small glass bar above the tools sets how many bands.

Questions:
- Q1, a shape closing: `sparkle` (flood, ripple, the two gold sparkles and the tap, as described)
  or `quiet` (flood and the tap; no ripple, no sparkle).
- Q2, the area card: `card` (a glass card beside the area, pointing at it, as drawn) or `panel`
  (the same contents in a panel at the screen's edge; nothing covers the picture).
- Q3, how many bands: `bar` (the small 2 3 4 5 bar, set before the drag, as drawn) or `drag` (the
  drag's length sets it: another band each time the finger passes another step).
- Q4, how Refine opens: `painting` (the picture in its paints, as drawn) or `paper` (lines and
  numbers on white paper, like a fresh page).
