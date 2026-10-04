# Advanced settings presets

Settings › Advanced › Presets sets Line Art, Line Appearance and Pipeline at once
(`AdvancedPreset`: a line style at its own defaults, the pipeline untuned and the lines drawn
as designed). Coloring Book is the app's defaults, so it is also Reset All; Layered and
Classic are the other two styles. Any other mix of settings travels as text: Copy Settings
writes a JSON object (`AdvancedReport.Snapshot`), and Paste Settings reads one back: an object
with some of the three groups, `lineArt`, `tuning` and `lineAppearance`, each naming only the
fields it changes (the others keep their defaults), a group left out staying as the painter
has it, values beyond a setting's range clamped.

## Coloring Book

The look of a coloring-book app (Happy Color and the like): a drawing in solid ink that stays
over the paint from the first fill to the last, the areas inside an outline told apart by their
numbers rather than by lines, no specks. The Coloring Book line style
(`LineArtSettings.Style.coloringBook`, `docs/coloring-book.md`) is what draws that way: every
line it keeps is drawn alike, in full ink, the paint boundaries inside an outline never, and a
selected color's cells are hatched, not outlined. Its defaults (`LineArtSettings()`) are the
settings the owner's own books used, measured on ten pictures (the freight train, the
Milkmaid, the turtle, the fox, the lighthouse, the parrots, the arch, the duck, the Paris
street and a portrait) with HED maps at the app's size and Suggested settings at Relaxed:

| Setting | Value | Why |
| --- | --- | --- |
| Line Style | Coloring Book | the drawing alone is drawn, over the paint; no color edges, no selected outline |
| Lines From | 60 % | what is drawn, read off the drawing laid over the contours. 50 % draws about a tenth more lines, 70 % a sixth fewer; 60 % keeps the structure (the fox's ears and legs, the Milkmaid's sleeves) and drops the brushwork. A book has no texture lines, so Texture From is hidden |
| Outlines From | 60 % | read off the contour map (HED) alone: an object's boundary is an outline wherever HED found it, the drawing's fur and creases are detail whatever their ink (`docs/coloring-book.md`, Detectors). Never below Lines From: the thresholds stay ordered |
| Shortest Line | 36 px | specks never become lines or cells |
| Gap Closing | 16 px | open strokes reach further for a line, paint boundary or the frame, so cells close |
| Line Smoothing | 70 % | flowing curves |
| Same Paint Across a Line | Join Across Detail | silhouettes split same-paint cells; fur, creases and strands are drawn inside their cells instead of walling slivers (10–20 % fewer cells, two to three times the strokes inside cells on the fox, the Milkmaid, the Arrieta and the turtle) |
| Keep Color Edges | On | the paints inside an outline stay separate areas (numbered, never drawn) |
| Outline Eyes | On | eyes as closed outlines with an iris |
| Outline Subjects | On | the subjects' silhouettes (Vision's foreground mask) close the drawing where the detectors left it open |
| Flatter paint | 1.5× smoothing, texture flattening and smallest area, built into the style (`SegmentationParameters.coloringBookFlattening`) | fewer small color cells inside the outlines, which are told apart by numbers only: a tenth to a third fewer cells on the ten pictures before Suggested settings re-balance the painting's length, and a calmer book after (the fox at 1× came out at 24 colors and detail 0.79 with numbered specks all over its body, at 1.5× at 32 colors and detail 0.59 with cells a painter can find). The Pipeline factors multiply it, so 1× there is the book's own paint |
| Line Appearance | default | a book reads only Line Weight (1×) |

The layered style keeps the research's defaults (Outlines From 85 %, Detail 50 %, Texture
30 %, 18 px, 9 px, 50 %), and choosing a style in Settings › Advanced carries each style's
defaults along (`LineArtSettings.changing(to:)`): a number the painter changed stays.

A preset is recognized as long as the settings generate the same template and draw the
same lines (`GenerationKey`): a setting the style ignores can sit anywhere.

Layered line art has the related per-layer *When Painted* slider of Line Appearance: how much
of a layer's lines stays once both sides are painted (0 % by default, dissolving every line
between painted cells as classic templates do). It gives a layered painting kept outlines
without the book's other rules.
