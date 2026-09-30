import CoreGraphics
import CoreText
import Foundation
import PaintCore
import simd

/// Printable template: page 1 is the outline template with numbers (vector, crisp at any
/// zoom), page 2 the color key (number, paint and name of every color) plus a small reference
/// of the finished picture.
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
                t, painted: nil, style: .printable, in: ctx, rect: rect,
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

    /// How the color key's entries are laid out: `rows` per column, filled column by column.
    nonisolated struct KeyLayout: Equatable, Sendable {
        var columns: Int
        var scale: CGFloat
        var columnWidth: CGFloat
        var rowHeight: CGFloat
        var rows: Int
        var count: Int

        var height: CGFloat { count == 0 ? 0 : CGFloat(rows) * rowHeight }
    }

    private static let keyGap: CGFloat = 12
    /// Width of an entry left of its name: number and dot, at scale 1.
    private static let keyNameInset: CGFloat = 36

    /// The largest scale (1 down to 0.6), then the fewest columns (3–5, or 4–6 on a wide page),
    /// whose rows fit the page and whose widest entry (`widestEntry` at scale 1) fits a column.
    /// When nothing fits, the smallest scale and most columns; long names then truncate.
    static func keyLayout(count: Int, widestEntry: CGFloat, in rect: CGRect) -> KeyLayout {
        let base = rect.width > 600 ? 4 : 3
        func layout(scale: CGFloat, columns: Int) -> KeyLayout {
            KeyLayout(
                columns: columns, scale: scale,
                columnWidth: (rect.width - keyGap * CGFloat(columns - 1)) / CGFloat(columns),
                rowHeight: 24 * scale, rows: max(1, (count + columns - 1) / columns), count: count)
        }
        for scale: CGFloat in [1, 0.9, 0.8, 0.7, 0.6] {
            for columns in base...(base + 2) {
                let candidate = layout(scale: scale, columns: columns)
                if candidate.height <= rect.height && widestEntry * scale <= candidate.columnWidth { return candidate }
            }
        }
        return layout(scale: 0.6, columns: base + 2)
    }

    /// The color key as a list: number, a dot of the paint and the color's name, with its hex
    /// value and area count below. Returns the rect it used.
    private static func legend(_ ctx: CGContext, _ t: Template, in rect: CGRect) -> CGRect {
        let names = t.palette.map { ColorNameText.title($0.colorName) }
        let nameFont = font(.emphasizedSystem, 8)
        let widestName = names.map { width(of: $0, font: nameFont) }.max() ?? 0
        let layout = keyLayout(count: t.palette.count, widestEntry: keyNameInset + widestName, in: rect)
        let s = layout.scale
        let counts = t.regionCountsByColor
        for (i, color) in t.palette.enumerated() {
            let col = i / layout.rows, row = i % layout.rows
            let x = rect.minX + CGFloat(col) * (layout.columnWidth + keyGap)
            let y = rect.minY + CGFloat(row) * layout.rowHeight
            text(ctx, "\(i + 1)", font: font(.emphasizedSystem, 8 * s), color: gray(0.12),
                 at: CGPoint(x: x + 18 * s, y: y + 10 * s), alignment: .right)
            let diameter = 9 * s
            let dot = CGRect(x: x + 26.5 * s - diameter / 2, y: y + 7 * s - diameter / 2, width: diameter, height: diameter)
            ctx.setFillColor(TemplateRasterizer.cgColor(SIMD4(color.rgb, 1), space: t.colorSpace))
            ctx.fillEllipse(in: dot)
            ctx.setStrokeColor(gray(0, alpha: 0.12))
            ctx.setLineWidth(0.5)
            ctx.strokeEllipse(in: dot)
            let textX = x + keyNameInset * s
            let textWidth = layout.columnWidth - keyNameInset * s
            text(ctx, names[i], font: font(.emphasizedSystem, 8 * s), color: gray(0.12),
                 at: CGPoint(x: textX, y: y + 10 * s), maxWidth: textWidth)
            text(ctx, "\(hex(color.rgb)) · \(counts[i]) areas", font: font(.system, 6 * s), color: gray(0.5),
                 at: CGPoint(x: textX, y: y + 19 * s), maxWidth: textWidth)
        }
        return CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: layout.height)
    }

    private static func fit(aspect: CGFloat, in rect: CGRect) -> CGRect {
        var size = CGSize(width: rect.width, height: rect.width / aspect)
        if size.height > rect.height { size = CGSize(width: rect.height * aspect, height: rect.height) }
        return CGRect(x: rect.midX - size.width / 2, y: rect.minY, width: size.width, height: size.height)
    }

    // MARK: Text & color

    private enum Alignment { case left, right }

    private static func font(_ type: CTFontUIFontType, _ size: CGFloat) -> CTFont {
        CTFontCreateUIFontForLanguage(type, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
    }

    private static func gray(_ white: CGFloat, alpha: CGFloat = 1) -> CGColor {
        CGColor(gray: white, alpha: alpha)
    }

    private static func line(_ string: String, font: CTFont, color: CGColor) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
    }

    private static func width(of string: String, font: CTFont) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(line(string, font: font, color: gray(0)), nil, nil, nil))
    }

    /// Draws one line of text with its baseline at `point` (y-down page space), truncated with
    /// an ellipsis when wider than `maxWidth`.
    private static func text(
        _ ctx: CGContext, _ string: String, font: CTFont, color: CGColor, at point: CGPoint,
        alignment: Alignment = .left, maxWidth: CGFloat? = nil
    ) {
        var run = line(string, font: font, color: color)
        var runWidth = CGFloat(CTLineGetTypographicBounds(run, nil, nil, nil))
        if let maxWidth, runWidth > maxWidth,
           let truncated = CTLineCreateTruncatedLine(
               run, Double(max(maxWidth, 0)), .end, line("…", font: font, color: color)) {
            run = truncated
            runWidth = CGFloat(CTLineGetTypographicBounds(run, nil, nil, nil))
        }
        let x = alignment == .right ? point.x - runWidth : point.x
        ctx.saveGState()
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = CGPoint(x: x, y: point.y)
        CTLineDraw(run, ctx)
        ctx.restoreGState()
    }

    private static func hex(_ rgb: SIMD3<Float>) -> String {
        let c = (rgb.clamped(lowerBound: .zero, upperBound: SIMD3(repeating: 1)) * 255).rounded(.toNearestOrAwayFromZero)
        return String(format: "#%02X%02X%02X", Int(c.x), Int(c.y), Int(c.z))
    }
}
