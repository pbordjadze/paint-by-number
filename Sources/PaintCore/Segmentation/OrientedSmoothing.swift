import Foundation

/// Smoothing along the grain: fur, feathers, grass and wood run in a direction, and a designer
/// draws them as a few strokes laid along it, where plain smoothing leaves camouflage blotches.
/// Each pixel is averaged along the local orientation of least change (the minor axis of the
/// structure tensor, Weickert's coherence-enhancing idea reduced to one straight line integral),
/// as far as the texture is coherent (one direction) and texture rather than a contour (the
/// gradients along it alternate, see `StructureMap`), so a clean edge is never smeared and
/// isotropic noise is left to the edge-preserving filter after it. Streaks laid this way turn
/// into elongated regions that follow the grain.
///
/// Deterministic: every pixel is computed on its own from the input, in float32, with the same
/// samples in the same order whatever the band layout.
enum OrientedSmoothing {
    /// Box radius (two passes) the structure tensor is averaged over: a few pixels, the width of
    /// a strand or two.
    static let tensorRadius = 2
    /// Coherence below this (the tensor's eigenvalue contrast, 0...1) counts as no direction.
    static let coherenceFloor: Float = 0.2

    /// `lab` with its lightness smoothed along the grain (the chroma stays: averaging hues
    /// across a strand's neighbours would drain them): `length` the half-length of the line
    /// (canvas units), `texture` per pixel how much the gradients there are texture rather than a
    /// contour (0...1; `StructureMap.textureness`), `within` which pixels take it (the subject).
    static func apply(
        _ lab: Grid<SIMD4<Float>>, length: Float, texture: [Float], within: [Bool], cancel: CancellationCheck
    ) throws -> Grid<SIMD4<Float>> {
        let w = lab.width, h = lab.height, n = w * h
        guard w > 2, h > 2, length >= 1 else { return lab }
        // The structure tensor of the lightness, averaged.
        var jxx = [Float](repeating: 0, count: n), jyy = [Float](repeating: 0, count: n), jxy = [Float](repeating: 0, count: n)
        lab.storage.withUnsafeBufferPointer { src in
            for y in 1..<(h - 1) {
                let row = y * w
                for x in 1..<(w - 1) {
                    let gx = (src[row + x + 1].x - src[row + x - 1].x) * 0.5
                    let gy = (src[row + w + x].x - src[row - w + x].x) * 0.5
                    jxx[row + x] = gx * gx
                    jyy[row + x] = gy * gy
                    jxy[row + x] = gx * gy
                }
            }
        }
        jxx = try BoxBlur.apply(jxx, width: w, height: h, radius: tensorRadius, passes: 2, cancel: cancel)
        jyy = try BoxBlur.apply(jyy, width: w, height: h, radius: tensorRadius, passes: 2, cancel: cancel)
        jxy = try BoxBlur.apply(jxy, width: w, height: h, radius: tensorRadius, passes: 2, cancel: cancel)
        try cancel.throwIfCancelled()

        let samples = max(1, Int(length.rounded()))
        // Gaussian taps along the line, sigma half the length; the center tap included.
        let sigma = max(1, length / 2)
        var taps = [Float](repeating: 0, count: samples + 1)
        for k in 0...samples { taps[k] = exp(-Float(k * k) / (2 * sigma * sigma)) }

        var out = [SIMD4<Float>](uninitializedCount: n)
        try lab.storage.withUnsafeBufferPointer { src in
            try out.withUnsafeMutableBufferPointer { dst in
                try jxx.withUnsafeBufferPointer { xxb in
                    try jyy.withUnsafeBufferPointer { yyb in
                        try jxy.withUnsafeBufferPointer { xyb in
                            try texture.withUnsafeBufferPointer { tb in
                                try taps.withUnsafeBufferPointer { tapb in
                                  try within.withUnsafeBufferPointer { wb in
                                    let s = UncheckedSendable(src.baseAddress!), d = UncheckedSendable(dst.baseAddress!)
                                    let xx = UncheckedSendable(xxb.baseAddress!), yy = UncheckedSendable(yyb.baseAddress!)
                                    let xy = UncheckedSendable(xyb.baseAddress!), t = UncheckedSendable(tb.baseAddress!)
                                    let g = UncheckedSendable(tapb.baseAddress!), inside = UncheckedSendable(wb.baseAddress!)
                                    try Parallel.forEachBand(h, minimumBandSize: 8, wave: Parallel.waveRows(width: w), cancel: cancel) { rows in
                                        for y in rows {
                                            for x in 0..<w {
                                                let i = y * w + x
                                                guard inside.value[i] else { d.value[i] = s.value[i]; continue }
                                                let a = xx.value[i], b = yy.value[i], c = xy.value[i]
                                                let trace = a + b
                                                guard trace > 1e-8 else { d.value[i] = s.value[i]; continue }
                                                let diff = a - b
                                                let root = (diff * diff + 4 * c * c).squareRoot()
                                                // Eigenvalue contrast: 1 for one direction, 0 for none.
                                                let coherence = root / trace
                                                let weight = max(0, (coherence - coherenceFloor) / (1 - coherenceFloor)) * t.value[i]
                                                guard weight > 0.01 else { d.value[i] = s.value[i]; continue }
                                                // The major eigenvector (the gradient's direction) is (c, λ1 − a) or
                                                // (λ1 − b, c); the grain runs perpendicular to it.
                                                let lambda1 = (trace + root) * 0.5
                                                var ex = c, ey = lambda1 - a
                                                if abs(ex) + abs(ey) < 1e-12 { ex = lambda1 - b; ey = c }
                                                let norm = (ex * ex + ey * ey).squareRoot()
                                                guard norm > 1e-12 else { d.value[i] = s.value[i]; continue }
                                                // Grain direction: perpendicular to the gradient.
                                                let tx = -ey / norm, ty = ex / norm
                                                var sum = s.value[i] * g.value[0]
                                                var total = g.value[0]
                                                for k in 1...samples {
                                                    let fk = Float(k)
                                                    for sign: Float in [-1, 1] {
                                                        let px = Float(x) + sign * fk * tx, py = Float(y) + sign * fk * ty
                                                        guard px >= 0, py >= 0, px <= Float(w - 1), py <= Float(h - 1) else { continue }
                                                        let x0 = Int(px), y0 = Int(py)
                                                        let x1 = min(x0 + 1, w - 1), y1 = min(y0 + 1, h - 1)
                                                        let fx = px - Float(x0), fy = py - Float(y0)
                                                        let top = s.value[y0 * w + x0] * (1 - fx) + s.value[y0 * w + x1] * fx
                                                        let bottom = s.value[y1 * w + x0] * (1 - fx) + s.value[y1 * w + x1] * fx
                                                        sum += (top * (1 - fy) + bottom * fy) * g.value[k]
                                                        total += g.value[k]
                                                    }
                                                }
                                                let along = sum / total
                                                var value = s.value[i]
                                                value.x = value.x * (1 - weight) + along.x * weight
                                                d.value[i] = value
                                            }
                                        }
                                    }
                                  }
                                }
                            }
                        }
                    }
                }
            }
        }
        return Grid(width: w, height: h, storage: out)
    }
}
