import Foundation

/// Repeated box blur (≈ Gaussian after 2–3 passes) with edge-normalized windows, O(1) per
/// pixel in the radius. Rows run in parallel; columns in parallel bands of whole rows so
/// memory access stays sequential.
enum BoxBlur {

    static func apply(_ input: [SIMD4<Float>], width w: Int, height h: Int, radius r: Int, passes: Int) -> [SIMD4<Float>] {
        guard w > 0, h > 0, r > 0, passes > 0 else { return input }
        return input.withUnsafeBufferPointer { src in
            let s = UncheckedSendable(src.baseAddress!)
            return blur(width: w, height: h, radius: r, passes: passes) { y, row in row.update(from: s.value + y * w, count: w) }
        }
    }

    static func apply(_ input: [Float], width w: Int, height h: Int, radius r: Int, passes: Int) -> [Float] {
        guard w > 0, h > 0, r > 0, passes > 0 else { return input }
        return input.withUnsafeBufferPointer { src in
            let s = UncheckedSendable(src.baseAddress!)
            return blur(width: w, height: h, radius: r, passes: passes) { y, row in row.update(from: s.value + y * w, count: w) }
        }
    }

    /// Blurs an image whose rows `source(y, into:)` produces on demand (called concurrently
    /// for different rows), so the unblurred image never has to be stored.
    @inline(__always)
    static func blur<T: Blurrable>(
        width w: Int, height h: Int, radius r: Int, passes: Int,
        source: (Int, UnsafeMutablePointer<T>) -> Void
    ) -> [T] {
        let n = w * h
        // Reciprocal window sizes along a row (edge windows are clipped).
        let inverse = (0..<w).map { x in 1 / Float(min(x + r, w - 1) - max(x - r, 0) + 1) }
        var a = [T](unsafeUninitializedCapacity: n) { _, count in count = n }
        var b = [T](unsafeUninitializedCapacity: n) { _, count in count = n }
        a.withUnsafeMutableBufferPointer { ab in
            b.withUnsafeMutableBufferPointer { bb in
                inverse.withUnsafeBufferPointer { ib in
                    let ap = UncheckedSendable(ab.baseAddress!)
                    let bp = UncheckedSendable(bb.baseAddress!)
                    let inv = UncheckedSendable(ib.baseAddress!)
                    for pass in 0..<passes {
                        Parallel.forEachBand(h, minimumBandSize: 8) { rows in
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
                                    var acc = T.zero
                                    for x in 0..<min(r, w) { acc += row[x] }
                                    for x in 0..<w {
                                        if x + r < w { acc += row[x + r] }
                                        if x - r - 1 >= 0 { acc -= row[x - r - 1] }
                                        out[x] = acc.scaled(inv.value[x])
                                    }
                                }
                            }
                        }
                        let s = bp, d = ap
                        Parallel.forEachBand(w, minimumBandSize: 32) { cols in
                            let c0 = cols.lowerBound, span = cols.count
                            withUnsafeTemporaryAllocation(of: T.self, capacity: span) { accBuffer in
                                let acc = accBuffer.baseAddress!
                                for k in 0..<span { (acc + k).initialize(to: .zero) }
                                for y in 0..<min(r, h) {
                                    let row = s.value + y * w + c0
                                    for k in 0..<span { acc[k] += row[k] }
                                }
                                for y in 0..<h {
                                    let inv = 1 / Float(min(y + r, h - 1) - max(y - r, 0) + 1)
                                    if y + r < h {
                                        let add = s.value + (y + r) * w + c0
                                        for k in 0..<span { acc[k] += add[k] }
                                    }
                                    if y - r - 1 >= 0 {
                                        let sub = s.value + (y - r - 1) * w + c0
                                        for k in 0..<span { acc[k] -= sub[k] }
                                    }
                                    let out = d.value + y * w + c0
                                    for k in 0..<span { out[k] = acc[k].scaled(inv) }
                                }
                            }
                        }
                    }
                }
            }
        }
        return a
    }
}

protocol Blurrable {
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
