import CoreGraphics
import Foundation
import MosaicCore
import MosaicKit
import UIKit

/// Draws Set in Stone's pages (`StoneBook`, painting-company row 367) with UIKit: the PDF that
/// prints and shares, and the pages the sheet previews. Each `BookPage` is a list of shapes, words
/// and the corner map in millimetres on A4; here a millimetre is 72/25.4 points.
nonisolated enum StoneBookRenderer {
    static let pointsPerMM: CGFloat = 72 / 25.4
    static var pageSize: CGSize {
        CGSize(width: BookPage.size.x * pointsPerMM, height: BookPage.size.y * pointsPerMM)
    }

    /// Every page as one PDF; empty when cancelled.
    static func pdf(_ book: StoneBook, strings: BookStrings) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: book.title, kCGPDFContextCreator as String: "Paint by Mosaic"]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize), format: format)
        var cancelled = false
        let data = renderer.pdfData { context in
            var images: [ObjectIdentifier: UIImage] = [:]
            for n in 1...max(book.pageCount, 1) {
                if Task.isCancelled { cancelled = true; return }
                context.beginPage()
                let cg = context.cgContext
                cg.saveGState()
                cg.scaleBy(x: pointsPerMM, y: pointsPerMM)
                draw(book.page(n, strings: strings), in: cg, images: &images)
                cg.restoreGState()
            }
        }
        return cancelled ? Data() : data
    }

    /// Page `number` as a picture `width` pixels across, on white.
    static func image(_ book: StoneBook, page number: Int, strings: BookStrings, width: CGFloat) -> UIImage {
        let scale = width / pageSize.width
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let size = CGSize(width: width, height: (pageSize.height * scale).rounded())
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let cg = context.cgContext
            cg.scaleBy(x: scale * pointsPerMM, y: scale * pointsPerMM)
            var images: [ObjectIdentifier: UIImage] = [:]
            draw(book.page(number, strings: strings), in: cg, images: &images)
        }
    }

    /// Draws a page into a context whose y runs down and whose unit is the millimetre.
    static func draw(_ page: BookPage, in cg: CGContext, images: inout [ObjectIdentifier: UIImage]) {
        UIGraphicsPushContext(cg)
        defer { UIGraphicsPopContext() }
        for item in page.items {
            switch item {
            case .shape(let path, let fill, let stroke):
                let p = cgPath(path)
                if let fill {
                    cg.addPath(p)
                    cg.setFillColor(cgColor(fill))
                    cg.fillPath()
                }
                if let stroke {
                    cg.addPath(p)
                    cg.setStrokeColor(cgColor(stroke.color))
                    cg.setLineWidth(stroke.width)
                    cg.setLineCap(stroke.round ? .round : .butt)
                    cg.setLineJoin(stroke.round ? .round : .miter)
                    cg.setLineDash(phase: 0, lengths: stroke.dash.map { CGFloat($0) })
                    cg.strokePath()
                    cg.setLineDash(phase: 0, lengths: [])
                }
            case .text(let t):
                text(t, in: cg)
            case .clip(let path):
                cg.saveGState()
                cg.addPath(cgPath(path))
                cg.clip()
            case .endClip:
                cg.restoreGState()
            case .image(let image, let origin, let size):
                let key = ObjectIdentifier(image)
                if images[key] == nil, let made = uiImage(image) { images[key] = made }
                images[key]?.draw(in: CGRect(x: origin.x, y: origin.y, width: size.x, height: size.y))
            }
        }
    }

    private static func cgPath(_ path: BookPath) -> CGPath {
        let p = CGMutablePath()
        func pt(_ v: SIMD2<Double>) -> CGPoint { CGPoint(x: v.x, y: v.y) }
        for e in path.elements {
            switch e {
            case .move(let a): p.move(to: pt(a))
            case .line(let a): p.addLine(to: pt(a))
            case .quad(let c, let a): p.addQuadCurve(to: pt(a), control: pt(c))
            case .cubic(let c1, let c2, let a): p.addCurve(to: pt(a), control1: pt(c1), control2: pt(c2))
            case .close: p.closeSubpath()
            }
        }
        return p
    }

    private static func cgColor(_ c: BookColor) -> CGColor {
        CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: c.a)
    }

    private static func font(_ t: BookText) -> UIFont {
        let weight: UIFont.Weight = switch t.weight {
        case ..<450: .regular
        case ..<550: .medium
        case ..<650: .semibold
        case ..<750: .bold
        default: .heavy
        }
        let base = UIFont.systemFont(ofSize: t.size, weight: weight)
        // the title in New York, as the app's titles are
        if t.face == .serif, let serif = base.fontDescriptor.withDesign(.serif) {
            return UIFont(descriptor: serif, size: t.size)
        }
        return base
    }

    private static func text(_ t: BookText, in cg: CGContext) {
        let f = font(t)
        let s = NSAttributedString(string: t.string, attributes: [
            .font: f, .foregroundColor: UIColor(cgColor: cgColor(t.color)),
        ])
        let width = s.size().width
        let dx: CGFloat = switch t.anchor {
        case .start: 0
        case .middle: -width / 2
        case .end: -width
        }
        cg.saveGState()
        cg.translateBy(x: t.at.x, y: t.at.y)
        if t.rotation != 0 { cg.rotate(by: t.rotation * .pi / 180) }
        s.draw(at: CGPoint(x: dx, y: -f.ascender))
        cg.restoreGState()
    }

    private static func uiImage(_ image: BookImage) -> UIImage? {
        guard let provider = CGDataProvider(data: Data(image.rgba) as CFData),
              let cg = CGImage(width: image.width, height: image.height, bitsPerComponent: 8, bitsPerPixel: 32,
                               bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        return UIImage(cgImage: cg)
    }
}
