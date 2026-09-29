import Foundation

/// Persistent painting state of one artwork: which regions are painted, and in what order
/// (the log drives the time-lapse replay).
nonisolated struct PaintProgress: Sendable, Equatable {
    struct Stroke: Sendable, Equatable {
        var region: UInt32
        /// Seconds of active painting time when the region was filled.
        var time: Float
    }

    private(set) var painted: [Bool]
    private(set) var log: [Stroke] = []
    /// Accumulated active painting time.
    var activeSeconds: Double = 0

    init(regionCount: Int) {
        painted = [Bool](repeating: false, count: regionCount)
    }

    var regionCount: Int { painted.count }
    var paintedCount: Int { log.count }
    var isComplete: Bool { !painted.isEmpty && log.count == painted.count }

    func isPainted(_ region: Int) -> Bool { painted[region] }

    /// Marks a region painted; returns false if it already was.
    @discardableResult
    mutating func paint(_ region: Int) -> Bool {
        guard !painted[region] else { return false }
        painted[region] = true
        log.append(Stroke(region: UInt32(region), time: Float(activeSeconds)))
        return true
    }

    /// Reverts the most recent fill.
    mutating func undo() -> Int? {
        guard let last = log.popLast() else { return nil }
        painted[Int(last.region)] = false
        return Int(last.region)
    }

    mutating func reset() {
        painted = [Bool](repeating: false, count: painted.count)
        log.removeAll()
        activeSeconds = 0
    }

    // MARK: Coding (compact binary: header, painting time, stroke log)

    private static let magic: UInt32 = 0x5250_4250  // "PBPR"

    func encoded() -> Data {
        var data = Data()
        func put<T: BitwiseCopyable>(_ v: T) { withUnsafeBytes(of: v) { data.append(contentsOf: $0) } }
        put(Self.magic)
        put(UInt32(1))
        put(UInt32(painted.count))
        put(activeSeconds)
        put(UInt32(log.count))
        for s in log { put(s.region); put(s.time) }
        return data
    }

    init(encoded data: Data) throws {
        struct Corrupt: Error {}
        var offset = data.startIndex
        func get<T: BitwiseCopyable>(_: T.Type) throws -> T {
            let size = MemoryLayout<T>.size
            guard offset + size <= data.endIndex else { throw Corrupt() }
            let v = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset - data.startIndex, as: T.self) }
            offset += size
            return v
        }
        guard try get(UInt32.self) == Self.magic, try get(UInt32.self) == 1 else { throw Corrupt() }
        let count = Int(try get(UInt32.self))
        self.init(regionCount: count)
        activeSeconds = try get(Double.self)
        let strokes = Int(try get(UInt32.self))
        guard strokes <= count else { throw Corrupt() }
        log.reserveCapacity(strokes)
        for _ in 0..<strokes {
            let region = try get(UInt32.self)
            let time = try get(Float.self)
            guard Int(region) < count, !painted[Int(region)] else { throw Corrupt() }
            painted[Int(region)] = true
            log.append(Stroke(region: region, time: time))
        }
    }
}
