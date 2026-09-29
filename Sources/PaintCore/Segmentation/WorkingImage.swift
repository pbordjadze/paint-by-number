import Foundation

/// Per-pixel inputs of the segmentation stage at working resolution.
enum WorkingImage {

    /// OKLab of every pixel after compositing over white (paper) in linear light, so
    /// transparent areas become one clean white region instead of garbage colors.
    /// Chroma axes are multiplied by `chromaScale`. The fourth lane is zero.
    static func okLab(_ image: RGBAImage, chromaScale: Float) -> Grid<SIMD4<Float>> {
        let n = image.width * image.height
        let lut = ColorScience.decodeLUT
        let space = image.colorSpace
        var out = [SIMD4<Float>](repeating: .zero, count: n)
        image.pixels.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                lut.withUnsafeBufferPointer { lutBuf in
                    let s = UncheckedSendable(src.baseAddress!)
                    let d = UncheckedSendable(dst.baseAddress!)
                    let l = UncheckedSendable(lutBuf.baseAddress!)
                    Parallel.forEachBand(n, minimumBandSize: 8192) { range in
                        for i in range {
                            let p = s.value + i * 4
                            var lin = SIMD3(l.value[Int(p[0])], l.value[Int(p[1])], l.value[Int(p[2])])
                            if p[3] != 255 {
                                let a = Float(p[3]) / 255
                                lin = lin * a + SIMD3(repeating: 1 - a)
                            }
                            let lab = ColorScience.linearToOKLab(lin, space: space)
                            d.value[i] = SIMD4(lab.x, lab.y * chromaScale, lab.z * chromaScale, 0)
                        }
                    }
                }
            }
        }
        return Grid(width: image.width, height: image.height, storage: out)
    }

    /// Resamples an importance map of any size to `width × height` (bilinear, clamped to
    /// 0...1). Without a map every pixel gets neutral importance 0.5.
    static func importance(_ map: Grid<Float>?, width: Int, height: Int) -> [Float] {
        let n = width * height
        guard let map, map.width > 0, map.height > 0 else {
            return [Float](repeating: 0.5, count: n)
        }
        var out = [Float](repeating: 0, count: n)
        let mw = map.width, mh = map.height
        let sx = Float(mw) / Float(width), sy = Float(mh) / Float(height)
        map.storage.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                let s = UncheckedSendable(src.baseAddress!)
                let d = UncheckedSendable(dst.baseAddress!)
                Parallel.forEachBand(height, minimumBandSize: 16) { rows in
                    for y in rows {
                        let fy = min(max((Float(y) + 0.5) * sy - 0.5, 0), Float(mh - 1))
                        let y0 = Int(fy), y1 = min(y0 + 1, mh - 1)
                        let ty = fy - Float(y0)
                        for x in 0..<width {
                            let fx = min(max((Float(x) + 0.5) * sx - 0.5, 0), Float(mw - 1))
                            let x0 = Int(fx), x1 = min(x0 + 1, mw - 1)
                            let tx = fx - Float(x0)
                            let top = s.value[y0 * mw + x0] * (1 - tx) + s.value[y0 * mw + x1] * tx
                            let bottom = s.value[y1 * mw + x0] * (1 - tx) + s.value[y1 * mw + x1] * tx
                            let v = top * (1 - ty) + bottom * ty
                            d.value[y * width + x] = v.isFinite ? min(max(v, 0), 1) : 0.5
                        }
                    }
                }
            }
        }
        return out
    }
}
