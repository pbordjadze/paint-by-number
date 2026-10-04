import Dispatch
import Foundation

/// Lightweight data-parallel helpers used throughout the pipeline.
///
/// The pipeline works on large flat buffers; the fastest portable way to spread that
/// work across performance cores is `concurrentPerform` over contiguous bands, which
/// keeps each worker streaming through its own cache lines.
///
/// Bands follow the core count (`bandCount`), so their boundaries differ between devices: use
/// `forEachBand` and `mapBands` where each index writes its own output or the per-band results
/// combine exactly (concatenated in band order, integer sums, max); never sum floating point
/// per band. For a floating-point reduction use `forEachChunk` with a fixed chunk size and add
/// the per-chunk results in chunk order (`RegionAdjacency.boundarySteps`,
/// `AutoSettings.colorError`), or compute each output whole in one task in a fixed order
/// (`RegionRuns.accumulate`: a region's pixels in raster order). `mapChunks` is `forEachChunk`
/// returning one result per chunk, in chunk order, for work whose cost per index is very
/// uneven (the vectorizer's regions and edges).
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

    /// `forEachBand` in consecutive waves of at most `wave` indices with a cancellation check
    /// between waves. Checks only see task cancellation on the calling thread, so long passes
    /// are split this way to stay responsive; the caller sizes a wave by how heavy an index is
    /// (`wavePixels` and `waveRows` for simple per-pixel work).
    @inlinable
    public static func forEachBand(
        _ count: Int,
        minimumBandSize: Int = 1,
        wave: Int,
        cancel: CancellationCheck,
        _ body: (Range<Int>) -> Void
    ) throws {
        var start = 0
        while start < count {
            let end = min(count, start + max(1, wave))
            forEachBand(end - start, minimumBandSize: minimumBandSize) { range in
                body((range.lowerBound + start)..<(range.upperBound + start))
            }
            start = end
            if start < count { try cancel.throwIfCancelled() }
        }
    }

    /// Pixels per cancellation wave: a few milliseconds of simple per-pixel work.
    public static let wavePixels = 300_000

    /// Rows per cancellation wave for images of the given width.
    @inlinable
    public static func waveRows(width: Int) -> Int { max(8, wavePixels / max(width, 1)) }

    /// Runs `body` over chunks of `chunk` consecutive indices covering `0..<count`, handed
    /// out dynamically, for work whose cost per index is very uneven.
    @inlinable
    public static func forEachChunk(_ count: Int, chunk: Int, _ body: (Range<Int>) -> Void) {
        guard count > 0 else { return }
        let size = max(1, chunk)
        let chunks = (count + size - 1) / size
        if chunks == 1 {
            body(0..<count)
            return
        }
        withoutActuallyEscaping(body) { body in
            let work = UncheckedSendable(body)
            DispatchQueue.concurrentPerform(iterations: chunks) { c in
                work.value((c * size)..<min(count, (c + 1) * size))
            }
        }
    }

    /// Parallel map over `0..<count` in chunks of `chunk`, scheduled dynamically; results
    /// in chunk order. With `cost` (per item), the most expensive chunks start first so a
    /// huge item late in the list does not leave the other workers idle at the end.
    static func mapChunks<T>(_ count: Int, chunk: Int, cost: ((Int) -> Int)? = nil, _ body: (Range<Int>) -> T) -> [T] {
        guard count > 0 else { return [] }
        let n = (count + chunk - 1) / chunk
        var order = Array(0..<n)
        if let cost {
            let chunkCost = (0..<n).map { c in ((c * chunk)..<min(count, (c + 1) * chunk)).reduce(0) { $0 + cost($1) } }
            order.sort { chunkCost[$0] != chunkCost[$1] ? chunkCost[$0] > chunkCost[$1] : $0 < $1 }
        }
        var results = [T?](repeating: nil, count: n)
        results.withUnsafeMutableBufferPointer { buf in
            order.withUnsafeBufferPointer { ob in
                let out = UncheckedSendable(buf.baseAddress!)
                let sequence = UncheckedSendable(ob.baseAddress!)
                withoutActuallyEscaping(body) { body in
                    let work = UncheckedSendable(body)
                    DispatchQueue.concurrentPerform(iterations: n) { k in
                        let i = sequence.value[k]
                        out.value[i] = work.value((i * chunk)..<min(count, (i + 1) * chunk))
                    }
                }
            }
        }
        return results.map { $0! }
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
    public let value: Value
    @inlinable public init(_ value: Value) { self.value = value }
}

/// Cooperative cancellation hook for long-running pipeline stages.
public struct CancellationCheck: Sendable {
    private let check: @Sendable () -> Bool

    public init(_ check: @escaping @Sendable () -> Bool) { self.check = check }

    /// Never cancels.
    public static let none = CancellationCheck { false }

    /// Cancels when the current Swift concurrency task is cancelled. It reads `Task.isCancelled`
    /// of the calling thread, so inside a `forEachBand`, `mapBands` or `forEachChunk` body it is
    /// seen only on the calling thread's share of the work: check between waves
    /// (`forEachBand(wave:cancel:)`), or share a `CancellationFlag` between the threads.
    public static let task = CancellationCheck { Task.isCancelled }

    public var isCancelled: Bool { check() }

    public func throwIfCancelled() throws {
        if check() { throw CancellationError() }
    }
}

/// A one-way latch every thread can set and read: a task's cancellation shows only on the thread
/// running it, so work spread over several threads shares one, set from a
/// `withTaskCancellationHandler` or by the first check that sees the cancellation
/// (`AutoSettings.choose`).
public final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    public init() {}

    public var isSet: Bool { lock.withLock { cancelled } }

    /// Sets the flag; returns true so it can end a check expression.
    @discardableResult
    public func set() -> Bool {
        lock.withLock { cancelled = true }
        return true
    }
}
