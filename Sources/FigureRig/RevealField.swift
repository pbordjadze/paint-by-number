import Foundation
import PaintCore

/// Arrival times through changed pixels of two equally sized F8 pictures. Color pairs
/// (including mixed PPM/PGM pairs, with gray promoted to RGB) use true OKLab; two gray
/// pictures use byte differences. Integer distance buckets visit each wave in raster
/// order, preserving shortest paths with straight/diagonal costs of 2/3.
public struct RevealField: Sendable, Equatable {
    public enum Seed: String, Sendable, CaseIterable, Codable { case left, center, strongest }

    public let width: Int, height: Int
    public let seed: Seed
    /// Raster order; nil means unchanged, while zero is a changed seed pixel.
    public let times: [Double?]
    public var changed: Double { Double(times.reduce(0) { $0 + ($1 == nil ? 0 : 1) }) / Double(times.count) }

    public static func make(from a: PipelineSnapshot.Picture, to b: PipelineSnapshot.Picture,
                            seed: Seed = .left) throws -> Self {
        func size(_ picture: PipelineSnapshot.Picture) -> (Int, Int) {
            switch picture {
            case .color(let image): return (image.width, image.height)
            case .grayscale(let image): return (image.width, image.height)
            }
        }
        let (width, height) = size(a)
        guard width > 0, height > 0, size(b) == (width, height),
              width <= Int.max / height else {
            throw FigureInputError("reveal: expected pictures of the same positive size")
        }
        let count = width * height
        func valid(_ picture: PipelineSnapshot.Picture) -> Bool {
            switch picture {
            case .color(let image): return count <= Int.max / 4 && image.pixels.count == count * 4
            case .grayscale(let image): return image.storage.count == count
            }
        }
        guard valid(a), valid(b) else { throw FigureInputError("reveal: invalid pixel buffer") }
        var strengths = [Double](repeating: 0, count: count)
        let threshold: Double
        if case .grayscale(let first) = a, case .grayscale(let second) = b {
            threshold = 9
            for i in 0..<count { strengths[i] = Double(abs(Int(first.storage[i]) - Int(second.storage[i]))) }
        } else {
            threshold = Double(Float(0.02))
            func lab(_ picture: PipelineSnapshot.Picture, _ i: Int) -> SIMD3<Float> {
                switch picture {
                case .color(let image):
                    let alpha = Float(image.pixels[i * 4 + 3]) / 255
                    let rgb = SIMD3(Float(image.pixels[i * 4]), Float(image.pixels[i * 4 + 1]),
                                    Float(image.pixels[i * 4 + 2])) / 255
                    return ColorScience.encodedToOKLab(rgb * alpha + SIMD3(repeating: 1 - alpha), space: image.colorSpace)
                case .grayscale(let image):
                    return ColorScience.encodedToOKLab(SIMD3(repeating: Float(image.storage[i]) / 255), space: .sRGB)
                }
            }
            for i in 0..<count { strengths[i] = Double(ColorScience.distance(lab(a, i), lab(b, i))) }
        }
        let pixels = (0..<count).filter { strengths[$0] >= threshold }
        guard !pixels.isEmpty else {
            return Self(width: width, height: height, seed: seed, times: Array(repeating: nil, count: count))
        }
        let seeds: [Int]
        switch seed {
        case .left:
            let column = pixels.map { $0 % width }.min()!
            seeds = pixels.filter { $0 % width == column }
        case .center:
            let x = Double(width - 1) / 2, y = Double(height - 1) / 2
            func distance(_ i: Int) -> Double {
                let dx = Double(i % width) - x, dy = Double(i / width) - y
                return dx * dx + dy * dy
            }
            // min keeps the first (raster order) pixel when distances tie.
            seeds = [pixels.min { distance($0) < distance($1) }!]
        case .strongest:
            let maximum = pixels.map { strengths[$0] }.max()!
            seeds = pixels.filter { strengths[$0] == maximum }
        }
        var distances = strengths.map { $0 >= threshold ? Int.max : -1 }
        var buckets = [[Int]](repeating: [], count: 4)
        for i in seeds { distances[i] = 0; buckets[0].append(i) }
        var pending = seeds.count, wave = 0, maximum = 0, nextRegion = 0
        while true {
            while pending > 0 {
                let slot = wave % 4
                let current = buckets[slot].sorted()
                buckets[slot].removeAll(keepingCapacity: true)
                pending -= current.count
                for i in current where distances[i] == wave {
                    maximum = max(maximum, wave)
                    let x = i % width, y = i / width
                    for dy in -1...1 {
                        for dx in -1...1 where dx != 0 || dy != 0 {
                            let nx = x + dx, ny = y + dy
                            guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                            let neighbor = ny * width + nx
                            let candidate = wave + (dx == 0 || dy == 0 ? 2 : 3)
                            if distances[neighbor] > candidate {
                                distances[neighbor] = candidate
                                buckets[candidate % 4].append(neighbor); pending += 1
                            }
                        }
                    }
                }
                wave += 1
            }
            // Seed each unreachable component at the largest time reached so far.
            while nextRegion < count, distances[nextRegion] != Int.max { nextRegion += 1 }
            guard nextRegion < count else { break }
            wave = maximum; distances[nextRegion] = wave
            buckets[wave % 4].append(nextRegion); pending = 1
        }
        let times = distances.map { $0 < 0 ? nil : Optional(maximum == 0 ? 0 : Double($0) / Double(maximum)) }
        return Self(width: width, height: height, seed: seed, times: times)
    }

    public func encodedPGM() -> Data {
        Netpbm.encodePGM(width: width, height: height,
                        values: times.map { $0.map { UInt8(1 + Int(($0 * 254).rounded())) } ?? 0 })
    }

    /// Pixel centers, binned into equal time intervals (t=1 belongs to the last),
    /// with empty bins omitted. Two open Chaikin rounds retain the end points.
    public func workerPath(steps: Int = 12) throws -> String {
        guard steps > 0 else { throw FigureInputError("reveal.steps: expected a positive integer") }
        // Sparse bins also allow large step counts without allocating K buffers.
        var bins: [Int: (x: Double, y: Double, count: Int)] = [:]
        for (i, time) in times.enumerated() {
            guard let time else { continue }
            let scaled = time * Double(steps)
            let bin = scaled >= Double(steps - 1) ? steps - 1 : Int(scaled)
            var sum = bins[bin] ?? (0, 0, 0)
            sum.x += Double(i % width) + 0.5; sum.y += Double(i / width) + 0.5; sum.count += 1
            bins[bin] = sum
        }
        var points = bins.keys.sorted().map { key in
            let sum = bins[key]!
            return Point(sum.x / Double(sum.count), sum.y / Double(sum.count))
        }
        guard !points.isEmpty else { return "" }
        for _ in 0..<2 where points.count > 1 {
            var smoothed = [points[0]]
            for i in 1..<points.count {
                smoothed.append(points[i - 1] * 0.75 + points[i] * 0.25)
                smoothed.append(points[i - 1] * 0.25 + points[i] * 0.75)
            }
            smoothed.append(points.last!); points = smoothed
        }
        return points.enumerated().map { index, point in
            "\(index == 0 ? "M" : "L") \(svgNumber(point.x)) \(svgNumber(point.y))"
        }.joined(separator: " ")
    }

    public struct Metadata: Codable, Sendable, Equatable {
        public let width: Int, height: Int
        public let changed: Double
        public let seed: Seed
        public let steps: Int
        public let path: String
    }

    public func metadata(steps: Int = 12) throws -> Metadata {
        Metadata(width: width, height: height, changed: changed, seed: seed,
                 steps: steps, path: try workerPath(steps: steps))
    }
}
