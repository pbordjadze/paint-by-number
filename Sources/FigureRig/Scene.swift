import Foundation

public struct FigureScene: Decodable, Sendable {
    public var version: Int, seed: UInt64, canvas: Canvas, background: String?, display: String
    public var figureHeight: Double, paths: [String: String], actors: [Actor], card: Citation, tail: Double
    public var props: [GroundProp]
    public var pointsPerUnit: Double { (display == "ipad13" ? 1032 : 402) / canvas.width }
    public var pixelWidth: Int { display == "ipad13" ? 2064 : 1206 }
    public var pixelHeight: Int { Int(ceil(Double(pixelWidth) * canvas.height / canvas.width)) }

    public init(from decoder: any Decoder) throws {
        let d = try Fields(decoder, "version seed canvas background display figureHeight paths actors card tail props")
        version = try d.integer("version", 1, 1...2); seed = try d.value("seed", UInt64(1))
        canvas = try d.required("canvas"); background = try d.optional("background")
        display = try d.choice("display", "ipad13", "ipad13 iphone")
        figureHeight = try d.number("figureHeight", 50, 0.01...100_000)
        paths = try d.required("paths"); actors = try d.required("actors"); card = try d.required("card")
        tail = try d.number("tail", 0.5, 0...FigureLimits.duration)
        props = try d.value("props", [])
        guard !actors.isEmpty else { throw FigureInputError("actors: expected at least 1 actor") }
        if version == 1 {
            guard actors.count == 1 else { throw FigureInputError("actors: version 1 expects exactly 1 actor") }
            guard !d.container.contains(FieldKey("props")) else { throw FigureInputError("props: requires scene version 2") }
        }
        var ids = Set<String>()
        for (i, actor) in actors.enumerated() {
            guard !actor.id.isEmpty, ids.insert(actor.id).inserted else {
                throw FigureInputError("actors[\(i)].id: expected a unique nonempty id")
            }
            if version == 1 && actor.hasHoldsField { throw FigureInputError("actors[\(i)].holds: requires scene version 2") }
            for (j, action) in actor.timeline.enumerated() where ["ink", "sweep"].contains(action.kind) {
                let field = "actors[\(i)].timeline[\(j)].do"
                guard version == 2 else { throw FigureInputError("\(field): requires scene version 2") }
                let tool: PropKind = action.kind == "ink" ? .brush : .broom
                guard actor.holds == tool else { throw FigureInputError("\(field): requires holds: \(tool.rawValue)") }
            }
        }
        try validateLimits()
    }

    // Rechecked by Rig because scenes are mutable values, also built directly by tests/tools.
    func validateLimits() throws {
        try FigureLimits.number(canvas.width, 1...100_000, "canvas.width")
        try FigureLimits.number(canvas.height, 1...100_000, "canvas.height")
        try FigureLimits.number(canvas.height / canvas.width, 0.125...8, "canvas.height/width")
        try FigureLimits.number(figureHeight, 0.01...100_000, "figureHeight")
        try FigureLimits.number(tail, 0...FigureLimits.duration, "tail")
        try FigureLimits.number(card.at, 0...FigureLimits.duration, "card.at")
        guard (1...1024).contains(actors.count) else { throw FigureInputError("actors: expected 1...1024 actors") }
        for (i, actor) in actors.enumerated() {
            guard actor.timeline.count <= 10_000 else {
                throw FigureInputError("actors[\(i)].timeline: expected at most 10000 actions")
            }
        }
    }
    public struct Canvas: Decodable, Sendable {
        public var width: Double, height: Double, paper: String, paperDark: String
        public init(from decoder: any Decoder) throws {
            let d = try Fields(decoder, "width height paper paperDark")
            width = try d.number("width", 1100, 1...100_000)
            height = try d.number("height", 825, 1...100_000)
            paper = try d.color("paper", "#F6F1E7"); paperDark = try d.color("paperDark", "#1E1B24")
        }
    }
    public struct Actor: Decodable, Sendable {
        public var id: String, at: Location, timeline: [Action]
        public var holds: PropKind?
        let hasHoldsField: Bool
        public init(from decoder: any Decoder) throws {
            let d = try Fields(decoder, "id at timeline holds")
            id = try d.required("id"); at = try d.required("at"); timeline = try d.required("timeline")
            holds = try d.optional("holds")
            hasHoldsField = d.container.contains(FieldKey("holds"))
        }
    }
    public struct GroundProp: Decodable, Sendable {
        public var kind: PropKind, at: Location
        public init(from decoder: any Decoder) throws {
            let d = try Fields(decoder, "kind at")
            kind = try d.required("kind"); at = try d.required("at")
        }
    }
    public struct Location: Decodable, Sendable {
        public var path: String, t: Double
        public init(from decoder: any Decoder) throws {
            let d = try Fields(decoder, "path t"); path = try d.required("path"); t = try d.number("t", 0, 0...1)
        }
    }
    public struct Action: Decodable, Sendable {
        public var kind: String, path: String?, from: Double?, to: Double?, heading: Double?, duration: Double?
        public init(from decoder: any Decoder) throws {
            let probe = try decoder.container(keyedBy: FieldKey.self)
            let kind = try probe.decode(String.self, forKey: FieldKey("do"))
            let allowed: String
            switch kind {
            case "walk", "sweep": allowed = "do path to"
            case "ink": allowed = "do path from to"
            case "turn": allowed = "do heading"
            case "cast", "idle": allowed = "do duration"
            default: throw FigureInputError("\(inputPath(decoder.codingPath)).do: expected walk turn cast idle sweep ink")
            }
            let d = try Fields(decoder, allowed); self.kind = kind
            if ["walk", "sweep", "ink"].contains(kind) {
                path = try d.required("path"); to = try d.number("to", 1, 0...1)
                if kind == "ink" { from = try d.number("from", 0, 0...1) }
            } else if kind == "turn" {
                heading = try d.required("heading")
                try FigureLimits.number(heading!, -1_000_000...1_000_000, d.field("heading"))
            } else {
                duration = try d.number("duration", 1, 0...FigureLimits.duration)
            }
        }
    }
    public struct Citation: Decodable, Sendable {
        public var authors: String, year: Int, title: String, at: Double
        public var words: Int { (authors + " " + String(year) + " " + title).split(whereSeparator: \.isWhitespace).count }
        public init(from decoder: any Decoder) throws {
            let d = try Fields(decoder, "authors year title at")
            authors = try d.required("authors"); year = try d.required("year"); title = try d.required("title")
            at = try d.number("at", 0, 0...FigureLimits.duration)
        }
    }
}
