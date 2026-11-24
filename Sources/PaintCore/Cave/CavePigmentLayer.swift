#if canImport(FoundationEssentials) && !canImport(Darwin)
import FoundationEssentials
#else
import Foundation
#endif

/// The pigment blown onto one bay of the cave wall (painting-company row 371), a pixel a wall
/// point: how thickly it lies (`coverage`, up to a little over 1) and its color. Blowing is
/// target-solved, so there are no wrong taps: pigment lands where it belongs, fully in an area of
/// the pigment in hand, a dusting on the rest of the animal, almost nothing on the bare rock
/// round it. An area half covered is done, and fills the rest of itself over a second in the
/// rock's grain, darker toward its edges and thinner on its crown, as the painters modelled a
/// flank. Once every area is done a hand pressed flat to the glass is blown round in red ochre,
/// its stencil left beside the painting (`CaveHand`).
///
/// Everything is a pure function of the plan and what was blown: the grain is the rock's own
/// (`CaveNoise`), so a painting restored from its progress settles the same way.
public struct CavePigmentLayer: Sendable {
    public static let width = CaveWall.bayWidth
    public static let height = CaveWall.height

    public let plan: CavePlan
    /// Per pixel: how thickly pigment lies, 0 to 1.15.
    public private(set) var coverage: [Float]
    /// Per pixel: its color, display-encoded RGB.
    public private(set) var color: [SIMD3<Float>]
    /// Per area (entry `k - 1` for area `k`): is it done, and how far it has settled (0 to 1).
    public private(set) var done: [Bool]
    public private(set) var settled: [Float]
    /// The hand stencilled beside the finished painting, once it is.
    public private(set) var hand: CaveHand?
    /// The pixels changed since the last `takeChanges()`: min x, min y, max x, max y.
    public private(set) var changed: (minX: Int, minY: Int, maxX: Int, maxY: Int)?

    /// Per pixel: its area, 0 off the painting.
    let area: [UInt16]
    /// Per pixel: how deep in its area, 0 at the edge to 1 at its middle.
    let depth: [Float]
    /// Per area: its pixels, and how many are covered over half with its own pigment.
    let pixels: [[Int32]]
    private(set) var covered: [Int]
    /// The hand's shape while it is stencilled, made once.
    private var stencilShape: CaveHand.Shape?

    public init(plan: CavePlan) {
        self.plan = plan
        let w = Self.width, h = Self.height, n = w * h, s = CaveWall.scale
        let origin = plan.origin
        let ox = Int(origin.x), oy = Int(origin.y)
        var area = [UInt16](repeating: 0, count: n)
        let labels = RegionMap(width: plan.width, height: plan.height, storage: plan.areas.map { UInt32($0) })
        let inside = DistanceTransform.interiorDistance(labels: labels)
        var deepest = [Float](repeating: 1, count: plan.areaCount + 1)
        for i in 0..<(plan.width * plan.height) where plan.areas[i] > 0 {
            deepest[Int(plan.areas[i])] = max(deepest[Int(plan.areas[i])], inside.storage[i])
        }
        var depth = [Float](repeating: 0, count: n)
        var pixels = [[Int32]](repeating: [], count: plan.areaCount)
        for y in 0..<(plan.height / s) where oy + y >= 0 && oy + y < h {
            for x in 0..<(plan.width / s) where ox + x >= 0 && ox + x < w {
                let p = (y * s + s / 2) * plan.width + x * s + s / 2
                let a = plan.areas[p]
                guard a > 0 else { continue }
                let i = (oy + y) * w + ox + x
                area[i] = a
                depth[i] = min(1, inside.storage[p] / deepest[Int(a)])
                pixels[Int(a) - 1].append(Int32(i))
            }
        }
        self.area = area
        self.depth = depth
        self.pixels = pixels
        coverage = [Float](repeating: 0, count: n)
        color = [SIMD3<Float>](repeating: .zero, count: n)
        // An area with no pixel in the bay (only a damaged plan has one) could never be blown:
        // it is done from the start, so the painting can still be finished.
        done = pixels.map(\.isEmpty)
        settled = pixels.map { $0.isEmpty ? 1 : 0 }
        covered = [Int](repeating: 0, count: plan.areaCount)
    }

    public var doneCount: Int { done.reduce(0) { $0 + ($1 ? 1 : 0) } }
    public var isFinished: Bool { !done.contains(false) }
    /// Whether a finished area is still filling itself in.
    public var isSettling: Bool { zip(done, settled).contains { $0 && $1 < 1 } }

    /// The area under a point of the bay (wall points), or nil.
    public func area(at p: SIMD2<Float>) -> Int? {
        let x = Int(p.x), y = Int(p.y)
        guard x >= 0, y >= 0, x < Self.width, y < Self.height else { return nil }
        let a = Int(area[y * Self.width + x])
        return a > 0 ? a : nil
    }

    /// The middle of an area not yet done, of `pigment` if one is, for VoiceOver's blow and a
    /// demo's painter: its pixel farthest from its edge, in bay points.
    public func middle(of a: Int) -> SIMD2<Float>? {
        guard a >= 1, a <= pixels.count, let best = pixels[a - 1].max(by: { depth[Int($0)] < depth[Int($1)] }) else { return nil }
        return SIMD2(Float(Int(best) % Self.width) + 0.5, Float(Int(best) / Self.width) + 0.5)
    }

    /// The first area not done, of `pigment` if one is left, else of any.
    public func nextArea(of pigment: CavePigment?) -> Int? {
        let open = (1...max(1, plan.areaCount)).filter { $0 <= done.count && !done[$0 - 1] }
        return open.first { plan.pigments[$0 - 1] == pigment } ?? open.first
    }

    /// The pixels of an area, for a painter played by a demo.
    public func points(of a: Int) -> [SIMD2<Float>] {
        guard a >= 1, a <= pixels.count else { return [] }
        return pixels[a - 1].map { SIMD2(Float(Int($0) % Self.width) + 0.5, Float(Int($0) / Self.width) + 0.5) }
    }

    // MARK: - Blowing

    /// Blows `pigment` at a point of the bay (wall points) over a spray `radius` points wide,
    /// `amount` of it (about 0.055 a sixtieth of a second held). Returns the areas it finished.
    @discardableResult
    public mutating func blow(at p: SIMD2<Float>, radius: Float, amount: Float, pigment: CavePigment) -> [Int] {
        let w = Self.width, h = Self.height
        let reach = radius * 2.2
        let x0 = max(0, Int(p.x - reach)), x1 = min(w - 1, Int(p.x + reach))
        let y0 = max(0, Int(p.y - reach)), y1 = min(h - 1, Int(p.y + reach))
        guard x0 <= x1, y0 <= y1, radius > 0 else { return [] }
        let tint = pigment.rgb
        var touched: Set<Int> = []
        for y in y0...y1 {
            for x in x0...x1 {
                let dx = Float(x) + 0.5 - p.x, dy = Float(y) + 0.5 - p.y
                let g = exp(-(dx * dx + dy * dy) / (2 * radius * radius))
                guard g >= 0.01 else { continue }
                let i = y * w + x
                let a = Int(area[i])
                let matches = a > 0 && plan.pigments[a - 1] == pigment
                let fit: Float = a == 0 ? 0 : matches ? (done[a - 1] ? 0.9 : 1) : 0.015
                let add = amount * g * fit * Self.grain(x, y)
                guard add > 0 else { continue }
                let c0 = coverage[i], c1 = min(1.15, c0 + add), t = add / (c0 + add)
                color[i] += (tint - color[i]) * t
                coverage[i] = c1
                if matches && c0 < 0.45 && c1 >= 0.45 {
                    covered[a - 1] += 1
                    touched.insert(a)
                }
            }
        }
        mark(x0, y0, x1, y1)
        var finished: [Int] = []
        for a in touched.sorted() where !done[a - 1] && covered[a - 1] * 2 > pixels[a - 1].count {
            done[a - 1] = true
            finished.append(a)
        }
        return finished
    }

    /// Lets each finished area fill the rest of itself, `seconds` further on.
    public mutating func settle(seconds: Float) {
        for a in 1...max(1, plan.areaCount) where a <= done.count && done[a - 1] && settled[a - 1] < 1 {
            settled[a - 1] = min(1, settled[a - 1] + seconds / 0.9)
            fill(a, to: settled[a - 1])
        }
    }

    /// Marks every area done and settled at once (a painting restored without its pigment, a
    /// demo's).
    public mutating func finishAll() {
        for a in 1...max(1, plan.areaCount) where a <= done.count {
            done[a - 1] = true
            settled[a - 1] = 1
            fill(a, to: 1)
        }
    }

    private mutating func fill(_ a: Int, to k: Float) {
        let tint = plan.pigments[a - 1].rgb
        var box = (Int.max, Int.max, -1, -1)
        for p in pixels[a - 1] {
            let i = Int(p), x = i % Self.width, y = i / Self.width
            let edge = min(1, depth[i] * 1.8)
            let target = (1 - 0.42 * edge + 0.18 * Self.grain(x, y) + 0.12 * (Self.breath(Float(x), Float(y)) - 0.5)) * k
            guard coverage[i] < target else { continue }
            let add = target - coverage[i], t = add / max(1e-6, coverage[i] + add)
            color[i] += (tint - color[i]) * t
            coverage[i] = target
            box = (min(box.0, x), min(box.1, y), max(box.2, x), max(box.3, y))
        }
        if box.2 >= 0 { mark(box.0, box.1, box.2, box.3) }
    }

    // MARK: - The hand

    /// Blows red ochre round a hand, `k` of the way (0 to 1). The first call keeps the hand.
    public mutating func stencil(_ hand: CaveHand, amount k: Float) {
        if stencilShape == nil || self.hand != hand { stencilShape = hand.shape() }
        self.hand = hand
        guard let shape = stencilShape else { return }
        let w = Self.width, h = Self.height
        let tint = CavePigment.redOchre.rgb * SIMD3(1.05, 1, 1)
        let box = shape.box
        let x0 = max(0, box.minX), x1 = min(w - 1, box.maxX), y0 = max(0, box.minY), y1 = min(h - 1, box.maxY)
        guard x0 <= x1, y0 <= y1 else { return }
        for y in y0...y1 {
            for x in x0...x1 {
                guard !shape.covers(x, y) else { continue }
                let i = y * w + x
                let d = ((Float(x) - shape.centre.x) * (Float(x) - shape.centre.x)
                    + (Float(y) - shape.centre.y) * (Float(y) - shape.centre.y) / 1.44).squareRoot()
                let reach = 80 + 40 * Self.breath(Float(x) + 300, Float(y))
                let g = min(1, exp(-pow(d / reach, 2.4)) + shape.nearness(x, y) * 0.5)
                let target = g * min(1, k * 1.3 - (1 - Self.breath(Float(x), Float(y))) * 0.3) * (0.45 + 0.75 * Self.grain(x, y))
                guard target > coverage[i] else { continue }
                let add = target - coverage[i], t = add / max(1e-6, coverage[i] + add)
                color[i] += (tint - color[i]) * t
                coverage[i] = target
            }
        }
        mark(x0, y0, x1, y1)
    }

    // MARK: - Changes and saving

    private mutating func mark(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) {
        if let c = changed {
            changed = (min(c.minX, x0), min(c.minY, y0), max(c.maxX, x1), max(c.maxY, y1))
        } else {
            changed = (x0, y0, x1, y1)
        }
    }

    /// The changed rectangle since the last call, cleared.
    public mutating func takeChanges() -> (minX: Int, minY: Int, maxX: Int, maxY: Int)? {
        defer { changed = nil }
        return changed
    }

    /// RGBA8 of a rectangle (all of it by default): the color, and the coverage in alpha.
    public func rgba(minX: Int = 0, minY: Int = 0, maxX: Int = width - 1, maxY: Int = height - 1) -> [UInt8] {
        let rw = maxX - minX + 1, rh = maxY - minY + 1
        var out = [UInt8](repeating: 0, count: max(0, rw * rh * 4))
        guard rw > 0, rh > 0 else { return out }
        for y in 0..<rh {
            for x in 0..<rw {
                let i = (minY + y) * Self.width + minX + x, o = (y * rw + x) * 4
                out[o] = CaveBay.byte(color[i].x)
                out[o + 1] = CaveBay.byte(color[i].y)
                out[o + 2] = CaveBay.byte(color[i].z)
                out[o + 3] = CaveBay.byte(min(1, coverage[i]))
            }
        }
        return out
    }

    /// Restores pigment saved as `rgba()` with its progress: which areas were done (settled at
    /// once) and the hand. Pigment that doesn't fit the bay is left out, never misread: the done
    /// areas are filled again and the hand stencilled again instead.
    public mutating func restore(rgba: [UInt8]?, progress: CaveProgress) {
        if let rgba, rgba.count == Self.width * Self.height * 4 {
            for i in 0..<(Self.width * Self.height) {
                coverage[i] = Float(rgba[i * 4 + 3]) / 255
                color[i] = SIMD3(Float(rgba[i * 4]), Float(rgba[i * 4 + 1]), Float(rgba[i * 4 + 2])) / 255
                let a = Int(area[i])
                if a > 0 && coverage[i] >= 0.45 { covered[a - 1] += 1 }
            }
        }
        for a in 1...max(1, plan.areaCount) where a <= done.count && a <= progress.done.count && progress.done[a - 1] {
            done[a - 1] = true
            settled[a - 1] = 1
            fill(a, to: 1)
        }
        if let hand = progress.hand { stencil(hand, amount: 1) }
        changed = (0, 0, Self.width - 1, Self.height - 1)
    }

    /// The progress to save beside the pigment.
    public var progress: CaveProgress { CaveProgress(done: done, hand: hand) }

    // MARK: - The rock's grain

    /// How much pigment the rock takes here, 0.35 to 1: its pores.
    @inline(__always) static func grain(_ x: Int, _ y: Int) -> Float {
        0.35 + 0.65 * CaveNoise.unit(Int32(x), Int32(y), 501) * CaveNoise.unit(Int32(x), Int32(y), 502)
    }

    /// Coarse waves, so a spray thins and thickens like breath (0 to 1).
    @inline(__always) static func breath(_ x: Float, _ y: Float) -> Float {
        let s = sin(x * 0.061 + sin(y * 0.043) * 2) + sin(y * 0.057 + sin(x * 0.039) * 2.3) + sin((x + y) * 0.029)
        return 0.5 + s / 6
    }
}

/// A hand pressed flat to the glass: each fingertip's place in the bay (wall points) and how wide
/// its touch was. Five fingers make a hand; four do too (a thumb kept back).
public struct CaveHand: Sendable, Equatable {
    public var fingers: [SIMD2<Float>]
    public var widths: [Float]

    public init(fingers: [SIMD2<Float>], widths: [Float]) {
        self.fingers = fingers
        self.widths = widths.count == fingers.count ? widths : Array(repeating: 9, count: fingers.count)
    }

    /// The hand's shape on the rock: the palm a rounded block below the fingertips, each finger a
    /// tapering bar from the palm to its tip, a thumb (the lowest finger at either side) shorter
    /// and wider, and the wrist and a short forearm below it.
    struct Shape: Sendable {
        let centre: SIMD2<Float>
        let box: (minX: Int, minY: Int, maxX: Int, maxY: Int)
        private let palm: SIMD2<Float>
        private let bars: [(base: SIMD2<Float>, tip: SIMD2<Float>, w0: Float, w1: Float)]
        private var cells: [Bool] = []

        init(_ hand: CaveHand) {
            let tips = hand.fingers.isEmpty ? [SIMD2<Float>(0, 0)] : hand.fingers
            let mean = tips.reduce(.zero, +) / Float(tips.count)
            let palm = mean + SIMD2(0, 60)
            let order = tips.indices.sorted { tips[$0].x < tips[$1].x }
            let typical = hand.widths.isEmpty ? 9 : hand.widths.reduce(0, +) / Float(hand.widths.count)
            var bars: [(SIMD2<Float>, SIMD2<Float>, Float, Float)] = []
            for (rank, k) in order.enumerated() {
                let tip = tips[k]
                let isThumb = (rank == 0 || rank == order.count - 1) && tip.y > mean.y + 10
                let reach: Float = isThumb ? 0.25 : 0.42
                let base = palm + (tip - palm) * reach
                let scale = min(1.25, max(0.8, (k < hand.widths.count ? hand.widths[k] : typical) / max(1, typical)))
                let middle = abs(Float(rank) - Float(order.count - 1) / 2)
                bars.append((base, tip, (isThumb ? 9.5 : 7.8 - middle * 0.4) * scale, (isThumb ? 6 : 4.6) * scale))
            }
            self.palm = palm
            self.bars = bars
            centre = mean + SIMD2(0, 30)
            box = (Int(centre.x - 220), Int(centre.y - 230), Int(centre.x + 220), Int(centre.y + 240))
            let bw = box.maxX - box.minX + 1, bh = box.maxY - box.minY + 1
            var cells = [Bool](repeating: false, count: bw * bh)
            for y in 0..<bh {
                for x in 0..<bw { cells[y * bw + x] = Self.inside(SIMD2(Float(box.minX + x), Float(box.minY + y)), palm: palm, bars: bars) }
            }
            self.cells = cells
        }

        private static func inside(_ p: SIMD2<Float>, palm: SIMD2<Float>, bars: [(base: SIMD2<Float>, tip: SIMD2<Float>, w0: Float, w1: Float)]) -> Bool {
            let px = p.x - palm.x, py = p.y - palm.y
            let half = 33 - max(0, py) * 0.18
            if abs(px) < half && py > -30 && py < 34 {
                let cx = max(0, abs(px) - half + 12), cy = max(0, max(py - 22, -30 - py + 12))
                if cx * cx + cy * cy < 144 { return true }
            }
            if py >= 20 && py < 120 && abs(px - py * 0.08) < 25 + py * 0.03 { return true }
            for b in bars {
                let v = b.tip - b.base, l2 = max(1e-3, (v * v).sum())
                let t0 = ((p - b.base) * v).sum() / l2
                guard t0 >= 0, t0 <= 1.08 else { continue }
                let t = min(1, t0)
                let q = b.base + v * t - p, w = b.w0 + (b.w1 - b.w0) * t
                if (q * q).sum() < w * w { return true }
            }
            return false
        }

        func covers(_ x: Int, _ y: Int) -> Bool {
            let bw = box.maxX - box.minX + 1
            let cx = x - box.minX, cy = y - box.minY
            guard cx >= 0, cy >= 0, cx < bw, cy <= box.maxY - box.minY else { return false }
            return cells[cy * bw + cx]
        }

        /// How much of the hand lies close round a point: spray gathers thickest at its edge.
        func nearness(_ x: Int, _ y: Int) -> Float {
            var n: Float = 0
            for (dx, dy) in [(5, 0), (-5, 0), (0, 5), (0, -5), (9, 0), (-9, 0), (0, 9), (0, -9)] where covers(x + dx, y + dy) { n += 0.125 }
            return n
        }
    }

    func shape() -> Shape { Shape(self) }

    /// A right hand spread flat, thumb at the left, its fingertips round `spot`: the hand waited
    /// for, and VoiceOver's.
    public static func spread(at spot: SIMD2<Float>) -> CaveHand {
        CaveHand(fingers: [spot + SIMD2(-54, 40), spot + SIMD2(-30, -18), spot + SIMD2(-4, -32), spot + SIMD2(22, -22), spot + SIMD2(42, 4)],
                 widths: [11, 9, 9, 9, 8])
    }

    /// A few grains of ochre already round where a hand would go, once a painting is finished: the
    /// only sign that the rock is waiting for one.
    public static func grains(at spot: SIMD2<Float>) -> [SIMD2<Float>] {
        let shape = spread(at: spot).shape()
        var out: [SIMD2<Float>] = []
        for y in stride(from: Int(spot.y) - 70, to: Int(spot.y) + 120, by: 3) {
            for x in stride(from: Int(spot.x) - 110, to: Int(spot.x) + 110, by: 3) {
                guard !shape.covers(x, y) else { continue }
                let near = [(4, 0), (-4, 0), (0, 4), (0, -4)].contains { shape.covers(x + $0.0, y + $0.1) }
                if near && CaveNoise.unit(Int32(x), Int32(y), 503) > 0.55 { out.append(SIMD2(Float(x), Float(y))) }
            }
        }
        return out
    }
}

/// What a cave painting keeps beside its pigment: which areas are done and the hand stencilled
/// once it was finished. `progress.bin` is read as hostile input: magic `PBCP`, a format version,
/// the area count and a byte an area, then the count of fingers and each one's place and width
/// (three `Float32`). Fields are only ever appended (readers ignore trailing bytes); bump
/// `formatVersion` only when one changes meaning.
public struct CaveProgress: Sendable, Equatable {
    public static let magic: UInt32 = 0x5043_4250 // "PBCP", little-endian
    public static let formatVersion: UInt32 = 1
    public static let maxFingers = 10

    public enum CodingError: Error, Equatable {
        case corrupt
        case newerVersion(UInt32)
        /// The file is for a painting with another number of areas.
        case otherPainting
    }

    public var done: [Bool]
    public var hand: CaveHand?

    public init(done: [Bool], hand: CaveHand? = nil) {
        self.done = done
        self.hand = hand
    }

    public func encoded() -> Data {
        var data = Data()
        func put<T: BitwiseCopyable>(_ v: T) { withUnsafeBytes(of: v) { data.append(contentsOf: $0) } }
        put(Self.magic)
        put(Self.formatVersion)
        put(UInt32(done.count))
        for d in done { put(UInt8(d ? 1 : 0)) }
        let fingers = hand?.fingers ?? []
        put(UInt32(min(fingers.count, Self.maxFingers)))
        for (k, f) in fingers.prefix(Self.maxFingers).enumerated() {
            put(f.x)
            put(f.y)
            put(hand?.widths[k] ?? 9)
        }
        return data
    }

    public init(encoded data: Data, areas: Int) throws {
        var offset = data.startIndex
        func get<T: BitwiseCopyable>(_: T.Type) throws -> T {
            let size = MemoryLayout<T>.size
            guard size <= data.endIndex - offset else { throw CodingError.corrupt }
            let v = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset - data.startIndex, as: T.self) }
            offset += size
            return v
        }
        guard try get(UInt32.self) == Self.magic else { throw CodingError.corrupt }
        let version = try get(UInt32.self)
        guard version != 0 else { throw CodingError.corrupt }
        guard version <= Self.formatVersion else { throw CodingError.newerVersion(version) }
        let count = Int(try get(UInt32.self))
        guard count <= data.endIndex - offset else { throw CodingError.corrupt }
        guard count == areas else { throw CodingError.otherPainting }
        var done = [Bool]()
        done.reserveCapacity(count)
        for _ in 0..<count {
            let b = try get(UInt8.self)
            guard b <= 1 else { throw CodingError.corrupt }
            done.append(b == 1)
        }
        let fingers = Int(try get(UInt32.self))
        guard fingers <= Self.maxFingers else { throw CodingError.corrupt }
        var places: [SIMD2<Float>] = [], widths: [Float] = []
        for _ in 0..<fingers {
            let x = try get(Float.self), y = try get(Float.self), w = try get(Float.self)
            // A fingertip on the bay, with room for one pressed at its edge.
            guard x.isFinite, y.isFinite, w.isFinite, x >= -200, y >= -200,
                  x <= Float(CaveWall.bayWidth + 200), y <= Float(CaveWall.height + 200), w > 0, w < 100
            else { throw CodingError.corrupt }
            places.append(SIMD2(x, y))
            widths.append(w)
        }
        self.done = done
        hand = fingers > 0 ? CaveHand(fingers: places, widths: widths) : nil
    }
}
