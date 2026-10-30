import Foundation

/// A photo of a drawing on paper → the drawing's ink, as a map the line art traces
/// (`EdgeMap`), and the sheet cleaned: white paper, the ink alone, square to the picture.
///
/// A phone's photo of a sheet is unevenly lit, a little askew, textured and surrounded by the
/// table. `clean` makes the sheet the picture:
/// 1. The paper's brightness under every pixel is estimated by a grey closing (a maximum over
///    `paperRadius`, wider than any line, then blurred): lines vanish from it, the light's
///    gradient and the paper's tone stay (`paper`).
/// 2. The sheet is what the paper estimate flows over from the picture's middle without a
///    step (`sheet`): a lit sheet shades smoothly, its edge against a table or frame is a
///    step. Its four corners (the hull's extremes) are pulled square by a homography
///    (`rectify`), the sheet's own proportions kept, unless the sheet is the whole picture or
///    no quadrilateral fits what was found; then the picture stays as it is.
/// 3. Ink is how far below its paper each pixel lies (`darkness`), scaled so the paper's own
///    texture reads 0 and the ink's body 1 (`inkStrength`: the thresholds come from the
///    picture's darkness histogram, so a pencil's grey and a marker's black both come out
///    at full strength).
/// `ink` is the same darkness at the working size, every line at least three pixels wide and
/// at least as strong as its strongest pixel (a maximum over the pixels each working pixel
/// covers, so a hair line survives the shrink); the line art thins it to centerlines.
///
/// Everything is sequential or per pixel in fixed order, so the same bytes give the same ink
/// on every device.
public enum DrawingScan {
    /// Long side of the picture the scan works at: twice the largest canvas, so a thin line
    /// is still a line after the shrink.
    public static let scanLongSide = 2400
    /// The grey closing's radius and the blur after it, as fractions of the long side: lines
    /// up to about 2 % of the sheet's width vanish from the paper estimate.
    static let paperRadius: Float = 0.011
    static let paperBlur: Float = 0.025
    /// Darkest a paper may be (of the photo's brightest): below it a pixel is a table, a frame
    /// or a shadow too deep to read, not paper.
    static let paperFloor: Float = 0.22
    /// The coarse grid the sheet is found on (its long side) and the largest change of the
    /// paper estimate between two of its cells that still is the same sheet.
    static let sheetGrid = 240
    static let sheetStep: Float = 0.035
    /// How far (grid cells) a cell's surroundings reach, and how bright a sheet cell is at
    /// least, of the brightest of them.
    static let sheetReach = 4
    static let sheetShare: Float = 0.82
    /// A sheet covering this share of the picture, or more, is the picture.
    static let wholeShare: Float = 0.9
    /// The sheet's hull must fill its quadrilateral this well for the corners to be the sheet's.
    static let quadFill: Float = 0.82
    /// How far inside the sheet's found edge the cleaned picture starts, of its size.
    static let edgeInset: Float = 0.012
    /// Width of the lines in the working-size ink map, pixels (odd).
    static let inkWidth = 3
    /// Ink deeper than this (of the working size's long side) that somewhere goes twice as
    /// deep is a solid fill, not a line: a silhouette, a black ground (`solids`).
    static let solidRadius: Float = 0.0055
    /// The share of a fill's core (the ink deeper than `solidRadius`) that is twice as deep.
    static let solidDepthShare: Float = 0.25

    /// The sheet cleaned: `clean`'s picture, with what it did.
    public struct Cleaned: Sendable {
        /// White paper and the ink alone, in sRGB, square to the picture.
        public var picture: RGBAImage
        /// Whether a sheet was found inside the picture and pulled square.
        public var rectified: Bool
        /// The sheet's corners in the photo (normalized, origin top-left), clockwise from the
        /// top-left, when `rectified`.
        public var corners: [SIMD2<Float>]

        public init(picture: RGBAImage, rectified: Bool, corners: [SIMD2<Float>]) {
            self.picture = picture
            self.rectified = rectified
            self.corners = corners
        }
    }

    /// The photo's sheet cleaned (above). Any size; the result is at most `scanLongSide` long.
    public static func clean(_ photo: RGBAImage, cancel: CancellationCheck = .none) throws -> Cleaned {
        let (luma, w, h) = try scanLuma(photo, cancel: cancel)
        try cancel.throwIfCancelled()
        let paper = try paperEstimate(luma, width: w, height: h, cancel: cancel)
        try cancel.throwIfCancelled()
        var picture = (luma: luma, paper: paper.blurred, width: w, height: h)
        var corners: [SIMD2<Float>] = []
        if let quad = sheet(paper: paper.dilated, width: w, height: h) {
            picture = rectify(luma: luma, paper: paper.blurred, width: w, height: h, quad: quad)
            corners = quad.map { SIMD2($0.x / Float(w), $0.y / Float(h)) }
        }
        try cancel.throwIfCancelled()
        let strength = inkStrength(darkness(picture.luma, paper: picture.paper))
        var pixels = [UInt8](repeating: 255, count: picture.width * picture.height * 4)
        for i in 0..<(picture.width * picture.height) {
            let v = UInt8(((1 - strength[i]) * 255).rounded())
            pixels[i * 4] = v; pixels[i * 4 + 1] = v; pixels[i * 4 + 2] = v
        }
        return Cleaned(
            picture: RGBAImage(width: picture.width, height: picture.height, pixels: pixels, colorSpace: .sRGB),
            rectified: !corners.isEmpty, corners: corners)
    }

    /// The drawing's ink at `width` × `height` (the working size), 0 paper … 255 ink: the
    /// strength under each working pixel, every line at least `inkWidth` wide. The line art
    /// thins it to centerlines (`LayeredLines.Tracing.skeleton`), so a marker's thick stroke
    /// and a pen's hair line each give one line.
    public static func ink(of picture: RGBAImage, width: Int, height: Int, cancel: CancellationCheck = .none) throws -> EdgeMap {
        precondition(width > 0 && height > 0, "ink size")
        let (luma, w, h) = try scanLuma(picture, cancel: cancel)
        try cancel.throwIfCancelled()
        let paper = try paperEstimate(luma, width: w, height: h, cancel: cancel).blurred
        try cancel.throwIfCancelled()
        let strength = inkStrength(darkness(luma, paper: paper))
        // The strongest pixel under each working pixel, then the lines widened.
        var pooled = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            let y0 = y * h / height, y1 = max(y0 + 1, (y + 1) * h / height)
            for x in 0..<width {
                let x0 = x * w / width, x1 = max(x0 + 1, (x + 1) * w / width)
                var best: Float = 0
                for yy in y0..<min(y1, h) {
                    let row = yy * w
                    for xx in x0..<min(x1, w) { best = max(best, strength[row + xx]) }
                }
                pooled[y * width + x] = best
            }
        }
        try cancel.throwIfCancelled()
        let r = inkWidth / 2
        var widened = pooled
        for y in 0..<height {
            for x in 0..<width {
                var best = pooled[y * width + x]
                for dy in -r...r {
                    let yy = y + dy
                    guard yy >= 0 && yy < height else { continue }
                    for dx in -r...r {
                        let xx = x + dx
                        guard xx >= 0 && xx < width else { continue }
                        best = max(best, pooled[yy * width + xx])
                    }
                }
                widened[y * width + x] = best
            }
        }
        return EdgeMap(width: width, height: height, values: widened.map { UInt8((min(max($0, 0), 1) * 255).rounded()) })
    }

    /// Where `ink` is a solid fill (above): the ink deeper than `solidRadius` from the paper
    /// whose core goes twice as deep over `solidDepthShare` of it (a blob, not a marker's
    /// thick stroke, deep only where strokes meet), grown back by the radius, so the fill's
    /// edge is the line around it. Per working pixel.
    public static func solids(of ink: EdgeMap, threshold: Float = 0.3) -> [Bool] {
        let w = ink.width, h = ink.height
        let r = max(2, Int((solidRadius * Float(max(w, h))).rounded()))
        let r2 = Float(r * r), seed2 = Float(4 * r * r)
        let level = UInt8((threshold * 255).rounded())
        let inside = DistanceTransform.squaredEDT(width: w, height: h) { ink.values[$0] < level }.storage
        // The deep core's components, kept where one holds a pixel twice as deep.
        var deep = Grid<UInt32>(width: w, height: h, repeating: 0)
        for i in deep.storage.indices where inside[i] > r2 { deep.storage[i] = 1 }
        let components = ConnectedComponents.label(deep)
        // A blob is deep over much of its core; a thick stroke's core is a thread, deep only
        // where strokes meet.
        var deeper = [Int](repeating: 0, count: components.count)
        for i in inside.indices where inside[i] > seed2 { deeper[Int(components.labels.storage[i])] += 1 }
        var blob = [Bool](repeating: false, count: components.count)
        for c in blob.indices where components.classOf[c] == 1 && Float(deeper[c]) >= solidDepthShare * Float(components.area[c]) {
            blob[c] = true
        }
        var core = [Bool](repeating: false, count: w * h)
        for i in core.indices where deep.storage[i] == 1 && blob[Int(components.labels.storage[i])] { core[i] = true }
        guard core.contains(true) else { return core }
        let spread = DistanceTransform.squaredEDT(width: w, height: h) { core[$0] }.storage
        var solid = [Bool](repeating: false, count: w * h)
        for i in solid.indices where spread[i] <= r2 && ink.values[i] >= level { solid[i] = true }
        return solid
    }

    // MARK: - Luma and paper

    /// The photo's luma (gamma-encoded, 0...1) at the scan size.
    static func scanLuma(_ photo: RGBAImage, cancel: CancellationCheck) throws -> ([Float], Int, Int) {
        let long = max(photo.width, photo.height)
        let image: RGBAImage
        if long > scanLongSide {
            let scale = Double(scanLongSide) / Double(long)
            image = try Resample.area(
                photo, width: max(1, Int((Double(photo.width) * scale).rounded())),
                height: max(1, Int((Double(photo.height) * scale).rounded())), cancel: cancel)
        } else {
            image = photo
        }
        let w = image.width, h = image.height
        var luma = [Float](repeating: 0, count: w * h)
        image.pixels.withUnsafeBufferPointer { p in
            for i in 0..<(w * h) {
                let r = Float(p[i * 4]), g = Float(p[i * 4 + 1]), b = Float(p[i * 4 + 2]), a = Float(p[i * 4 + 3]) / 255
                // Transparent pixels (a scan with no paper) count as paper.
                luma[i] = (0.299 * r + 0.587 * g + 0.114 * b) / 255 * a + (1 - a)
            }
        }
        return (luma, w, h)
    }

    /// The paper's brightness under each pixel: a grey closing (a maximum over `paperRadius`,
    /// `dilated`: the lines gone, every edge of the sheet still a step) blurred by `paperBlur`
    /// (`blurred`: what the ink is read against).
    static func paperEstimate(
        _ luma: [Float], width w: Int, height h: Int, cancel: CancellationCheck
    ) throws -> (dilated: [Float], blurred: [Float]) {
        let long = Float(max(w, h))
        let r = max(2, Int((paperRadius * long).rounded()))
        let dilated = maxFilter(luma, width: w, height: h, radius: r)
        try cancel.throwIfCancelled()
        let blurRadius = max(3, Int((paperBlur * long).rounded()))
        return (dilated, try BoxBlur.apply(dilated, width: w, height: h, radius: blurRadius, passes: 2, cancel: cancel))
    }

    /// Separable maximum over a (2r+1)² window, the picture's edge clamped.
    static func maxFilter(_ input: [Float], width w: Int, height h: Int, radius r: Int) -> [Float] {
        var rows = [Float](repeating: 0, count: w * h)
        input.withUnsafeBufferPointer { src in
            rows.withUnsafeMutableBufferPointer { dst in
                let s = UncheckedSendable(src.baseAddress!), d = UncheckedSendable(dst.baseAddress!)
                Parallel.forEachBand(h, minimumBandSize: 16) { band in
                    for y in band {
                        let row = s.value + y * w, out = d.value + y * w
                        for x in 0..<w {
                            var best: Float = 0
                            for xx in max(0, x - r)...min(w - 1, x + r) { best = max(best, row[xx]) }
                            out[x] = best
                        }
                    }
                }
            }
        }
        var out = [Float](repeating: 0, count: w * h)
        rows.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                let s = UncheckedSendable(src.baseAddress!), d = UncheckedSendable(dst.baseAddress!)
                Parallel.forEachBand(h, minimumBandSize: 16) { band in
                    for y in band {
                        let o = d.value + y * w
                        for x in 0..<w { o[x] = 0 }
                        for yy in max(0, y - r)...min(h - 1, y + r) {
                            let row = s.value + yy * w
                            for x in 0..<w { o[x] = max(o[x], row[x]) }
                        }
                    }
                }
            }
        }
        return out
    }

    /// How far below its paper each pixel lies, 0...1.
    static func darkness(_ luma: [Float], paper: [Float]) -> [Float] {
        var d = [Float](repeating: 0, count: luma.count)
        for i in luma.indices { d[i] = min(max(1 - luma[i] / max(paper[i], 0.05), 0), 1) }
        return d
    }

    /// Darkness scaled to ink: the paper's texture (what most pixels show) is 0, the ink's body
    /// 1. `low` is the paper's darkest texture, read from the middle of the histogram (the 50th
    /// and 75th percentiles are paper on any drawing that is less than half ink); `high` lies
    /// three fifths of the way from it to the ink's typical darkness (the 70th percentile of
    /// what is darker than `low`), so a pencil's lines, never black, still count whole.
    static func inkStrength(_ darkness: [Float]) -> [Float] {
        let bins = 1024
        var histogram = [Int](repeating: 0, count: bins)
        for d in darkness { histogram[min(Int(d * Float(bins - 1)), bins - 1)] += 1 }
        func percentile(_ p: Float, from start: Int = 0) -> Float {
            var total = 0
            for b in start..<bins { total += histogram[b] }
            guard total > 0 else { return 0 }
            let target = Int(Float(total) * p)
            var seen = 0
            for b in start..<bins {
                seen += histogram[b]
                if seen >= target { return Float(b) / Float(bins - 1) }
            }
            return 1
        }
        let p50 = percentile(0.5), p75 = percentile(0.75)
        let spread = max(p75 - p50, 0.008)
        let low = min(p75 + 3 * spread + 0.02, 0.5)
        let lowBin = min(Int(low * Float(bins - 1)) + 1, bins - 1)
        let body = max(percentile(0.7, from: lowBin), low + 0.12)
        let high = low + 0.6 * (body - low)
        let scale = 1 / max(high - low, 0.02)
        return darkness.map { min(max(($0 - low) * scale, 0), 1) }
    }

    // MARK: - The sheet

    /// The sheet's corners in scan pixels, clockwise from the top-left: where the paper
    /// estimate flows from the middle of the picture without a step; nil when that is the
    /// whole picture or doesn't fill a quadrilateral.
    static func sheet(paper: [Float], width w: Int, height h: Int) -> [SIMD2<Float>]? {
        let k = max(1, Int((Float(max(w, h)) / Float(sheetGrid)).rounded(.up)))
        let gw = (w + k - 1) / k, gh = (h + k - 1) / k
        guard gw >= 4, gh >= 4 else { return nil }
        var coarse = [Float](repeating: 0, count: gw * gh)
        var brightest: Float = 0
        for gy in 0..<gh {
            for gx in 0..<gw {
                var sum: Float = 0, count: Float = 0
                for y in (gy * k)..<min((gy + 1) * k, h) {
                    for x in (gx * k)..<min((gx + 1) * k, w) { sum += paper[y * w + x]; count += 1 }
                }
                let v = sum / max(count, 1)
                coarse[gy * gw + gx] = v
                brightest = max(brightest, v)
            }
        }
        let floor = paperFloor * brightest
        // The brightest cell within `sheetReach`: a cell on the sheet is nearly as bright as
        // its surroundings, a table cell beside the sheet's edge is not, though the cells
        // straddling a slanted edge step down gently enough to pass the step test alone.
        var local = [Float](repeating: 0, count: gw * gh)
        for gy in 0..<gh {
            for gx in 0..<gw {
                var best: Float = 0
                for yy in max(0, gy - sheetReach)...min(gh - 1, gy + sheetReach) {
                    for xx in max(0, gx - sheetReach)...min(gw - 1, gx + sheetReach) { best = max(best, coarse[yy * gw + xx]) }
                }
                local[gy * gw + gx] = best
            }
        }
        var inside = [Bool](repeating: false, count: gw * gh)
        var stack = [middleCell(gw, gh)]
        inside[stack[0]] = true
        var area = 0
        while let i = stack.popLast() {
            area += 1
            let y = i / gw, x = i - y * gw
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let xx = x + dx, yy = y + dy
                guard xx >= 0, yy >= 0, xx < gw, yy < gh else { continue }
                let j = yy * gw + xx
                guard !inside[j], coarse[j] >= floor, abs(coarse[j] - coarse[i]) <= sheetStep,
                      coarse[j] >= sheetShare * local[j] else { continue }
                inside[j] = true
                stack.append(j)
            }
        }
        // What the flood went round (a figure hatched too densely to flow over) is still the
        // sheet: only what reaches the grid's edge from outside is outside.
        var outside = [Bool](repeating: false, count: gw * gh)
        for gy in 0..<gh {
            for gx in 0..<gw where (gx == 0 || gy == 0 || gx == gw - 1 || gy == gh - 1) && !inside[gy * gw + gx] {
                outside[gy * gw + gx] = true
                stack.append(gy * gw + gx)
            }
        }
        while let i = stack.popLast() {
            let y = i / gw, x = i - y * gw
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let xx = x + dx, yy = y + dy
                guard xx >= 0, yy >= 0, xx < gw, yy < gh else { continue }
                let j = yy * gw + xx
                guard !outside[j], !inside[j] else { continue }
                outside[j] = true
                stack.append(j)
            }
        }
        area = 0
        for i in 0..<(gw * gh) where !outside[i] { inside[i] = true; area += 1 }
        guard Float(area) < wholeShare * Float(gw * gh) else { return nil }
        // The sheet's outline: the inside cells with an outside 4-neighbour (or on the grid's
        // edge), as the corners of the cells, in scan pixels.
        var points: [SIMD2<Float>] = []
        for gy in 0..<gh {
            for gx in 0..<gw where inside[gy * gw + gx] {
                var edge = gx == 0 || gy == 0 || gx == gw - 1 || gy == gh - 1
                if !edge {
                    for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where !inside[(gy + dy) * gw + gx + dx] { edge = true }
                }
                guard edge else { continue }
                let x0 = Float(gx * k), y0 = Float(gy * k), x1 = Float(min((gx + 1) * k, w)), y1 = Float(min((gy + 1) * k, h))
                points += [SIMD2(x0, y0), SIMD2(x1, y0), SIMD2(x1, y1), SIMD2(x0, y1)]
            }
        }
        let hull = convexHull(points)
        guard hull.count >= 4 else { return nil }
        let directions: [SIMD2<Float>] = [SIMD2(-1, -1), SIMD2(1, -1), SIMD2(1, 1), SIMD2(-1, 1)]
        var corners: [SIMD2<Float>] = []
        for direction in directions {
            var best = hull[0]
            var bestDot = simdDot(best, direction)
            for p in hull.dropFirst() {
                let d = simdDot(p, direction)
                if d > bestDot { bestDot = d; best = p }
            }
            corners.append(best)
        }
        // A sheet seen as a quadrilateral fills it; a shape with a bite out of it, or the
        // table's own lit patch, doesn't.
        let quadArea = abs(polygonArea(corners))
        let cellArea = Float(area) * Float(k * k)
        guard quadArea > 0, cellArea / quadArea >= quadFill, cellArea <= quadArea * 1.15 else { return nil }
        // Degenerate corners (two at the same spot) are no sheet.
        for i in 0..<4 where simdLength(corners[i] - corners[(i + 1) % 4]) < Float(4 * k) { return nil }
        return corners
    }

    private static func middleCell(_ gw: Int, _ gh: Int) -> Int { (gh / 2) * gw + gw / 2 }

    /// Andrew's monotone chain, counter-clockwise in picture coordinates (y down).
    static func convexHull(_ input: [SIMD2<Float>]) -> [SIMD2<Float>] {
        var unique = Swift.Set<SIMD2<Int32>>()
        for p in input { unique.insert(SIMD2<Int32>(Int32(p.x), Int32(p.y))) }
        let sorted = unique.sorted { (a: SIMD2<Int32>, b: SIMD2<Int32>) -> Bool in a.x != b.x ? a.x < b.x : a.y < b.y }
        let points: [SIMD2<Float>] = sorted.map { SIMD2<Float>(Float($0.x), Float($0.y)) }
        guard points.count >= 3 else { return points }
        func cross(_ o: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        var lower: [SIMD2<Float>] = []
        for p in points {
            while lower.count >= 2 && cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 { lower.removeLast() }
            lower.append(p)
        }
        var upper: [SIMD2<Float>] = []
        for p in points.reversed() {
            while upper.count >= 2 && cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 { upper.removeLast() }
            upper.append(p)
        }
        return Array(lower.dropLast() + upper.dropLast())
    }

    static func polygonArea(_ p: [SIMD2<Float>]) -> Float {
        var a: Float = 0
        for i in p.indices { let q = p[(i + 1) % p.count]; a += p[i].x * q.y - q.x * p[i].y }
        return a / 2
    }

    // MARK: - Rectification

    /// `luma` and `paper` resampled so `quad` (clockwise from the top-left) becomes the whole
    /// picture, of the quadrilateral's own mean width and height.
    static func rectify(
        luma: [Float], paper: [Float], width w: Int, height h: Int, quad: [SIMD2<Float>]
    ) -> (luma: [Float], paper: [Float], width: Int, height: Int) {
        // Inside the sheet's edge by `edgeInset`: the corners come from a coarse grid, and the
        // paper's edge, its shadow and a sliver of table lie along them.
        let centre = (quad[0] + quad[1] + quad[2] + quad[3]) / 4
        let quad = quad.map { $0 + (centre - $0) * edgeInset * 2 }
        let top = simdLength(quad[1] - quad[0]), bottom = simdLength(quad[2] - quad[3])
        let left = simdLength(quad[3] - quad[0]), right = simdLength(quad[2] - quad[1])
        let ow = max(8, Int(((top + bottom) / 2).rounded())), oh = max(8, Int(((left + right) / 2).rounded()))
        guard let hm = homography(from: [SIMD2(0, 0), SIMD2(Float(ow), 0), SIMD2(Float(ow), Float(oh)), SIMD2(0, Float(oh))], to: quad)
        else { return (luma, paper, w, h) }
        let h0 = hm[0], h1 = hm[1], h2 = hm[2]
        var outLuma = [Float](repeating: 1, count: ow * oh), outPaper = [Float](repeating: 1, count: ow * oh)
        @inline(__always) func sample(_ a: [Float], _ x: Float, _ y: Float) -> Float {
            let cx = min(max(x, 0), Float(w - 1)), cy = min(max(y, 0), Float(h - 1))
            let x0 = min(Int(cx), w - 2), y0 = min(Int(cy), h - 2)
            let fx = cx - Float(x0), fy = cy - Float(y0)
            let t = a[y0 * w + x0] * (1 - fx) + a[y0 * w + x0 + 1] * fx
            let b = a[(y0 + 1) * w + x0] * (1 - fx) + a[(y0 + 1) * w + x0 + 1] * fx
            return t * (1 - fy) + b * fy
        }
        for y in 0..<oh {
            for x in 0..<ow {
                let p = SIMD3<Double>(Double(x) + 0.5, Double(y) + 0.5, 1)
                let q = SIMD3<Double>((h0 * p).sum(), (h1 * p).sum(), (h2 * p).sum())
                guard abs(q.z) > 1e-9 else { continue }
                let sx = Float(q.x / q.z) - 0.5, sy = Float(q.y / q.z) - 0.5
                outLuma[y * ow + x] = sample(luma, sx, sy)
                outPaper[y * ow + x] = sample(paper, sx, sy)
            }
        }
        return (outLuma, outPaper, ow, oh)
    }

    /// The homography taking the four `from` points to the four `to` points, as the three rows
    /// of a matrix applied to (x, y, 1); nil when the points are degenerate.
    static func homography(from a: [SIMD2<Float>], to b: [SIMD2<Float>]) -> [SIMD3<Double>]? {
        // Eight equations in the eight unknowns of H (h33 = 1).
        var m = [[Double]](repeating: [Double](repeating: 0, count: 9), count: 8)
        for i in 0..<4 {
            let x = Double(a[i].x), y = Double(a[i].y), u = Double(b[i].x), v = Double(b[i].y)
            m[2 * i] = [x, y, 1, 0, 0, 0, -u * x, -u * y, u]
            m[2 * i + 1] = [0, 0, 0, x, y, 1, -v * x, -v * y, v]
        }
        // Gaussian elimination with partial pivoting.
        for col in 0..<8 {
            var pivot = col
            for r in col..<8 where abs(m[r][col]) > abs(m[pivot][col]) { pivot = r }
            guard abs(m[pivot][col]) > 1e-12 else { return nil }
            m.swapAt(col, pivot)
            for r in 0..<8 where r != col {
                let f = m[r][col] / m[col][col]
                guard f != 0 else { continue }
                for c in col..<9 { m[r][c] -= f * m[col][c] }
            }
        }
        var hv = [Double](repeating: 0, count: 8)
        for r in 0..<8 { hv[r] = m[r][8] / m[r][r] }
        return [SIMD3(hv[0], hv[1], hv[2]), SIMD3(hv[3], hv[4], hv[5]), SIMD3(hv[6], hv[7], 1)]
    }
}
