# Recolor in Refine (Colors)

Backlog row 38. Paul, October 18, 2026: "Rick thinks it would be really fun if you could change the
colors from what they are in the original picture. Have to be in the refine tab. Probably filters?
But also even like, more granular control? Not sure how to implement this exactly. Maybe a report
with some options." Paul picked option A of the report (14:26): "Yeah do this": looks and paints
behind one Colors button.

Today Refine (the screen after a new painting is made, before painting starts) has a row of round
buttons along the bottom: Pen, Color Splitter, Shapes, Eraser, Smart Eraser, Fill | Photo,
Painting, Text. Every color comes from the photo.

Claude proposes a new Colors button after Fill (a fan of swatches). Picking it shows the painting
in its paints (as the Color Splitter does) and a glass panel above the buttons, in place of the
hint line:

- **Looks**: a row of round chips, each showing four of the painting's paints in that look:
  Photo (the photo's own colors), Moonlit, Pastel, Golden Hour, Sepia, and three painters'
  palettes, Starry Night (Van Gogh), Water Lilies (Monet) and Great Wave (Hokusai). A tap lays the
  look on every paint at once; a Strength slider under the row softens it.
- **Paints**: the painting's numbered swatches. A tap on one opens the system color picker beside
  it, with "Similar colors too" (on by default): the paints of about the same hue move with it,
  since one bird is often six paints and one swatch alone leaves it patchy. A tap on an area of
  the painting picks its swatch. Two paints made the same color become one, and the numbers after
  close up.

Shapes, lines and numbers never change. Undo and Redo work as for every other tool. Nothing here
regenerates the painting.

The mock-ups (iPad, made from CI's screenshot of Refine; the panel and the new button are drawn,
shadows and the system picker approximate): "a look", the parrots in Starry Night with the
Strength slider; "a paint", the red macaw turned blue with its family, the picker open over the
swatch.

Questions:
- Q1, the looks: `row` (always in the panel, as drawn) or `menu` (a Looks button in the panel that
  opens the list; the panel shows only the paints until then).
- Q2, strength: `slider` (shown once a look is chosen) or `fixed` (each look at full strength;
  Photo or Undo goes back).
- Q3, a paint's family: `family` ("Similar colors too" on by default) or `one` (off by default:
  only the paint tapped changes until it is turned on).
- Q4, the painters' looks' names: `paintings` (Starry Night, Water Lilies, Great Wave) or `plain`
  (Night Sky, Lily Pond, Big Wave).
