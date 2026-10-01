import Foundation
import Testing
@testable import PaintCore

@Suite("CurveFitter")
struct CurveFitterTests {

    // MARK: - Helpers

    /// The fitter at the boundary smoothing's crisp end (no fillets).
    static func crisp() -> CurveFitter {
        CurveFitter(alphaMax: 0.6, minCornerAngle: 35, cornerRadius: 0, flattenTolerance: 0.05)
    }

    /// The fitter at the paper's default corner threshold, as `EdgeSmoother` uses at smoothness 0.5.
    static func standard() -> CurveFitter {
        CurveFitter(alphaMax: 1, minCornerAngle: 55, cornerRadius: 0, flattenTolerance: 0.05)
    }

    /// Lattice chains of the interior edges of a class map (classes split into 4-connected regions).
    static func chains(width: Int, height: Int, _ classOf: (Int, Int) -> UInt32) throws -> [(points: [SIMD2<Int32>], closed: Bool)] {
        var classes = [UInt32](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width { classes[y * width + x] = classOf(x, y) }
        }
        let labels = ConnectedComponents.label(Grid(width: width, height: height, storage: classes)).labels
        let graph = try BoundaryGraph.build(labels: labels)
        var result: [(points: [SIMD2<Int32>], closed: Bool)] = []
        var points: [SIMD2<Int32>] = []
        for e in 0..<graph.edgeCount where graph.edgeRight[e] != BoundaryEdge.outside {
            graph.latticePoints(e, into: &points)
            result.append((points, graph.edgeClosed[e]))
        }
        return result
    }

    /// The single closed boundary of a shape drawn away from the canvas border.
    static func loop(width: Int, height: Int, _ inside: (Int, Int) -> Bool) throws -> [SIMD2<Int32>] {
        let found = try chains(width: width, height: height) { inside($0, $1) ? 1 : 0 }
        #expect(found.count == 1 && found[0].closed)
        return found[0].points
    }

    /// Lower boundary of the half-plane y ≥ (x·num + offset) / den over `columns` pixel
    /// columns: a digitized straight line of slope num/den as an east/south staircase.
    static func staircase(num: Int, den: Int, columns: Int, offset: Int = 0) -> [SIMD2<Int32>] {
        func top(_ x: Int) -> Int { (x * num + offset + den - 1) / den }
        var points = [SIMD2<Int32>(0, Int32(top(0)))]
        for x in 0..<columns {
            points.append(SIMD2(Int32(x + 1), Int32(top(x))))
            if x + 1 < columns {
                for y in top(x)..<top(x + 1) { points.append(SIMD2(Int32(x + 1), Int32(y + 1))) }
            }
        }
        return points
    }

    static func double(_ p: SIMD2<Int32>) -> SIMD2<Double> { SIMD2(Double(p.x), Double(p.y)) }

    static func length(_ v: SIMD2<Double>) -> Double { (v * v).sum().squareRoot() }

    static func segmentDistance(_ p: SIMD2<Double>, _ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
        let d = b - a, l2 = (d * d).sum()
        let t = l2 > 0 ? min(max(((p - a) * d).sum() / l2, 0), 1) : 0
        return length(p - (a + d * t))
    }

    /// Largest distance from any point of `curve` to the polyline `lattice`.
    static func deviation(_ curve: [SIMD2<Double>], from lattice: [SIMD2<Int32>]) -> Double {
        curve.map { p in
            (0..<(lattice.count - 1)).map { segmentDistance(p, double(lattice[$0]), double(lattice[$0 + 1])) }.min()!
        }.max()!
    }

    static func signedArea(_ ring: [SIMD2<Double>]) -> Double {
        var sum = 0.0
        for i in 0..<(ring.count - 1) { sum += ring[i].x * ring[i + 1].y - ring[i].y * ring[i + 1].x }
        return sum / 2
    }

    /// Largest turn (radians) between consecutive segments of a closed polyline.
    static func maxTurn(_ ring: [SIMD2<Double>]) -> Double {
        let n = ring.count - 1
        var worst = 0.0
        for i in 0..<n {
            let a = ring[(i + n - 1) % n], b = ring[i], c = ring[(i + 1) % n]
            let u = b - a, v = c - b
            worst = max(worst, abs(atan2(u.x * v.y - u.y * v.x, (u * v).sum())))
        }
        return worst
    }

    // MARK: - Straight lines

    @Test func digitalStraightLinesFitOneSegment() {
        var fitter = Self.standard()
        var out = DenseCurve()
        for (num, den) in [(0, 1), (1, 3), (2, 5), (1, 1), (3, 7), (1, 9), (5, 2), (7, 3), (13, 29)] {
            for offset in [0, 1, den / 2] {
                let chain = Self.staircase(num: num, den: den, columns: 70, offset: offset)
                #expect(fitter.fitOpen(chain, into: &out))
                #expect(out.points == [Self.double(chain.first!), Self.double(chain.last!)], "slope \(num)/\(den) offset \(offset)")
                #expect(out.pinned == [true, true])
            }
        }
    }

    // MARK: - Round shapes

    @Test(arguments: [4.0, 9.5, 20, 40, 75])
    func circlesStayRound(radius: Double) throws {
        let size = Int(2 * radius) + 10, c = Double(size) / 2
        let ring = try Self.loop(width: size, height: size) { x, y in
            let dx = Double(x) + 0.5 - c, dy = Double(y) + 0.5 - c
            return dx * dx + dy * dy < radius * radius
        }
        // Small circles have polygons with few, sharply turning vertices, which the crisp
        // setting keeps as corners.
        for var fitter in radius >= 20 ? [Self.crisp(), Self.standard()] : [Self.standard()] {
            var out = DenseCurve()
            #expect(fitter.fitClosed(ring, into: &out))
            #expect(out.points.first == out.points.last)
            #expect(!out.pinned.contains(true))
            let radii = out.points.map { Self.length($0 - SIMD2(c, c)) }
            #expect(radii.allSatisfy { abs($0 - radius) < 0.6 }, "radius \(radius): \(radii.min()!)…\(radii.max()!)")
            #expect(radii.max()! - radii.min()! < 0.6)
            #expect(Self.maxTurn(out.points) < max(0.25, 2.2 / radius))
            let area = Double.pi * radius * radius
            #expect(abs(abs(Self.signedArea(out.points)) - area) < (radius < 5 ? 0.2 : 0.04) * area)
        }
    }

    @Test func ellipsesStayRound() throws {
        let ring = try Self.loop(width: 140, height: 80) { x, y in
            let dx = (Double(x) + 0.5 - 70) / 60, dy = (Double(y) + 0.5 - 40) / 25
            return dx * dx + dy * dy < 1
        }
        var fitter = Self.standard()
        var out = DenseCurve()
        #expect(fitter.fitClosed(ring, into: &out))
        #expect(!out.pinned.contains(true))
        #expect(Self.maxTurn(out.points) < 0.3)
        #expect(Self.deviation(out.points, from: ring) < 0.75)
    }

    // MARK: - Corners

    @Test func squareKeepsSharpCorners() throws {
        let ring = try Self.loop(width: 30, height: 30) { x, y in x >= 5 && x < 25 && y >= 5 && y < 25 }
        var out = DenseCurve()
        for var fitter in [Self.crisp(), Self.standard()] {
            #expect(fitter.fitClosed(ring, into: &out))
            #expect(out.points.first == out.points.last)
            let pinned = Set(out.points.indices.filter { out.pinned[$0] }.map { out.points[$0] })
            #expect(pinned == [SIMD2(5, 5), SIMD2(25, 5), SIMD2(25, 25), SIMD2(5, 25)])
            // Everything else lies on the square's sides.
            for p in out.points {
                #expect((p.x == 5 || p.x == 25) && p.y >= 5 && p.y <= 25 || (p.y == 5 || p.y == 25) && p.x >= 5 && p.x <= 25)
            }
        }
    }

    @Test func cornerRadiusRoundsCorners() throws {
        let ring = try Self.loop(width: 30, height: 30) { x, y in x >= 5 && x < 25 && y >= 5 && y < 25 }
        var fitter = CurveFitter(alphaMax: 1, minCornerAngle: 75, cornerRadius: 2, flattenTolerance: 0.05)
        var out = DenseCurve()
        #expect(fitter.fitClosed(ring, into: &out))
        #expect(out.points.first == out.points.last)
        for corner in [SIMD2<Double>(5, 5), SIMD2(25, 5), SIMD2(25, 25), SIMD2(5, 25)] {
            // A quarter circle of radius 2 passes 2(√2 − 1) from the corner it rounds.
            let nearest = out.points.map { Self.length($0 - corner) }.min()!
            #expect(abs(nearest - 2 * (2.0.squareRoot() - 1)) < 0.05)
            let fillet = out.points.indices.filter { Self.length(out.points[$0] - corner) < 2.01 }
            #expect(fillet.allSatisfy { out.pinned[$0] })
        }
        #expect(out.points.allSatisfy { $0.x >= 5 && $0.x <= 25 && $0.y >= 5 && $0.y <= 25 })
    }

    @Test func gentleBendsStaySmooth() {
        // Long sides meeting at a 26.6° bend: α is high there, but it is no corner unless
        // the minimum corner angle allows it.
        var chain: [SIMD2<Int32>] = (0...40).map { SIMD2(Int32($0), 0) }
        for p in Self.staircase(num: 1, den: 2, columns: 40).dropFirst() { chain.append(SIMD2(40, 0) &+ p) }
        var out = DenseCurve()
        var smooth = Self.crisp()
        #expect(smooth.fitOpen(chain, into: &out))
        #expect(out.pinned.dropFirst().dropLast().allSatisfy { !$0 })
        var sharp = CurveFitter(alphaMax: 0.6, minCornerAngle: 20, cornerRadius: 0, flattenTolerance: 0.05)
        #expect(sharp.fitOpen(chain, into: &out))
        let corners = out.points.indices.dropFirst().dropLast().filter { out.pinned[$0] }
        #expect(corners.count == 1)
        #expect(corners.allSatisfy { Self.length(out.points[$0] - SIMD2(40, 0)) < 1 })
    }

    // MARK: - Open chains and loops

    @Test func openChainsKeepPinnedEnds() throws {
        // Every interior edge of a blobby class map, open or closed, at both ends of the
        // smoothness range.
        var rng = SplitMix64(seed: 7)
        let w = 90, h = 70, cell = 9
        let coarse = (0..<((w / cell + 2) * (h / cell + 2))).map { _ in UInt32(rng.next() % 4) }
        let found = try Self.chains(width: w, height: h) { x, y in
            let cx = (x + (y % 5)) / cell, cy = (y + (x % 7)) / cell
            return coarse[cy * (w / cell + 2) + cx]
        }
        #expect(found.contains { !$0.closed } && found.contains { $0.closed })
        for var fitter in [Self.crisp(), Self.standard(), CurveFitter(alphaMax: 1, minCornerAngle: 75, cornerRadius: 3, flattenTolerance: 0.05)] {
            var out = DenseCurve()
            for chain in found {
                let ok = chain.closed ? fitter.fitClosed(chain.points, into: &out) : fitter.fitOpen(chain.points, into: &out)
                #expect(ok)
                #expect(out.points.count == out.pinned.count)
                if chain.closed {
                    #expect(out.points.count >= 4 && out.points.first == out.points.last)
                } else {
                    #expect(out.points.first == Self.double(chain.points.first!))
                    #expect(out.points.last == Self.double(chain.points.last!))
                    #expect(out.pinned.first == true && out.pinned.last == true)
                }
                #expect(Self.deviation(out.points, from: chain.points) < 0.8)
            }
        }
    }

    @Test func loopThroughAJunctionKeepsItsEnd() {
        // A 10×6 rectangle traced from a point on its top side back to that point.
        var chain: [SIMD2<Int32>] = []
        for x in 4...10 { chain.append(SIMD2(Int32(x), 0)) }
        for y in 1...6 { chain.append(SIMD2(10, Int32(y))) }
        for x in stride(from: 9, through: 0, by: -1) { chain.append(SIMD2(Int32(x), 6)) }
        for y in stride(from: 5, through: 0, by: -1) { chain.append(SIMD2(0, Int32(y))) }
        for x in 1...4 { chain.append(SIMD2(Int32(x), 0)) }
        var fitter = Self.crisp()
        var out = DenseCurve()
        #expect(fitter.fitOpen(chain, into: &out))
        #expect(out.points.first == SIMD2(4, 0) && out.points.last == SIMD2(4, 0))
        #expect(out.pinned.first == true && out.pinned.last == true)
        #expect(Set(out.points.indices.filter { out.pinned[$0] }.map { out.points[$0] })
            == [SIMD2(4, 0), SIMD2(10, 0), SIMD2(10, 6), SIMD2(0, 6), SIMD2(0, 0)])
        #expect(abs(Self.signedArea(out.points)) == 60)
    }

    @Test func shortChains() {
        var fitter = Self.standard()
        var out = DenseCurve()
        #expect(fitter.fitOpen([SIMD2(3, 4), SIMD2(4, 4)], into: &out))
        #expect(out.points == [SIMD2(3, 4), SIMD2(4, 4)] && out.pinned == [true, true])
        #expect(fitter.fitOpen([SIMD2(3, 4), SIMD2(4, 4), SIMD2(4, 5)], into: &out))
        #expect(out.points.first == SIMD2(3, 4) && out.points.last == SIMD2(4, 5))
        #expect(!fitter.fitOpen([SIMD2(3, 4)], into: &out))
        #expect(!fitter.fitClosed([SIMD2(0, 0), SIMD2(1, 0), SIMD2(0, 0)], into: &out))
        // Not a lattice chain.
        #expect(!fitter.fitOpen([SIMD2(0, 0), SIMD2(2, 0)], into: &out))
    }

    @Test func tinyLoopsComeOutRound() throws {
        let shapes: [[(Int, Int)]] = [
            [(0, 0)], [(0, 0), (1, 0)], [(0, 0), (0, 1)], [(0, 0), (1, 0), (0, 1), (1, 1)],
            [(0, 0), (1, 0), (2, 0)], [(0, 0), (1, 0), (0, 1)], [(0, 0), (1, 0), (2, 0), (1, 1)],
            [(1, 0), (0, 1), (1, 1), (2, 1), (1, 2)],
        ]
        for var fitter in [Self.crisp(), Self.standard()] {
            for shape in shapes {
                let ring = try Self.loop(width: 7, height: 7) { x, y in shape.contains { $0.0 + 2 == x && $0.1 + 2 == y } }
                var out = DenseCurve()
                #expect(fitter.fitClosed(ring, into: &out), "\(shape)")
                #expect(out.points.count >= 4 && out.points.first == out.points.last)
                #expect(Set(out.points).count >= 3)
                let lattice = Self.signedArea(ring.map(Self.double))
                let fitted = Self.signedArea(out.points)
                // Rounded, same orientation, and neither collapsed nor blown up.
                #expect(fitted * lattice > 0)
                #expect(abs(fitted) > 0.5 * abs(lattice) && abs(fitted) <= abs(lattice) + 0.01, "\(shape): \(fitted) vs \(lattice)")
                #expect(Self.deviation(out.points, from: ring) < 0.75)
            }
        }
    }

    @Test func closedFitDoesNotDependOnWhereTheChainStarts() throws {
        // The optimal polygon of a closed path is a cycle: tracing the same loop from
        // another point must give the same curve. (A shape with corners and inflections, so
        // the joined curves cannot depend on where the cycle is cut either.)
        let ring = try Self.loop(width: 70, height: 60) { x, y in
            let dx = Double(x) - 33, dy = Double(y) - 28
            let a = atan2(dy, dx)
            return dx * dx + dy * dy < pow(22 + 5 * sin(3 * a) + 2 * cos(7 * a + 1), 2) || (x >= 45 && x < 62 && y >= 20 && y < 34)
        }
        var fitter = Self.standard()
        var reference = DenseCurve()
        #expect(fitter.fitClosed(ring, into: &reference))
        let points = reference.points.dropLast()
        for shift in [1, 17, ring.count / 2, ring.count - 3] {
            let rotated = Array(ring[shift..<(ring.count - 1)] + ring[0...shift])
            var out = DenseCurve()
            #expect(fitter.fitClosed(rotated, into: &out))
            #expect(out.points.count == reference.points.count)
            guard out.points.count == reference.points.count,
                let offset = points.firstIndex(where: { Self.length($0 - out.points[0]) < 1e-9 })
            else {
                Issue.record("shift \(shift): different curve")
                continue
            }
            for (i, p) in out.points.dropLast().enumerated() {
                #expect(Self.length(p - points[(offset + i) % points.count]) < 1e-9)
                #expect(out.pinned[i] == reference.pinned[(offset + i) % points.count])
            }
        }
    }

    // MARK: - Determinism

    @Test func deterministicAcrossReuse() throws {
        let ring = try Self.loop(width: 60, height: 60) { x, y in
            let dx = Double(x) - 30, dy = Double(y) - 30
            return dx * dx + 2 * dy * dy + 9 * sin(Double(x) / 3) < 500
        }
        let line = Self.staircase(num: 3, den: 11, columns: 50)
        let speck = try Self.loop(width: 5, height: 5) { x, y in x == 2 && y == 2 }
        var fresh = DenseCurve(), reused = DenseCurve(), scratch = DenseCurve()
        var a = Self.standard()
        #expect(a.fitClosed(ring, into: &fresh))
        // Scratch state left by other chains must not leak into the next fit.
        var b = Self.standard()
        #expect(b.fitOpen(line, into: &scratch))
        #expect(b.fitClosed(speck, into: &scratch))
        #expect(b.fitClosed(ring, into: &reused))
        #expect(fresh.points == reused.points && fresh.pinned == reused.pinned)
        #expect(b.fitOpen(line, into: &reused))
        #expect(a.fitOpen(line, into: &fresh))
        #expect(fresh.points == reused.points && fresh.pinned == reused.pinned)
    }
}
