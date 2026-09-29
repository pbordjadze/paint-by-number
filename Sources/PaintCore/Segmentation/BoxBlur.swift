import Foundation

/// Repeated box blur (≈ Gaussian after 2–3 passes) with edge-normalized windows, O(1) per
/// pixel in the radius. Rows run in parallel; columns in parallel bands of whole rows so
/// memory access stays sequential.
enum BoxBlur {

    static func apply(
        _ input: [SIMD4<Float>], width w: Int, height h: Int, radius r: Int, passes: Int, cancel: CancellationCheck = .none
    ) throws -> [SIMD4<Float>] {
        guard w > 0, h > 0, r > 0, passes > 0 else { return input }
        return try input.withUnsafeBufferPointer { src in
            let s = UncheckedSendable(src.baseAddress!)
            var scratch: [SIMD4<Float>] = []
            return try blur(width: w, height: h, radius: r, passes: passes, cancel: cancel, scratch: &scratch) { y, row in
                row.update(from: s.value + y * w, count: w)
            }
        }
    }

    static func apply(
        _ input: [Float], width w: Int, height h: Int, radius r: Int, passes: Int, cancel: CancellationCheck = .none
    ) throws -> [Float] {
        guard w > 0, h > 0, r > 0, passes > 0 else { return input }
        return try input.withUnsafeBufferPointer { src in
            let s = UncheckedSendable(src.baseAddress!)
            var scratch: [Float] = []
            return try blur(width: w, height: h, radius: r, passes: passes, cancel: cancel, scratch: &scratch) { y, row in
                row.update(from: s.value + y * w, count: w)
            }
        }
    }

    /// Blurs an image whose rows `source(y, into:)` produces on demand (called concurrently
    /// for different rows), so the unblurred image never has to be stored. `scratch` (any
    /// contents) is used as the intermediate buffer when it has the image's size, and holds
    /// that buffer afterwards, so consecutive blurs share it.
    @inline(__always)
    static func blur<T: Blurrable>(
        width w: Int, height h: Int, radius r: Int, passes: Int, cancel: CancellationCheck = .none,
        scratch: inout [T],
        source: (Int, UnsafeMutablePointer<T>) -> Void
    ) throws -> [T] {
        let n = w * h
        let waveRows = Parallel.waveRows(width: w)
        // Reciprocal window sizes along a row (edge windows are clipped).
        let inverse = (0..<w).map { x in 1 / Float(min(x + r, w - 1) - max(x - r, 0) + 1) }
        var a = [T](uninitializedCount: n)
        var b = scratch.count == n ? scratch : [T](uninitializedCount: n)
        scratch = []
        defer { scratch = b }
        // Running column sums, kept across the waves of a column pass.
        var sums = [T](repeating: .zero, count: w)
        try a.withUnsafeMutableBufferPointer { ab in
            try b.withUnsafeMutableBufferPointer { bb in
                try inverse.withUnsafeBufferPointer { ib in
                    try sums.withUnsafeMutableBufferPointer { sb in
                        let ap = UncheckedSendable(ab.baseAddress!)
                        let bp = UncheckedSendable(bb.baseAddress!)
                        let inv = UncheckedSendable(ib.baseAddress!)
                        let acc = UncheckedSendable(sb.baseAddress!)
                        for pass in 0..<passes {
                            try Parallel.forEachBand(h, minimumBandSize: 8, wave: waveRows, cancel: cancel) { rows in
                                withUnsafeTemporaryAllocation(of: T.self, capacity: pass == 0 ? w : 0) { scratch in
                                    for y in rows {
                                        let row: UnsafePointer<T>
                                        if pass == 0 {
                                            source(y, scratch.baseAddress!)
                                            row = UnsafePointer(scratch.baseAddress!)
                                        } else {
                                            row = UnsafePointer(ap.value + y * w)
                                        }
                                        let out = bp.value + y * w
                                        var sum = T.zero
                                        for x in 0..<min(r, w) { sum += row[x] }
                                        for x in 0..<w {
                                            if x + r < w { sum += row[x + r] }
                                            if x - r - 1 >= 0 { sum -= row[x - r - 1] }
                                            out[x] = sum.scaled(inv.value[x])
                                        }
                                    }
                                }
                            }
                            try cancel.throwIfCancelled()
                            let s = bp, d = ap
                            var y0 = 0
                            while y0 < h {
                                let y1 = min(h, y0 + waveRows)
                                Parallel.forEachBand(w, minimumBandSize: 32) { cols in
                                    let c0 = cols.lowerBound, span = cols.count
                                    let column = acc.value + c0
                                    if y0 == 0 {
                                        for k in 0..<span { column[k] = .zero }
                                        for y in 0..<min(r, h) {
                                            let row = s.value + y * w + c0
                                            for k in 0..<span { column[k] += row[k] }
                                        }
                                    }
                                    for y in y0..<y1 {
                                        let inv = 1 / Float(min(y + r, h - 1) - max(y - r, 0) + 1)
                                        if y + r < h {
                                            let add = s.value + (y + r) * w + c0
                                            for k in 0..<span { column[k] += add[k] }
                                        }
                                        if y - r - 1 >= 0 {
                                            let sub = s.value + (y - r - 1) * w + c0
                                            for k in 0..<span { column[k] -= sub[k] }
                                        }
                                        let out = d.value + y * w + c0
                                        for k in 0..<span { out[k] = column[k].scaled(inv) }
                                    }
                                }
                                y0 = y1
                                if y0 < h { try cancel.throwIfCancelled() }
                            }
                        }
                    }
                }
            }
        }
        return a
    }
}

protocol Blurrable: BitwiseCopyable {
    static var zero: Self { get }
    static func += (lhs: inout Self, rhs: Self)
    static func -= (lhs: inout Self, rhs: Self)
    func scaled(_ s: Float) -> Self
}

extension Float: Blurrable {
    @inline(__always) func scaled(_ s: Float) -> Float { self * s }
}

extension SIMD4: Blurrable where Scalar == Float {
    @inline(__always) func scaled(_ s: Float) -> SIMD4<Float> { self * s }
}
