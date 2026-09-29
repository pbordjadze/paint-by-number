import Foundation

/// How busy the labelling is around each pixel. Texture (knit, foliage, gravel, fur)
/// shows up as a dense scatter of label changes; smooth areas and clean contours as few.
enum TextureMap {

    /// Density of label changes (right/down neighbour pairs) in a window of about 2% of the
    /// frame, mapped to 0...1 (1 ≈ a change between half of all neighbour pairs).
    static func boundaryDensity(_ classes: [UInt32], width w: Int, height h: Int) -> [Float] {
        let n = w * h
        guard n > 0 else { return [] }
        var changes = [Float](repeating: 0, count: n)
        classes.withUnsafeBufferPointer { cb in
            changes.withUnsafeMutableBufferPointer { ob in
                let c = UncheckedSendable(cb.baseAddress!)
                let o = UncheckedSendable(ob.baseAddress!)
                Parallel.forEachBand(h, minimumBandSize: 16) { rows in
                    for y in rows {
                        let row = y * w
                        for x in 0..<w {
                            let i = row + x
                            var v: Float = 0
                            if x + 1 < w && c.value[i + 1] != c.value[i] { v += 0.5 }
                            if y + 1 < h && c.value[i + w] != c.value[i] { v += 0.5 }
                            o.value[i] = v
                        }
                    }
                }
            }
        }
        let radius = max(2, Int(Float(n).squareRoot() / 100))
        var density = BoxBlur.apply(changes, width: w, height: h, radius: radius, passes: 2)
        density.withUnsafeMutableBufferPointer { buf in
            let d = UncheckedSendable(buf.baseAddress!)
            Parallel.forEachBand(n, minimumBandSize: 16_384) { range in
                for i in range { d.value[i] = min(d.value[i] * 2, 1) }
            }
        }
        return density
    }
}
