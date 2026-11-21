import Foundation

/// One bay of the cave wall, made for the renderer (painting-company row 371): its relief, a
/// height a map pixel, and its rock, an RGBA color a map pixel with the daylight in alpha. Made
/// from wall coordinates by pure functions of them, so a bay is the same at every visit and its
/// edges meet its neighbours' (`CaveNoise`). The relief is limestone in three scales of swell,
/// flowstone ridges and cracks; under a painting the rock bulges, the way the Lascaux painters
/// chose a bulge for a belly or a flank; a ledge runs along the bottom. Its rock carries the
/// painting's charcoal: a contour heavy along the back and belly and thin at the legs, the inner
/// lines, and each area's dots in its pigment. The bay being worked has the painter's things on
/// its ledge: four hollows of pigment, each with its dots, and a stone fat-lamp; bare rock has a
/// lump of charcoal and the lamp. Bay 0 is the cave mouth: no view, only daylight too bright to
/// look into after the dark.
public enum CaveBay {
    public enum Content: Sendable, Equatable {
        case mouth
        case bare
        case painting(CavePlan)
    }

    /// What lies on the bay's ledge.
    public enum Tools: Sendable, Equatable {
        case none
        /// The four hollows of pigment and the lamp: a painting being blown.
        case pigments
        /// A lump of charcoal and the lamp: bare rock waiting for a drawing.
        case charcoal
    }

    public struct Maps: Sendable {
        public let index: Int
        public let width: Int
        public let height: Int
        /// The relief, a height a map pixel (about -0.6 in the mouth to 1.5 on a bulge).
        public var relief: [Float]
        /// The rock's color, RGBA8 a map pixel, display-encoded; alpha is the daylight.
        public var rock: [UInt8]
    }

    /// How far the relief stands out for the renderer, in wall points per unit of height.
    public static let reliefDepth: Float = 32

    static let rockColor = SIMD3<Float>(0.86, 0.79, 0.67)
    static let ink = SIMD3<Float>(0.08, 0.065, 0.06)

    public static func maps(index: Int, content: Content, tools: Tools) -> Maps {
        let w = CaveWall.mapWidth, h = CaveWall.mapHeight, s = Float(CaveWall.scale)
        let bayX = Float(index * CaveWall.bayWidth)
        let crack = cracks(index: index)
        let plan: CavePlan? = if case .painting(let p) = content { p } else { nil }
        let placed = plan.map { place($0) }
        let bulge = placed.map { bulgeMap($0.mask) }
        let ink = placed.map { drawing($0, plan: $0.plan, index: index) }
        let isMouth = content == .mouth

        var relief = [Float](repeating: 0, count: w * h)
        var rock = [UInt8](repeating: 0, count: w * h * 4)
        relief.withUnsafeMutableBufferPointer { rb in
            rock.withUnsafeMutableBufferPointer { cb in
                let rp = UncheckedSendable(rb.baseAddress!), cp = UncheckedSendable(cb.baseAddress!)
                Parallel.forEachBand(h, minimumBandSize: 8) { rows in
                    for j in rows {
                        let y = (Float(j) + 0.5) / s
                        for i in 0..<w {
                            let lx = (Float(i) + 0.5) / s, x = bayX + lx
                            let k = j * w + i
                            var height = 0.45 * CaveNoise.fbm(x, y, size: 800, octaves: 3, seed: 1)
                                + 0.018 * CaveNoise.fbm(x, y, size: 150, octaves: 3, seed: 2)
                                + 0.008 * CaveNoise.fbm(x, y, size: 25, octaves: 3, seed: 12)
                            // Flowstone ridges, and the stone's fine grain.
                            height += 0.025 * sin(x * 0.05 + y * 0.012 + 3 * CaveNoise.fbm(x, y, size: 225, octaves: 3, seed: 3))
                            height += 0.0019 * CaveNoise.gradient(x * 0.9, y * 0.9, seed: 33) * 3.3
                            let c = crack.line[k]
                            height -= 0.015 * crack.groove[k] / 0.3
                            // The mouth: a ragged opening, daylight beyond it.
                            var mouth: Float = 0, mouthD: Float = 2
                            if isMouth {
                                let m = (SIMD2(lx, y) - CaveWall.mouth) / CaveWall.mouthRadii
                                mouthD = (m * m).sum().squareRoot() + 0.22 * CaveNoise.fbm(x, y, size: 200, octaves: 3, seed: 21)
                                mouth = min(1, max(0, (1 - mouthD) * 6))
                                height = height * (1 - mouth) - 0.6 * mouth
                            }
                            if let bulge { height += 0.9 * bulge[k] }
                            // The ledge, all the way along.
                            let edge = CaveWall.ledge + 9 * CaveNoise.fbm(x, 0, size: 250, octaves: 3, seed: 4) + 12 * sin(x / 110)
                            let ledge = 1 / (1 + exp(-(y - edge) / 14)) * (1 - mouth)
                            if ledge > 0.001 {
                                height += ledge * (0.25 + 0.04 * CaveNoise.fbm(x, y, size: 100, octaves: 5, seed: 5) - 0.002 * max(0, y - edge))
                            }
                            // The rock's color.
                            var color = rockColor * (0.94 + 0.07 * CaveNoise.fbm(x, y, size: 150, octaves: 5, seed: 7))
                            let stain = min(1, max(0, CaveNoise.fbm(x, y, size: 400, octaves: 4, seed: 8) * 1.2 - 0.3))
                            color = color * (1 - 0.25 * stain) + 0.25 * stain * SIMD3(0.62, 0.42, 0.30)
                            color *= (1 - ledge * 0.08) * (1 - 0.75 * c)
                            // Pale streaks running down, and a crystalline speckle.
                            let streak = min(2, max(-2, CaveNoise.gradient(x / 12, y / 90, seed: 31) * 3.3))
                            color *= 1 + 0.02 * streak
                            color *= 0.96 + 0.08 * CaveNoise.unit(Int32(i), Int32(j), 32 &+ UInt32(bitPattern: Int32(index)))
                            // Moss near the daylight, where plants can live.
                            let g = (SIMD2(x, y) - CaveWall.mouth) / SIMD2(260, 330)
                            let near = 1.2 - (g * g).sum().squareRoot()
                            if near > 0 {
                                let green = min(1, near) * (1 - mouth) * min(1, max(0, CaveNoise.fbm(x, y, size: 75, octaves: 4, seed: 22) + 0.3))
                                color = color * (1 - 0.5 * green) + 0.5 * green * SIMD3(0.32, 0.40, 0.20)
                            }
                            if let ink { color = color * (1 - 0.96 * ink[k]) + 0.96 * ink[k] * Self.ink }
                            let day = mouth * min(1, max(0, 1.1 - 0.5 * mouthD))
                            rp.value[k] = height
                            let o = k * 4
                            cp.value[o] = byte(color.x)
                            cp.value[o + 1] = byte(color.y)
                            cp.value[o + 2] = byte(color.z)
                            cp.value[o + 3] = byte(day)
                        }
                    }
                }
            }
        }
        var maps = Maps(index: index, width: w, height: h, relief: relief, rock: rock)
        if let placed, let plan { dots(of: plan, at: placed.origin, on: &maps) }
        switch tools {
        case .none: break
        case .pigments:
            for (k, cup) in CaveWall.cups.enumerated() { hollow(cup.centre, radii: cup.radii, pigment: CavePigment(rawValue: UInt8(k))!, on: &maps) }
            lamp(on: &maps)
        case .charcoal:
            lump(on: &maps)
            lamp(on: &maps)
        }
        return maps
    }

    @inline(__always) static func byte(_ v: Float) -> UInt8 { UInt8(min(255, max(0, v * 255 + 0.5))) }

    // MARK: - The painting on the rock

    /// A plan placed in its bay: its mask on the bay's map, and where its top-left corner is.
    struct Placed {
        let plan: CavePlan
        let origin: SIMD2<Float>
        /// The plan's mask on the whole map.
        let mask: [Bool]
        let pixelOrigin: SIMD2<Int>
    }

    static func place(_ plan: CavePlan) -> Placed {
        let w = CaveWall.mapWidth, h = CaveWall.mapHeight
        let origin = plan.origin
        let px = Int(origin.x) * CaveWall.scale, py = Int(origin.y) * CaveWall.scale
        var mask = [Bool](repeating: false, count: w * h)
        for y in 0..<plan.height where py + y >= 0 && py + y < h {
            for x in 0..<plan.width where px + x >= 0 && px + x < w {
                mask[(py + y) * w + px + x] = plan.mask[y * plan.width + x]
            }
        }
        return Placed(plan: plan, origin: origin, mask: mask, pixelOrigin: SIMD2(px, py))
    }

    /// The swell of rock under a painting, 0 to 1, fading to nothing at the bay's sides so bays
    /// meet. Blurred at a quarter of the size: it is broad.
    static func bulgeMap(_ mask: [Bool]) -> [Float] {
        let w = CaveWall.mapWidth, h = CaveWall.mapHeight
        let qw = w / 4, qh = h / 4
        var small = [Float](repeating: 0, count: qw * qh)
        for y in 0..<qh {
            for x in 0..<qw {
                var n = 0
                for dy in 0..<4 { for dx in 0..<4 where mask[(y * 4 + dy) * w + x * 4 + dx] { n += 1 } }
                small[y * qw + x] = Float(n) / 16
            }
        }
        let blurred = Gaussian.filter(small, width: qw, height: qh, sigma: 15, orderX: 0, orderY: 0)
        let peak = max(1e-6, blurred.max() ?? 1)
        var out = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            let fy = min(Float(qh - 1), max(0, (Float(y) + 0.5) / 4 - 0.5))
            let y0 = Int(fy), y1 = min(qh - 1, y0 + 1), ty = fy - Float(y0)
            for x in 0..<w {
                let fx = min(Float(qw - 1), max(0, (Float(x) + 0.5) / 4 - 0.5))
                let x0 = Int(fx), x1 = min(qw - 1, x0 + 1), tx = fx - Float(x0)
                let a = blurred[y0 * qw + x0] * (1 - tx) + blurred[y0 * qw + x1] * tx
                let b = blurred[y1 * qw + x0] * (1 - tx) + blurred[y1 * qw + x1] * tx
                let v = max(0, (a * (1 - ty) + b * ty) / peak)
                let side = min(Float(x), Float(w - 1 - x)) / Float(30 * CaveWall.scale)
                let window = side >= 1 ? 1 : side * side * (3 - 2 * side)
                out[y * w + x] = pow(v, 0.8) * window
            }
        }
        return out
    }

    /// The charcoal on the rock, 0 to 1: the contour, its weight from how deep in the body it
    /// runs (heavy along the back and belly, thin at legs and ears), broken where the stone's grain
    /// skips it, and the inner lines.
    static func drawing(_ placed: Placed, plan: CavePlan, index: Int) -> [Float] {
        let w = CaveWall.mapWidth, h = CaveWall.mapHeight, s = Float(CaveWall.scale)
        let mask = placed.mask
        let outside = DistanceTransform.squaredEDT(width: w, height: h) { mask[$0] }
        let edge = DistanceTransform.squaredEDT(width: w, height: h) { !mask[$0] }
        let body = Gaussian.filter(mask.map { $0 ? 1 : 0 }, width: w, height: h, sigma: 9 * s / 2, orderX: 0, orderY: 0)
        var inner = [Bool](repeating: false, count: w * h)
        let o = placed.pixelOrigin
        for y in 0..<plan.height where o.y + y >= 0 && o.y + y < h {
            for x in 0..<plan.width where o.x + x >= 0 && o.x + x < w && plan.lines[y * plan.width + x] {
                for dy in -1...1 {
                    for dx in -1...1 {
                        let xx = o.x + x + dx, yy = o.y + y + dy
                        if xx >= 0, yy >= 0, xx < w, yy < h { inner[yy * w + xx] = true }
                    }
                }
            }
        }
        var stroke = [Float](repeating: 0, count: w * h)
        let seed = 9 &+ UInt32(bitPattern: Int32(truncatingIfNeeded: index))
        for k in 0..<(w * h) {
            let dOut = outside.storage[k].squareRoot() / s
            let weight = 1.4 + 4.6 * min(1, max(0, (body[k] - 0.2) / 0.4))
            let line = (dOut > 0 && dOut < weight) || (mask[k] && edge.storage[k] <= s * s)
            var v: Float = 0
            if line {
                let x = Float(k % w) / s, y = Float(k / w) / s
                let broken = CaveNoise.fbm(x, y, size: 35, octaves: 3, seed: seed) <= -1.25
                if !broken { v = 0.85 + 0.15 * CaveNoise.unit(Int32(k % w), Int32(k / w), 3) }
            }
            if inner[k] { v += 0.6 }
            stroke[k] = v
        }
        return Gaussian.filter(stroke, width: w, height: h, sigma: 0.7 * s, orderX: 0, orderY: 0).map { min(1, max(0, $0)) }
    }

    /// Each area's dots, in its pigment, at the middle of its widest part.
    static func dots(of plan: CavePlan, at origin: SIMD2<Float>, on maps: inout Maps) {
        let s = Float(CaveWall.scale)
        for (k, spot) in plan.dotSpots().enumerated() {
            let pigment = plan.pigments[k]
            let room = spot.room / s
            let count = pigment.dots
            let gap = max(6, min(11, 1.9 * room / Float(count)))
            let centre = origin + spot.centre / s
            dotRow(centre, count: count, radius: min(4.4, 0.5 * room), gap: gap, color: pigment.rgb * 0.9, opacity: 1, on: &maps)
        }
    }

    /// `count` fingertip dots in a row, centred on `centre` (wall points within the bay).
    static func dotRow(_ centre: SIMD2<Float>, count: Int, radius: Float, gap: Float, color: SIMD3<Float>, opacity: Float, on maps: inout Maps) {
        let s = Float(CaveWall.scale)
        for d in 0..<count {
            let c = centre + SIMD2((Float(d) - Float(count - 1) / 2) * gap, 0)
            paint(around: c, reach: radius + 1, on: &maps) { p, grain in
                let dist = ((p - c) * (p - c)).sum().squareRoot()
                return (min(1, max(0, (radius - dist) * s * 0.7)) * opacity * (0.75 + 0.25 * grain), color)
            }
        }
    }

    /// Blends a color into the rock around a point: `shade` gives each map pixel's opacity and
    /// color from its wall point and a grain of the stone.
    static func paint(around c: SIMD2<Float>, reach: Float, on maps: inout Maps,
                      _ shade: (SIMD2<Float>, Float) -> (Float, SIMD3<Float>)) {
        let s = Float(CaveWall.scale), w = maps.width, h = maps.height
        let x0 = max(0, Int((c.x - reach) * s)), x1 = min(w - 1, Int((c.x + reach) * s) + 1)
        let y0 = max(0, Int((c.y - reach) * s)), y1 = min(h - 1, Int((c.y + reach) * s) + 1)
        guard x0 <= x1, y0 <= y1 else { return }
        for j in y0...y1 {
            for i in x0...x1 {
                let p = SIMD2((Float(i) + 0.5) / s, (Float(j) + 0.5) / s)
                let grain = CaveNoise.unit(Int32(i), Int32(j), 77)
                let (a, color) = shade(p, grain)
                guard a > 0 else { continue }
                let o = (j * w + i) * 4
                for ch in 0..<3 {
                    let old = Float(maps.rock[o + ch]) / 255
                    maps.rock[o + ch] = byte(old * (1 - a) + a * color[ch])
                }
            }
        }
    }

    /// Adds to the relief around a point, scaled by how far onto the ledge it is.
    static func shape(around c: SIMD2<Float>, reach: SIMD2<Float>, on maps: inout Maps, _ lift: (SIMD2<Float>) -> Float) {
        let s = Float(CaveWall.scale), w = maps.width, h = maps.height
        let x0 = max(0, Int((c.x - reach.x) * s)), x1 = min(w - 1, Int((c.x + reach.x) * s) + 1)
        let y0 = max(0, Int((c.y - reach.y) * s)), y1 = min(h - 1, Int((c.y + reach.y) * s) + 1)
        guard x0 <= x1, y0 <= y1 else { return }
        for j in y0...y1 {
            for i in x0...x1 {
                maps.relief[j * w + i] += lift(SIMD2((Float(i) + 0.5) / s, (Float(j) + 0.5) / s))
            }
        }
    }

    /// A hollow worn into the ledge holding a pigment's powder, its dots above it.
    static func hollow(_ centre: SIMD2<Float>, radii: SIMD2<Float>, pigment: CavePigment, on maps: inout Maps) {
        let bayX = Float(maps.index * CaveWall.bayWidth)
        let seed = 40 &+ UInt32(pigment.rawValue)
        func distance(_ p: SIMD2<Float>) -> Float {
            let d = (p - centre) / radii
            return (d * d).sum().squareRoot() + 0.08 * CaveNoise.fbm(bayX + p.x, p.y, size: 30, octaves: 2, seed: seed)
        }
        shape(around: centre, reach: radii * 1.3, on: &maps) { p in
            let d = distance(p)
            let bowl = pow(min(1, max(0, 1 - d)), 0.7), powder = pow(min(1, max(0, 1 - d / 0.7)), 0.8) * 0.38
            return -0.2 * bowl + powder
        }
        let color = pointwiseMin(SIMD3(repeating: 1), pigment.rgb * 1.25 + 0.05)
        paint(around: centre, reach: max(radii.x, radii.y), on: &maps) { p, grain in
            let d = ((p - centre) / (radii * 0.66))
            return (min(1, max(0, (1 - (d * d).sum().squareRoot()) * 4)) * (0.85 + (grain > 0.5 ? 0.15 : 0)), color)
        }
        dotRow(centre - SIMD2(0, radii.y + 14), count: pigment.dots, radius: 4.4, gap: 11, color: pigment.rgb * 0.85, opacity: 0.9, on: &maps)
    }

    /// The stone fat-lamp, like the one found at Lascaux: red sandstone, hollowed, black with fat.
    static func lamp(on maps: inout Maps) {
        let c = CaveWall.lamp, radii = SIMD2<Float>(25, 15)
        func distance(_ p: SIMD2<Float>) -> Float { let d = (p - c) / radii; return (d * d).sum().squareRoot() }
        shape(around: c, reach: radii * 1.2, on: &maps) { p in
            let d = distance(p)
            return pow(min(1, max(0, 1 - d)), 0.4) * 0.35 - pow(min(1, max(0, 1 - d / 0.62)), 0.6) * 0.25
        }
        paint(around: c, reach: 26, on: &maps) { p, _ in
            let d = distance(p)
            let stone = min(1, max(0, (1 - d) * 5)), soot = min(1, max(0, (1 - d / 0.6) * 5))
            return soot > 0 ? (1, SIMD3(0.55, 0.32, 0.22) * (1 - soot) + SIMD3(0.09, 0.06, 0.04) * soot) : (stone, SIMD3(0.55, 0.32, 0.22))
        }
    }

    /// A lump of charcoal on bare rock's ledge.
    static func lump(on maps: inout Maps) {
        let c = CaveWall.charcoal, radii = SIMD2<Float>(17, 9)
        let bayX = Float(maps.index * CaveWall.bayWidth)
        func distance(_ p: SIMD2<Float>) -> Float {
            let d = (p - c) / radii
            return (d * d).sum().squareRoot() + 0.18 * CaveNoise.fbm(bayX + p.x, p.y, size: 14, octaves: 2, seed: 60)
        }
        shape(around: c, reach: radii * 1.4, on: &maps) { p in 0.22 * pow(min(1, max(0, 1 - distance(p))), 0.5) }
        paint(around: c, reach: 24, on: &maps) { p, grain in
            (min(1, max(0, (1 - distance(p)) * 6)), SIMD3(0.07, 0.06, 0.055) * (0.8 + 0.4 * grain))
        }
    }

    // MARK: - Cracks

    /// A few cracks wandering across the bay: each line (0 to 1), and the groove round it.
    static func cracks(index: Int) -> (line: [Float], groove: [Float]) {
        let w = CaveWall.mapWidth, h = CaveWall.mapHeight, s = Float(CaveWall.scale)
        var random = SplitMix64(seed: 0xC4A3 &+ UInt64(bitPattern: Int64(index)) &* 0x9E37_79B9)
        var stamp = [Float](repeating: 0, count: w * h)
        let count = 3 + Int(random.next() % 2)
        for _ in 0..<count {
            var x = (0.1 + 0.8 * random.nextFloat()) * Float(w), y = random.nextFloat() * 0.7 * Float(h)
            var angle = 0.6 + random.nextFloat() * 1.9
            let steps = Int((120 + random.nextFloat() * 240) * s)
            for _ in 0..<steps {
                // A small turn each step: the sum of two uniforms, near a normal's.
                angle += (random.nextFloat() + random.nextFloat() - 1) * 0.1
                x += cos(angle)
                y += sin(angle)
                // Cracks stay off the bay's sides, so bays meet.
                guard x >= 8 * s, x < Float(w) - 8 * s, y >= 0, y < Float(h) else { break }
                stamp[Int(y) * w + Int(x)] = 1
            }
        }
        let line = Gaussian.filter(stamp, width: w, height: h, sigma: 0.6 * s, orderX: 0, orderY: 0)
        let peak = max(1e-6, line.max() ?? 1)
        let normalized = line.map { $0 / peak }
        return (normalized, Gaussian.filter(normalized, width: w, height: h, sigma: 1.5 * s, orderX: 0, orderY: 0))
    }
}
