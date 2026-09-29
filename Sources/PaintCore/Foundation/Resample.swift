import Foundation

public enum Resample {

    /// High-quality area-average (box) resampling, performed in linear light so that
    /// fine high-contrast detail (foliage, hair) averages to the right brightness.
    /// Suitable for downscaling; upscaling degenerates to bilinear-ish nearest blending.
    public static func area(_ image: RGBAImage, width outW: Int, height outH: Int) -> RGBAImage {
        let inW = image.width, inH = image.height
        if inW == outW && inH == outH { return image }
        let lut = ColorScience.decodeLUT
        let xWeights = Weights(inCount: inW, outCount: outW)
        let yWeights = Weights(inCount: inH, outCount: outH)

        // Horizontal pass: inH rows × outW columns, linear premultiplied float RGBA.
        var horizontal = [SIMD4<Float>](unsafeUninitializedCapacity: outW * inH) { _, count in count = outW * inH }
        image.pixels.withUnsafeBufferPointer { src in
            horizontal.withUnsafeMutableBufferPointer { dst in
                lut.withUnsafeBufferPointer { l in
                    let s = UncheckedSendable(src.baseAddress!)
                    let d = UncheckedSendable(dst.baseAddress!)
                    let lp = UncheckedSendable(l.baseAddress!)
                    Parallel.forEachBand(inH, minimumBandSize: 8) { rows in
                        withUnsafeTemporaryAllocation(of: SIMD4<Float>.self, capacity: inW) { line in
                            let linear = line.baseAddress!
                            for y in rows {
                                let rowIn = s.value + y * inW * 4
                                for ix in 0..<inW {
                                    let p = rowIn + ix * 4
                                    let a = Float(p[3]) / 255
                                    // Premultiply so transparent pixels don't bleed color.
                                    linear[ix] = SIMD4(lp.value[Int(p[0])] * a, lp.value[Int(p[1])] * a, lp.value[Int(p[2])] * a, a)
                                }
                                let out = d.value + y * outW
                                for ox in 0..<outW {
                                    var acc = SIMD4<Float>.zero
                                    for k in xWeights.start[ox]..<xWeights.start[ox + 1] {
                                        acc += linear[Int(xWeights.index[k])] * xWeights.weight[k]
                                    }
                                    out[ox] = acc
                                }
                            }
                        }
                    }
                }
            }
        }

        let encode = ColorScience.EncodeTable.shared
        var out = [UInt8](repeating: 0, count: outW * outH * 4)
        horizontal.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                let s = UncheckedSendable(src.baseAddress!)
                let d = UncheckedSendable(dst.baseAddress!)
                Parallel.forEachBand(outH, minimumBandSize: 8) { rows in
                    withUnsafeTemporaryAllocation(of: SIMD4<Float>.self, capacity: outW) { line in
                        let acc = line.baseAddress!
                        for oy in rows {
                            for ox in 0..<outW { acc[ox] = .zero }
                            for k in yWeights.start[oy]..<yWeights.start[oy + 1] {
                                let row = s.value + Int(yWeights.index[k]) * outW
                                let wgt = yWeights.weight[k]
                                for ox in 0..<outW { acc[ox] += row[ox] * wgt }
                            }
                            for ox in 0..<outW {
                                let v = acc[ox]
                                let a = v.w
                                let rgb = a > 1e-6 ? SIMD3(v.x, v.y, v.z) / a : .zero
                                let p = d.value + (oy * outW + ox) * 4
                                p[0] = encode.quantized(rgb.x)
                                p[1] = encode.quantized(rgb.y)
                                p[2] = encode.quantized(rgb.z)
                                p[3] = quantize(a)
                            }
                        }
                    }
                }
            }
        }
        return RGBAImage(width: outW, height: outH, pixels: out, colorSpace: image.colorSpace)
    }

    @inline(__always)
    static func quantize(_ v: Float) -> UInt8 {
        UInt8(min(max(v * 255 + 0.5, 0), 255))
    }

    /// Per output sample: contributing input indices and normalized weights (box filter
    /// of the output pixel's footprint; at least one input pixel wide), flattened: sample
    /// o uses entries `start[o]..<start[o + 1]`.
    struct Weights: Sendable {
        var start: [Int] = [0]
        var index: [Int32] = []
        var weight: [Float] = []

        init(inCount: Int, outCount: Int) {
            let scale = Double(inCount) / Double(outCount)
            var raw: [Float] = []
            for o in 0..<outCount {
                var lo = Double(o) * scale
                var hi = Double(o + 1) * scale
                if hi - lo < 1 {  // upscaling: widen footprint to one input pixel
                    let c = (lo + hi) / 2
                    lo = c - 0.5; hi = c + 0.5
                }
                lo = max(0, lo); hi = min(Double(inCount), hi)
                raw.removeAll(keepingCapacity: true)
                var total = 0.0
                var i = Int(lo.rounded(.down))
                while Double(i) < hi && i < inCount {
                    let w = min(hi, Double(i + 1)) - max(lo, Double(i))
                    if w > 1e-9 {
                        index.append(Int32(i))
                        raw.append(Float(w))
                        total += w
                    }
                    i += 1
                }
                for w in raw { weight.append(Float(Double(w) / total)) }
                start.append(index.count)
            }
        }
    }
}

extension ColorScience {
    /// `Resample.quantize(encodeSRGB(v))` for linear v ≥ 0 without evaluating `pow`: the
    /// function is a monotone step function, so it is tabulated by its 255 step positions,
    /// found once by bisection over floats with the very same `encodeSRGB`. Buckets of
    /// 1/4096 hold at most one step (the curve rises by < 1 code per bucket).
    struct EncodeTable: Sendable {
        static let shared = EncodeTable()
        static let buckets = 4096

        /// Code at the start of each bucket, and where within it the code steps up by one
        /// (`.infinity`: no step).
        private let base: [UInt8]
        private let step: [Float]

        private init() {
            @inline(__always) func code(_ v: Float) -> UInt8 { Resample.quantize(ColorScience.encodeSRGB(v)) }
            var base = [UInt8](repeating: 255, count: Self.buckets + 1)
            var step = [Float](repeating: .infinity, count: Self.buckets + 1)
            for b in 0..<Self.buckets {
                let lo = Float(b) / Float(Self.buckets), hi = Float(b + 1) / Float(Self.buckets)
                let first = code(lo), last = code(hi.nextDown)
                base[b] = first
                guard last != first else { continue }
                precondition(last == first + 1, "sRGB encode steps more than once per bucket")
                // Smallest float in [lo, hi) with the higher code (bit patterns of
                // non-negative floats are ordered like the floats).
                var a = lo.bitPattern, z = hi.nextDown.bitPattern
                while a < z {
                    let mid = a + (z - a) / 2
                    if code(Float(bitPattern: mid)) == first { a = mid + 1 } else { z = mid }
                }
                step[b] = Float(bitPattern: a)
            }
            self.base = base
            self.step = step
        }

        @inline(__always)
        func quantized(_ v: Float) -> UInt8 {
            // Values ≥ 1 (and rounding overshoot) encode to 255; negatives do not occur.
            guard v < 1 else { return 255 }
            let b = Int(max(v, 0) * Float(Self.buckets))
            return base[b] &+ (v >= step[b] ? 1 : 0)
        }
    }
}
