import Foundation

/// Tells structure from texture, per pixel and axis, with relative total variation (Xu et al.,
/// "Structure Extraction from Texture via Relative Total Variation", 2012).
///
/// Over a small window, the gradients of a real edge point the same way, so the magnitude of
/// their sum equals the sum of their magnitudes; in texture (weave, ripples, foliage, stains)
/// they alternate and cancel. The ratio of the two (0 = texture … 1 = structure) scales how
/// strongly the edge-preserving filter stops at a gradient, so it flattens texture into
/// painterly patches but still halts at contours.
struct StructureMap {
    let width: Int
    let height: Int
    /// Window sums of the horizontal / vertical color steps; `w` holds the sum of step
    /// magnitudes, `xyz` the summed step vectors.
    let horizontal: [SIMD4<Float>]
    let vertical: [SIMD4<Float>]

    /// - Parameter radius: Window radius (box, applied twice) in pixels.
    init(_ lab: Grid<SIMD4<Float>>, radius: Int, cancel: CancellationCheck = .none) throws {
        precondition(radius > 0 && lab.count > 0)
        let w = lab.width, h = lab.height
        width = w
        height = h
        // Steps are produced row by row inside the blur's first pass.
        (horizontal, vertical) = try lab.storage.withUnsafeBufferPointer { src in
            let s = UncheckedSendable(src.baseAddress!)
            @inline(__always) func step(_ a: SIMD4<Float>, _ b: SIMD4<Float>) -> SIMD4<Float> {
                var d = a - b
                d.w = 0
                d.w = (d * d).sum().squareRoot()
                return d
            }
            var scratch: [SIMD4<Float>] = []
            let horizontal = try BoxBlur.blur(
                width: w, height: h, radius: radius, passes: 2, cancel: cancel, scratch: &scratch
            ) { (y: Int, row: UnsafeMutablePointer<SIMD4<Float>>) in
                let line = s.value + y * w
                row[0] = .zero
                for x in 1..<w { row[x] = step(line[x], line[x - 1]) }
            }
            try cancel.throwIfCancelled()
            let vertical = try BoxBlur.blur(
                width: w, height: h, radius: radius, passes: 2, cancel: cancel, scratch: &scratch
            ) { (y: Int, row: UnsafeMutablePointer<SIMD4<Float>>) in
                let line = s.value + y * w
                if y == 0 {
                    for x in 0..<w { row[x] = .zero }
                } else {
                    for x in 0..<w { row[x] = step(line[x], line[x - w]) }
                }
            }
            return (horizontal, vertical)
        }
    }

    /// Magnitude of the coherent (non-cancelling) gradient: high on contours, low in flat
    /// areas and in texture alike.
    func coherentMagnitude() -> [Float] {
        var out = [Float](uninitializedCount: width * height)
        horizontal.withUnsafeBufferPointer { hb in
            vertical.withUnsafeBufferPointer { vb in
                out.withUnsafeMutableBufferPointer { ob in
                    let hp = UncheckedSendable(hb.baseAddress!)
                    let vp = UncheckedSendable(vb.baseAddress!)
                    let op = UncheckedSendable(ob.baseAddress!)
                    Parallel.forEachBand(ob.count, minimumBandSize: 16_384) { range in
                        for i in range {
                            var a = hp.value[i], b = vp.value[i]
                            a.w = 0
                            b.w = 0
                            op.value[i] = (a * a).sum().squareRoot() + (b * b).sum().squareRoot()
                        }
                    }
                }
            }
        }
        return out
    }

    /// Per-pixel factors (0...1) for the filter's horizontal and vertical gradient terms.
    /// - Parameters:
    ///   - importance: Areas with importance → 1 keep full edge-stopping (eyelashes, a
    ///     macaw's facial stripes are "texture" by this measure but must survive).
    ///   - strength: 0 disables texture flattening, 1 applies it fully.
    func edgeScales(
        importance: [Float], strength: Float, exponent: Float, cancel: CancellationCheck = .none
    ) throws -> (horizontal: [Float], vertical: [Float]) {
        let n = width * height
        var sh = [Float](uninitializedCount: n)
        var sv = [Float](uninitializedCount: n)
        try horizontal.withUnsafeBufferPointer { xb in
            try vertical.withUnsafeBufferPointer { yb in
                try importance.withUnsafeBufferPointer { ib in
                    try sh.withUnsafeMutableBufferPointer { hb in
                        try sv.withUnsafeMutableBufferPointer { vb in
                            let xp = UncheckedSendable(xb.baseAddress!)
                            let yp = UncheckedSendable(yb.baseAddress!)
                            let ip = UncheckedSendable(ib.baseAddress!)
                            let hp = UncheckedSendable(hb.baseAddress!)
                            let vp = UncheckedSendable(vb.baseAddress!)
                            try Parallel.forEachBand(n, minimumBandSize: 16_384, wave: Parallel.wavePixels, cancel: cancel) { range in
                                for i in range {
                                    let keep = ip.value[i] * ip.value[i]
                                    hp.value[i] = Self.scale(xp.value[i], keep: keep, strength: strength, exponent: exponent)
                                    vp.value[i] = Self.scale(yp.value[i], keep: keep, strength: strength, exponent: exponent)
                                }
                            }
                        }
                    }
                }
            }
        }
        return (sh, sv)
    }

    @inline(__always)
    private static func scale(_ g: SIMD4<Float>, keep: Float, strength: Float, exponent: Float) -> Float {
        var coherent = g
        coherent.w = 0
        let ratio = min((coherent * coherent).sum().squareRoot() / (g.w + 1e-4), 1)
        let flattened = max(1 - strength * (1 - pow(ratio, exponent)), 0)
        return flattened + (1 - flattened) * keep
    }
}
