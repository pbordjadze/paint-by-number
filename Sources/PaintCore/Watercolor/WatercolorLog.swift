#if canImport(FoundationEssentials) && !canImport(Darwin)
import FoundationEssentials
#else
import Foundation
#endif

/// A watercolor painting as its painter made it (painting-company row 373): the painting's seed
/// and every tap, where, when (the simulation's step) and whether it carried paint. Replayed by
/// `WatercolorSim.replay` it makes the painting again, so this is what is saved
/// (`watercolor.json` beside the template), and it is also the painting's time-lapse. Read as
/// hostile input: a tap of no area, off the canvas or out of order is left out, never trusted.
public struct WatercolorLog: Codable, Sendable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    public var seed: UInt64
    public var taps: [Tap]

    public struct Tap: Codable, Sendable, Equatable {
        public var step: Int
        public var region: Int
        /// Where the finger touched, canvas units.
        public var x: Float
        public var y: Float
        /// The area's own paint (false: water alone, a bloom).
        public var paint: Bool

        public init(step: Int, region: Int, x: Float, y: Float, paint: Bool) {
            self.step = step
            self.region = region
            self.x = x
            self.y = y
            self.paint = paint
        }
    }

    public enum CodingError: Error, Equatable {
        case newerVersion(Int)
    }

    public init(seed: UInt64, taps: [Tap] = []) {
        version = Self.currentVersion
        self.seed = seed
        self.taps = taps
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    /// The log in `data`, its taps checked against a template of `regions` areas and
    /// `width` × `height` canvas units: what doesn't fit is dropped. A newer version throws.
    public init(encoded data: Data, regions: Int, width: Int, height: Int) throws {
        // The version first: a newer app's log may not decode as this one's, and must never be
        // taken for a damaged one (which the app would begin again and write over).
        struct Versioned: Decodable { var version: Int }
        let found = try JSONDecoder().decode(Versioned.self, from: data).version
        guard found <= Self.currentVersion else { throw CodingError.newerVersion(found) }
        let read = try JSONDecoder().decode(WatercolorLog.self, from: data)
        version = read.version
        seed = read.seed
        var step = 0
        taps = read.taps.filter { tap in
            guard tap.region >= 0, tap.region < regions, tap.step >= step, tap.step < Int(Int32.max),
                  tap.x.isFinite, tap.y.isFinite, tap.x >= 0, tap.y >= 0, tap.x <= Float(width), tap.y <= Float(height)
            else { return false }
            step = tap.step
            return true
        }
    }
}
