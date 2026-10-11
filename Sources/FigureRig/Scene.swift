import Foundation

public struct FigureScene: Decodable, Sendable {
    public var version: Int, seed: UInt64, canvas: Canvas, background: String?, display: String
    public var figureHeight: Double, paths: [String: String], actors: [Actor], card: Citation, tail: Double
    public var pointsPerUnit: Double { (display == "ipad13" ? 1032 : 402) / canvas.width }
    public var pixelWidth: Int { display == "ipad13" ? 2064 : 1206 }
    public var pixelHeight: Int { Int(ceil(Double(pixelWidth) * canvas.height / canvas.width)) }

    public init(from decoder: any Decoder) throws {
        let d = try Fields(decoder, "version seed canvas background display figureHeight paths actors card tail")
        version = try d.integer("version", 1, 1...1); seed = try d.value("seed", UInt64(1))
        canvas = try d.required("canvas"); background = try d.optional("background")
        display = try d.choice("display", "ipad13", "ipad13 iphone")
        figureHeight = try d.number("figureHeight", 50, Double.leastNonzeroMagnitude...Double.greatestFiniteMagnitude)
        paths = try d.required("paths"); actors = try d.required("actors"); card = try d.required("card")
        tail = try d.number("tail", 0.5, 0...Double.greatestFiniteMagnitude)
        guard actors.count == 1 else { throw FigureInputError("actors: v0 expects exactly 1 actor") }
        guard !actors[0].id.isEmpty else { throw FigureInputError("actors[0].id: expected a nonempty id") }
    }
    public struct Canvas: Decodable, Sendable {
        public var width: Double, height: Double, paper: String, paperDark: String
        public init(from decoder: any Decoder) throws {
            let d = try Fields(decoder, "width height paper paperDark")
            width = try d.number("width", 1100, Double.leastNonzeroMagnitude...Double.greatestFiniteMagnitude)
            height = try d.number("height", 825, Double.leastNonzeroMagnitude...Double.greatestFiniteMagnitude)
            paper = try d.color("paper", "#F6F1E7"); paperDark = try d.color("paperDark", "#1E1B24")
        }
    }
    public struct Actor: Decodable, Sendable {
        public var id: String, at: Location, timeline: [Action]
        public init(from decoder: any Decoder) throws {
            let d = try Fields(decoder, "id at timeline")
            id = try d.required("id"); at = try d.required("at"); timeline = try d.required("timeline")
        }
    }
    public struct Location: Decodable, Sendable {
        public var path: String, t: Double
        public init(from decoder: any Decoder) throws {
            let d = try Fields(decoder, "path t"); path = try d.required("path"); t = try d.number("t", 0, 0...1)
        }
    }
    public struct Action: Decodable, Sendable {
        public var kind: String, path: String?, to: Double?, heading: Double?, duration: Double?
        public init(from decoder: any Decoder) throws {
            let probe = try decoder.container(keyedBy: FieldKey.self)
            let kind = try probe.decode(String.self, forKey: FieldKey("do"))
            let allowed: String
            switch kind {
            case "walk": allowed = "do path to"
            case "turn": allowed = "do heading"
            case "cast", "idle": allowed = "do duration"
            default: throw FigureInputError("\(inputPath(decoder.codingPath)).do: expected walk turn cast idle")
            }
            let d = try Fields(decoder, allowed); self.kind = kind
            if kind == "walk" {
                path = try d.required("path"); to = try d.number("to", 1, 0...1)
            } else if kind == "turn" {
                heading = try d.required("heading")
                guard heading!.isFinite else { throw FigureInputError("\(d.field("heading")): expected finite degrees") }
            } else {
                duration = try d.number("duration", 1, 0...Double.greatestFiniteMagnitude)
            }
        }
    }
    public struct Citation: Decodable, Sendable {
        public var authors: String, year: Int, title: String, at: Double
        public var words: Int { (authors + " " + String(year) + " " + title).split(whereSeparator: \.isWhitespace).count }
        public init(from decoder: any Decoder) throws {
            let d = try Fields(decoder, "authors year title at")
            authors = try d.required("authors"); year = try d.required("year"); title = try d.required("title")
            at = try d.number("at", 0, 0...Double.greatestFiniteMagnitude)
        }
    }
}
