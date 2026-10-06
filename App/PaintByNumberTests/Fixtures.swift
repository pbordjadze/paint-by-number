import CoreGraphics
import Foundation
import PaintCore
import Testing
@testable import PaintByNumber

enum Fixtures {
    /// The repository checkout the tests were built from (tests run on the build machine's
    /// simulator, which sees the host's files).
    static let repositoryRoot = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// The canvas tests' synthetic mosaic: 480×640, 6×8 cells.
    static let mosaic = SyntheticTemplate.make(.init(width: 480, height: 640, columns: 6, rows: 8, seed: 3))

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
        // The Metal canvas fills regions from the mesh: two triangles per stripe, positive area.
        var mesh = FillMesh()
        for i in 0..<count {
            let x0 = Float(i * stripeWidth), x1 = Float((i + 1) * stripeWidth)
            let first = UInt32(mesh.vertices.count)
            mesh.vertices += [SIMD2(x0, 0), SIMD2(x1, 0), SIMD2(x1, h), SIMD2(x0, h)]
            mesh.vertexRegion += Array(repeating: UInt32(i), count: 4)
            mesh.indices += [first, first + 1, first + 2, first, first + 2, first + 3]
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
            rings: vector ? rings : [], labels: labels, mesh: vector ? mesh : FillMesh(),
            regionMap: RegionMap(width: width, height: height, storage: map))
    }

    /// A template generated from a library picture by the real pipeline.
    static func sample(_ name: String = "great-wave", colors: Int = 12, detail: Float = 0.2) throws -> Template {
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

    /// A PDF page drawn on white at `scale` pixels per point.
    static func rasterize(_ page: CGPDFPage, scale: CGFloat) -> CGImage? {
        let box = page.getBoxRect(.mediaBox)
        let width = Int(box.width * scale), height = Int(box.height * scale)
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.scaleBy(x: scale, y: scale)
        ctx.drawPDFPage(page)
        return ctx.makeImage()
    }
}

/// Polls `condition` until it holds; a timeout is recorded at the caller and ends the test.
@MainActor
func waitUntil(
    timeout: Duration = .seconds(120), polling interval: Duration = .milliseconds(50),
    sourceLocation: SourceLocation = #_sourceLocation, _ condition: () -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while !condition() {
        guard clock.now < deadline else {
            Issue.record("Timed out waiting for the condition", sourceLocation: sourceLocation)
            throw CancellationError()
        }
        try await Task.sleep(for: interval)
    }
}

extension TemplateRasterizer.Style {
    /// Outlines with numbers on paper, as a painting starts: the rasterizer's outline and number
    /// paths at screen sizes (the painting screen itself draws with Metal).
    static let template = TemplateRasterizer.Style(outlineWidth: 1, numbers: true)
}

/// Attaches `image` to the test's results as `<name>.png`.
func record(_ image: CGImage, _ name: String) {
    if let png = ImageCodec.pngData(image) { Attachment.record(png, named: "\(name).png") }
}

/// Reads back a rendered image's pixels as 8-bit RGB in its own color space (sRGB when it has
/// none); a read past an edge returns the nearest pixel.
struct PixelReader {
    let width: Int
    let height: Int
    private let data: [UInt8]

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
        data = buffer
    }

    /// RGB at (x, y), origin top-left.
    subscript(x: Int, y: Int) -> SIMD3<Int> {
        let cx = min(max(x, 0), width - 1), cy = min(max(y, 0), height - 1)
        let i = (cy * width + cx) * 4
        return SIMD3(Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
    }
}

func bytes(_ encoded: SIMD3<Float>) -> SIMD3<Int> {
    SIMD3(Int((encoded.x * 255).rounded()), Int((encoded.y * 255).rounded()), Int((encoded.z * 255).rounded()))
}

/// Linear P3 → 8-bit encoded P3.
func encoded(_ linear: SIMD3<Float>) -> SIMD3<Int> {
    bytes(SIMD3(ColorScience.encodeSRGB(linear.x), ColorScience.encodeSRGB(linear.y), ColorScience.encodeSRGB(linear.z)))
}

func maxDifference(_ a: SIMD3<Int>, _ b: SIMD3<Int>) -> Int {
    max(abs(a.x - b.x), abs(a.y - b.y), abs(a.z - b.z))
}

func luma(_ c: SIMD3<Int>) -> Int {
    (c.x * 2126 + c.y * 7152 + c.z * 722) / 10000
}
