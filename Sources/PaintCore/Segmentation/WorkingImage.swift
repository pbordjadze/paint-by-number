import Foundation

/// Per-pixel inputs of the segmentation stage at working resolution.
enum WorkingImage {

    /// OKLab of every pixel after compositing over white (paper) in linear light, so
    /// transparent areas become one clean white region instead of garbage colors.
    /// Chroma axes are multiplied by `chromaScale`. The fourth lane is zero.
    static func okLab(_ image: RGBAImage, chromaScale: Float, cancel: CancellationCheck = .none) throws -> Grid<SIMD4<Float>> {
        let n = image.width * image.height
        let lut = ColorScience.decodeLUT
        let space = image.colorSpace
        var out = [SIMD4<Float>](uninitializedCount: n)
        try image.pixels.withUnsafeBufferPointer { src in
            try out.withUnsafeMutableBufferPointer { dst in
                try lut.withUnsafeBufferPointer { lutBuf in
                    let s = UncheckedSendable(src.baseAddress!)
                    let d = UncheckedSendable(dst.baseAddress!)
                    let l = UncheckedSendable(lutBuf.baseAddress!)
                    try Parallel.forEachBand(n, minimumBandSize: 8192, wave: Parallel.wavePixels, cancel: cancel) { range in
                        // Photos repeat exact pixel values a lot (flat or clipped areas, JPEG
                        // blocks): a small direct-mapped cache skips the cube roots for repeats.
                        withUnsafeTemporaryAllocation(of: UInt64.self, capacity: cacheSize) { keys in
                            withUnsafeTemporaryAllocation(of: SIMD4<Float>.self, capacity: cacheSize) { values in
                                keys.initialize(repeating: .max)
                                for i in range {
                                    let p = s.value + i * 4
                                    let key = UInt32(p[0]) | UInt32(p[1]) << 8 | UInt32(p[2]) << 16 | UInt32(p[3]) << 24
                                    let slot = Int((key &* 0x9E37_79B1) >> (32 - cacheBits))
                                    if keys[slot] == UInt64(key) {
                                        d.value[i] = values[slot]
                                        continue
                                    }
                                    var lin = SIMD3(l.value[Int(p[0])], l.value[Int(p[1])], l.value[Int(p[2])])
                                    if p[3] != 255 {
                                        let a = Float(p[3]) / 255
                                        lin = lin * a + SIMD3(repeating: 1 - a)
                                    }
                                    let lab = ColorScience.linearToOKLab(lin, space: space)
                                    let v = SIMD4(lab.x, lab.y * chromaScale, lab.z * chromaScale, 0)
                                    keys[slot] = UInt64(key)
                                    values[slot] = v
                                    d.value[i] = v
                                }
                            }
                        }
                    }
                }
            }
        }
        return Grid(width: image.width, height: image.height, storage: out)
    }

    private static let cacheBits: UInt32 = 12
    private static let cacheSize = 1 << Int(cacheBits)
}
