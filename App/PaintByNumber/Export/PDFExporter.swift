import CoreGraphics
import CoreText
import Foundation
import PaintCore

/// Printable template: page 1 is the outline template with numbers (vector, crisp at any
/// zoom), page 2 the numbered color key plus a small reference of the finished picture.
nonisolated enum PDFExporter {
    enum Paper: String, Sendable, CaseIterable, Identifiable {
        case letter, a4

        var id: String { rawValue }

        /// Portrait size in points.
        var size: CGSize {
            switch self {
            case .letter: CGSize(width: 612, height: 792)
            case .a4: CGSize(width: 595.28, height: 841.89)
            }
        }

        var name: String {
            switch self {
            case .letter: "US Letter"
            case .a4: "A4"
            }
        }

        /// Letter where it is the norm, A4 everywhere else.
        static func `default`(for region: Locale.Region?) -> Paper {
            let letterRegions: Set<String> = ["US", "CA", "MX", "PH", "CL", "CO", "VE", "GT", "PR", "CR", "DO", "PA", "SV"]
            return letterRegions.contains(region?.identifier ?? "") ? .letter : .a4
        }
    }

    static func document(for t: Template, title: String, paper: Paper = .default(for: Locale.current.region)) -> Data {
        let data = NSMutableData()
        let landscape = t.width > t.height
        var box = CGRect(origin: .zero, size: landscape ? CGSize(width: paper.size.height, height: paper.size.width) : paper.size)
        let info: [CFString: Any] = [kCGPDFContextTitle: title, kCGPDFContextCreator: "Paint by Numbers"]
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, info as CFDictionary)
        else { return Data() }

        let stats = "\(t.palette.count) colors · \(t.regions.count.formatted()) areas"
        page(ctx, box) { content in
            let body = header(ctx, in: content, title: title, detail: stats)
            let rect = fit(aspect: CGFloat(t.width) / CGFloat(t.height), in: body)
            TemplateRasterizer.draw(
                t, painted: nil, style: .print, in: ctx, rect: rect,
                rasterResolution: CGSize(width: t.width * 2, height: t.height * 2))
            ctx.setStrokeColor(gray(0.75))
            ctx.setLineWidth(0.5)
            ctx.stroke(rect)
        }
        page(ctx, box) { content in
            let body = header(ctx, in: content, title: "Color Key", detail: title)
            let used = legend(ctx, t, in: body)
            let remaining = CGRect(x: body.minX, y: used.maxY + 24, width: body.width, height: body.maxY - used.maxY - 24)
            if remaining.height > 110 {
                text(ctx, "Reference", font: font(.emphasizedSystem, 10), color: gray(0.35), at: CGPoint(x: remaining.minX, y: remaining.minY + 10))
                let area = CGRect(x: remaining.minX, y: remaining.minY + 20, width: remaining.width, height: remaining.height - 20)
                let rect = fit(aspect: CGFloat(t.width) / CGFloat(t.height), in: area)
                TemplateRasterizer.draw(
                    t, painted: nil, style: .painting, in: ctx, rect: rect,
                    rasterResolution: CGSize(width: rect.width * 3, height: rect.height * 3))
            }
        }
        ctx.closePDF()
        return data as Data
    }

    // MARK: Layout

    private static let margin: CGFloat = 36

    /// Runs `body` for one page with a y-down user space and the content rect inside margins.
    private static func page(_ ctx: CGContext, _ box: CGRect, _ body: (CGRect) -> Void) {
        ctx.beginPDFPage(nil)
        ctx.saveGState()
        ctx.translateBy(x: 0, y: box.height)
        ctx.scaleBy(x: 1, y: -1)
        let content = box.insetBy(dx: margin, dy: margin)
        body(content)
        text(ctx, "Paint by Numbers", font: font(.system, 7.5), color: gray(0.6), at: CGPoint(x: content.minX, y: content.maxY + 16))
        ctx.restoreGState()
        ctx.endPDFPage()
    }

    /// Draws the page header and returns the rect below it.
    private static func header(_ ctx: CGContext, in content: CGRect, title: String, detail: String) -> CGRect {
        text(ctx, title, font: font(.emphasizedSystem, 17), color: gray(0.1), at: CGPoint(x: content.minX, y: content.minY + 14))
        text(ctx, detail, font: font(.system, 9), color: gray(0.45), at: CGPoint(x: content.maxX, y: content.minY + 13), alignment: .right)
        ctx.setStrokeColor(gray(0.85))
        ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: content.minX, y: content.minY + 24))
        ctx.addLine(to: CGPoint(x: content.maxX, y: content.minY + 24))
        ctx.strokePath()
        return CGRect(x: content.minX, y: content.minY + 36, width: content.width, height: content.height - 36)
    }

    /// Numbered swatches in a grid; returns the rect it used.
    private static func legend(_ ctx: CGContext, _ t: Template, in rect: CGRect) -> CGRect {
        let columns = rect.width > 600 ? 10 : 8
        let cellW = rect.width / CGFloat(columns)
        let cellH: CGFloat = 62
        let diameter: CGFloat = 30
        let counts = t.regionCountsByColor
        for (i, color) in t.palette.enumerated() {
            let col = i % columns, row = i / columns
            let center = CGPoint(x: rect.minX + (CGFloat(col) + 0.5) * cellW, y: rect.minY + CGFloat(row) * cellH + diameter / 2 + 2)
            let circle = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
            ctx.setFillColor(TemplateRasterizer.cgColor(SIMD4(color.rgb, 1), space: t.colorSpace))
            ctx.fillEllipse(in: circle)
            ctx.setStrokeColor(gray(0, alpha: 0.12))
            ctx.setLineWidth(0.5)
            ctx.strokeEllipse(in: circle)
            let luminance = ColorScience.relativeLuminance(encoded: color.rgb, space: t.colorSpace)
            let ink = luminance > 0.42 ? gray(0.12) : gray(1)
            text(ctx, "\(i + 1)", font: font(.emphasizedSystem, 12), color: ink, at: CGPoint(x: center.x, y: center.y + 4.3), alignment: .center)
            text(ctx, hex(color.rgb), font: font(.system, 6.5), color: gray(0.45), at: CGPoint(x: center.x, y: circle.maxY + 11), alignment: .center)
            text(ctx, "\(counts[i]) areas", font: font(.system, 6.5), color: gray(0.62), at: CGPoint(x: center.x, y: circle.maxY + 20), alignment: .center)
        }
        let rows = (t.palette.count + columns - 1) / columns
        return CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: CGFloat(rows) * cellH)
    }

    private static func fit(aspect: CGFloat, in rect: CGRect) -> CGRect {
        var size = CGSize(width: rect.width, height: rect.width / aspect)
        if size.height > rect.height { size = CGSize(width: rect.height * aspect, height: rect.height) }
        return CGRect(x: rect.midX - size.width / 2, y: rect.minY, width: size.width, height: size.height)
    }

    // MARK: Text & color

    private enum Alignment { case left, center, right }

    private static func font(_ type: CTFontUIFontType, _ size: CGFloat) -> CTFont {
        CTFontCreateUIFontForLanguage(type, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
    }

    private static func gray(_ white: CGFloat, alpha: CGFloat = 1) -> CGColor {
        CGColor(gray: white, alpha: alpha)
    }

    /// Draws one line of text with its baseline at `point` (y-down page space).
    private static func text(_ ctx: CGContext, _ string: String, font: CTFont, color: CGColor, at point: CGPoint, alignment: Alignment = .left) {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let x: CGFloat
        switch alignment {
        case .left: x = point.x
        case .center: x = point.x - width / 2
        case .right: x = point.x - width
        }
        ctx.saveGState()
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = CGPoint(x: x, y: point.y)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    private static func hex(_ rgb: SIMD3<Float>) -> String {
        let c = (rgb.clamped(lowerBound: .zero, upperBound: SIMD3(repeating: 1)) * 255).rounded(.toNearestOrAwayFromZero)
        return String(format: "#%02X%02X%02X", Int(c.x), Int(c.y), Int(c.z))
    }
}
