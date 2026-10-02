import Foundation
import PaintCore
#if canImport(ImageIO)
import CoreGraphics
import ImageIO
#endif

// Headless driver for the template pipeline: generate templates, render previews and
// report timings/metrics. Images are exchanged as PPM so no codecs are needed.
//
//   pbn generate <in.ppm> <outdir> [--colors N] [--detail F] [--smooth F] [--importance m.pgm]
//       [--auto [--length quick|relaxed|detailed] [--hints hints.json] [--candidates N]]
//       [--line-style classic|layered --edges map.pgm [--eyes eyes.json] [--line-art key=value]...]
//       [--tuning key=value]...
//       --auto generates at the settings Auto suggests (stats.json gains `auto` and `analysis`);
//       layered line art splits the cells along the edge map's lines (stats.json gains
//       `lineArt`); eyes.json is an array of closed polygons of [x, y] normalized to the photo;
//       --line-art sets a LineArtSettings field and --tuning a PipelineTuning factor by name
//   pbn suggest <image> [--importance m.pgm] [--hints hints.json] [--length relaxed] [--candidates 5]
//       [--out dir]
//       runs Auto at the draft size, prints the candidate table and writes decision.json (into
//       dir, else the current directory); with --out also the draft (draft.ppm), its working
//       image and every candidate's painted preview and region outlines (tools/auto_sheet.py)
//   pbn bench <in.ppm>... [--runs N] [--colors N] [--detail F] [--smooth F] [--edges map.pgm]
//       also times a live preview, detail 1 on a large photo, the same with 150 colors and
//       Auto's suggestion (Relaxed, 5 candidates); with --edges also layered line art (its
//       stages listed), the map resampled to each photo
//   pbn trace <flat.ppm> <outdir> [--smooth F] [--runs N]
//       vectorizes a flat-color image directly (each distinct color is a palette entry,
//       each 4-connected component a region), bypassing segmentation
//   pbn check <template.pbnt> [--min-label-radius R]
//       prints format and pipeline versions, validates a template's invariants, including
//       every label's room for its number (single-digit minimum R, default
//       LabelSizing.minimumRadius; R ≤ 0 skips that check) and layered line data, whose
//       edges per layer and interior strokes it counts
//   pbn names <template.pbnt> [--seed N]
//       prints each palette color's nickname (seeded like the app's per-painting names; the
//       default seed is generate's), structured name and hex

struct Options {
    var positional: [String] = []
    var settings = GenerationSettings()
    var importance: String?
    var runs = 3
    var minLabelRadius = LabelSizing.minimumRadius
    var auto = false
    var length = PaintingLength.relaxed
    var hints: String?
    var candidates = 5
    var out: String?
    var edges: String?
    var eyes: String?
}

/// `--line-art` and `--tuning` fields by name.
enum Fields {
    static var lineArtFloats: [String: WritableKeyPath<LineArtSettings, Float>] {
        ["outlineThreshold": \.outlineThreshold, "detailThreshold": \.detailThreshold, "textureThreshold": \.textureThreshold,
         "minimumStrokeLength": \.minimumStrokeLength, "gapBridging": \.gapBridging, "lineSmoothing": \.lineSmoothing]
    }
    static var lineArtBools: [String: WritableKeyPath<LineArtSettings, Bool>] {
        ["keepColorEdges": \.keepColorEdges, "outlineEyes": \.outlineEyes]
    }
    static var tuning: [String: WritableKeyPath<PipelineTuning, Float>] {
        ["smoothing": \.smoothing, "textureFlattening": \.textureFlattening, "minimumCellSize": \.minimumCellSize,
         "subjectEmphasis": \.subjectEmphasis, "accentColors": \.accentColors, "colorfulness": \.colorfulness]
    }
}

func keyValue(_ flag: String, _ argument: String?) -> (String, String) {
    guard let argument, let eq = argument.firstIndex(of: "=") else { fail("\(flag): key=value, not \(argument ?? "nothing")") }
    return (String(argument[..<eq]), String(argument[argument.index(after: eq)...]))
}

func setLineArt(_ s: inout LineArtSettings, _ argument: String?) {
    let (key, value) = keyValue("--line-art", argument)
    if let path = Fields.lineArtFloats[key] {
        guard let v = Float(value) else { fail("--line-art \(key): a number, not \(value)") }
        s[keyPath: path] = v
    } else if let path = Fields.lineArtBools[key] {
        guard let v = Bool(value) else { fail("--line-art \(key): true or false, not \(value)") }
        s[keyPath: path] = v
    } else if key == "style" {
        guard let v = LineArtSettings.Style(rawValue: value) else { fail("--line-art style: classic or layered, not \(value)") }
        s.style = v
    } else if key == "samePaint" {
        guard let v = LineArtSettings.SamePaint(rawValue: value) else {
            fail("--line-art samePaint: " + LineArtSettings.SamePaint.allCases.map(\.rawValue).joined(separator: ", ") + ", not \(value)")
        }
        s.samePaint = v
    } else {
        let keys = (Array(Fields.lineArtFloats.keys) + Array(Fields.lineArtBools.keys) + ["style", "samePaint"]).sorted()
        fail("--line-art: unknown field \(key) (known: \(keys.joined(separator: ", ")))")
    }
}

func setTuning(_ t: inout PipelineTuning, _ argument: String?) {
    let (key, value) = keyValue("--tuning", argument)
    guard let path = Fields.tuning[key] else {
        fail("--tuning: unknown factor \(key) (known: \(Fields.tuning.keys.sorted().joined(separator: ", ")))")
    }
    guard let v = Float(value) else { fail("--tuning \(key): a number, not \(value)") }
    t[keyPath: path] = v
}

func parse(_ args: ArraySlice<String>) -> Options {
    var o = Options()
    var it = args.makeIterator()
    while let a = it.next() {
        switch a {
        case "--colors": o.settings.colorCount = Int(it.next() ?? "") ?? o.settings.colorCount
        case "--detail": o.settings.detail = Float(it.next() ?? "") ?? o.settings.detail
        case "--smooth": o.settings.smoothness = Float(it.next() ?? "") ?? o.settings.smoothness
        case "--seed": o.settings.seed = UInt64(it.next() ?? "") ?? o.settings.seed
        case "--importance": o.importance = it.next()
        case "--runs": o.runs = Int(it.next() ?? "") ?? o.runs
        case "--min-label-radius": o.minLabelRadius = Float(it.next() ?? "") ?? o.minLabelRadius
        case "--auto": o.auto = true
        case "--length":
            let value = it.next() ?? ""
            guard let length = PaintingLength(rawValue: value) else { fail("--length: quick, relaxed or detailed, not \(value)") }
            o.length = length
        case "--hints": o.hints = it.next()
        case "--candidates": o.candidates = Int(it.next() ?? "") ?? o.candidates
        case "--out": o.out = it.next()
        case "--edges": o.edges = it.next()
        case "--eyes": o.eyes = it.next()
        case "--line-style":
            let value = it.next() ?? ""
            guard let style = LineArtSettings.Style(rawValue: value) else { fail("--line-style: classic or layered, not \(value)") }
            o.settings.lineArt.style = style
        case "--line-art": setLineArt(&o.settings.lineArt, it.next())
        case "--tuning": setTuning(&o.settings.tuning, it.next())
        default: o.positional.append(a)
        }
    }
    return o
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func loadImage(_ path: String) -> RGBAImage {
    guard let data = FileManager.default.contents(atPath: path) else { fail("cannot read \(path)") }
    if data.first == UInt8(ascii: "P") {
        do { return try Netpbm.read(data) } catch { fail("cannot decode \(path): \(error)") }
    }
    #if canImport(ImageIO)
    // On Apple platforms any ImageIO format works (JPEG, HEIC, PNG…), decoded to sRGB.
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fail("cannot decode \(path)") }
    let w = image.width, h = image.height
    var pixels = [UInt8](repeating: 0, count: w * h * 4)
    pixels.withUnsafeMutableBytes { raw in
        let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    return RGBAImage(width: w, height: h, pixels: pixels)
    #else
    fail("\(path): only PPM/PGM input is supported on this platform")
    #endif
}

func loadImportance(_ path: String?) -> Grid<Float>? {
    guard let path else { return nil }
    let img = loadImage(path)
    return Grid(width: img.width, height: img.height,
                storage: (0..<(img.width * img.height)).map { Float(img.pixels[$0 * 4]) / 255 })
}

/// The edge map and eyes layered line art draws from (`--edges`, `--eyes`).
func loadLineArt(_ options: Options) -> LineArtInput? {
    guard let path = options.edges else {
        if options.settings.lineArt.style == .layered { fail("--line-style layered needs --edges map.pgm") }
        return nil
    }
    let img = loadImage(path)
    let edges = EdgeMap(width: img.width, height: img.height, values: (0..<(img.width * img.height)).map { img.pixels[$0 * 4] })
    var eyes: [[SIMD2<Float>]] = []
    if let eyesPath = options.eyes {
        guard let data = FileManager.default.contents(atPath: eyesPath) else { fail("cannot read \(eyesPath)") }
        do {
            eyes = try JSONDecoder().decode([[[Float]]].self, from: data).map { poly in
                poly.map { p in
                    guard p.count == 2 else { fail("\(eyesPath): points are [x, y]") }
                    return SIMD2(p[0], p[1])
                }
            }
        } catch { fail("cannot decode \(eyesPath): \(error)") }
    }
    return LineArtInput(edges: edges, eyes: eyes)
}

func loadHints(_ path: String?) -> SubjectHints? {
    guard let path else { return nil }
    guard let data = FileManager.default.contents(atPath: path) else { fail("cannot read \(path)") }
    do { return try JSONDecoder().decode(SubjectHints.self, from: data) } catch { fail("cannot decode \(path): \(error)") }
}

/// Raster preview: each pixel painted with its region's palette color.
func paintedRaster(_ t: Template) -> RGBAImage {
    var px = [UInt8](repeating: 255, count: t.width * t.height * 4)
    let colors = t.palette.map { c in
        SIMD3<UInt8>(UInt8((c.rgb.x * 255).rounded()), UInt8((c.rgb.y * 255).rounded()), UInt8((c.rgb.z * 255).rounded()))
    }
    for i in 0..<(t.width * t.height) {
        let c = colors[Int(t.regions[Int(t.regionMap.storage[i])].colorIndex)]
        px[i * 4] = c.x; px[i * 4 + 1] = c.y; px[i * 4 + 2] = c.z
    }
    return RGBAImage(width: t.width, height: t.height, pixels: px, colorSpace: t.colorSpace)
}

/// Region-shape debug view at 2× scale: softened palette fills with 1-px dark lines wherever
/// neighbouring canvas units belong to different regions.
func boundaryRaster(_ t: Template) -> RGBAImage {
    let w = t.width, h = t.height, ow = w * 2, oh = h * 2
    var px = [UInt8](repeating: 255, count: ow * oh * 4)
    let colors = t.palette.map { c -> SIMD3<UInt8> in
        let soft = c.rgb * 0.7 + SIMD3(repeating: 0.3)
        return SIMD3(UInt8((soft.x * 255).rounded()), UInt8((soft.y * 255).rounded()), UInt8((soft.z * 255).rounded()))
    }
    let map = t.regionMap
    for y in 0..<oh {
        let sy = y / 2
        for x in 0..<ow {
            let sx = x / 2
            let r = map[sx, sy]
            var line = false
            if x & 1 == 1 && sx + 1 < w && map[sx + 1, sy] != r { line = true }
            if y & 1 == 1 && sy + 1 < h && map[sx, sy + 1] != r { line = true }
            if x & 1 == 1 && y & 1 == 1 && sx + 1 < w && sy + 1 < h && map[sx + 1, sy + 1] != r { line = true }
            let c = line ? SIMD3<UInt8>(40, 40, 40) : colors[Int(t.regions[Int(r)].colorIndex)]
            let o = (y * ow + x) * 4
            px[o] = c.x; px[o + 1] = c.y; px[o + 2] = c.z
        }
    }
    return RGBAImage(width: ow, height: oh, pixels: px, colorSpace: t.colorSpace)
}

/// `pbn generate`'s stats.json. Field names are a stable interface for regression tooling:
/// add fields, never rename or repurpose them. Validation runs outside the timed pipeline.
struct Metrics: Codable {
    var width: Int
    var height: Int
    var colors: Int
    var regions: Int
    var edges: Int
    var points: Int
    var triangles: Int
    var meanDeltaE: Float
    var p95DeltaE: Float
    /// `BandRings.count`: regions bounded mostly by weak (ramp) boundaries, the rings a
    /// smooth gradient is posterized into.
    var bandRings: Int
    var medianRegionArea: Float
    var regionsUnderRadius2: Int
    var regionsUnderRadius3: Int
    var minInscribedRadius: Float
    var minPaletteDistance: Float
    /// What the segmentation guarantees for `minPaletteDistance` at these settings.
    var minPaletteDistanceFloor: Float
    var timingsMs: [String: Double]
    var totalMs: Double
    var encodedBytes: Int
    var palette: [String]
    /// Smallest free radius of any label (canvas units, measured on the vector polygons).
    var minLabelRadius: Float
    /// Smallest label radius divided by `LabelSizing.roomFactor` of its number: the
    /// single-digit equivalent, comparable with `legibleLabelRadius`.
    var minLabelRoom: Float
    /// `LabelSizing.minimumRadius`: the single-digit room every label is guaranteed.
    var legibleLabelRadius: Float
    /// Smallest size any number fits in its label (canvas units, `LabelSizing.fittedFontSize`).
    var minLabelFontSize: Float
    /// `LabelSizing.minimumFontSize`: numbers are never drawn smaller.
    var legibleFontSize: Float
    /// Labels whose number would fit only below `legibleFontSize`; 0 for pipeline output.
    var labelsBelowLegibleSize: Int
    /// Edges the smoother left unfaired to keep the geometry valid.
    var smoothingFallbackEdges: Int
    /// Edges stepped toward the pixel outline so a label keeps its room.
    var labelRoomEdges: Int
    /// Regions whose label needed such edges.
    var labelRoomRegions: Int
    /// Regions whose label the smoother could not give its room (`VectorStats.labelRoomUnmet`);
    /// 0 unless its guarantee broke.
    var labelRoomUnmet: Int
    /// `Template.validate(minLabelRadius: LabelSizing.minimumRadius)` and its report.
    var valid: Bool
    var validation: String
    var colorNames: [String]
    /// With --auto: the decision and the bands it had to respect.
    var auto: AutoStats?
    /// With --auto: the photo features the decision read.
    var analysis: PhotoAnalysis?
    /// `ColorNickname.assign` with the generation seed; the stats' `colorNames` are the structured names.
    var colorNicknames: [String]
    /// Layered templates: what line art did and how the template's lines divide into layers.
    var lineArt: LineArtReport?
    /// Non-default `PipelineTuning` factors the template was generated with.
    var tuning: PipelineTuning?
}

/// `stats.json`'s `lineArt`.
struct LineArtReport: Codable {
    var settings: LineArtSettings
    /// Size of the edge map read.
    var edgeMap: [Int]
    var stats: LineArtStats
    /// Template edges per layer: outline, detail, texture, color.
    var edgesPerLayer: [Int]
    /// Their length (canvas units) per layer.
    var edgeLengthPerLayer: [Float]
    var interiorStrokes: Int
    var interiorPoints: Int
    /// Cells against the segmentation's regions (a classic template at the same settings).
    var cellsVsClassic: Float

    init?(_ out: TemplateGenerator.Output, settings: LineArtSettings, input: LineArtInput?) {
        guard let stats = out.lineArtStats, let lines = out.template.lineArt, let input else { return nil }
        let t = out.template
        self.settings = settings
        edgeMap = [input.edges.width, input.edges.height]
        self.stats = stats
        var count = [0, 0, 0, 0]
        var length: [Float] = [0, 0, 0, 0]
        for (k, e) in t.edges.enumerated() {
            let l = Int(min(lines.edgeLayers[k], 3))
            count[l] += 1
            let p = t.points(of: e)
            for i in p.indices.dropFirst() {
                let d = p[i] - p[i - 1]
                length[l] += (d * d).sum().squareRoot()
            }
        }
        edgesPerLayer = count
        edgeLengthPerLayer = length.map { ($0 * 10).rounded() / 10 }
        interiorStrokes = lines.strokes.count
        interiorPoints = lines.strokePoints.count
        cellsVsClassic = Float(t.regions.count) / Float(max(stats.segmentationRegions, 1))
    }
}

/// `stats.json`'s `auto`: the chosen settings, every candidate with its score terms, and the
/// preference's bands (the regression gate checks the choice against them).
struct AutoStats: Codable {
    struct Bands: Codable {
        var colors: [Int]
        var detail: [Float]
        var smoothness: [Float]
        var minutes: [Double]
    }
    var preference: PaintingLength
    var settings: GenerationSettings
    var winner: Int
    var candidates: [AutoCandidate]
    var bands: Bands
    var suggestMs: Double

    init(_ decision: AutoDecision, milliseconds: Double) {
        let p = decision.preference
        preference = p
        settings = decision.settings
        winner = decision.winner
        candidates = decision.candidates
        bands = Bands(
            colors: [p.colorBand.lowerBound, p.colorBand.upperBound],
            detail: [p.detailBand.lowerBound, p.detailBand.upperBound],
            smoothness: [AutoSettings.smoothnessBand.lowerBound, AutoSettings.smoothnessBand.upperBound],
            minutes: [p.timeBand.lowerBound / 60, p.timeBand.upperBound / 60])
        suggestMs = milliseconds
    }
}

func metrics(_ out: TemplateGenerator.Output, working: RGBAImage, settings: GenerationSettings) -> Metrics {
    let t = out.template
    let lab = ColorScience.okLabImage(from: working)
    var errors = [Float](repeating: 0, count: t.width * t.height)
    for i in 0..<errors.count {
        let p = lab.storage[i]
        let c = t.palette[Int(t.regions[Int(t.regionMap.storage[i])].colorIndex)].oklab
        errors[i] = ColorScience.distance(SIMD3(p.x, p.y, p.z), c)
    }
    let sortedErrors = errors.sorted()
    let areas = t.regions.map(\.area).sorted()
    var minPal = Float.infinity
    for i in 0..<t.palette.count {
        for j in (i + 1)..<t.palette.count {
            minPal = min(minPal, ColorScience.distance(t.palette[i].oklab, t.palette[j].oklab))
        }
    }
    var timings: [String: Double] = [:]
    for timing in out.timings { timings[timing.name, default: 0] += timing.seconds * 1000 }
    var minLabelRoom = Float.infinity, minFontSize = Float.infinity
    var belowLegible = 0
    for label in t.labels {
        let digits = LabelSizing.digitCount(colorIndex: t.regions[Int(label.region)].colorIndex)
        minLabelRoom = min(minLabelRoom, label.radius / LabelSizing.roomFactor(digits: digits))
        let size = LabelSizing.fittedFontSize(radius: label.radius, digits: digits)
        minFontSize = min(minFontSize, size)
        if size < LabelSizing.minimumFontSize - 1e-4 { belowLegible += 1 }
    }
    let report = t.validate(minLabelRadius: LabelSizing.minimumRadius)
    return Metrics(
        width: t.width, height: t.height, colors: t.palette.count, regions: t.regions.count,
        edges: t.edges.count, points: t.points.count, triangles: t.mesh.indices.count / 3,
        meanDeltaE: errors.reduce(0, +) / Float(max(1, errors.count)),
        p95DeltaE: sortedErrors.isEmpty ? 0 : sortedErrors[Int(Float(sortedErrors.count - 1) * 0.95)],
        bandRings: BandRings.count(out.segmentation, working: working),
        medianRegionArea: areas.isEmpty ? 0 : areas[areas.count / 2],
        regionsUnderRadius2: t.regions.filter { $0.inscribedRadius < 2 }.count,
        regionsUnderRadius3: t.regions.filter { $0.inscribedRadius < 3 }.count,
        minInscribedRadius: t.regions.map(\.inscribedRadius).min() ?? 0,
        minPaletteDistance: minPal.isFinite ? minPal : 0,
        minPaletteDistanceFloor: settings.minPaletteDistance,
        timingsMs: timings, totalMs: out.totalSeconds * 1000,
        encodedBytes: t.encoded().count,
        palette: t.palette.map { c in
            c.rgb.indices.map { String(format: "%02x", Int((min(max(c.rgb[$0], 0), 1) * 255).rounded())) }.joined()
        },
        minLabelRadius: t.labels.map(\.radius).min() ?? 0,
        minLabelRoom: minLabelRoom.isFinite ? minLabelRoom : 0,
        legibleLabelRadius: LabelSizing.minimumRadius,
        minLabelFontSize: minFontSize.isFinite ? minFontSize : 0,
        legibleFontSize: LabelSizing.minimumFontSize,
        labelsBelowLegibleSize: belowLegible,
        smoothingFallbackEdges: out.vectorStats.fallbackEdges,
        labelRoomEdges: out.vectorStats.labelRoomEdges,
        labelRoomRegions: out.vectorStats.labelRoomRegions,
        labelRoomUnmet: out.vectorStats.labelRoomUnmet,
        valid: report.isValid,
        validation: report.description,
        colorNames: t.palette.map(\.colorName.english),
        colorNicknames: ColorNickname.assign(t.palette, seed: settings.seed))
}

/// Measures the longest stretch of pipeline work between two cancellation checks, i.e. the
/// worst-case latency with which a stale preview stops.
final class CancellationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let clock = ContinuousClock()
    private let start: ContinuousClock.Instant
    private var last: ContinuousClock.Instant
    private var worst: (gap: Duration, end: Duration) = (.zero, .zero)

    init() {
        start = clock.now
        last = start
    }

    /// Only checks on the calling thread count: on pool threads `Task.isCancelled` is false.
    var check: CancellationCheck {
        CancellationCheck { [self] in
            guard Thread.isMainThread else { return false }
            let now = clock.now
            lock.withLock {
                if now - last > worst.gap { worst = (now - last, now - start) }
                last = now
            }
            return false
        }
    }

    /// Worst gap and the time it ended (since the start), in milliseconds, including the
    /// stretch from the last check to now.
    func finish() -> (gap: Double, end: Double) {
        _ = check.isCancelled
        let w = lock.withLock { worst }
        @inline(__always) func ms(_ d: Duration) -> Double {
            Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) * 1e-15
        }
        return (ms(w.gap), ms(w.end))
    }
}

func milliseconds(since start: ContinuousClock.Instant) -> Double {
    let d = ContinuousClock.now - start
    return Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) * 1e-15
}

/// Remembers when something happened (milliseconds since its creation), from any thread.
final class Lap: @unchecked Sendable {
    private let lock = NSLock()
    private let start = ContinuousClock.now
    private var value = 0.0

    func mark() { lock.withLock { value = pbn.milliseconds(since: start) } }
    var milliseconds: Double { lock.withLock { value } }
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

func jsonEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
}

func writeSVGs(_ t: Template, to outDir: URL) throws {
    try SVGExport.render(t, options: .init(painted: true, outlines: false, numbers: false))
        .write(to: outDir.appendingPathComponent("painted.svg"), atomically: true, encoding: .utf8)
    try SVGExport.render(t, options: .init(painted: false, outlines: true, numbers: true))
        .write(to: outDir.appendingPathComponent("template.svg"), atomically: true, encoding: .utf8)
    try SVGExport.render(t, options: .init(painted: true, outlines: true, numbers: false))
        .write(to: outDir.appendingPathComponent("painted-outlined.svg"), atomically: true, encoding: .utf8)
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

let args = CommandLine.arguments
guard args.count >= 2 else { fail("usage: pbn generate|suggest|bench|trace|check|names ...") }
let options = parse(args.dropFirst(2))

switch args[1] {
case "generate":
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
    try writeSVGs(t, to: outDir)
    print(String(data: try encoder.encode(m), encoding: .utf8)!)

case "suggest":
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

case "trace":
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

case "check":
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
            print("layered lines: edges " + zip(names, counts).map { "\($0) \($1)" }.joined(separator: ", ")
                + "; \(lines.strokes.count) interior strokes (\(lines.strokePoints.count) points)")
        }
        let report = template.validate(minLabelRadius: options.minLabelRadius > 0 ? options.minLabelRadius : nil)
        print(report.isValid ? "valid" : "INVALID", report)
    } catch { fail("cannot decode: \(error)") }

case "names":
    guard let path = options.positional.first, let data = FileManager.default.contents(atPath: path) else {
        fail("usage: pbn names <template.pbnt> [--seed N]")
    }
    do {
        let template = try Template(encoded: data)
        let nicknames = ColorNickname.assign(template.palette, seed: options.settings.seed)
        for (index, color) in template.palette.enumerated() {
            let hex = color.rgb.indices.map { String(format: "%02X", Int((min(max(color.rgb[$0], 0), 1) * 255).rounded())) }.joined()
            print(String(format: "%3d  %@  ·  %@  ·  #%@", index + 1, nicknames[index].padding(toLength: 18, withPad: " ", startingAt: 0),
                         color.colorName.english, hex))
        }
    } catch { fail("cannot decode: \(error)") }

case "bench":
    guard !options.positional.isEmpty else { fail("usage: pbn bench <in.ppm>...") }
    /// Runs the generator `runs` times; per-stage timings, region count, worst gap and the
    /// median of the per-run worst gaps (a lone outlier on a busy machine is a scheduling
    /// hiccup; a high median is a stretch of work that needs another check).
    func measure(_ image: RGBAImage, _ settings: GenerationSettings, runs: Int, lineArt: LineArtInput? = nil) -> (
        totals: [String: [Double]], order: [String], regions: Int, size: String,
        gap: (gap: Double, end: Double), stage: String, medianGap: Double
    ) {
        let generator = TemplateGenerator(settings: settings)
        var totals: [String: [Double]] = [:]
        var order: [String] = []
        var regionCount = 0
        var size = ""
        var worstGap = (gap: 0.0, end: 0.0)
        var worstStage = ""
        var gaps: [Double] = []
        for _ in 0..<runs {
            let probe = CancellationProbe()
            let out: TemplateGenerator.Output
            do { out = try generator.generate(from: image, lineArt: lineArt, cancel: probe.check) } catch { fail("\(error)") }
            regionCount = out.template.regions.count
            size = "\(out.template.width)×\(out.template.height)"
            let gap = probe.finish()
            gaps.append(gap.gap)
            if gap.gap > worstGap.gap {
                worstGap = gap
                // The innermost stage running when the stretch ended.
                let end = gap.end / 1000
                worstStage = out.timings.filter { $0.start <= end && end <= $0.start + $0.seconds }
                    .min { $0.seconds < $1.seconds }?.name ?? "between stages"
            }
            var perRun: [String: Double] = ["total": out.totalSeconds * 1000]
            for t in out.timings {
                if totals[t.name] == nil && perRun[t.name] == nil { order.append(t.name) }
                perRun[t.name, default: 0] += t.seconds * 1000
            }
            for (k, v) in perRun { totals[k, default: []].append(v) }
        }
        return (totals, order, regionCount, size, worstGap, worstStage, gaps.sorted()[gaps.count / 2])
    }
    func stat(_ values: [Double]) -> String {
        let v = values.sorted()
        return String(format: "median %8.1f ms   min %8.1f ms", v[v.count / 2], v[0])
    }
    for path in options.positional {
        let image = loadImage(path)
        let m = measure(image, options.settings, runs: options.runs)
        print("\(path) — \(m.size), \(m.regions) regions, longest stretch without a cancellation check "
            + String(format: "%.1f ms (ending %.0f ms into the run, in ", m.gap.gap, m.gap.end) + m.stage
            + String(format: "; median over runs %.1f ms)", m.medianGap))
        for name in m.order + ["total"] {
            print(String(format: "  %-28@ ", name as NSString) + stat(m.totals[name]!))
        }
        // The app's other regimes: a live preview at about 700 px, full detail on a large photo
        // (the source is enlarged so the working size reaches its 2100 px cap), and that with
        // the largest palette.
        let long = max(image.width, image.height)
        let preview = Resample.area(image, width: max(1, image.width * 467 / long), height: max(1, image.height * 467 / long))
        var fine = options.settings
        fine.detail = 1
        var many = fine
        many.colorCount = GenerationSettings.colorCountRange.upperBound
        let big = Resample.area(image, width: image.width * 1400 / long, height: image.height * 1400 / long)
        let regimes = [
            ("preview", preview, options.settings), ("detail 1", big, fine),
            ("\(many.colorCount) colors, detail 1", big, many),
        ]
        for (label, input, settings) in regimes {
            let v = measure(input, settings, runs: options.runs)
            print(String(format: "  %-28@ ", "\(label) \(v.size)" as NSString) + stat(v.totals["total"]!)
                + String(format: "   worst gap %.1f ms (in ", v.gap.gap) + v.stage
                + String(format: "; median %.1f ms)", v.medianGap))
        }
        if let input = loadLineArt(options) {
            var layered = options.settings
            layered.lineArt.style = .layered
            let v = measure(image, layered, runs: options.runs, lineArt: input)
            print(String(format: "  %-28@ ", "layered \(v.size), \(v.regions) cells" as NSString) + stat(v.totals["total"]!)
                + String(format: "   worst gap %.1f ms (in ", v.gap.gap) + v.stage + ")")
            for name in v.order where name.hasPrefix("lineArt") {
                print(String(format: "    %-26@ ", name as NSString) + stat(v.totals[name]!))
            }
        }
        // Auto's suggestion as the create flow runs it, and its analysis alone.
        var auto = options
        auto.length = .relaxed
        auto.candidates = 5
        var suggestMs: [Double] = [], analysisMs: [Double] = []
        var decision: AutoDecision?
        for _ in 0..<max(1, options.runs) {
            let start = ContinuousClock.now
            do {
                _ = try AutoSettings.analyze(image, importance: nil, hints: nil, cancel: .none)
            } catch { fail("\(error)") }
            analysisMs.append(milliseconds(since: start))
            let (d, ms) = suggest(image, importance: nil, options: auto)
            suggestMs.append(ms)
            decision = d
        }
        let draft = AutoSettings.draftImage(from: image)
        let chosen = decision!.settings
        print(String(format: "  %-28@ ", "suggest \(draft.width)×\(draft.height)" as NSString) + stat(suggestMs)
            + String(format: "   analysis median %.1f ms; %d candidates → %d colors, detail %.2f, smoothness %.2f",
                     analysisMs.sorted()[analysisMs.count / 2], decision!.candidates.count, chosen.colorCount,
                     Double(chosen.detail), Double(chosen.smoothness)))
    }

default:
    fail("unknown command \(args[1])")
}
