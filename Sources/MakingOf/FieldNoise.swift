import Foundation
import PaintCore

/// Value noise on wrapping lattices drawn from the field show's noise stream, its octaves summed
/// (fbm) and domain-warped (`warped`), on a plane of cells: `Noise` in `making_of_fields.py`. The
/// lattices and the fields from `fine` and `warped` are bit for bit the reference's (`+ - *` and
/// `floor` only); `rough` goes through `exp`, so it agrees with it to a few last bits.
struct FieldNoise: Sendable {
    /// Lattices there are; octaves take them in turn.
    private static let grids = 6
    /// Values in a lattice.
    private static let values = FieldShow.lattice * FieldShow.lattice
    /// Cells across a lattice: one fewer than its points, the last point being the first again.
    private static let cells = FieldShow.lattice - 1

    /// The lattices' values, row-major, one lattice after the other, every value one draw of the
    /// stream in that order.
    let lattices: [Double]

    init(streams: ShowStreams) {
        var rng = streams.field(6)
        lattices = (0..<Self.grids * Self.values).map { _ in rng.nextDouble() }
    }

    /// The noise of one lattice at (`x`, `y`), blended between its four nearest points.
    @inline(__always)
    private static func value(_ lattice: UnsafePointer<Double>, _ x: Double, _ y: Double) -> Double {
        let (x0, y0) = (x.rounded(.down), y.rounded(.down))
        let (fx, fy) = (ease(x - x0), ease(y - y0))
        let n = cells
        let xi = ((truncated(x0) % n) + n) % n, yi = ((truncated(y0) % n) + n) % n
        let row = lattice + yi * FieldShow.lattice
        let below = row + FieldShow.lattice
        let top = row[xi] + (row[xi + 1] - row[xi]) * fx
        let bottom = below[xi] + (below[xi + 1] - below[xi]) * fx
        return top + (bottom - top) * fy
    }

    /// `octaves` octaves of the noise summed, each twice as fine and half as strong, the first from
    /// lattice `first` (the lattices go round).
    @inline(__always)
    private static func fbm(
        _ lattices: UnsafePointer<Double>, _ x: Double, _ y: Double, octaves: Int, first: Int
    ) -> Double {
        var out = 0.0, amplitude = 1.0, frequency = 1.0, total = 0.0
        for o in 0..<octaves {
            let lattice = lattices + ((first + o) % grids) * values
            out = out + amplitude * value(lattice, x * frequency + 17.3 * Double(o), y * frequency + 9.1 * Double(o))
            total += amplitude
            amplitude = amplitude / 2
            frequency = frequency * 2.03
        }
        return out / total
    }

    /// An fbm of four octaves from lattice 5 over a field `width` by `height` cells, a cell
    /// 1 / `scale` apart on the lattice: the grain, unwarped.
    func grain(width: Int, height: Int, scale: Double) -> [Double] {
        fill(width: width, height: height) { lattices, x, y in
            Self.fbm(lattices, Double(x) / scale, Double(y) / scale, octaves: 4, first: 5)
        }
    }

    /// An fbm of five octaves over a field `width` by `height` cells, a cell 1 / `scale` apart on the
    /// lattice, its coordinates warped by two others, `strength` of them: swells and fingers.
    func warped(width: Int, height: Int, scale: Double, strength: Double = 3.0) -> [Double] {
        fill(width: width, height: height) { lattices, x, y in
            let (xs, ys) = (Double(x) / scale, Double(y) / scale)
            let warpX = Self.fbm(lattices, xs, ys, octaves: 4, first: 1)
            let warpY = Self.fbm(lattices, xs + 5.2, ys + 1.3, octaves: 4, first: 2)
            return Self.fbm(lattices, xs + strength * warpX, ys + strength * warpY, octaves: 5, first: 3)
        }
    }

    /// A speed factor, exp(strength * the warped noise, standardized): swells and fingers.
    func rough(width: Int, height: Int, scale: Double, strength: Double) -> [Double] {
        var field = warped(width: width, height: height, scale: scale)
        let (mean, deviation) = FieldMath.meanAndDeviation(field)
        field.withUnsafeMutableBufferPointer { buffer in
            let out = UncheckedSendable(buffer.baseAddress!)
            FieldBands.forEach(buffer.count) { cells in
                for i in cells { out.value[i] = exp(strength * (out.value[i] - mean) / (deviation + 1e-9)) }
            }
        }
        return field
    }

    /// A field of `noise` at each cell, rows in parallel.
    private func fill(width: Int, height: Int, _ noise: (UnsafePointer<Double>, Int, Int) -> Double) -> [Double] {
        var field = [Double](repeating: 0, count: width * height)
        lattices.withUnsafeBufferPointer { lattices in
            field.withUnsafeMutableBufferPointer { buffer in
                let out = UncheckedSendable(buffer.baseAddress!)
                FieldBands.forEach(height) { rows in
                    for y in rows {
                        for x in 0..<width { out.value[y * width + x] = noise(lattices.baseAddress!, x, y) }
                    }
                }
            }
        }
        return field
    }
}
