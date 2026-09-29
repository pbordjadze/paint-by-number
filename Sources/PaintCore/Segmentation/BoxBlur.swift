import Foundation

/// Repeated box blur (≈ Gaussian after 2–3 passes) with edge-normalized windows, O(1) per
/// pixel in the radius. Rows run in parallel; columns in parallel bands of whole rows so
/// memory access stays sequential.
enum BoxBlur {

    static func apply(_ input: [SIMD4<Float>], width w: Int, height h: Int, radius r: Int, passes: Int) -> [SIMD4<Float>] {
        blur(input, width: w, height: h, radius: r, passes: passes)
    }

    static func apply(_ input: [Float], width w: Int, height h: Int, radius r: Int, passes: Int) -> [Float] {
        blur(input, width: w, height: h, radius: r, passes: passes)
    }

    @inline(__always)
    private static func blur<T: Blurrable>(_ input: [T], width w: Int, height h: Int, radius r: Int, passes: Int) -> [T] {
        guard w > 0, h > 0, r > 0 else { return input }
        var a = input
        var b = [T](repeating: .zero, count: input.count)
        for _ in 0..<passes {
            a.withUnsafeBufferPointer { src in
                b.withUnsafeMutableBufferPointer { dst in
                    let s = UncheckedSendable(src.baseAddress!)
                    let d = UncheckedSendable(dst.baseAddress!)
                    Parallel.forEachBand(h, minimumBandSize: 8) { rows in
                        for y in rows {
                            let row = s.value + y * w
                            let out = d.value + y * w
                            var acc = T.zero
                            for x in 0..<min(r, w) { acc += row[x] }
                            for x in 0..<w {
                                if x + r < w { acc += row[x + r] }
                                if x - r - 1 >= 0 { acc -= row[x - r - 1] }
                                let count = Float(min(x + r, w - 1) - max(x - r, 0) + 1)
                                out[x] = acc.scaled(1 / count)
                            }
                        }
                    }
                }
            }
            b.withUnsafeBufferPointer { src in
                a.withUnsafeMutableBufferPointer { dst in
                    let s = UncheckedSendable(src.baseAddress!)
                    let d = UncheckedSendable(dst.baseAddress!)
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
