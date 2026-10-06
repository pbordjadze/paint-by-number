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

/// A map image's value per pixel, its red channel (a PGM decodes to equal channels).
func redChannel(_ image: RGBAImage) -> [UInt8] {
    (0..<(image.width * image.height)).map { image.pixels[$0 * 4] }
}

func loadImportance(_ path: String?) -> Grid<Float>? {
    guard let path else { return nil }
    let img = loadImage(path)
    return Grid(width: img.width, height: img.height, storage: redChannel(img).map { Float($0) / 255 })
}

/// The edge map and eyes a coloring book draws from: `--edges` (a contour
/// map, HED), `--lines` (a line drawing), or both combined as the app combines its two models
/// (`EdgeMap.combined`, the contours alone then deciding the outlines, `--contour-weight` the
/// weight), unless `--line-art detector=drawing|contours` keeps one of them; `--eyes`,
/// `--objects` and `--writing`.
func loadLineArt(_ options: Options) -> LineArtInput? {
    func map(_ path: String) -> EdgeMap {
        let img = loadImage(path)
        return EdgeMap(width: img.width, height: img.height, values: redChannel(img))
    }
    let drawing = options.lines.map(map), contours = options.edges.map(map)
    guard let single = drawing ?? contours else {
        let style = options.settings.lineArt.style
        if style.usesEdgeMap { fail("--line-style \(style.rawValue) needs --edges map.pgm and/or --lines drawing.pgm") }
        return nil
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
    let writing = options.writing.map(polygons) ?? []
    var objects: [[SIMD2<Float>]] = []
    if let path = options.objects {
        if path.hasSuffix(".json") {
            objects = polygons(path)
        } else {
            // A mask (PGM or PPM, the red channel): inside at or above half.
            let img = loadImage(path)
            let mask = redChannel(img).map { $0 >= 128 }
            objects = MaskContours.outlines(of: mask, width: img.width, height: img.height)
        }
    }
    if let drawing, let contours {
        return LineArtInput(
            drawing: drawing, contours: contours, detector: options.settings.lineArt.detector, eyes: eyes, objects: objects,
            writing: writing, contourWeight: options.contourWeight)
    }
    // One map is drawn as it is, whatever the detector says.
    return LineArtInput(edges: single, eyes: eyes, objects: objects, writing: writing)
}

func loadHints(_ path: String?) -> SubjectHints? {
    guard let path else { return nil }
    guard let data = FileManager.default.contents(atPath: path) else { fail("cannot read \(path)") }
    do { return try JSONDecoder().decode(SubjectHints.self, from: data) } catch { fail("cannot decode \(path): \(error)") }
}
