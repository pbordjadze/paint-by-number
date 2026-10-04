import Foundation
import PaintCore

func runGenerate(_ options: Options) throws {
    guard options.positional.count == 2 else { fail("usage: pbn generate <in.ppm> <outdir> [options]") }
    let image = loadImage(options.positional[0])
    let outDir = URL(fileURLWithPath: options.positional[1])
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    let importance = loadImportance(options.importance)
    let lineArtInput = loadLineArt(options)
    let decision = options.auto ? suggest(image, importance: importance, options: options) : nil
    // Auto's decision carries the line art and tuning asked for.
    let generator = TemplateGenerator(settings: decision?.0.settings ?? options.settings)
    let output: TemplateGenerator.Output
    do {
        output = try generator.generate(from: image, importance: importance, lineArt: lineArtInput, cancel: .none)
    } catch { fail("generation failed: \(error)") }
    let t = output.template
    let size = generator.settings.workingSize(sourceWidth: image.width, sourceHeight: image.height)
    let working = Resample.area(image, width: size.width, height: size.height)
    var m = metrics(output, working: working, settings: generator.settings)
    m.lineArt = LineArtReport(output, settings: generator.settings.lineArt, input: lineArtInput)
    m.tuning = generator.settings.tuning.isDefault ? nil : generator.settings.tuning
    if let (decision, ms) = decision {
        m.auto = AutoStats(decision, milliseconds: ms)
        m.analysis = decision.analysis
    }
    let encoder = jsonEncoder()
    try encoder.encode(m).write(to: outDir.appendingPathComponent("stats.json"))
    try t.encoded().write(to: outDir.appendingPathComponent("template.pbnt"))
    try Netpbm.encodePPM(paintedRaster(t)).write(to: outDir.appendingPathComponent("raster.ppm"))
    try Netpbm.encodePPM(working).write(to: outDir.appendingPathComponent("working.ppm"))
    try Netpbm.encodePPM(boundaryRaster(t)).write(to: outDir.appendingPathComponent("boundaries.ppm"))
    if t.lineArt != nil { try Netpbm.encodePPM(areasRaster(t)).write(to: outDir.appendingPathComponent("areas.ppm")) }
    try writeSVGs(t, selected: m.lineArt?.selectedColor, to: outDir)
    print(String(data: try encoder.encode(m), encoding: .utf8)!)
}

func runSuggest(_ options: Options) throws {
    guard options.positional.count == 1 else {
        fail("usage: pbn suggest <image> [--importance m.pgm] [--hints h.json] [--length L] [--candidates N] [--out dir]")
    }
    let path = options.positional[0]
    let image = loadImage(path)
    let importance = loadImportance(options.importance)
    let firstDraft = Lap()
    let (decision, ms) = suggest(image, importance: importance, options: options) { _ in firstDraft.mark() }
    let draft = AutoSettings.draftImage(from: image)
    let draftSize = decision.settings.workingSize(sourceWidth: draft.width, sourceHeight: draft.height)
    print("\(path) — draft \(draft.width)×\(draft.height) (working \(draftSize.width)×\(draftSize.height)), "
        + "\(decision.preference.rawValue), \(decision.candidates.count) candidates: "
        + String(format: "%.0f ms (first draft %.0f ms)", ms, firstDraft.milliseconds))
    print(candidateTable(decision))
    let outDir = URL(fileURLWithPath: options.out ?? ".")
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    try jsonEncoder().encode(decision).write(to: outDir.appendingPathComponent("decision.json"))
    if options.out != nil {
        // Previews for tools/auto_sheet.py: the pipeline is deterministic, so regenerating
        // each candidate on the draft reproduces exactly what was scored.
        try Netpbm.encodePPM(draft).write(to: outDir.appendingPathComponent("draft.ppm"))
        try Netpbm.encodePPM(Resample.area(draft, width: draftSize.width, height: draftSize.height))
            .write(to: outDir.appendingPathComponent("working.ppm"))
        for (i, candidate) in decision.candidates.enumerated() {
            let t: Template
            do {
                t = try TemplateGenerator(settings: candidate.settings).generate(from: draft, importance: importance, cancel: .none).template
            } catch { fail("generation failed: \(error)") }
            try Netpbm.encodePPM(paintedRaster(t)).write(to: outDir.appendingPathComponent("candidate-\(i).ppm"))
            try Netpbm.encodePPM(boundaryRaster(t)).write(to: outDir.appendingPathComponent("candidate-\(i)-boundaries.ppm"))
        }
    }
}

func runTrace(_ options: Options) throws {
    guard options.positional.count == 2 else { fail("usage: pbn trace <flat.ppm> <outdir> [--smooth F]") }
    let image = loadImage(options.positional[0])
    let outDir = URL(fileURLWithPath: options.positional[1])
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    let segmentation = flatSegmentation(image)
    var result: (template: Template, stats: VectorStats)?
    var best: [String: Double] = [:]
    for _ in 0..<max(1, options.runs) {
        let clock = StageClock()
        do {
            result = try Vectorizer.vectorizeWithStats(segmentation, settings: options.settings, cancel: .none, clock: clock)
        } catch { fail("vectorize failed: \(error)") }
        for timing in clock.timings { best[timing.name] = min(best[timing.name] ?? .infinity, timing.seconds * 1000) }
    }
    let t = result!.template, stats = result!.stats
    try t.encoded().write(to: outDir.appendingPathComponent("template.pbnt"))
    try Netpbm.encodePPM(image).write(to: outDir.appendingPathComponent("working.ppm"))
    try Netpbm.encodePPM(paintedRaster(t)).write(to: outDir.appendingPathComponent("raster.ppm"))
    try writeSVGs(t, to: outDir)
    let report = t.validate()
    let summary: [String: String] = [
        "regions": "\(t.regions.count)", "edges": "\(t.edges.count)", "points": "\(t.points.count)",
        "triangles": "\(t.mesh.indices.count / 3)", "labels": "\(t.labels.count)", "valid": "\(report.isValid)",
        "report": report.description, "fallbackEdges": "\(stats.fallbackEdges)",
        "labelRoomEdges": "\(stats.labelRoomEdges)", "labelRoomRegions": "\(stats.labelRoomRegions)",
        "labelRoomUnmet": "\(stats.labelRoomUnmet)",
        "timings": best.sorted { $0.key < $1.key }.map { String(format: "%@=%.1f", $0.key, $0.value) }.joined(separator: " "),
    ]
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let json = try encoder.encode(summary)
    try json.write(to: outDir.appendingPathComponent("trace.json"))
    print(String(data: json, encoding: .utf8)!)
}

func runCheck(_ options: Options) throws {
    guard let path = options.positional.first, let data = FileManager.default.contents(atPath: path) else {
        fail("usage: pbn check <template.pbnt> [--min-label-radius R]")
    }
    do {
        let template = try Template(encoded: data)
        // Decoding succeeded, so the 8-byte header is there.
        let format = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self) }
        print("format \(format), pipeline \(template.pipelineVersion)")
        if let lines = template.lineArt {
            let names = ["outline", "detail", "texture", "color"]
            let counts = names.indices.map { l in lines.edgeLayers.filter { Int($0) == l }.count }
            let style = lines.style == .coloringBook ? "coloring book" : "layered"
            print("\(style) lines: edges " + zip(names, counts).map { "\($0) \($1)" }.joined(separator: ", ")
                + "; \(lines.strokes.count) interior strokes (\(lines.strokePoints.count) points)")
        }
        let report = template.validate(minLabelRadius: options.minLabelRadius > 0 ? options.minLabelRadius : nil)
        print(report.isValid ? "valid" : "INVALID", report)
    } catch { fail("cannot decode: \(error)") }
}

func runNames(_ options: Options) throws {
    guard let path = options.positional.first, let data = FileManager.default.contents(atPath: path) else {
        fail("usage: pbn names <template.pbnt> [--seed N]")
    }
    do {
        let template = try Template(encoded: data)
        let nicknames = ColorNickname.assign(template.palette, seed: options.settings.seed)
        for (index, color) in template.palette.enumerated() {
            print(String(format: "%3d  %@  ·  %@  ·  #%@", index + 1, nicknames[index].padding(toLength: 18, withPad: " ", startingAt: 0),
                         color.colorName.english, color.hexDigits.uppercased()))
        }
    } catch { fail("cannot decode: \(error)") }
}

/// Auto's decision for `image` (reduced to the draft size inside), and how long it took.
func suggest(_ image: RGBAImage, importance: Grid<Float>?, options: Options,
             firstDraft: (@Sendable (TemplateGenerator.Output) -> Void)? = nil) -> (AutoDecision, Double) {
    let start = ContinuousClock.now
    do {
        let decision = try AutoSettings.choose(
            image: image, importance: importance, hints: loadHints(options.hints), preference: options.length,
            maxCandidates: options.candidates, lineArt: options.settings.lineArt, tuning: options.settings.tuning,
            cancel: .none, firstDraft: firstDraft)
        return (decision, milliseconds(since: start))
    } catch { fail("suggestion failed: \(error)") }
}

/// The candidate table `pbn suggest` prints: every score term, the winner starred.
func candidateTable(_ decision: AutoDecision) -> String {
    let a = decision.analysis
    let curve = zip(AutoSettings.paletteCurveKs, a.paletteCurve).map { "\($0)→\($1)" }.joined(separator: " ")
    var lines = [
        "analysis: source \(a.sourceWidth)×\(a.sourceHeight)  palette curve (k→mean dE) \(curve)",
        String(format: "  chromatic %.3f  chroma spread %.3f  structure %.3f  texture %.3f  smooth %.3f  noise %.4f",
               a.chromaticFraction, a.chromaSpread, a.structureDensity, a.textureFraction, a.smoothFraction, a.noise),
        String(format: "  subject %.3f  importance mean %.3f  entropy %.3f  faces %.3f  animals %.3f",
               a.subjectCoverage, a.meanImportance, a.importanceEntropy, a.faceCoverage, a.animalCoverage)
            + (a.labels.isEmpty ? "" : "  labels " + a.labels.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }
                .joined(separator: ", ")),
        "    #  colors  detail  smooth  regions  est min  fidelity     p95  rings  tiny   room  band pen    total",
    ]
    for (i, c) in decision.candidates.enumerated() {
        let mark = i == decision.winner ? "*" : " "
        let head = String(format: "  %@ %d  %6d  %6.2f  %6.2f", mark, i, c.settings.colorCount, Double(c.settings.detail),
                          Double(c.settings.smoothness))
        guard let s = c.score else {
            lines.append(head + "  (not run)")
            continue
        }
        lines.append(head + String(
            format: "  %7d  %7.0f  %8.4f  %6.4f  %5d  %4d  %5.2f  %8.4f  %7.4f", s.regions, s.estimatedSeconds / 60,
            Double(s.fidelity), Double(s.fidelityP95), s.bandRings, s.tinyRegions, Double(s.minLabelRoom),
            Double(s.bandPenalty), Double(s.total)))
    }
    lines.append("  " + AutoSettings.scoreFormula)
    lines.append("  bands (\(decision.preference.rawValue)): colors \(decision.preference.colorBand), detail "
        + "\(decision.preference.detailBand), smoothness \(AutoSettings.smoothnessBand), minutes "
        + "\(Int(decision.preference.timeBand.lowerBound / 60))...\(Int(decision.preference.timeBand.upperBound / 60))")
    return lines.joined(separator: "\n")
}

/// Flat-color image → segmentation: one palette entry per distinct color.
func flatSegmentation(_ image: RGBAImage) -> Segmentation {
    var index: [UInt32: UInt32] = [:]
    var palette: [PaletteColor] = []
    var classes = [UInt32](repeating: 0, count: image.width * image.height)
    for i in 0..<classes.count {
        let key = UInt32(image.pixels[i * 4]) << 16 | UInt32(image.pixels[i * 4 + 1]) << 8 | UInt32(image.pixels[i * 4 + 2])
        if let c = index[key] {
            classes[i] = c
        } else {
            let c = UInt32(palette.count)
            index[key] = c
            let rgb = SIMD3(Float(image.pixels[i * 4]), Float(image.pixels[i * 4 + 1]), Float(image.pixels[i * 4 + 2])) / 255
            palette.append(PaletteColor(oklab: ColorScience.encodedToOKLab(rgb, space: .sRGB), rgb: rgb))
            classes[i] = c
        }
    }
    let cc = ConnectedComponents.label(Grid(width: image.width, height: image.height, storage: classes))
    return Segmentation(labels: cc.labels, regionColor: cc.classOf, palette: palette, colorSpace: .sRGB)
}
