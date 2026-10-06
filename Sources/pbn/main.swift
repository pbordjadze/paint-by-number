// Headless driver for the template pipeline: generate templates, render previews and
// report timings/metrics. Images are exchanged as PPM/PGM (on Apple platforms any ImageIO
// format is read too).
//
//   pbn generate <in.ppm> <outdir> [--colors N] [--detail F] [--smooth F] [--seed N] [--importance m.pgm]
//       [--auto [--length quick|relaxed|detailed] [--hints hints.json] [--candidates N]]
//       [--line-style classic|layered|coloringBook --edges map.pgm [--lines drawing.pgm [--contour-weight W]]
//        [--eyes eyes.json] [--objects mask.pgm|polygons.json] [--writing writing.json] [--line-art key=value]...]
//       [--tuning key=value]...
//       --seed seeds the pipeline's stochastic steps and the paints' nicknames;
//       --auto generates at the settings Auto suggests (stats.json gains `auto` and `analysis`);
//       layered and coloring-book line art split the cells along the edge map's lines
//       (stats.json gains `lineArt`, with the drawing's density, open ends and the areas it
//       encloses, and selected.svg hatches the cells of the paint with the most of them, as the
//       canvas shows the selected color); eyes.json is an array of closed polygons of [x, y]
//       normalized to the photo, and the subjects (--objects) either the same or a mask image
//       whose shapes MaskContours traces; writing.json holds the lines of text found in the photo
//       the same way (a quadrilateral each), whose ink is traced from the photo and drawn
//       legibly; --line-art sets a LineArtSettings field and --tuning a PipelineTuning factor by
//       name
//   pbn suggest <image> [--importance m.pgm] [--hints hints.json] [--length relaxed] [--candidates 5]
//       [--out dir]
//       runs Auto at the draft size, prints the candidate table and writes decision.json (into
//       dir, else the current directory); with --out also the draft (draft.ppm), its working
//       image and every candidate's painted preview and region outlines (tools/auto_sheet.py)
//   pbn bench <in.ppm>... [--runs N] [--colors N] [--detail F] [--smooth F] [--edges map.pgm]
//       [--lines drawing.pgm]
//       also times a live preview, detail 1 on a large photo, the same with 150 colors and
//       Auto's suggestion (Relaxed, 5 candidates); with --edges and/or --lines (and generate's
//       other line-art options) also layered and coloring-book line art, each style at its own
//       defaults with the --line-art fields on top (the layered stages listed), the map
//       resampled to each photo
//   pbn trace <flat.ppm> <outdir> [--smooth F] [--runs N]
//       vectorizes a flat-color image directly (each distinct color is a palette entry,
//       each 4-connected component a region), bypassing segmentation
//   pbn check <template.pbnt> [--min-label-radius R]
//       prints format and pipeline versions, validates a template's invariants, including
//       every label's room for its number (single-digit minimum R, default
//       LabelSizing.minimumRadius; R ≤ 0 skips that check) and line data, whose style, edges
//       per layer and interior strokes it prints
//   pbn names <template.pbnt> [--seed N]
//       prints each palette color's nickname (seeded like the app's per-painting names; the
//       default seed is generate's), structured name and hex

let args = CommandLine.arguments
guard args.count >= 2 else { fail("usage: pbn generate|suggest|bench|trace|check|names ...") }
let options = parse(args.dropFirst(2))

switch args[1] {
case "generate": try runGenerate(options)
case "suggest": try runSuggest(options)
case "trace": try runTrace(options)
case "check": try runCheck(options)
case "names": try runNames(options)
case "bench": try runBench(options)
default:
    fail("unknown command \(args[1])")
}
