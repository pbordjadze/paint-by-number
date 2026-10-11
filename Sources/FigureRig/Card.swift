import Foundation

public struct CardLayout: Sendable {
    /// Keep at least 85% of each glyph's width: mild condensation for an unbreakable word,
    /// never arbitrary squeezing. The 11 pt gate also measures this narrower dimension.
    public static let minimumHorizontalScale = 0.85
    public let shapes: [FilledShape]
    public let hold: Double, start: Double, end: Double
    public let minimum: Point, maximum: Point
    public let titleLines: [String]
    public let authorLines: [String], minimumSizePoints: Double
    let fade: Double
    public func opacity(at time: Double) -> Double {
        if time <= start || time >= end { return 0 }
        if time < holdStart { return clamp((time - start) / fade) }
        if time > end - fade { return clamp((end - time) / fade) }
        return 1
    }
    public var holdStart: Double { start + fade }

    init(spec: FigureSpec, scene: FigureScene) {
        let settings = spec.card, citation = scene.card, pts = scene.pointsPerUnit
        let size = settings.size / pts, maxWidth = scene.canvas.width * 0.6, margin = 24 / pts
        start = citation.at; fade = settings.fade
        hold = max(2, settings.holdBase + settings.perWord * Double(citation.words))
        end = start + 2 * fade + hold
        let roman = Charter.fonts["roman"]!, italic = Charter.fonts["italic"]!
        func width(_ text: String, _ font: [String: CardGlyph]) -> Double {
            text.reduce(0) { $0 + (font[String($1)] ?? font["?"]!).advance * size }
        }
        let author = citation.authors + " · " + String(citation.year)
        func wrapped(_ text: String, _ font: [String: CardGlyph]) -> [String] {
            var lines: [String] = [], current = ""
            for word in text.split(whereSeparator: \.isWhitespace).map(String.init) {
                let next = current.isEmpty ? word : current + " " + word
                if !current.isEmpty && width(next, font) > maxWidth {
                    lines.append(current); current = word
                } else { current = next }
            }
            if !current.isEmpty { lines.append(current) }
            return lines.isEmpty ? [""] : lines
        }
        let lines = wrapped(citation.title, italic), authors = wrapped(author, roman)
        titleLines = lines
        authorLines = authors
        let texts = authors + lines
        let measured = texts.enumerated().map { width($0.element, $0.offset < authors.count ? roman : italic) }
        let scales = measured.map { max(Self.minimumHorizontalScale, min(1, maxWidth / max($0, 1e-9))) }
        minimumSizePoints = settings.size * (scales.min() ?? 1)
        // An oversized word retains the minimum scale and may fail cardOnScreen; bounds
        // measure the actual laid-out width rather than pretending it fit the target.
        let textWidth = zip(measured, scales).map(*).max() ?? 0
        let height = size * (Double(texts.count) * 1.25 + 0.3)
        let leading = settings.position.hasSuffix("Leading"), top = settings.position.hasPrefix("top")
        let x = leading ? margin : (scene.canvas.width - textWidth) / 2
        let y = top ? margin : scene.canvas.height - margin - height
        minimum = Point(x - size * 0.5, y - size * 0.4)
        maximum = Point(x + textWidth + size * 0.5, y + height + size * 0.25)
        var output: [FilledShape] = []
        if settings.backdrop == "paper" {
            let low = minimum, high = maximum, radius = size * 0.4
            var border: [Point] = []
            for (i, center) in [Point(high.x - radius, high.y - radius), Point(low.x + radius, high.y - radius),
                                Point(low.x + radius, low.y + radius), Point(high.x - radius, low.y + radius)].enumerated() {
                for j in 0...6 { let angle = Double(i) * .pi / 2 + Double(j) * .pi / 12; border.append(center + Point(cos(angle), sin(angle)) * radius) }
            }
            output.append(FilledShape(subpaths: [border], color: scene.canvas.paper, opacity: 0.92, blur: size * 0.04, layer: "card"))
        }
        for (index, text) in texts.enumerated() {
            let font = index < authors.count ? roman : italic, squeeze = scales[index]
            var cursor = x + (leading ? 0 : (textWidth - measured[index] * squeeze) / 2)
            let baseline = y + size * (1 + Double(index) * 1.25)
            for char in text {
                let glyph = font[String(char)] ?? font["?"]!
                let contours = glyph.contours.map { $0.map { Point(cursor + $0[0] * size * squeeze, baseline + $0[1] * size) } }
                if !contours.isEmpty { output.append(FilledShape(subpaths: contours, color: spec.ink.color, layer: "card")) }
                cursor += glyph.advance * size * squeeze
            }
        }
        shapes = output
    }
}
