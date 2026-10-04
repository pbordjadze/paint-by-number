import Foundation
import PaintCore

struct Options {
    var positional: [String] = []
    /// pbn draws lines only from an edge map it is handed (`--edges`), so it starts classic
    /// whatever the pipeline's default style; `--line-style` picks a style at its own
    /// defaults, and `--line-art` fields apply on top of it whatever their order.
    var settings = GenerationSettings(lineArt: LineArtSettings(style: .classic))
    var lineStyle: LineArtSettings.Style?
    var lineArtFields: [String] = []
    var importance: String?
    var runs = 3
    var minLabelRadius = LabelSizing.minimumRadius
    var auto = false
    var length = PaintingLength.relaxed
    var hints: String?
    var candidates = 5
    var out: String?
    var edges: String?
    var lines: String?
    var eyes: String?
    var objects: String?
    /// How much of `--edges` goes under `--lines` when both are given (`EdgeMap.contourWeight`).
    var contourWeight = EdgeMap.contourWeight
}

/// `--line-art` and `--tuning` fields by name.
enum Fields {
    static var lineArtFloats: [String: WritableKeyPath<LineArtSettings, Float>] {
        ["outlineThreshold": \.outlineThreshold, "detailThreshold": \.detailThreshold, "textureThreshold": \.textureThreshold,
         "minimumStrokeLength": \.minimumStrokeLength, "gapBridging": \.gapBridging, "lineSmoothing": \.lineSmoothing]
    }
    static var lineArtBools: [String: WritableKeyPath<LineArtSettings, Bool>] {
        ["keepColorEdges": \.keepColorEdges, "outlineEyes": \.outlineEyes, "outlineObjects": \.outlineObjects]
    }
    static var tuning: [String: WritableKeyPath<PipelineTuning, Float>] {
        ["smoothing": \.smoothing, "textureFlattening": \.textureFlattening, "minimumCellSize": \.minimumCellSize,
         "subjectEmphasis": \.subjectEmphasis, "accentColors": \.accentColors, "colorfulness": \.colorfulness]
    }
}

/// "classic, layered or coloringBook", for error messages.
let lineStyles: String = {
    let names = LineArtSettings.Style.allCases.map(\.rawValue)
    return names.dropLast().joined(separator: ", ") + " or " + names.last!
}()

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
        guard let v = LineArtSettings.Style(rawValue: value) else { fail("--line-art style: \(lineStyles), not \(value)") }
        s.style = v
    } else if key == "samePaint" {
        guard let v = LineArtSettings.SamePaint(rawValue: value) else {
            fail("--line-art samePaint: " + LineArtSettings.SamePaint.allCases.map(\.rawValue).joined(separator: ", ") + ", not \(value)")
        }
        s.samePaint = v
    } else if key == "detector" {
        guard let v = LineArtSettings.Detector(rawValue: value) else {
            fail("--line-art detector: " + LineArtSettings.Detector.allCases.map(\.rawValue).joined(separator: ", ") + ", not \(value)")
        }
        s.detector = v
    } else {
        let keys = (Array(Fields.lineArtFloats.keys) + Array(Fields.lineArtBools.keys) + ["style", "samePaint", "detector"]).sorted()
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
        case "--lines": o.lines = it.next()
        case "--eyes": o.eyes = it.next()
        case "--objects": o.objects = it.next()
        case "--contour-weight": o.contourWeight = Float(it.next() ?? "") ?? o.contourWeight
        case "--line-style":
            let value = it.next() ?? ""
            guard let style = LineArtSettings.Style(rawValue: value) else { fail("--line-style: \(lineStyles), not \(value)") }
            o.lineStyle = style
        case "--line-art": o.lineArtFields.append(it.next() ?? "")
        case "--tuning": setTuning(&o.settings.tuning, it.next())
        default: o.positional.append(a)
        }
    }
    if let style = o.lineStyle { o.settings.lineArt = LineArtSettings(style: style) }
    for field in o.lineArtFields { setLineArt(&o.settings.lineArt, field) }
    return o
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}
