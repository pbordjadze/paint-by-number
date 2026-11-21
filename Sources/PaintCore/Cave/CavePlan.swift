import Foundation

/// One cave painting's drawing (painting-company row 371): the subject's shape on the wall, its
/// areas, the earth pigment of each, and the few inner lines the photo insists on (an eye, a mane,
/// a leg behind another), at `CaveWall.scale` pixels a point. The rock under it, its charcoal
/// contour and its dots are made from this (`CaveBay`); what has been blown onto it is the
/// painting's progress (`CaveProgress`, `CavePigmentLayer`).
///
/// An animal is drawn properly: its silhouette from the subject's mask, its areas from the photo's
/// light and dark, darkest charcoal to lightest yellow ochre, the way the painters modelled a
/// flank. Any other subject becomes a charmingly crude stick figure, a child's first try on the
/// wall (Paul's choice, November 20, 2026: `CaveFigure`).
///
/// `cave.plan` is read as hostile input: magic `PBCV`, a format version, the kind, width and
/// height, the pigment of each area, then the mask, the areas and the inner lines run-length
/// coded. Fields are only ever appended; bump `formatVersion` only when one changes meaning.
public struct CavePlan: Sendable, Equatable {
    public enum Kind: UInt8, Sendable {
        case animal, figure
    }

    public static let magic: UInt32 = 0x5643_4250 // "PBCV", little-endian
    public static let formatVersion: UInt32 = 1
    /// The largest plan a file may hold, in pixels a side.
    public static let maxSide = 2048

    public enum CodingError: Error, Equatable {
        case corrupt
        case newerVersion(UInt32)
    }

    public let kind: Kind
    public let width: Int
    public let height: Int
    /// The subject, a pixel each.
    public let mask: [Bool]
    /// Each pixel's area, 1 to `areaCount`, or 0 off the subject.
    public let areas: [UInt16]
    /// Each area's pigment: area `k`'s is `pigments[k - 1]`.
    public let pigments: [CavePigment]
    /// The charcoal lines inside the subject.
    public let lines: [Bool]

    public var areaCount: Int { pigments.count }

    public init(kind: Kind, width: Int, height: Int, mask: [Bool], areas: [UInt16], pigments: [CavePigment], lines: [Bool]) {
        precondition(mask.count == width * height && areas.count == width * height && lines.count == width * height)
        self.kind = kind
        self.width = width
        self.height = height
        self.mask = mask
        self.areas = areas
        self.pigments = pigments
        self.lines = lines
    }

    /// Its size on the wall, in points.
    public var size: SIMD2<Float> { SIMD2(Float(width), Float(height)) / Float(CaveWall.scale) }

    /// Its top-left corner in its bay, in points: centred in `CaveWall.paintingBox`.
    public var origin: SIMD2<Float> {
        let box = CaveWall.paintingBox
        return SIMD2(((box.minX + box.maxX) - size.x) / 2, ((box.minY + box.maxY) - size.y) / 2).rounded(.down)
    }

    /// The largest painting a bay holds, in map pixels.
    static var maxSize: SIMD2<Float> {
        let box = CaveWall.paintingBox
        return SIMD2(box.maxX - box.minX, box.maxY - box.minY) * Float(CaveWall.scale)
    }

    // MARK: - Making one

    /// A painting of `photo`'s subject. `subject` is the foreground mask (any size, 0 to 1 over
    /// the photo); without one, or with too little in it, or when `kind` is `.figure`, the subject
    /// is a stick figure as tall as the subject's shape (or the photo's) suggests.
    public static func make(photo: RGBAImage, subject: Grid<Float>?, kind: Kind) -> CavePlan {
        let bounds = subject.flatMap { Self.bounds(of: $0) }
        guard kind == .animal, let subject, let bounds else {
            let aspect = bounds.map { Float($0.width) / Float(max(1, $0.height)) } ?? Float(photo.width) / Float(max(1, photo.height))
            return CaveFigure.plan(aspect: aspect, seed: UInt64(photo.width &* 31 &+ photo.height))
        }
        // The subject's box with a margin, in the photo's pixels.
        let sx = Float(photo.width) / Float(subject.width), sy = Float(photo.height) / Float(subject.height)
        let margin = 0.05 * Float(max(bounds.width, bounds.height))
        let x0 = max(0, (Float(bounds.minX) - margin) * sx), y0 = max(0, (Float(bounds.minY) - margin) * sy)
        let x1 = min(Float(photo.width), (Float(bounds.maxX + 1) + margin) * sx)
        let y1 = min(Float(photo.height), (Float(bounds.maxY + 1) + margin) * sy)
        let fit = min(maxSize.x / (x1 - x0), maxSize.y / (y1 - y0))
        let w = max(16, Int((x1 - x0) * fit)), h = max(16, Int((y1 - y0) * fit))
        let luma = Self.luma(of: photo, x0: x0, y0: y0, x1: x1, y1: y1, width: w, height: h)
        var shape = Self.resample(subject, x0: x0 / sx, y0: y0 / sy, x1: x1 / sx, y1: y1 / sy, width: w, height: h)
        shape = Self.clean(shape, width: w, height: h)
        let inside = shape.reduce(0) { $0 + ($1 ? 1 : 0) }
        // A sliver of a subject draws nothing worth blowing: a figure instead.
        guard inside > w * h / 12 else {
            return CaveFigure.plan(aspect: Float(w) / Float(h), seed: UInt64(w &* 31 &+ h))
        }
        let pigment = Self.pigments(luma: luma, mask: shape, width: w, height: h)
        let (areas, pigments) = Self.areas(pigment: pigment, width: w, height: h)
        let lines = Self.innerLines(luma: luma, mask: shape, width: w, height: h)
        return CavePlan(kind: .animal, width: w, height: h, mask: shape, areas: areas, pigments: pigments, lines: lines)
    }

    /// The box of a mask's pixels over half, nil when there are none.
    static func bounds(of mask: Grid<Float>) -> (minX: Int, minY: Int, maxX: Int, maxY: Int, width: Int, height: Int)? {
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for y in 0..<mask.height {
            for x in 0..<mask.width where mask.storage[y * mask.width + x] > 0.5 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return (minX, minY, maxX, maxY, maxX - minX + 1, maxY - minY + 1)
    }

    /// The photo's light (Rec. 601 luma, 0 to 1) over a rectangle, each output pixel the mean of
    /// the photo's under it.
    static func luma(of photo: RGBAImage, x0: Float, y0: Float, x1: Float, y1: Float, width w: Int, height h: Int) -> [Float] {
        var out = [Float](repeating: 0, count: w * h)
        let stepX = (x1 - x0) / Float(w), stepY = (y1 - y0) / Float(h)
        photo.pixels.withUnsafeBufferPointer { px in
            out.withUnsafeMutableBufferPointer { o in
                let src = UncheckedSendable(px.baseAddress!), dst = UncheckedSendable(o.baseAddress!)
                Parallel.forEachBand(h, minimumBandSize: 16) { rows in
                    for y in rows {
                        let ya = min(photo.height - 1, Int(y0 + Float(y) * stepY))
                        let yb = max(ya, min(photo.height - 1, Int(y0 + Float(y + 1) * stepY) - 1))
                        for x in 0..<w {
                            let xa = min(photo.width - 1, Int(x0 + Float(x) * stepX))
                            let xb = max(xa, min(photo.width - 1, Int(x0 + Float(x + 1) * stepX) - 1))
                            var sum: Float = 0
                            for yy in ya...yb {
                                for xx in xa...xb {
                                    let i = (yy * photo.width + xx) * 4
                                    sum += 0.299 * Float(src.value[i]) + 0.587 * Float(src.value[i + 1]) + 0.114 * Float(src.value[i + 2])
                                }
                            }
                            dst.value[y * w + x] = sum / Float((yb - ya + 1) * (xb - xa + 1)) / 255
                        }
                    }
                }
            }
        }
        return out
    }

    /// A mask sampled bilinearly over a rectangle of its own pixels, cut at half.
    static func resample(_ mask: Grid<Float>, x0: Float, y0: Float, x1: Float, y1: Float, width w: Int, height h: Int) -> [Bool] {
        var out = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            let fy = y0 + (Float(y) + 0.5) / Float(h) * (y1 - y0) - 0.5
            for x in 0..<w {
                let fx = x0 + (Float(x) + 0.5) / Float(w) * (x1 - x0) - 0.5
                out[y * w + x] = Self.bilinear(mask, fx, fy) > 0.5
            }
        }
        return out
    }

    static func bilinear(_ g: Grid<Float>, _ x: Float, _ y: Float) -> Float {
        let cx = min(max(x, 0), Float(g.width - 1)), cy = min(max(y, 0), Float(g.height - 1))
        let xa = Int(cx), ya = Int(cy), xb = min(xa + 1, g.width - 1), yb = min(ya + 1, g.height - 1)
        let tx = cx - Float(xa), ty = cy - Float(ya)
        let a = g.storage[ya * g.width + xa] * (1 - tx) + g.storage[ya * g.width + xb] * tx
        let b = g.storage[yb * g.width + xa] * (1 - tx) + g.storage[yb * g.width + xb] * tx
        return a * (1 - ty) + b * ty
    }

    /// The subject's mask made one clean shape: specks opened away, gaps closed, holes filled,
    /// only the largest piece kept, its edge smoothed.
    static func clean(_ mask: [Bool], width w: Int, height h: Int) -> [Bool] {
        var m = grow(shrink(mask, by: 2, width: w, height: h), by: 2, width: w, height: h)
        m = shrink(grow(m, by: 6, width: w, height: h), by: 6, width: w, height: h)
        m = fillHoles(m, width: w, height: h)
        m = largest(m, width: w, height: h)
        let soft = Gaussian.filter(m.map { $0 ? 1 : 0 }, width: w, height: h, sigma: 5, orderX: 0, orderY: 0)
        return soft.map { $0 > 0.5 }
    }

    static func grow(_ mask: [Bool], by r: Float, width w: Int, height h: Int) -> [Bool] {
        let d = DistanceTransform.squaredEDT(width: w, height: h) { mask[$0] }
        return d.storage.map { $0 <= r * r }
    }

    /// Shrinks a mask; outside the plan counts as unset.
    static func shrink(_ mask: [Bool], by r: Float, width w: Int, height h: Int) -> [Bool] {
        let d = DistanceTransform.squaredEDT(width: w, height: h) { i in
            let x = i % w, y = i / w
            return !mask[i] || x == 0 || y == 0 || x == w - 1 || y == h - 1
        }
        return d.storage.map { $0 > r * r }
    }

    static func fillHoles(_ mask: [Bool], width w: Int, height h: Int) -> [Bool] {
        var outside = [Bool](repeating: false, count: w * h)
        var stack: [Int] = []
        for x in 0..<w { stack.append(x); stack.append((h - 1) * w + x) }
        for y in 0..<h { stack.append(y * w); stack.append(y * w + w - 1) }
        while let i = stack.popLast() {
            guard !mask[i], !outside[i] else { continue }
            outside[i] = true
            let x = i % w, y = i / w
            if x > 0 { stack.append(i - 1) }
            if x < w - 1 { stack.append(i + 1) }
            if y > 0 { stack.append(i - w) }
            if y < h - 1 { stack.append(i + w) }
        }
        return outside.map { !$0 }
    }

    static func largest(_ mask: [Bool], width w: Int, height h: Int) -> [Bool] {
        let c = ConnectedComponents.label(Grid(width: w, height: h, storage: mask.map { $0 ? 1 : 0 }))
        var best = -1, bestArea = 0
        for k in 0..<c.count where c.classOf[k] == 1 && c.area[k] > bestArea {
            best = k
            bestArea = c.area[k]
        }
        guard best >= 0 else { return mask }
        return c.labels.storage.map { Int($0) == best }
    }

    /// Each pixel's pigment by its light (darkest charcoal), cut at the subject's own quantiles so
    /// every animal has all four, then smoothed into areas a finger can blow; 255 off the subject.
    static func pigments(luma: [Float], mask: [Bool], width w: Int, height h: Int) -> [UInt8] {
        // Blurred within the subject alone, so the background's light never seeps into its edge.
        let weight = mask.map { Float($0 ? 1 : 0) }
        let sum = Gaussian.filter(zip(luma, weight).map { $0 * $1 }, width: w, height: h, sigma: 6, orderX: 0, orderY: 0)
        let cover = Gaussian.filter(weight, width: w, height: h, sigma: 6, orderX: 0, orderY: 0)
        let soft = zip(sum, cover).map { $1 > 1e-4 ? $0 / $1 : 0 }
        var inside = [Float]()
        inside.reserveCapacity(w * h / 2)
        for i in 0..<(w * h) where mask[i] { inside.append(soft[i]) }
        inside.sort()
        let cuts = [0.16, 0.36, 0.66].map { inside[min(inside.count - 1, Int(Float(inside.count) * Float($0)))] }
        var pigment = soft.map { v -> UInt8 in UInt8(cuts.reduce(0) { $0 + (v >= $1 ? 1 : 0) }) }
        // Votes at a quarter of the size first (broad areas), then at full size (their edges).
        let qw = (w + 3) / 4, qh = (h + 3) / 4
        var small = [UInt8](repeating: 0, count: qw * qh)
        for y in 0..<qh { for x in 0..<qw { small[y * qw + x] = pigment[min(h - 1, y * 4) * w + min(w - 1, x * 4)] } }
        small = Self.vote(small, width: qw, height: qh, radius: 3, times: 6)
        for y in 0..<h { for x in 0..<w { pigment[y * w + x] = small[(y / 4) * qw + x / 4] } }
        pigment = Self.vote(pigment, width: w, height: h, radius: 4, times: 2)
        for i in 0..<(w * h) where !mask[i] { pigment[i] = 255 }
        return pigment
    }

    /// Majority votes of the four pigments in a square window, `times` over (ties to the darker).
    static func vote(_ classes: [UInt8], width w: Int, height h: Int, radius r: Int, times: Int) -> [UInt8] {
        var c = classes
        for _ in 0..<times {
            var counts = [[Int32]](repeating: [], count: 4)
            for k in 0..<4 { counts[k] = Self.boxSums(c.map { $0 == k ? 1 : 0 }, width: w, height: h, radius: r) }
            for i in 0..<(w * h) {
                var best = 0
                for k in 1..<4 where counts[k][i] > counts[best][i] { best = k }
                c[i] = UInt8(best)
            }
        }
        return c
    }

    /// Sums over a (2r + 1)² window, clamped at the borders, by an integral image.
    static func boxSums(_ v: [Int32], width w: Int, height h: Int, radius r: Int) -> [Int32] {
        var integral = [Int32](repeating: 0, count: (w + 1) * (h + 1))
        for y in 0..<h {
            var row: Int32 = 0
            for x in 0..<w {
                row += v[y * w + x]
                integral[(y + 1) * (w + 1) + x + 1] = integral[y * (w + 1) + x + 1] + row
            }
        }
        var out = [Int32](repeating: 0, count: w * h)
        for y in 0..<h {
            let ya = max(0, y - r), yb = min(h, y + r + 1)
            for x in 0..<w {
                let xa = max(0, x - r), xb = min(w, x + r + 1)
                out[y * w + x] = integral[yb * (w + 1) + xb] - integral[ya * (w + 1) + xb] - integral[yb * (w + 1) + xa] + integral[ya * (w + 1) + xa]
            }
        }
        return out
    }

    /// The smallest area a fingertip can comfortably fill, in map pixels (26 points square).
    static var minimumArea: Int { (26 * CaveWall.scale) * (26 * CaveWall.scale) }

    /// The areas: each connected run of one pigment, the small ones taken in by the neighbour they
    /// touch most, numbered from 1 in the order their first pixels come in rows.
    static func areas(pigment: [UInt8], width w: Int, height h: Int) -> (areas: [UInt16], pigments: [CavePigment]) {
        let n = w * h
        let comps = ConnectedComponents.label(Grid(width: w, height: h, storage: pigment.map { $0 == 255 ? 4 : UInt32($0) }))
        // Each component's area: union by merging a small one into its strongest neighbour.
        var owner = (0..<comps.count).map { $0 }
        let cls = comps.classOf
        var area = comps.area
        func root(_ k: Int) -> Int {
            var r = k
            while owner[r] != r { r = owner[r] }
            return r
        }
        let labels = comps.labels.storage
        for _ in 0..<6 {
            var touching: [Int: [Int: Int]] = [:]
            var any = false
            for y in 0..<h {
                for x in 0..<w {
                    let a = root(Int(labels[y * w + x]))
                    guard cls[a] != 4, area[a] < minimumArea else { continue }
                    for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                        let xx = x + dx, yy = y + dy
                        guard xx >= 0, yy >= 0, xx < w, yy < h else { continue }
                        let b = root(Int(labels[yy * w + xx]))
                        if b != a && cls[b] != 4 { touching[a, default: [:]][b, default: 0] += 1 }
                    }
                }
            }
            for a in touching.keys.sorted() {
                let ra = root(a)
                guard ra == a, area[a] < minimumArea else { continue }
                let best = touching[a]!.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
                guard let into = best.map({ root($0.key) }).first(where: { $0 != a }) else { continue }
                owner[a] = into
                area[into] += area[a]
                any = true
            }
            if !any { break }
        }
        var number = [Int](repeating: 0, count: comps.count)
        var pigments: [CavePigment] = []
        var areas = [UInt16](repeating: 0, count: n)
        for i in 0..<n {
            let r = root(Int(labels[i]))
            guard cls[r] != 4 else { continue }
            if number[r] == 0 {
                guard pigments.count < Int(UInt16.max) else { continue }
                pigments.append(CavePigment(rawValue: UInt8(cls[r])) ?? .charcoal)
                number[r] = pigments.count
            }
            areas[i] = UInt16(number[r])
        }
        return (areas, pigments)
    }

    /// The photo's dark lines inside the subject (a difference of blurs, kept where it is long
    /// enough to be drawn), which become the charcoal's inner strokes.
    static func innerLines(luma: [Float], mask: [Bool], width w: Int, height h: Int) -> [Bool] {
        let fine = Gaussian.filter(luma, width: w, height: h, sigma: 2.4, orderX: 0, orderY: 0)
        let broad = Gaussian.filter(luma, width: w, height: h, sigma: 7, orderX: 0, orderY: 0)
        let deep = shrink(mask, by: 6, width: w, height: h)
        var line = [Bool](repeating: false, count: w * h)
        for i in 0..<(w * h) where deep[i] { line[i] = fine[i] - broad[i] < -0.045 }
        let c = ConnectedComponents.label(Grid(width: w, height: h, storage: line.map { $0 ? 1 : 0 }))
        let minimum = 44 * CaveWall.scale
        return c.labels.storage.map { k in c.classOf[Int(k)] == 1 && c.area[Int(k)] >= minimum }
    }

    // MARK: - Dots

    /// Where each area's dots go, and how big they may be: the middle of its widest part (the point
    /// farthest from its edge) and that distance, in map pixels. Area `k` is entry `k - 1`.
    public func dotSpots() -> [(centre: SIMD2<Float>, room: Float)] {
        let labels = RegionMap(width: width, height: height, storage: areas.map { UInt32($0) })
        let inside = DistanceTransform.interiorDistance(labels: labels)
        var best = [(centre: SIMD2<Float>, room: Float)](repeating: (.zero, 0), count: areaCount)
        for i in 0..<(width * height) {
            let a = Int(areas[i])
            guard a > 0, inside.storage[i] > best[a - 1].room else { continue }
            best[a - 1] = (SIMD2(Float(i % width) + 0.5, Float(i / width) + 0.5), inside.storage[i])
        }
        return best
    }

    // MARK: - Coding

    public func encoded() -> Data {
        var data = Data()
        func put<T: BitwiseCopyable>(_ v: T) { withUnsafeBytes(of: v) { data.append(contentsOf: $0) } }
        put(Self.magic)
        put(Self.formatVersion)
        put(kind.rawValue)
        put(UInt32(width))
        put(UInt32(height))
        put(UInt32(pigments.count))
        for p in pigments { put(p.rawValue) }
        func bits(_ b: [Bool]) {
            var runs: [UInt32] = []
            var current = false, length: UInt32 = 0
            for v in b {
                if v == current { length += 1 } else { runs.append(length); current = v; length = 1 }
            }
            runs.append(length)
            put(UInt32(runs.count))
            for r in runs { put(r) }
        }
        bits(mask)
        var runs: [(UInt16, UInt32)] = []
        for v in areas {
            if let last = runs.last, last.0 == v { runs[runs.count - 1].1 += 1 } else { runs.append((v, 1)) }
        }
        put(UInt32(runs.count))
        for (v, l) in runs { put(v); put(l) }
        bits(lines)
        return data
    }

    public init(encoded data: Data) throws {
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
        guard let kind = Kind(rawValue: try get(UInt8.self)) else { throw CodingError.corrupt }
        let w = Int(try get(UInt32.self)), h = Int(try get(UInt32.self))
        guard w > 0, h > 0, w <= Self.maxSide, h <= Self.maxSide else { throw CodingError.corrupt }
        let n = w * h
        let count = Int(try get(UInt32.self))
        guard count <= data.endIndex - offset, count <= Int(UInt16.max) else { throw CodingError.corrupt }
        var pigments: [CavePigment] = []
        for _ in 0..<count {
            guard let p = CavePigment(rawValue: try get(UInt8.self)) else { throw CodingError.corrupt }
            pigments.append(p)
        }
        func bits() throws -> [Bool] {
            let runs = Int(try get(UInt32.self))
            guard runs >= 1, runs <= (data.endIndex - offset) / 4, runs <= n + 1 else { throw CodingError.corrupt }
            var out = [Bool]()
            out.reserveCapacity(n)
            var value = false
            for _ in 0..<runs {
                let length = Int(try get(UInt32.self))
                guard length <= n - out.count else { throw CodingError.corrupt }
                out.append(contentsOf: repeatElement(value, count: length))
                value.toggle()
            }
            guard out.count == n else { throw CodingError.corrupt }
            return out
        }
        let mask = try bits()
        let runs = Int(try get(UInt32.self))
        guard runs >= 1, runs <= (data.endIndex - offset) / 6, runs <= n else { throw CodingError.corrupt }
        var areas = [UInt16]()
        areas.reserveCapacity(n)
        for _ in 0..<runs {
            let v = try get(UInt16.self), length = Int(try get(UInt32.self))
            guard Int(v) <= count, length <= n - areas.count else { throw CodingError.corrupt }
            areas.append(contentsOf: repeatElement(v, count: length))
        }
        guard areas.count == n else { throw CodingError.corrupt }
        let lines = try bits()
        self.init(kind: kind, width: w, height: h, mask: mask, areas: areas, pigments: pigments, lines: lines)
    }
}
