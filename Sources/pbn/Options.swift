import Foundation
import PaintCore

struct Options {
    var positional: [String] = []
    var vocabulary: Int?
    var nicknameTable: String?
    /// pbn draws lines only from an edge map it is handed (`--edges`, `--lines`), so it starts
    /// classic whatever the pipeline's default style; `--line-style` picks a style at its own
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
    var snapshots: String?
    var edges: String?
    var lines: String?
    var eyes: String?
    var objects: String?
    var writing: String?
    var lineEdits: String?
    /// `pbn edit`'s photo: draws without paints take its colors, as the app's do.
    var photo: String?
    /// `pbn refine`'s template, instead of one generated from the photo.
    var template: String?
    /// `pbn refine` from Refine's Start From Blank: the photo as one area (`TemplateEditor.blank`).
    var blank = false
    /// `pbn refine` writes each gesture's pictures; `--no-steps` only before and after.
    var steps = true
    /// How much of `--edges` goes under `--lines` when both are given (`EdgeMap.contourWeight`).
    var contourWeight = EdgeMap.contourWeight
}

/// `--line-art` and `--tuning` fields by name.
enum Fields {
    static var lineArtFloats: [String: WritableKeyPath<LineArtSettings, Float>] {
        ["outlineThreshold": \.outlineThreshold, "detailThreshold": \.detailThreshold,
         "minimumStrokeLength": \.minimumStrokeLength, "gapBridging": \.gapBridging, "lineSmoothing": \.lineSmoothing]
    }
    static var lineArtBools: [String: WritableKeyPath<LineArtSettings, Bool>] {
        ["keepColorEdges": \.keepColorEdges, "outlineEyes": \.outlineEyes, "outlineObjects": \.outlineObjects,
         "keepWriting": \.keepWriting]
    }
    static var tuning: [String: WritableKeyPath<PipelineTuning, Float>] {
        ["smoothing": \.smoothing, "textureFlattening": \.textureFlattening, "minimumCellSize": \.minimumCellSize,
         "subjectEmphasis": \.subjectEmphasis, "accentColors": \.accentColors, "colorfulness": \.colorfulness]
    }
}

typealias Arguments = IndexingIterator<ArraySlice<String>>

/// The argument after `flag`.
func value(_ flag: String, _ it: inout Arguments) -> String {
    guard let argument = it.next() else { fail("\(flag) needs a value") }
    return argument
}

/// The number after `flag`.
func number<T: LosslessStringConvertible>(_ flag: String, _ it: inout Arguments) -> T {
    let argument = value(flag, &it)
    guard let n = T(argument) else { fail("\(flag): a number, not \(argument)") }
    return n
}

/// The case of `T` that `argument` names, failing with "a, b or c" over its cases.
func choice<T: CaseIterable & RawRepresentable>(_ flag: String, _ argument: String) -> T where T.RawValue == String {
    if let c = T(rawValue: argument) { return c }
    let names = T.allCases.map(\.rawValue)
    fail("\(flag): " + names.dropLast().joined(separator: ", ") + " or " + names.last! + ", not \(argument)")
}

func keyValue(_ flag: String, _ argument: String) -> (String, String) {
    guard let eq = argument.firstIndex(of: "=") else { fail("\(flag): key=value, not \(argument)") }
    return (String(argument[..<eq]), String(argument[argument.index(after: eq)...]))
}

func setLineArt(_ s: inout LineArtSettings, _ argument: String) {
    let (key, value) = keyValue("--line-art", argument)
    if let path = Fields.lineArtFloats[key] {
        guard let v = Float(value) else { fail("--line-art \(key): a number, not \(value)") }
        s[keyPath: path] = v
    } else if let path = Fields.lineArtBools[key] {
        guard let v = Bool(value) else { fail("--line-art \(key): true or false, not \(value)") }
        s[keyPath: path] = v
    } else if key == "style" {
        s.style = choice("--line-art style", value)
    } else if key == "samePaint" {
        s.samePaint = choice("--line-art samePaint", value)
    } else if key == "detector" {
        s.detector = choice("--line-art detector", value)
    } else {
        let keys = (Array(Fields.lineArtFloats.keys) + Array(Fields.lineArtBools.keys) + ["style", "samePaint", "detector"]).sorted()
        fail("--line-art: unknown field \(key) (known: \(keys.joined(separator: ", ")))")
    }
}

func setTuning(_ t: inout PipelineTuning, _ argument: String) {
    let (key, value) = keyValue("--tuning", argument)
    guard let path = Fields.tuning[key] else {
        fail("--tuning: unknown factor \(key) (known: \(Fields.tuning.keys.sorted().joined(separator: ", ")))")
    }
    guard let v = Float(value) else { fail("--tuning \(key): a number, not \(value)") }
    t[keyPath: path] = v
}

/// The settings `--line-style` and `--line-art` ask for: the style at its own defaults, the
/// fields on top.
func lineArtSettings(_ style: LineArtSettings.Style, fields: [String]) -> LineArtSettings {
    var s = LineArtSettings(style: style)
    for field in fields { setLineArt(&s, field) }
    return s
}

func parse(_ args: ArraySlice<String>) -> Options {
    var o = Options()
    var it = args.makeIterator()
    while let a = it.next() {
        switch a {
        case "--colors": o.settings.colorCount = number(a, &it)
        case "--detail": o.settings.detail = number(a, &it)
        case "--smooth": o.settings.smoothness = number(a, &it)
        case "--seed": o.settings.seed = number(a, &it)
        case "--vocabulary":
            o.vocabulary = number(a, &it)
            guard o.vocabulary! >= 1 else { fail("--vocabulary: at least 1") }
        case "--nickname-table": o.nicknameTable = value(a, &it)
        case "--importance": o.importance = value(a, &it)
        case "--runs":
            o.runs = number(a, &it)
            guard o.runs >= 1 else { fail("--runs: at least 1") }
        case "--min-label-radius": o.minLabelRadius = number(a, &it)
        case "--auto": o.auto = true
        case "--length": o.length = choice(a, value(a, &it))
        case "--hints": o.hints = value(a, &it)
        case "--candidates": o.candidates = number(a, &it)
        case "--out": o.out = value(a, &it)
        case "--snapshots": o.snapshots = value(a, &it)
        case "--edges": o.edges = value(a, &it)
        case "--lines": o.lines = value(a, &it)
        case "--eyes": o.eyes = value(a, &it)
        case "--objects": o.objects = value(a, &it)
        case "--writing": o.writing = value(a, &it)
        case "--line-edits": o.lineEdits = value(a, &it)
        case "--photo": o.photo = value(a, &it)
        case "--template": o.template = value(a, &it)
        case "--blank": o.blank = true
        case "--no-steps": o.steps = false
        case "--contour-weight": o.contourWeight = number(a, &it)
        case "--line-style": o.lineStyle = choice(a, value(a, &it))
        case "--line-art": o.lineArtFields.append(value(a, &it))
        case "--tuning": setTuning(&o.settings.tuning, value(a, &it))
        default:
            if a.hasPrefix("--") { fail("unknown option \(a)") }
            o.positional.append(a)
        }
    }
    o.settings.lineArt = lineArtSettings(o.lineStyle ?? .classic, fields: o.lineArtFields)
    return o
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}
