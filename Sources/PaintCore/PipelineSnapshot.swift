/// A making-of picture captured synchronously between pipeline stages. Pictures never
/// exceed 1024 pixels on the long side; coordinates cover the whole working canvas.
/// Color pictures retain the source primaries. Label maps use nearest-neighbour sampling
/// so a snapshot never invents a paint. Structure is coherent gradient magnitude,
/// normalized to the map's maximum (white = strongest); lines are black on white.
public struct PipelineSnapshot: Sendable, Equatable {
    public enum Stage: String, Sendable, CaseIterable {
        case working, structure, smoothed, palette, simplified
        case lineArt = "line-art"
        case vectorized
    }

    public enum Picture: Sendable, Equatable {
        case color(RGBAImage)
        case grayscale(Grid<UInt8>)
    }

    public let stage: Stage
    public let picture: Picture
    /// The paints used by the palette-colored label map, in palette-index order. Empty for
    /// pictures without paints; the simplified stage has the final, refitted palette.
    public var palette: [PaletteColor] = []

    /// Runs on the generating thread, in stage order, once per stage (line art only
    /// with a book's input). Throwing stops generation, e.g. when a snapshot cannot be saved.
    public typealias Observer = @Sendable (PipelineSnapshot) throws -> Void
}

/// Rendering is called only inside an `if let observer` branch. It reads stage buffers
/// without retaining or changing them, and allocates at most a preview-sized picture.
enum SnapshotPictures {
    static func size(width: Int, height: Int) -> (width: Int, height: Int) {
        let long = max(width, height)
        guard long > 1024 else { return (width, height) }
        return (max(1, width * 1024 / long), max(1, height * 1024 / long))
    }

    static func working(_ image: RGBAImage, cancel: CancellationCheck) throws -> PipelineSnapshot {
        let s = size(width: image.width, height: image.height)
        return PipelineSnapshot(stage: .working, picture: .color(
            try Resample.area(image, width: s.width, height: s.height, cancel: cancel)))
    }

    static func structure(_ map: StructureMap) -> PipelineSnapshot {
        let values = map.coherentMagnitude()
        let peak = values.max() ?? 0
        let s = size(width: map.width, height: map.height)
        var picture = Grid<UInt8>(width: s.width, height: s.height, repeating: 0)
        for y in 0..<s.height {
            for x in 0..<s.width {
                let i = sourceIndex(x, y, size: s, width: map.width, height: map.height)
                picture[x, y] = peak > 0 ? byte(values[i] / peak) : 0
            }
        }
        return PipelineSnapshot(stage: .structure, picture: .grayscale(picture))
    }

    static func smoothed(_ lab: Grid<SIMD4<Float>>, chromaScale: Float, space: RGBColorSpace) -> PipelineSnapshot {
        let image = color(width: lab.width, height: lab.height, space: space) { i in
            let v = lab.storage[i]
            return rgb(ColorScience.okLabToEncoded(SIMD3(v.x, v.y / chromaScale, v.z / chromaScale), space: space))
        }
        return PipelineSnapshot(stage: .smoothed, picture: .color(image))
    }

    static func palette(_ classes: [UInt32], width: Int, height: Int, colors: [SIMD3<Float>],
                        chromaScale: Float, space: RGBColorSpace) -> PipelineSnapshot {
        let paints = colors.map { PaletteColor(oklab: $0 * SIMD3(1, 1 / chromaScale, 1 / chromaScale), space: space) }
        let bytes = paints.map { rgb($0.rgb) }
        let image = color(width: width, height: height, space: space) { bytes[Int(classes[$0])] }
        return PipelineSnapshot(stage: .palette, picture: .color(image), palette: paints)
    }

    static func simplified(_ segmentation: Segmentation) -> PipelineSnapshot {
        let paints = segmentation.palette.map { rgb($0.rgb) }
        let w = segmentation.width, h = segmentation.height
        let image = color(width: w, height: h, space: segmentation.colorSpace) { i in
            paints[Int(segmentation.regionColor[Int(segmentation.labels.storage[i])])]
        }
        return PipelineSnapshot(stage: .simplified, picture: .color(image), palette: segmentation.palette)
    }

    static func lineArt(_ plan: LayeredLines.Plan) -> PipelineSnapshot {
        var canvas = Lines(width: plan.segmentation.width, height: plan.segmentation.height)
        for line in plan.boundaryLines { canvas.draw(line) }
        for (line, _) in plan.interiorLines { canvas.draw(line) }
        return PipelineSnapshot(stage: .lineArt, picture: .grayscale(canvas.picture))
    }

    static func vectorized(_ template: Template) -> PipelineSnapshot {
        var canvas = Lines(width: template.width, height: template.height)
        for edge in template.edges { canvas.draw(template.points(of: edge)) }
        return PipelineSnapshot(stage: .vectorized, picture: .grayscale(canvas.picture))
    }

    private static func byte(_ value: Float) -> UInt8 { UInt8((min(max(value, 0), 1) * 255).rounded()) }

    private static func rgb(_ value: SIMD3<Float>) -> SIMD3<UInt8> {
        SIMD3(byte(value.x), byte(value.y), byte(value.z))
    }

    private static func sourceIndex(_ x: Int, _ y: Int, size: (width: Int, height: Int), width: Int, height: Int) -> Int {
        let sx = min(width - 1, (2 * x + 1) * width / (2 * size.width))
        let sy = min(height - 1, (2 * y + 1) * height / (2 * size.height))
        return sy * width + sx
    }

    private static func color(width: Int, height: Int, space: RGBColorSpace, pixel: (Int) -> SIMD3<UInt8>) -> RGBAImage {
        let s = size(width: width, height: height)
        var image = RGBAImage(width: s.width, height: s.height, fill: SIMD4(repeating: 255), colorSpace: space)
        for y in 0..<s.height {
            for x in 0..<s.width {
                let c = pixel(sourceIndex(x, y, size: s, width: width, height: height))
                image[x, y] = SIMD4(c.x, c.y, c.z, 255)
            }
        }
        return image
    }

    private struct Lines {
        var picture: Grid<UInt8>
        let scale: SIMD2<Float>

        init(width: Int, height: Int) {
            let s = SnapshotPictures.size(width: width, height: height)
            picture = Grid(width: s.width, height: s.height, repeating: 255)
            scale = SIMD2(Float(s.width) / Float(max(1, width)), Float(s.height) / Float(max(1, height)))
        }

        mutating func draw(_ line: DrawnLine) {
            // DrawnLine's integer coordinates refer to pixel centres; template points
            // instead use the canvas corner convention.
            draw(line.points.map { $0 + SIMD2(repeating: 0.5) })
            if line.closed, let first = line.points.first, let last = line.points.last {
                segment(last + SIMD2(repeating: 0.5), first + SIMD2(repeating: 0.5))
            }
        }

        mutating func draw<C: Collection>(_ points: C) where C.Element == SIMD2<Float> {
            var previous: SIMD2<Float>?
            for point in points {
                if let previous { segment(previous, point) }
                previous = point
            }
        }

        mutating func segment(_ from: SIMD2<Float>, _ to: SIMD2<Float>) {
            guard picture.width > 0 && picture.height > 0 else { return }
            let a = from * scale, b = to * scale
            // Canvas-border points belong to the last pixel. Integer steps avoid
            // floating-point interpolation rounding just below a pixel and skipping it.
            var x = min(picture.width - 1, max(0, Int(a.x)))
            var y = min(picture.height - 1, max(0, Int(a.y)))
            let endX = min(picture.width - 1, max(0, Int(b.x)))
            let endY = min(picture.height - 1, max(0, Int(b.y)))
            let dx = abs(endX - x), dy = -abs(endY - y)
            let sx = x < endX ? 1 : -1, sy = y < endY ? 1 : -1
            var error = dx + dy
            while true {
                picture[x, y] = 0
                if x == endX && y == endY { break }
                let twice = 2 * error
                if twice >= dy { error += dy; x += sx }
                if twice <= dx { error += dx; y += sy }
            }
        }
    }
}
