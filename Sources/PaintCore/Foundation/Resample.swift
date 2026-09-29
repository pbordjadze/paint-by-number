import Foundation

public enum Resample {

    /// High-quality area-average (box) resampling, performed in linear light so that
    /// fine high-contrast detail (foliage, hair) averages to the right brightness.
    /// Suitable for downscaling; upscaling degenerates to bilinear-ish nearest blending.
    public static func area(_ image: RGBAImage, width outW: Int, height outH: Int) -> RGBAImage {
        let inW = image.width, inH = image.height
        if inW == outW && inH == outH { return image }
        let lut = ColorScience.decodeLUT

        // Horizontal pass: inH rows × outW columns, linear float RGBA.
        let xWeights = weights(inCount: inW, outCount: outW)
        let yWeights = weights(inCount: inH, outCount: outH)

        var horizontal = [SIMD4<Float>](repeating: .zero, count: outW * inH)
        image.pixels.withUnsafeBufferPointer { src in
            horizontal.withUnsafeMutableBufferPointer { dst in
                let s = UncheckedSendable(src.baseAddress!)
                let d = UncheckedSendable(dst.baseAddress!)
                lut.withUnsafeBufferPointer { l in
                    let lp = UncheckedSendable(l.baseAddress!)
                    Parallel.forEachBand(inH, minimumBandSize: 8) { rows in
                        for y in rows {
                            let rowIn = s.value + y * inW * 4
                            for ox in 0..<outW {
                                var acc = SIMD4<Float>.zero
                                for (ix, wgt) in xWeights[ox] {
                                    let p = rowIn + ix * 4
                                    let a = Float(p[3]) / 255
                                    // Premultiply so transparent pixels don't bleed color.
                                    acc += SIMD4(lp.value[Int(p[0])] * a, lp.value[Int(p[1])] * a, lp.value[Int(p[2])] * a, a) * wgt
                                }
                                d.value[y * outW + ox] = acc
                            }
                        }
                    }
                }
            }
        }

        var out = [UInt8](repeating: 0, count: outW * outH * 4)
        horizontal.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                let s = UncheckedSendable(src.baseAddress!)
                let d = UncheckedSendable(dst.baseAddress!)
                Parallel.forEachBand(outH, minimumBandSize: 8) { rows in
                    for oy in rows {
                        for ox in 0..<outW {
                            var acc = SIMD4<Float>.zero
                            for (iy, wgt) in yWeights[oy] { acc += s.value[iy * outW + ox] * wgt }
                            let a = acc.w
                            let rgb = a > 1e-6 ? SIMD3(acc.x, acc.y, acc.z) / a : .zero
                            let p = d.value + (oy * outW + ox) * 4
                            p[0] = quantize(ColorScience.encodeSRGB(rgb.x))
                            p[1] = quantize(ColorScience.encodeSRGB(rgb.y))
                            p[2] = quantize(ColorScience.encodeSRGB(rgb.z))
                            p[3] = quantize(a)
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
    /// of the output pixel's footprint; at least one input pixel wide).
    static func weights(inCount: Int, outCount: Int) -> [[(Int, Float)]] {
        let scale = Double(inCount) / Double(outCount)
        return (0..<outCount).map { o in
            var start = Double(o) * scale
            var end = Double(o + 1) * scale
            if end - start < 1 {  // upscaling: widen footprint to one input pixel
                let c = (start + end) / 2
                start = c - 0.5; end = c + 0.5
            }
            start = max(0, start); end = min(Double(inCount), end)
            var list: [(Int, Float)] = []
            var total = 0.0
            var i = Int(start.rounded(.down))
            while Double(i) < end && i < inCount {
                let lo = max(start, Double(i)), hi = min(end, Double(i + 1))
                let w = hi - lo
                if w > 1e-9 { list.append((i, Float(w))); total += w }
                i += 1
            }
            return list.map { ($0.0, Float(Double($0.1) / total)) }
        }
    }
}
