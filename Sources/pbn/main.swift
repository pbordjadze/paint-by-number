// Headless driver for the template pipeline: generate templates, render previews and
// report timings/metrics. Images are exchanged as PPM/PGM (on Apple platforms any ImageIO
// format is read too).
//
//   pbn generate <in.ppm> <outdir> [--colors N] [--detail F] [--smooth F] [--seed N] [--importance m.pgm]
//       [--paint-mix photo|kit|lively|rich|beauty]
//       [--auto [--length quick|relaxed|detailed] [--taste fidelity|finished] [--hints hints.json] [--candidates N]]
//       [--line-style classic|coloringBook --edges map.pgm [--lines drawing.pgm [--contour-weight W]]
//        [--eyes eyes.json] [--objects mask.pgm|polygons.json] [--writing writing.json]
//        [--line-edits edits.json] [--line-art key=value]...]
//       [--tuning key=value]... [--snapshots dir]
//       --snapshots writes making-of pictures, at most 1024 px on the long side:
//       working-image.ppm, structure.pgm (normalized coherent gradient), smoothed.ppm,
//       palette.ppm (palette-colored pixel labels), simplified.ppm (final region paints),
//       line-art.pgm (books with an edge map), vectorized.pgm (all smoothed boundaries).
//       --seed seeds the pipeline's stochastic steps and the paints' nicknames;
//       --paint-mix kit mixes the paints as a kit would (KitPaint), the regions unchanged, and
//       lively spreads kit paint's hues for a broader variety of colors (LivelyPaint), rich
//       turns them further and gives a face paints of its own (FacePaints), and beauty mixes
//       rich paint for a pretty painting over a faithful one (BeautyPaint);
//       --auto generates at the settings Auto suggests (stats.json gains `auto` and `analysis`;
//       --taste finished scores the finished painting, AutoTaste);
//       a coloring book splits the cells along the edge map's lines
//       (stats.json gains `lineArt`, with the drawing's density, open ends and the areas it
//       encloses, and selected.svg hatches the cells of the paint with the most of them, as the
//       canvas shows the selected color); eyes.json is an array of closed polygons of [x, y]
//       normalized to the photo, and the subjects (--objects) either the same or a mask image
//       whose shapes MaskContours traces; writing.json holds the lines of text found in the photo
//       the same way (a quadrilateral each), whose ink is traced from the photo and drawn
//       legibly; edits.json the lines a painter drew and erased and the shapes filled, in order,
//       as the app's Refine makes them: [{"kind": "draw", "points": [[x, y], ...]}, {"kind":
//       "erase", "radius": r, "points": [...]}, {"kind": "eraseLine", "radius": r, "points":
//       [...]}, {"kind": "fill", "points": [[x, y]]}] (a line drawn, the eraser's pass, a line
//       tapped away along its own path, the cell under a point made a detail area of the
//       photo's color there; radius a fraction of the photo's long side; a kind pbn doesn't
//       know is skipped with a warning; stats.json gains `detailRegions`); --line-art sets a
//       LineArtSettings field and --tuning a PipelineTuning factor by name
//   pbn glass <photo> <lines.json | suggest> --out <dir> [generate options]
//       a Stained Glass window (painting-company row 366; GlassWindow.leaded): the photo leaded
//       by lines.json's {"lines": [[[x, y], ...], ...]} (fractions of the photo's width and
//       height), each closed piece a region with the glass the photo suggests (GlassPalette);
//       `suggest` in place of lines.json leads it with the lead the photo suggests
//       (GlassLeadSuggestion), as the Lead screen starts. Writes window.pbnt, glass.json (pieces, glasses, offered, background pieces, valid and
//       validation), lit.ppm (every piece in its suggested glass, lead along every boundary) and
//       unlit.ppm (the window before glazing).
<<<<<<< HEAD
//   pbn cave [<photo> <subject-mask.pgm>] --out <dir> [--figure]
//       the Cave (painting-company row 371): a cave painting's plan (CavePlan.make) from the photo
//       and its subject's mask (white the subject; without them, CaveSample's horse), --figure
//       its stick figure. Writes cave.plan, cave.json (kind, size, areas, areas of each pigment,
//       the plan's bytes, seconds), areas.ppm (each area in its pigment, its lines in black) and
//       wall.ppm (four bays lit by a torch as the app lights them: the mouth, the painting
//       finished with a hand, half blown with its pigments, bare rock with its charcoal).
=======
//   pbn watercolor <photo | template.pbnt> --out <dir> [--seed N] [--spacing S] [--order paint|sweep]
//       [--frames t1,t2,…] [generate options]
//       a Watercolor painting (painting-company row 373; WatercolorSim): every area tapped once,
//       paint by paint (sweep: top left down, any paint), S seconds apart (0.12), and the sheet drawn as the app draws it
//       (Watercolor.swift's doc comment): painting.ppm dried, frame-<t>.ppm wet at each time,
//       watercolor.json (the tap log), and the steps' and the replay's timings printed.
//       With --making-of [--fps N]: the app's Making Of instead (WatercolorMakingOf), frame-NNNN.ppm
//       every 1/N second shown (15) until it settles and on through the app's ending,
//       making-of.csv, and its steps' cost printed;
//       tools/watercolor_making_of.py makes its contact sheet and film.
>>>>>>> origin/main
//   pbn drawing <photo.ppm> <outdir> [--palette crayons|pastels|earth|sea|garden] [--paints N]
//       [--seed N] [--detail F] [--smooth F] [--cleaned]
//       starts a painting from a drawing (GenerationSettings.drawing): the photo of a line
//       drawing on paper is cleaned (DrawingScan.clean: the sheet found and pulled square, the
//       paper flattened to white, the ink alone kept; --cleaned skips this, for a picture that
//       is one already) and written as cleaned.ppm, then generated as the app generates it
//       (the ink traced as the lines, every area bounded by them, the palette set's paints
//       laid so neighbours differ; --paints caps them, else the number of areas decides):
//       ink.pgm (the ink at the working size), template.pbnt, the previews generate writes and
//       stats.json (its `drawing` block: the settings, whether the sheet was pulled square and
//       its corners)
//   pbn edit <template.pbnt> <edits.json> --out <dir> [--photo <image>]
//       applies manual edits to a finished coloring-book template, in order, as the app's Refine
//       does (TemplateEditor): no edge map, no segmentation. edits.json: [{"kind": "draw",
//       "points": [[x, y], ...], "closed": false, "paints": [{"at": [x, y], "color": [L, a,
//       b]}]}, {"kind": "erase", "radius": r,
//       "points": [...]}, {"kind": "eraseLine", "points": [[x, y]], "reach": r}, {"kind": "fill",
//       "points": [[x, y]], "color": [L, a, b] | "paint": n}, {"kind": "paintArea", as "fill"},
//       {"kind": "split", as "draw"}, {"kind": "cellEdge", "points": [...], "closed": false},
//       {"kind": "merge", "points": [...]}, {"kind": "brush", "points": [...], "radius": r,
//       "color": [L, a, b] | "paint": n}, {"kind": "reshape", "points": [from, to], "reach": r,
//       "target": "ink" | "edge"}, {"kind": "moveLabel", "points": [from, to], "reach": r},
//       {"kind": "look", "points": [], "look": "moonlit", "strength": 1}, {"kind": "repaint",
//       "points": [], "from": [L, a, b], "color": [L, a, b], "family": true}], read as the app's
//       refinements.json keeps its edits (PaintCore's EditCoding: every edit has its "points", a
//       brush its "radius", a look its "strength"; "paint": n, a paint's number in place of a
//       "color", is pbn's own), all in canvas units (the
//       template's, origin top-left; unlike --line-edits, which is normalized to the photo): a
//       line drawn exactly as given and cutting the cell it closes (with "paints", nudged through
//       the junctions it crosses beside and each piece it cuts recolored; --photo reads those
//       paints from the photo for every draw without them, as the app does), the eraser's pass cutting the
//       ink at the edge of its reach (the cells it frees merging), a line tapped away from
//       junction to junction, the shape under a point made one detail area of a paint (the
//       color's, within a just-noticeable difference, else a new one), the area under a point
//       alone given that paint (Only This Area: a paint it leaves with no area leaves the
//       palette), a split dividing the
//       colors on either side of the line without drawing it, a cell edge dividing a cell along the
//       line without drawing it, both pieces keeping its paint, a merge joining the cells a path
//       crosses into the first (each next one that borders those joined; the boundaries between
//       them go, ink and all, and a paint left with no area leaves the palette), the Paint Brush (what
//       lies within the radius of the stroke takes the paint, the outline laid as a cell edge,
//       ink untouched, areas of that paint across an undrawn boundary joining), Bend Line and Move
//       Edge (the line nearest `from` within "reach", from junction to junction, bent so its
//       point there goes to `to`, its ends held, the areas on its sides following; "target"
//       "ink", Bend Line's, grabs drawn lines only, "edge", Move Edge's, the boundaries between
//       cells only), Move Number (the number nearest `from` within its radius and "reach" moved
//       to `to` in its own region, sized for the room there, clear of the region's other
//       numbers), Refine's Looks and Edit Paint (a look over every
//       paint, its lightness read from the template when the file gives none, or one paint
//       repainted with or without its family; later edits bring their colors through them, as
//       the app's trail does, but for an area's, a color of the template as it is then); a kind
//       pbn doesn't know is
//       skipped with a warning. Writes the edited template.pbnt, the same previews as generate
//       (raster.ppm, boundaries.ppm, painted.svg, template.svg, painted-outlined.svg) and
//       stats.json: the template's counts and validation, per edit what it did (a draw: how far
//       the ink strays from the line, `maxDeviation`, in the middle of the line, and how far an
//       end moved onto ink, `maxEndShift`; `unexpectedChanges`, 0: regions the edit changed that
//       it neither touched, merged nor sat beside) and how many regions are bit for bit as
//       they were (`identicalRegions`)
//   pbn refine <photo> <gestures.json> --out <dir> [--template t.pbnt | --blank | --edges map.pgm [--lines drawing.pgm]]
//       [--no-steps] [generate options]
//       replays Refine's gestures as the app makes them (RefineGestures: the Pen's smoothing and
//       its ends joining the lines they land near, the retired Color Splitter, the Cell Edge, Shapes (a line, rectangle, oval, hexagon, star or curve), the Eraser's reach on screen, the Merge, the Paint Brush, Bend Line and Move Edge, Move Number, the Line
//       Eraser's line from junction to junction, Fill with the photo's color there, the Bucket
//       (`bucket`: a paint by number, OKLab `color` or the picker's sRGB `rgb`, else the photo's
//       color there), Edit Paint (`repaint`: paint `paint` to `color` or `rgb`, `family`), Undo,
//       Redo) on the coloring book of the photo (generated as the app does, the coloring book at
//       its defaults unless --line-style says otherwise, --template, or --blank: Start From
//       Blank, the photo as one area), each edit laid as the app lays
//       it (a drawn line with the photo's colors, TemplateEditor.painted; EditTrail). gestures.json:
//       Sources/pbn/Refine.swift's RefineScript, points normalized to the picture. Writes
//       before.ppm, after.ppm and per gesture steps/NN-<tool>.ppm (the painting with the drawing in
//       ink at 2×) and steps/NN-<tool>-touches.ppm (its touches over it, in magenta), photo.ppm, before.pbnt, template.pbnt, edits.json (the
//       edits as refinements.json keeps them) and refine.json: per gesture the edit, what it did,
//       the toast Refine shows and, for a Merge, how many areas it lit while the finger was down
//       (`lit`); tools/refine_sheet.py lays them out in one picture. --no-steps
//       writes no step pictures (a long script's would fill the disk: 70 MB a gesture at the
//       largest canvas), and refine.json's `picture` and `touches` are empty
//   pbn practice painted|inked --out <dir>
//       writes the Tool Guide's practice picture (RefinePractice) for pbn refine: photo.ppm,
//       template.pbnt (its scene, for --template) and painting.ppm (as the page shows it)
//   pbn practice note --out <dir>
//       writes Writing's practice picture (RefinePracticeNote) for pbn generate --line-style book:
//       photo.ppm, edges.pgm (--edges), writing.json (--writing, the lines the app found) and
//       missed.json (the pencil line it missed)
//   pbn suggest <image> [--importance m.pgm] [--hints hints.json] [--length relaxed] [--taste finished] [--candidates 5]
//       [--out dir]
//       runs Auto at the draft size, prints the candidate table and writes decision.json (into
//       dir, else the current directory); with --out also the draft (draft.ppm), its working
//       image and every candidate's painted preview and region outlines (tools/auto_sheet.py)
//   pbn bench <in.ppm>... [--runs N] [--colors N] [--detail F] [--smooth F] [--edges map.pgm]
//       [--lines drawing.pgm]
//       also times a live preview, detail 1 on a large photo, the same with 150 colors and
//       Auto's suggestion (Relaxed, 5 candidates); with --edges and/or --lines (and generate's
//       other line-art options) also the coloring book at its defaults with the --line-art fields
//       on top (its line-art stages listed), the map resampled to each photo
//   pbn trace <flat.ppm> <outdir> [--smooth F] [--runs N]
//       vectorizes a flat-color image directly (each distinct color is a palette entry,
//       each 4-connected component a region), bypassing segmentation
//   pbn check <template.pbnt> [--min-label-radius R]
//       prints format and pipeline versions, validates a template's invariants, including
//       every label's room for its number (single-digit minimum R, default
//       LabelSizing.minimumRadius, a detail area's scaled down as LabelSizing.detailMinimumRadius
//       is; R ≤ 0 skips that check) and line data, whose style, edges per layer and interior
//       strokes (and how many are writing) it prints, and the detail areas
//   pbn names <template.pbnt> [--seed N] [--vocabulary N | --nickname-table file.tsv]
//       prints each palette color's nickname (seeded like the app's per-painting names; the
//       default seed is generate's), structured name and hex; the default vocabulary is
//       --vocabulary 2: identical stored OKLab, seed and palette order give identical nicknames
//       on every platform (canonical anchors and integer arithmetic, including the fallback).
//       --vocabulary 1 preserves the original platform's libm behavior: Linux names can differ
//       from Apple; old artworks with missing metadata keep 1. Unknown future versions use 2.
//       A proposed table uses the version 1 draw (RRGGBB<TAB>Name per line, no header; the frozen table's
//       single-space separator is also accepted)
//   pbn vocab check [<table.tsv> | --vocabulary N]
//       reports the vocabulary's mechanical style-guide and gamut problems; exits nonzero
//       if any fail. Without a table it checks the built-in vocabulary (default 2), including
//       its canonical anchors. Proposed tables are not installed or written into templates

//
// PBN_BANDS=<n> in the environment makes the pipeline split its work as a device with n bands does (twice its
// cores: an iPad Air's 16, a ten-core Mac's 20): a template must come out the same whatever the number, and the
// template hashes run under it to show that at the app's sizes (tools/book_hashes.py --bands).

import Foundation
import PaintCore

let args = CommandLine.arguments
guard args.count >= 2 else { fail("usage: pbn generate|drawing|glass|cave|edit|refine|practice|suggest|bench|trace|check|names|vocab ...") }
let options = parse(args.dropFirst(2))

func run(_ command: String, _ options: Options) throws {
    switch command {
    case "generate": try runGenerate(options)
    case "drawing": try runDrawing(options)
    case "glass": try runGlass(options)
<<<<<<< HEAD
    case "cave": try runCave(options)
=======
    case "watercolor": try runWatercolor(options)
>>>>>>> origin/main
    case "edit": try runEdit(options)
    case "refine": try runRefine(options)
    case "practice": try runPractice(options)
    case "suggest": try runSuggest(options)
    case "trace": try runTrace(options)
    case "check": try runCheck(options)
    case "names": try runNames(options)
    case "vocab": runVocabCheck(options)
    case "bench": try runBench(options)
    default:
        fail("unknown command \(command)")
    }
}

if let bands = ProcessInfo.processInfo.environment["PBN_BANDS"].flatMap({ Int($0) }) {
    try Parallel.withBandCount(bands) { try run(args[1], options) }
} else {
    try run(args[1], options)
}
