# Advanced settings presets

Settings › Advanced › Presets sets Line Art, Line Appearance and Pipeline at once
(`AdvancedPreset`, the single source of each preset's values). Any other mix of settings
travels as text: Copy Settings writes a JSON object (`AdvancedReport.Snapshot`), and Paste
Settings reads one back: an object with some of the three groups, `lineArt`, `tuning` and
`lineAppearance`, each naming only the fields it changes (the others keep their defaults), a
group left out staying as the painter has it, values beyond a setting's range clamped.

## Coloring Book

The look of a coloring-book app (Happy Color and the like): a drawing in solid ink that stays
over the paint from the first fill to the last, the areas inside an outline told apart by their
numbers rather than by lines, no specks. The Coloring Book line style
(`LineArtSettings.Style.coloringBook`, `docs/coloring-book.md`) is what draws that way: every
line it keeps is drawn alike, in full ink, the paint boundaries inside an outline never, and a
selected color's cells are hatched, not outlined. The preset puts the style at the settings the
owner's own books used (the style's own defaults are the layered ones).

What each setting does for that, measured on ten pictures (the freight train, the Milkmaid,
the turtle, the fox, the lighthouse, the parrots, the arch, the duck, the Paris street and a
portrait) with HED maps at the app's size and Suggested settings at Relaxed:

| Setting | Value | Why |
| --- | --- | --- |
| Line Style | Coloring Book | the drawing alone is drawn, over the paint; no color edges, no selected outline |
| Lines From, Detail From | 60 % each | one class of line: every drawn edge is an outline (busy areas demote to Detail, drawn alike in a book). 50 % draws about a tenth more lines, 70 % a sixth fewer; 60 % keeps the structure (the fox's ears and legs, the Milkmaid's sleeves) and drops the brushwork. A book has no texture lines, so Texture From is hidden |
| Shortest Line | 36 px | specks never become lines or cells |
| Gap Closing | 16 px | open strokes reach further for a line, paint boundary or the frame, so cells close |
| Line Smoothing | 70 % | flowing curves |
| Same Paint Across a Line | default | a book has no texture lines to join across, so every line splits same-paint cells |
| Keep Color Edges | On | the paints inside an outline stay separate areas (numbered, never drawn) |
| Outline Eyes | On | eyes as closed outlines with an iris |
| Smoothing, Texture Flattening, Smallest Area | 1.5× | flatter paint, fewer small color cells (a fifth to a quarter fewer areas) |
| Line Appearance | default | a book reads only Line Weight (1×) |

The preset is recognized as long as the settings generate the same template and draw the
same lines (`GenerationKey`): a setting the style ignores can sit anywhere.

Layered line art has the related per-layer *When Painted* slider of Line Appearance: how much
of a layer's lines stays once both sides are painted (0 % by default, dissolving every line
between painted cells as classic templates do). It gives a layered painting kept outlines
without the book's other rules.
