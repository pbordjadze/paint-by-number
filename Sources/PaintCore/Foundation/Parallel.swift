import Dispatch
import Foundation

/// Lightweight data-parallel helpers used throughout the pipeline.
///
/// The pipeline works on large flat buffers; the fastest portable way to spread that
/// work across performance cores is `concurrentPerform` over contiguous bands, which
/// keeps each worker streaming through its own cache lines.
public enum Parallel {
    /// Number of worker bands to split work into. Oversubscribes slightly so that
    /// uneven bands (and efficiency cores) balance out.
    public static var bandCount: Int {
        max(1, ProcessInfo.processInfo.activeProcessorCount * 2)
    }

    /// Runs `body(range)` over disjoint sub-ranges covering `0..<count`, in parallel.
    /// Falls back to a single serial call for small workloads.
    @inlinable
    public static func forEachBand(
        _ count: Int,
        minimumBandSize: Int = 1,
        _ body: (Range<Int>) -> Void
    ) {
        guard count > 0 else { return }
        let bands = min(bandCount, max(1, count / max(1, minimumBandSize)))
        if bands <= 1 {
            body(0..<count)
            return
        }
        let size = (count + bands - 1) / bands
        withoutActuallyEscaping(body) { body in
            let work = UncheckedSendable(body)
            DispatchQueue.concurrentPerform(iterations: bands) { band in
                let start = band * size
                let end = min(count, start + size)
                if start < end { work.value(start..<end) }
            }
        }
    }

    /// Parallel map over `0..<count` producing one result per band, in band order.
    @inlinable
    public static func mapBands<T>(
        _ count: Int,
        minimumBandSize: Int = 1,
        _ body: (Range<Int>) -> T
    ) -> [T] {
        guard count > 0 else { return [] }
        let bands = min(bandCount, max(1, count / max(1, minimumBandSize)))
        let size = (count + bands - 1) / bands
        let actualBands = (count + size - 1) / size
        var results = [T?](repeating: nil, count: actualBands)
        results.withUnsafeMutableBufferPointer { out in
            let outBase = UncheckedSendable(out.baseAddress!)
            withoutActuallyEscaping(body) { body in
                let work = UncheckedSendable(body)
                DispatchQueue.concurrentPerform(iterations: actualBands) { band in
                    let start = band * size
                    let end = min(count, start + size)
                    outBase.value[band] = work.value(start..<end)
                }
            }
        }
        return results.map { $0! }
    }
}

/// Wraps a non-Sendable value (typically a raw pointer into a buffer whose disjoint
/// regions are written by different workers) so it can cross into concurrent closures.
/// Callers are responsible for guaranteeing data-race freedom.
public struct UncheckedSendable<Value>: @unchecked Sendable {
    public var value: Value
    @inlinable public init(_ value: Value) { self.value = value }
}

/// Cooperative cancellation hook for long-running pipeline stages.
public struct CancellationCheck: Sendable {
    private let check: @Sendable () -> Bool

    public init(_ check: @escaping @Sendable () -> Bool) { self.check = check }

    /// Never cancels.
    public static let none = CancellationCheck { false }

    /// Cancels when the current Swift concurrency task is cancelled.
    public static let task = CancellationCheck { Task.isCancelled }

    public var isCancelled: Bool { check() }

    public func throwIfCancelled() throws {
        if check() { throw CancellationError() }
    }
}
