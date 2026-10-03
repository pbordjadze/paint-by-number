# Advanced settings presets

Settings › Advanced › Presets sets Line Art, Line Appearance and Pipeline at once
(`AdvancedPreset`, the single source of each preset's values). Any other mix of settings
travels as text: Copy Settings writes a JSON object (`AdvancedReport.Snapshot`), and Paste
Settings reads one back: an object with some of the three groups, `lineArt`, `tuning` and
`lineAppearance`, each naming only the fields it changes (the others keep their defaults), a
group left out staying as the painter has it, values beyond a setting's range clamped.

## Coloring Book

The look of a coloring-book app (Happy Color and the like): closed cells bounded by solid
lines, no lines dangling inside a cell, the areas inside an outline divided only by their
paints, and the drawing kept over the paint once a cell is filled.

What each setting does for that, measured on ten pictures (the freight train, the Milkmaid,
the turtle, the fox, the lighthouse, the parrots, the arch, the duck, the Paris street and a
portrait) with HED maps at the app's size and Suggested settings at Relaxed:

| Setting | Value | Why |
| --- | --- | --- |
| Line Style | Layered | lines follow the drawing, not every paint boundary |
| Outlines, Detail and Texture From | 60 % each | one class of line: every drawn edge is an outline (busy areas demote to Detail, drawn almost as strong). No faint texture lines, so no small texture cells. 50 % draws about a tenth more lines, 70 % a sixth fewer; 60 % keeps the structure (the fox's ears and legs, the Milkmaid's sleeves) and drops the brushwork |
| Shortest Line | 36 px | specks never become cells |
| Gap Closing | 16 px | open strokes reach further for a line, paint boundary or the frame, so cells close |
| Line Smoothing | 70 % | flowing curves |
| Same Paint Across a Line | Always Split | every line bounds a cell; nothing is drawn inside one. Lines drawn inside cells went from 5–71 per picture at the defaults to none (the pipeline also drops the 2–5 unit slivers trimming used to leave, pipeline version 4) |
| Keep Color Edges | On | the paints inside an outline stay separate areas (faint color edges, no drawn line) |
| Outline Eyes | On | eyes as closed outlines with an iris |
| Smoothing, Texture Flattening, Smallest Area | 1.5× | flatter paint, fewer small color cells (a fifth to a quarter fewer areas) |
| Line Appearance | Outlines 100 % kept when painted, Detail 85 %, Texture 70 %, Color Edges 0 % | the drawing stays over the painting; the paint divisions inside a cell dissolve as they are painted. Color edges draw at 35 % in the full view so every cell reads as closed before painting |

Lines kept when painted is the per-layer *When Painted* slider of Line Appearance; the
default (0 %) dissolves every line between painted cells, as classic templates do.
