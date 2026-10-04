import Foundation
import PaintCore

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
