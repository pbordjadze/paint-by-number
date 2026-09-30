import CoreGraphics
import Foundation
import PaintCore
@testable import PaintByNumber

enum Fixtures {
    static let stripeColors: [SIMD3<Float>] = [SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1), SIMD3(1, 1, 0)]

    /// `count` vertical stripes (one region and palette color each, red/green/blue/yellow),
    /// with complete shared-edge vector geometry unless `vector` is false.
    static func stripes(count: Int = 3, stripeWidth: Int = 20, height: Int = 40, vector: Bool = true) -> Template {
        let width = count * stripeWidth
        let palette = (0..<count).map { i in
            PaletteColor(oklab: ColorScience.encodedToOKLab(stripeColors[i % stripeColors.count], space: .sRGB), rgb: stripeColors[i % stripeColors.count])
        }
        var points: [SIMD2<Float>] = []
        var edges: [BoundaryEdge] = []
        func addEdge(_ a: SIMD2<Float>, _ b: SIMD2<Float>, left: UInt32, right: UInt32) -> UInt32 {
            edges.append(BoundaryEdge(left: left, right: right, pointStart: UInt32(points.count), pointCount: 2))
            points.append(a)
            points.append(b)
            return UInt32(edges.count - 1)
        }
        let h = Float(height)
        // Vertical separators at x = k * stripeWidth, top to bottom.
        var separators: [UInt32] = []
        for k in 0...count {
            let x = Float(k * stripeWidth)
            let left: UInt32 = k == 0 ? 0 : UInt32(k - 1)
            let right: UInt32 = (k == 0 || k == count) ? BoundaryEdge.outside : UInt32(k)
            separators.append(addEdge(SIMD2(x, 0), SIMD2(x, h), left: left, right: right))
        }
        var ringEdges: [EdgeRef] = []
        var rings: [Ring] = []
        var regions: [Region] = []
        var labels: [Label] = []
        for i in 0..<count {
            let x0 = Float(i * stripeWidth), x1 = Float((i + 1) * stripeWidth)
            let top = addEdge(SIMD2(x0, 0), SIMD2(x1, 0), left: UInt32(i), right: BoundaryEdge.outside)
            let bottom = addEdge(SIMD2(x1, h), SIMD2(x0, h), left: UInt32(i), right: BoundaryEdge.outside)
            let start = UInt32(ringEdges.count)
            ringEdges += [
                EdgeRef(edge: top, reversed: false),
                EdgeRef(edge: separators[i + 1], reversed: false),
                EdgeRef(edge: bottom, reversed: false),
                EdgeRef(edge: separators[i], reversed: true),
            ]
            rings.append(Ring(edgeStart: start, edgeCount: 4, isHole: false))
            regions.append(Region(
                colorIndex: UInt32(i), area: Float(stripeWidth * height),
                bounds: PixelBounds(minX: Int32(i * stripeWidth), minY: 0, maxX: Int32((i + 1) * stripeWidth), maxY: Int32(height)),
                inscribedRadius: Float(min(stripeWidth, height)) / 2,
                ringStart: vector ? UInt32(i) : 0, ringCount: vector ? 1 : 0,
                labelStart: UInt32(i), labelCount: 1))
            labels.append(Label(position: SIMD2((x0 + x1) / 2, h / 2), radius: Float(min(stripeWidth, height)) / 2, region: UInt32(i)))
        }
        var map = [UInt32](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width { map[y * width + x] = UInt32(x / stripeWidth) }
        }
        return Template(
            width: width, height: height, colorSpace: .sRGB, palette: palette, regions: regions,
            points: vector ? points : [], edges: vector ? edges : [], ringEdges: vector ? ringEdges : [],
            rings: vector ? rings : [], labels: labels, mesh: FillMesh(),
            regionMap: RegionMap(width: width, height: height, storage: map))
    }

    /// A template generated from a bundled sample by the real pipeline.
    static func sample(_ name: String = "parrots", colors: Int = 12, detail: Float = 0.2) throws -> Template {
        guard let url = Bundle.main.url(forResource: name, withExtension: "jpg") else { throw CocoaError(.fileNoSuchFile) }
        let photo = try PhotoLoader.load(url: url, maxPixelSize: 480)
        return try TemplateGenerator(settings: GenerationSettings(colorCount: colors, detail: detail))
            .generate(from: photo, cancel: .none).template
    }

    static func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "PBNTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// Reads back pixels of a rendered image as 8-bit RGBA in the image's own color space.
struct PixelReader {
    let width: Int
    let height: Int
    private let bytes: [UInt8]

    init(_ image: CGImage) {
        width = image.width
        height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        buffer.withUnsafeMutableBytes { raw in
            let ctx = CGContext(
                data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ctx?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        bytes = buffer
    }

    /// RGB at (x, y), origin top-left.
    subscript(x: Int, y: Int) -> SIMD3<Int> {
        let i = (y * width + x) * 4
        return SIMD3(Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]))
    }
}
