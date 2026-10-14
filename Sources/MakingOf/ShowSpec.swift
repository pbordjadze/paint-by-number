import Foundation

/// The making-of show's spec: `making-of.json`, which the Lamp edits. Decoding is strict (version
/// 1, the six steps in order, known poses, no unknown key at any level, every duration and length
/// positive and within the bounds below), so a bad edit throws, with the key in the error, and
/// never reaches the planner. Times are seconds; crew lengths are in the pet's own height; a
/// `height` is a share of the picture's.
public struct ShowSpec: Sendable, Equatable, Decodable {
    public static let version = 1
    /// The largest file `init(json:)` reads.
    public static let maximumBytes = 64 * 1024

    public var about: String
    public var timing: Timing
    public var steps: [Step]
    public var cards: Cards
    public var tones: Tones
    public var sketch: Sketch
    public var seeds: Seeds
    public var outlines: Outlines
    public var crew: Crew

    public enum StepID: String, Sendable, CaseIterable, Decodable {
        case sketch, shading, paints, merged, ink, template
    }

    /// What a pet does at a job: the hands-on steps show it busy, the others reviewing.
    public enum Pose: String, Sendable, Decodable {
        case busy, review
    }

    public struct Timing: Sendable, Equatable {
        public var intro: Double
        public var step: Double
        public var outro: Double
    }

    public struct Step: Sendable, Equatable {
        public var id: StepID
        /// What the step does, in a few plain words: the card's text.
        public var caption: String
        /// The methods the card credits in a footnote, by their names in Acknowledgements.
        public var methods: [String]
        public var pose: Pose
    }

    public struct Cards: Sendable, Equatable {
        public var opacity: Double
        /// How faint the footnote's credit lines are: 1 is as bold as the caption.
        public var footnote: Double
    }

    /// The greys of the paints, merged and ink steps: lightness mapped from `low` to `high`, bent
    /// so the picture averages `mean` (the Snow Queen's lighter, clearer greys).
    public struct Tones: Sendable, Equatable {
        public var low: Double
        public var high: Double
        public var mean: Double
    }

    public struct Sketch: Sendable, Equatable {
        public var coherenceFrom: Double
        public var coherenceSpan: Double
        public var coherenceExponent: Double
        public var smearRadius: Double
    }

    public struct Seeds: Sendable, Equatable {
        public var dropEvery: Double
        public var dot: Double
        public var fade: Double
    }

    public struct Outlines: Sendable, Equatable {
        public var grid: Double
        public var relax: Double
        public var inkRamp: Double
    }

    /// The seconds a move speeds up over and slows down over.
    public struct Ramp: Sendable, Equatable {
        public var up: Double
        public var down: Double
    }

    /// The crew's motion; `making_of_pets.py` explains each number.
    public struct Crew: Sendable, Equatable {
        public var pets: [String]
        public var height: Double
        public var walk: Double
        public var lean: Double
        public var accel: Double
        public var decel: Double
        public var stride: Double
        public var hop: Double
        public var hopTime: Double
        public var hopMin: Double
        public var work: ClosedRange<Double>
        public var pop: Double
        public var side: Double
        public var still: Double
        public var margin: Double
        public var bands: Int
        public var space: Double
        public var trace: Double
        public var traceRamp: Ramp
        public var hold: Double
        public var exit: Double
        public var wave: Double
        /// Seconds of a last look at the finished picture, before the wave.
        public var look: Double
        /// Seconds the last one out waves again, just inside the edge.
        public var edgeWave: Double
        public var tilt: Double
        public var beat: Double
    }

    /// Reads a spec from `making-of.json`'s bytes.
    public init(json: Data) throws {
        guard json.count <= Self.maximumBytes else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "the spec is over \(Self.maximumBytes) bytes"))
        }
        self = try JSONDecoder().decode(ShowSpec.self, from: json)
    }

    public init(from decoder: any Decoder) throws {
        let f = try Fields(decoder, keys: ["about", "version", "timing", "steps", "cards", "tones", "sketch", "seeds", "outlines", "crew"])
        let found = try f.integer("version", in: 0...Int.max)
        guard found == Self.version else {
            throw f.invalid("version", "\(found), but this reader knows version \(Self.version)")
        }
        about = try f.string("about", maxLength: 2000)
        timing = try f.value("timing")
        steps = try f.value("steps")
        cards = try f.value("cards")
        tones = try f.value("tones")
        sketch = try f.value("sketch")
        seeds = try f.value("seeds")
        outlines = try f.value("outlines")
        crew = try f.value("crew")
        guard steps.map(\.id) == StepID.allCases else {
            throw f.invalid("steps", "must be the \(StepID.allCases.count) steps \(StepID.allCases.map(\.rawValue)), in that order")
        }
    }
}

extension ShowSpec.Timing: Decodable {
    public init(from decoder: any Decoder) throws {
        let f = try Fields(decoder, keys: ["intro", "step", "outro"])
        intro = try f.number("intro", in: 0.01...10)
        step = try f.number("step", in: 0.5...30)
        outro = try f.number("outro", in: 0.01...30)
    }
}

extension ShowSpec.Step: Decodable {
    public init(from decoder: any Decoder) throws {
        let f = try Fields(decoder, keys: ["id", "caption", "methods", "pose"])
        id = try f.value("id")
        caption = try f.string("caption", maxLength: 200)
        guard !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw f.invalid("caption", "must not be empty")
        }
        let methods: [String] = try f.value("methods")
        guard (1...8).contains(methods.count), methods.allSatisfy({ !$0.isEmpty && $0.count <= 200 }) else {
            throw f.invalid("methods", "must be one to eight names of up to 200 characters")
        }
        self.methods = methods
        pose = try f.value("pose")
    }
}

extension ShowSpec.Cards: Decodable {
    public init(from decoder: any Decoder) throws {
        let f = try Fields(decoder, keys: ["opacity", "footnote"])
        opacity = try f.number("opacity", in: 0...1)
        footnote = try f.fraction("footnote")
    }
}

extension ShowSpec.Tones: Decodable {
    public init(from decoder: any Decoder) throws {
        let f = try Fields(decoder, keys: ["low", "high", "mean"])
        low = try f.fraction("low")
        high = try f.fraction("high")
        mean = try f.fraction("mean")
        guard low < mean && mean < high else { throw f.invalid("mean", "must lie between low and high") }
    }
}

extension ShowSpec.Sketch: Decodable {
    public init(from decoder: any Decoder) throws {
        let f = try Fields(decoder, keys: ["coherenceFrom", "coherenceSpan", "coherenceExponent", "smearRadius"])
        coherenceFrom = try f.number("coherenceFrom", in: 0...1)
        coherenceSpan = try f.number("coherenceSpan", in: 0.01...1)
        coherenceExponent = try f.number("coherenceExponent", in: 0.1...8)
        smearRadius = try f.number("smearRadius", in: 0.1...64)
    }
}

extension ShowSpec.Seeds: Decodable {
    public init(from decoder: any Decoder) throws {
        let f = try Fields(decoder, keys: ["dropEvery", "dot", "fade"])
        dropEvery = try f.number("dropEvery", in: 0.001...1)
        dot = try f.number("dot", in: 0.5...100)
        fade = try f.number("fade", in: 0.01...5)
    }
}

extension ShowSpec.Outlines: Decodable {
    public init(from decoder: any Decoder) throws {
        let f = try Fields(decoder, keys: ["grid", "relax", "inkRamp"])
        grid = try f.number("grid", in: 0.5...50)
        relax = try f.number("relax", in: 0.01...5)
        inkRamp = try f.number("inkRamp", in: 0.01...5)
    }
}

extension ShowSpec.Crew: Decodable {
    public init(from decoder: any Decoder) throws {
        let f = try Fields(decoder, keys: [
            "pets", "height", "walk", "lean", "accel", "decel", "stride", "hop", "hopTime", "hopMin", "work",
            "pop", "side", "still", "margin", "bands", "space", "trace", "traceRamp", "hold", "exit", "wave",
            "look", "edgeWave", "tilt", "beat",
        ])
        let pets: [String] = try f.value("pets")
        guard (1...20).contains(pets.count), pets.allSatisfy({ !$0.isEmpty && $0.count <= 64 }),
              Set(pets).count == pets.count
        else {
            throw f.invalid("pets", "must be one to twenty different ids of up to 64 characters")
        }
        self.pets = pets
        height = try f.number("height", in: 0.02...0.5)
        walk = try f.number("walk", in: 0.1...20)
        lean = try f.number("lean", in: 0.01...2)
        accel = try f.number("accel", in: 0.01...2)
        decel = try f.number("decel", in: 0.01...2)
        stride = try f.number("stride", in: 0.1...10)
        hop = try f.number("hop", in: 0.001...1)
        hopTime = try f.number("hopTime", in: 0.01...2)
        hopMin = try f.number("hopMin", in: 0.01...20)
        let work = try f.numbers("work", count: 2, in: 0.01...10)
        guard work[0] <= work[1] else { throw f.invalid("work", "must be the shortest time, then the longest") }
        self.work = work[0]...work[1]
        pop = try f.number("pop", in: 0.01...5)
        side = try f.number("side", in: 0.01...5)
        still = try f.number("still", in: 0.01...5)
        margin = try f.number("margin", in: 0...0.4)
        bands = try f.integer("bands", in: 1...8)
        space = try f.number("space", in: 0.1...5)
        trace = try f.number("trace", in: 0.1...20)
        let ramp = try f.numbers("traceRamp", count: 2, in: 0.01...2)
        traceRamp = ShowSpec.Ramp(up: ramp[0], down: ramp[1])
        hold = try f.number("hold", in: 0.01...5)
        exit = try f.number("exit", in: 0.1...20)
        wave = try f.number("wave", in: 0.01...10)
        look = try f.number("look", in: 0.01...5)
        edgeWave = try f.number("edgeWave", in: 0.01...5)
        tilt = try f.number("tilt", in: 0...45)
        beat = try f.number("beat", in: 0.01...1)
    }
}

/// A keyed container that lists the keys it may hold: any other key is an error, and so is a
/// number outside the range its key allows.
private struct Fields {
    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.init(stringValue) }
        init?(intValue: Int) { nil }
    }

    private let container: KeyedDecodingContainer<Key>

    init(_ decoder: any Decoder, keys: [String]) throws {
        container = try decoder.container(keyedBy: Key.self)
        if let unknown = container.allKeys.map(\.stringValue).sorted().first(where: { !keys.contains($0) }) {
            throw DecodingError.dataCorruptedError(
                forKey: Key(unknown), in: container, debugDescription: "unknown key “\(unknown)”")
        }
    }

    func invalid(_ key: String, _ message: String) -> DecodingError {
        DecodingError.dataCorruptedError(forKey: Key(key), in: container, debugDescription: "“\(key)” \(message)")
    }

    func value<T: Decodable>(_ key: String) throws -> T {
        try container.decode(T.self, forKey: Key(key))
    }

    func string(_ key: String, maxLength: Int) throws -> String {
        let text: String = try value(key)
        guard text.count <= maxLength else { throw invalid(key, "is over \(maxLength) characters") }
        return text
    }

    /// A number above 0 and at most 1.
    func fraction(_ key: String) throws -> Double {
        let v: Double = try value(key)
        guard v > 0 && v <= 1 else { throw invalid(key, "is \(v), but must be above 0 and at most 1") }
        return v
    }

    func number(_ key: String, in range: ClosedRange<Double>) throws -> Double {
        let v: Double = try value(key)
        guard range.contains(v) else { throw invalid(key, "is \(v), outside \(range.lowerBound) to \(range.upperBound)") }
        return v
    }

    func numbers(_ key: String, count: Int, in range: ClosedRange<Double>) throws -> [Double] {
        let list: [Double] = try value(key)
        guard list.count == count, list.allSatisfy(range.contains) else {
            throw invalid(key, "must be \(count) numbers from \(range.lowerBound) to \(range.upperBound)")
        }
        return list
    }

    func integer(_ key: String, in range: ClosedRange<Int>) throws -> Int {
        let v: Int = try value(key)
        guard range.contains(v) else { throw invalid(key, "is \(v), outside \(range.lowerBound) to \(range.upperBound)") }
        return v
    }
}
