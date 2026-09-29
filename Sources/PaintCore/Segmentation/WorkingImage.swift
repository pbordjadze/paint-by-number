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
}
