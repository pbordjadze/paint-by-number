#if UNRELEASED
import CoreGraphics
import Foundation
import os
import PaintCore

/// Makes the stickers of the finished paintings (painting-company row 349) and lays them on the
/// shelf for the sticker extension. Each painting gets its picture as a small print with a white
/// edge, and, where Vision finds a subject in the photo it was made from, the subject alone,
/// cut out of the finished painting with a white edge round it: the painter's own cat, in the
/// painter's own paints. Nothing is uploaded; Messages sends what the painter picks.
nonisolated enum StickerMaker {
    /// A sticker's long side in pixels: Messages' regular size, 136 points, at 3×.
    static let pixels = 408
    /// Messages takes no sticker over 500 KB.
    static let mostBytes = 500_000
    /// Vision runs for at most this many paintings each time the stickers are laid out with the
    /// app in front (`OutsideDesk.cutOutStickers`); the rest wait for the next time. Leaving the
    /// foreground, with seconds to spare, it runs for none.
    static let mostCutOutsALayout = 3
    /// The share of the picture a subject may take to be worth cutting out: less is a speck,
    /// more is the whole picture with its corners missing.
    static let subjectShare: ClosedRange<Double> = 0.04...0.85

    @concurrent
    static func layOut(_ artworks: [Artwork], store: ArtworkStore, shelf: OutsideShelf, cutOuts: Int = mostCutOutsALayout) async {
        let files = FileManager.default
        var stickers: [OutsideShelf.Stickers.Sticker] = []
        var kept = Set<String>()
        var cutOutsTried = 0
        for artwork in artworks {
            let base = "sticker-\(artwork.id.uuidString)-\(artwork.thumbnailVersion)"
            let plain = base + ".png", cut = base + "-cut.png", noCut = base + "-nocut"
            func has(_ name: String) -> Bool { files.fileExists(atPath: shelf.url(name).path) }
            let triesCut = !has(cut) && !has(noCut) && cutOutsTried < cutOuts
            if !has(plain) || triesCut {
                guard let template = try? store.readTemplate(artwork.id),
                      let painting = TemplateRasterizer.image(template, style: .finished, maxPixelSize: 1024)
                else { continue }
                if !has(plain), let data = framed(painting).flatMap(ImageCodec.pngData), data.count <= mostBytes {
                    try? shelf.write(data, named: plain)
                }
                if triesCut {
                    cutOutsTried += 1
                    let data = await cutOut(of: artwork, painting: painting, store: store)
                    try? shelf.write(data ?? Data(), named: data == nil ? noCut : cut)
                }
            }
            for name in [cut, plain] where has(name) {
                stickers.append(OutsideShelf.Stickers.Sticker(painting: artwork.id, title: artwork.title, picture: name))
                kept.insert(name)
            }
            if has(noCut) { kept.insert(noCut) }
        }
        do {
            try shelf.write(OutsideShelf.Stickers(stickers: stickers), to: .stickers)
            shelf.sweep(prefix: "sticker-", keeping: kept)
        } catch {
            Log.library.error("Laying out the stickers failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// The subject of the artwork's photo cut out of `painting`, as PNG data; nil when it has
    /// no photo, the photo isn't the painting's shape, or Vision finds no subject worth cutting.
    private static func cutOut(of artwork: Artwork, painting: CGImage, store: ArtworkStore) async -> Data? {
        let photo = store.source(artwork.id, maxPixelSize: 1024)
            ?? artwork.sampleName.flatMap(Sample.named).flatMap(\.url).flatMap { ImageCodec.image(at: $0, maxPixelSize: 1024) }
        guard let photo, let mask = await SubjectVision.findings(in: photo).subjects else { return nil }
        guard let image = cutOut(painting, inside: mask.inside, width: mask.width, height: mask.height),
              let data = ImageCodec.pngData(image), data.count <= mostBytes
        else { return nil }
        return data
    }

    // MARK: Drawing

    /// The picture as a small print: on white, with a white edge and rounded corners, on nothing.
    static func framed(_ painting: CGImage, pixels: Int = pixels) -> CGImage? {
        let edge = CGFloat(pixels) * 0.035
        let room = CGFloat(pixels) - 2 * edge
        let scale = room / CGFloat(max(painting.width, painting.height))
        let inner = CGSize(width: (CGFloat(painting.width) * scale).rounded(), height: (CGFloat(painting.height) * scale).rounded())
        let size = CGSize(width: inner.width + 2 * edge, height: inner.height + 2 * edge)
        guard let ctx = context(width: Int(size.width.rounded(.up)), height: Int(size.height.rounded(.up)), like: painting) else { return nil }
        let outer = CGRect(origin: .zero, size: size)
        ctx.addPath(CGPath(roundedRect: outer, cornerWidth: edge * 2, cornerHeight: edge * 2, transform: nil))
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fillPath()
        let picture = outer.insetBy(dx: edge, dy: edge)
        ctx.addPath(CGPath(roundedRect: picture, cornerWidth: edge, cornerHeight: edge, transform: nil))
        ctx.clip()
        ctx.draw(painting, in: picture)
        return ctx.makeImage()
    }

    /// `painting` where `inside` says the subject is (a mask of `width` × `height`, row 0 its
    /// top, of the painting's shape), with a white edge round it, cropped to it and scaled so
    /// its long side is `pixels`. Nil when the mask isn't the painting's shape or the subject
    /// isn't worth cutting out (`subjectShare`).
    static func cutOut(_ painting: CGImage, inside: [Bool], width: Int, height: Int, pixels: Int = pixels) -> CGImage? {
        guard width > 0, height > 0, inside.count == width * height else { return nil }
        let shape = Double(painting.width) / Double(painting.height), maskShape = Double(width) / Double(height)
        guard abs(shape - maskShape) <= 0.03 * shape else { return nil }
        let share = Double(inside.count(where: { $0 })) / Double(inside.count)
        guard subjectShare.contains(share) else { return nil }

        let reach = max(3, Int((Double(max(width, height)) * 0.028).rounded()))
        let edged = grown(inside, width: width, height: height, by: reach)
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where edged[y * width + x] {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let cropWidth = maxX - minX + 1, cropHeight = maxY - minY + 1
        let scale = CGFloat(pixels) / CGFloat(max(cropWidth, cropHeight))
        guard let subject = gray(inside, width: width, height: height),
              let white = gray(edged, width: width, height: height),
              let ctx = context(
                  width: max(1, Int((CGFloat(cropWidth) * scale).rounded())),
                  height: max(1, Int((CGFloat(cropHeight) * scale).rounded())), like: painting)
        else { return nil }
        // Where the whole mask lies in the cropped picture: CoreGraphics counts rows from the
        // bottom, the mask from the top.
        let whole = CGRect(
            x: -CGFloat(minX) * scale, y: -CGFloat(height - 1 - maxY) * scale,
            width: CGFloat(width) * scale, height: CGFloat(height) * scale)
        ctx.interpolationQuality = .high
        ctx.saveGState()
        ctx.clip(to: whole, mask: white)
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(whole)
        ctx.restoreGState()
        ctx.saveGState()
        ctx.clip(to: whole, mask: subject)
        ctx.draw(painting, in: whole)
        ctx.restoreGState()
        return ctx.makeImage()
    }

    /// `inside` with every cell within `reach` cells of it: the mask's edge cells stamped as discs.
    static func grown(_ inside: [Bool], width: Int, height: Int, by reach: Int) -> [Bool] {
        var result = inside
        func isInside(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < width && y < height && inside[y * width + x] }
        for y in 0..<height {
            for x in 0..<width where inside[y * width + x] {
                guard !isInside(x - 1, y) || !isInside(x + 1, y) || !isInside(x, y - 1) || !isInside(x, y + 1) else { continue }
                for dy in -reach...reach where y + dy >= 0 && y + dy < height {
                    let span = Int(Double(reach * reach - dy * dy).squareRoot())
                    for nx in max(0, x - span)...min(width - 1, x + span) {
                        result[(y + dy) * width + nx] = true
                    }
                }
            }
        }
        return result
    }

    /// A gray picture of a mask, white where it is true, which CoreGraphics clips to smoothly.
    private static func gray(_ mask: [Bool], width: Int, height: Int) -> CGImage? {
        let bytes = Data(mask.map { $0 ? UInt8(255) : 0 })
        guard let provider = CGDataProvider(data: bytes as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// A clear bitmap in `image`'s color space (sRGB when it has none a bitmap can be made in).
    private static func context(width: Int, height: Int, like image: CGImage) -> CGContext? {
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        return CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }
}
#endif
