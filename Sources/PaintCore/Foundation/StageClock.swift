import Foundation

/// Records wall-clock timings of pipeline stages. Sub-stages use dotted names
/// ("segment.smooth") so reports can nest them; only top-level names count toward totals.
public final class StageClock: @unchecked Sendable {
    public struct Timing: Sendable, CustomStringConvertible {
        public var name: String
        public var seconds: Double
        /// When the stage began, in seconds since the clock was created.
        public var start: Double = 0
        public var description: String { "\(name): \(String(format: "%.1f", seconds * 1000)) ms" }
    }

    private let lock = NSLock()
    private var _timings: [Timing] = []
    private let clock = ContinuousClock()
    private let origin: ContinuousClock.Instant

    public init() { origin = clock.now }

    public var timings: [Timing] { lock.withLock { _timings } }

    @discardableResult
    public func measure<T>(_ name: String, _ body: () throws -> T) rethrows -> T {
        let start = clock.now
        defer {
            @inline(__always) func seconds(_ d: Duration) -> Double {
                Double(d.components.seconds) + Double(d.components.attoseconds) * 1e-18
            }
            let timing = Timing(name: name, seconds: seconds(clock.now - start), start: seconds(start - origin))
            lock.withLock { _timings.append(timing) }
        }
        return try body()
    }
}
