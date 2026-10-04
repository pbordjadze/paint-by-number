import Foundation
import PaintCore

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
        palette: t.palette.map(\.hexDigits),
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

func jsonEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
}
