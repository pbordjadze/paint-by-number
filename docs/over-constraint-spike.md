# Over-constraint spike: where the template is held to the photo

A research spike (painting-company row 191, October 30, 2026 ET), on the branch
`claude/over-constraint-spike`. Nothing in the app changed. The question was where the pipeline's rules
and measures hold a template to the photo at the expense of a satisfying painting. The tool is
`tools/loosen_eval.py`, whose header is its manual. It reuses `tools/scene_eval.py`'s setup: the coloring
book from `Tests/EvalSet`'s maps, 24 colours, detail 0.5, and the app's importance map from the stand-in
scene.

## The constraints, and what each costs

| Constraint | Protects | Costing the result? |
| --- | --- | --- |
| Determinism, saved-data format, `pipelineVersion` | paintings reopen and regenerate | no |
| Every number legible (`LabelSizing.minimumRadius` 2.12, `minRadius` 2.7–3.5) | a region you can find and read | no: it is a floor, not the reason regions are small |
| Paint count: Auto picks the knee of the ΔE palette curve (`AutoSettings.marginalGain`), Relaxed 8–40 | fidelity per paint | mildly: 24 is a kit's count, but it is chosen by ΔE alone |
| Paints are the regions' mean colours (`PaletteRefiner` refit), and the paints that fusing frees are re-spent on the worst-fitting regions | ΔE | **yes**: averaging pulls paints toward grey. Over 12 photos the painting keeps 98 % of the photo's mean chroma, 95 % of its top-decile chroma and 96 % of its lightness spread. Kits mix brighter than the photo |
| Importance scales the smallest area (`areaScale`, ×2^(3·(0.5−importance))): the subject at 0.75 keeps small regions | faces and eyes | **yes, on pets and fur**: the subject's texture comes out as confetti |
| Coloring-book ink: HED lines at 0.6, drawn over the paint to the last fill | shapes read; the method itself | sometimes: creases across a face (kodim04) stay in the finished picture |
| Auto's score: ΔE, p95 ΔE, rings, crumbs, a paint price, a time band | a faithful painting of the asked length | **yes, structurally**: the only taste term is ΔE. The time band (Relaxed 20–50 min) and `detailPerImportance` raise detail whenever a map protects less, so Auto would undo any calming change |
| The measures we judge by (`scene_eval.py`: ΔE, detail kept, regions) | comparability | **yes**: every round of row 188 was steered by fidelity |
| `minPaletteDistance` (0.04 at 24) | paints you can tell apart | no |

## Looser variants (12 photos; regions and colours are means)

| Variant | What it changes | Regions | Colours | ΔE | Visible? |
| --- | --- | --- | --- | --- | --- |
| today | | 328 | 23.8 | 0.040 | |
| kitpaint | the same regions; paints with up to 1.3× chroma (fading out on greys and already-vivid paints) and 1.15× lightness spread | 328 | 23.8 | (paints moved on purpose) | **yes, at a glance** |
| loosesubject | `--tuning subjectEmphasis=0.5 minimumCellSize=2 textureFlattening=2.5 smoothing=1.5` | 243 | 23.5 | 0.042 | moderately: calmer fur and hat, but it loses small objects (the barn's shed) |
| loosekit | loosesubject + kitpaint | 243 | 23.5 | | yes |
| paints12 | `--colors 12` | 309 | 12.0 | 0.044 | yes, posterized, with dark blotches; regions fall only 6 % (the lines and the smallest area make the cells) |
| calmback | background importance 0 | 285 | 22.3 | 0.042 | slightly, and it drops objects (the barn's shed and windows), as the scene method did |
| bold | `minimumCellSize=3 smoothing=1.8 textureFlattening=2` everywhere | 239 | 22.8 | 0.042 | moderately: blobby |
| flat | `--smooth 0.9 textureFlattening=2` | 305 | 23.6 | 0.041 | barely |
| inkbold / noink | the drawing at 2.5× width / no ink in the finished picture | 328 | 23.8 | | inkbold: comic-like, and it shows the mask's ragged outlines; noink: cleaner faces, closer to a finished kit |
| kit | 14 colours, cells 2.5×, smoothing 1.5, calm background, kitpaint | 209 | 13.8 | 0.049 | yes, and it loses objects and goes muddy |

To reproduce: `tools/loosen_eval.py run --out DIR --only kodim04,sailor-and-girl,tabby-cat,red-fox,parrots,oxbow-bend,hibiscus,barn,german-shepherd,kodim13,lighthouse,school-children`,
then `grid --out DIR` for one picture per photo, and `blind --out DIR PAGE.html` for the
blind page (its key is written beside it).
