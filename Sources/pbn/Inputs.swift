import Foundation
import PaintCore
#if canImport(ImageIO)
import CoreGraphics
import ImageIO
#endif

func loadImage(_ path: String) -> RGBAImage {
    guard let data = FileManager.default.contents(atPath: path) else { fail("cannot read \(path)") }
    if data.first == UInt8(ascii: "P") {
        do { return try Netpbm.read(data) } catch { fail("cannot decode \(path): \(error)") }
    }
    #if canImport(ImageIO)
    // On Apple platforms any ImageIO format works (JPEG, HEIC, PNG…), decoded to sRGB.
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fail("cannot decode \(path)") }
    let w = image.width, h = image.height
    var pixels = [UInt8](repeating: 0, count: w * h * 4)
    pixels.withUnsafeMutableBytes { raw in
        let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    return RGBAImage(width: w, height: h, pixels: pixels)
    #else
    fail("\(path): only PPM/PGM input is supported on this platform")
    #endif
}

func loadImportance(_ path: String?) -> Grid<Float>? {
    guard let path else { return nil }
    let img = loadImage(path)
    return Grid(width: img.width, height: img.height,
                storage: (0..<(img.width * img.height)).map { Float(img.pixels[$0 * 4]) / 255 })
}

/// The edge map and eyes layered and coloring-book line art draw from: `--edges` (a contour
/// map, HED), `--lines` (a line drawing), or both combined as the app combines its two models
/// (`EdgeMap.combined`, the contours alone then deciding the outlines, `--contour-weight` the
/// weight), unless `--line-art detector=drawing|contours` keeps one of them; and `--eyes`.
func loadLineArt(_ options: Options) -> LineArtInput? {
    guard options.edges != nil || options.lines != nil else {
        let style = options.settings.lineArt.style
        if style.usesEdgeMap { fail("--line-style \(style.rawValue) needs --edges map.pgm and/or --lines drawing.pgm") }
        return nil
    }
    func map(_ path: String) -> EdgeMap {
        let img = loadImage(path)
        return EdgeMap(width: img.width, height: img.height, values: (0..<(img.width * img.height)).map { img.pixels[$0 * 4] })
    }
    let edges: EdgeMap
    var outlines: EdgeMap?
    switch (options.lines.map(map), options.edges.map(map), options.settings.lineArt.detector) {
    case let (drawing?, contours?, .drawingAndContours):
        edges = EdgeMap.combined(drawing: drawing, contours: contours, contourWeight: options.contourWeight)
        outlines = contours
    case let (drawing?, _, .drawing), let (drawing?, nil, _): edges = drawing
    case let (_, contours?, .contours), let (nil, contours?, _): edges = contours
    case (nil, nil, _): fatalError()
    }
    /// Closed polygons of [x, y] normalized to the photo, from a JSON file.
    func polygons(_ path: String) -> [[SIMD2<Float>]] {
        guard let data = FileManager.default.contents(atPath: path) else { fail("cannot read \(path)") }
        do {
            return try JSONDecoder().decode([[[Float]]].self, from: data).map { poly in
                poly.map { p in
                    guard p.count == 2 else { fail("\(path): points are [x, y]") }
                    return SIMD2(p[0], p[1])
                }
            }
        } catch { fail("cannot decode \(path): \(error)") }
    }
    let eyes = options.eyes.map(polygons) ?? []
    var objects: [[SIMD2<Float>]] = []
    if let path = options.objects {
        if path.hasSuffix(".json") {
            objects = polygons(path)
        } else {
            // A mask (PGM or PPM, the red channel): inside at or above half.
            let img = loadImage(path)
            let mask = (0..<(img.width * img.height)).map { img.pixels[$0 * 4] >= 128 }
            objects = MaskContours.outlines(of: mask, width: img.width, height: img.height)
        }
    }
    return LineArtInput(edges: edges, eyes: eyes, objects: objects, contours: outlines)
}

func loadHints(_ path: String?) -> SubjectHints? {
    guard let path else { return nil }
    guard let data = FileManager.default.contents(atPath: path) else { fail("cannot read \(path)") }
    do { return try JSONDecoder().decode(SubjectHints.self, from: data) } catch { fail("cannot decode \(path): \(error)") }
}
