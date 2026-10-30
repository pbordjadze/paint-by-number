# The scene method: regions that follow the picture

`GenerationSettings.Method.scene` (painting-company row 188), beside the color method every
template has been made with so far. The color method segments the whole photo by color, the
importance map tilting detail toward the subject. The scene method lays the template out the way
a paint-by-number designer draws one: the subject's outline first, the background simplified into
a few calm shapes, the detail and the paints spent on the face and its features.

## What it reads: the scene map

`SceneMap` (`Model/SceneMap.swift`) is what the device knows of the photo beyond its pixels, at
256 px on the long side: the subjects' soft mask, an attention map, the faces' and animals' rects
and the subjects' features (eyes, noses, mouths, each with a radius). The app fills it from one
Vision pass (`SubjectVision`); off the device `tools/scene_standin.py` does, with ISNet for the
mask, spectral residual saliency, MediaPipe's face detector, landmarker and object detector
(cats and dogs, like Vision), and hand-checked overrides where a detector misses what Vision
finds (`Tests/EvalSet/overrides.json`). `pbn generate --method scene --scene scene.json` reads it.

A template made by the scene method keeps its scene map in the `SCEN` chunk (`Template.scene`),
so regeneration from the same photo and settings, on any device, reads the same scene and makes
the same bytes. The chunk is optional: every reader since 1.0 skips it.

## What it does (`Segmentation/SceneLayers.swift`, `Segmenter`)

1. **Sides.** The mask is resampled to the working size and snapped to the photo
   (`SceneLayers.snap`): pixels the mask is sure of keep its side; in the band between, a pixel
   joins the side whose nearby sure colours it is closer to, the mask's own leaning counting as
   much; islands under sixteen smallest areas flip. The silhouette then runs where the subject
   meets the background. A mask that covers under 1 % of the frame is none
   (`SceneMap.minimumSubjectShare`): the photo is all subject.
2. **Importance** is derived from the scene, in place of the app's map, at the app's own levels:
   the background as the app's map has it (0.25, or 0.2 + 0.4 × saliency where that is more),
   the subject at 0.7 + 0.2 × saliency, faces 1, animals 0.85, a feature 1 within its radius. Paints, the smallest area, band fusion and
   texture consolidation follow it as they do in the color method, so the subject keeps the
   detail it had. Without a subject the importance is the app's map of the same findings, and
   the method is the color method.
3. **Treatment.** How far the background is simplified, per pixel (`SceneLayers.treatment`):
   fully where it is flat or blurred, not at all on sharp structure (the density of coherent
   contours, `ImportanceMap.busyness`, times `SceneLayers.sharpness`, the gradient energy at a
   pixel against that at the coarse scale): a house behind the subject, an island on the
   horizon, an in-focus flower behind the butterfly the mask chose are drawn as the color
   method draws them; bokeh and sky are not.
4. **Smoothing.** The background is smoothed up to 1.3 times as widely as the color method
   smooths (by treatment), the subject as the color method does, a face 1.15 times (planes of
   skin, not patches), a feature 0.6 times (the filter's per-pixel domain stretch), and a barrier
   on the domain derivative stops the diffusion across the silhouette.
5. **Two kits.** From pixel labelling to texture consolidation, the subject's classes are offset
   by the palette's count and the palette repeated (`SegmentationParameters.sidePaints`): the two
   sides never share a region, band fusion and consolidation never join them, and a merge across
   the silhouette pays `sceneCrossPenalty` (0.15 OKLab), so only a speck with nothing of its
   colour on its own side crosses. The sides then fold into the regions (`RegionRuns.side`), and
   no later fuse of same-paint neighbours (the refit, the label-room pass) crosses either.
6. **A calm background.** Its smallest area is up to 1.6 × the importance-scaled one (by
   treatment); its outlines get a second mode filter with twice the boundary radius on treated
   pixels farther than that from the silhouette (`sceneCalmRadius`); narrow bands fuse at 1.2 ×
   the color method's tolerance, a band counting as narrow up to 1.5 × the width.

The color method is untouched: with `method == .color` every stage runs the code it ran, and
`tools/regression.py` holds its baselines (byte-identical templates on the corpus). The scene
method's templates have adjacent regions of one paint along the silhouette, which is what a
drawn silhouette is; `TestScenes.checkInvariants` allows that for the method.

## Measuring it

`tools/scene_eval.py run` generates `Tests/EvalSet` (32 photos: pets, faces, couples, landscapes,
flowers, food, buildings, and low light, busy scenes and small subjects) with both methods, from
the same stand-in scene, as coloring books from the set's edge maps, and lays each pair side by
side with the measures of its docstring: ΔE (whole, subject, background), the share of the
subject's strong edges a region boundary keeps, background regions per 1000 px², tiny regions,
outline smoothness, the smallest number's room, and time.

## Rounds

Each round: a change, the whole set, the measures, a fresh critic (a professional paint-by-number
designer who thinks most generated templates are mush, given only the side-by-side pictures and
the goal), its worst complaint fixed next. Times are ET.

| Round | Change | Means over the set (old → new): ΔE, subject ΔE, detail kept, regions, background regions/kpx, paints | Critic's worst complaint | Decision |
| --- | --- | --- | --- | --- |
| 1 (Oct 30, ~1 a.m. ET) | sides, importance 0.12/0.55/0.9, smoothing 2.2×, area 1.6×, fusion 1.6×, calm 2.5× | 0.0422→0.0509, 0.0701→0.0723, 0.55→0.53, 294→213, 0.12→0.04, 24→22 | it erases the subject or key objects (the island, the trains, the orbiter: a mask with specks made the whole photo background; the subject was smoothed more than the color method does) | fix the subject's parity and the no-subject case |
| 2 | subject at the app's levels (0.7, faces 1), smoothing relative to the color method's, fusion only with a subject | →0.0477, →0.0705, →0.56, →256, →0.05, →22 | (not sent) | structure must protect background objects |
| 3 | background structure raises importance; fusion 1.25× on bands only; features 0.5×; eye outlines for both methods; background lines attenuated 0.6× | →0.0447, →0.0679, →0.58, →232, →0.10, →23 | (not sent: a near-empty mask still counted as a subject, and the attenuation emptied templates) | subject share rule, importance-aware attenuation |
| 4–5 | 1 % subject share; no-subject photos take the app's own importance | →0.0445, →0.0705, →0.56, →295, →0.10, →23 | (not sent) | sides carried in the regions; sharpness |
| 6 | sharpness gates the structure term; sides survive the refit | →0.0453, →0.0709, →0.56, →285, →0.09, →23 | mixed, slightly worse: numbers float where lines were attenuated away; simplification deletes content (drifts, shoreline); petals and heads merge; muddy colours from fusion | drop the attenuation; soften the background; wrong-side specks cross |
| 7 | no attenuation; floor 0.2; smoothing 1.4×, fusion 1.2×, width 1.5×, calm 2×; cross penalty 0.15; islands 16× | →0.0429, →0.0703, →0.56, →319, →0.12, →23 | worse: faces and animal heads break into camouflage; busy sharp backgrounds busier than the color method (the structure term added detail) | treatment separated from importance; face planes; grain |
| 8 | treatment (structure × sharpness) scales the background treatments, importance stays near the app's levels; faces 1.3× planes, features 0.6×; grain 11 px; 32 photos | 0.0416→0.0428, 0.0668→0.0657, 0.56→0.55, 323→318, 0.11→0.09, 24→23 | mixed, leaning worse; would ship the color method: the key colours drain (barn red, aspen yellow, lupine violet, white surf), subject detail comes as crumbs, petals fuse; better: calmer backgrounds, eye shapes, the man's face in kodim12 | background importance at exactly the app's levels; grain on the subject's lightness only; smoothing 1.3× |
| 9 | background importance at the app's levels; grain on the subject's lightness only; smoothing 1.3× | 0.0416→0.0421, 0.0668→0.0655, 0.56→0.57, 323→325, 0.11→0.10, 24→23 | mixed; would ship the color method: faces wash out (the 1.3× planes), subject colours read muddier (the palettes' saturated paints are the same: parrots' top paints identical old and new, so it is the labelling, not the palette), thin structures dissolve, more crumbs in fur | the grain step goes (no visible gain, more crumbs); face planes 1.15× |
| 10 (Oct 30, 2:40 a.m. ET) | no grain; face planes 1.15× | 0.0416→0.0426, 0.0668→0.0670, 0.56→0.56, 323→329, 0.11→0.10, 24→24 | mixed, leaning worse; would ship the color method: the barn's shed, pond reflections and waterline drain into the trees (a real failure); fur, cake and crowds still shatter into confetti, by more regions than the color method; whites go grey (the eagle's head, the tomb's marble); a calmed background takes an object with it (the hummingbird's leaves, kodim16's island); better: kodim12's face, the fox's silhouette, the macaw's eye, calm skies and grass, the tabby's forehead | stop (below) |

**Stopped after round 10** (overruling the critic, with the reason the brief asks for). The worst
complaint is real, not a quibble, but it is one end of a trade the loop has walked both ways:
rounds 7 and 8 moved the one knob the complaints hang on, how far the treated background is
simplified, and the critic's worst complaint flipped from "busier backgrounds" to "colours
drain", and back; round 10 sits between, with the barn's sharp pond and shed still over-treated
and the hummingbird's bokeh still not calm enough. The second complaint, fur and crowds as
confetti, is the color method's own (the subject is smoothed as the color method smooths it, by
design, since every round that smoothed it more lost the eyes and the faces); the scene method
inherits it and adds a few fragments along the silhouette, where the barrier halves a pixel's
neighbourhood. What the method wins (faces that were grey blobs, silhouettes without halos, eye
rings, one calm sky) it wins on every round since 8, and what it loses it loses on sharp,
object-filled backgrounds. Knobs will not close that gap: the next gains need a different idea,
a texture-aware consolidation of fur and foliage into strokes (region-level, after
simplification), or paints budgeted by side, each a design of its own. So the method ships off by
default, behind Settings › Scene Method in the SideStore build, for a judgement by eye on the
blind pairs (`tools/blind_page.py`), and the loop's harness, set and critic brief stay for the
next idea.
