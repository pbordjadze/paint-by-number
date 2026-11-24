#if canImport(FoundationEssentials) && !canImport(Darwin)
import FoundationEssentials
#else
import Foundation
#endif

/// The few words the book has (the stone list) and how it writes numbers and units, in the
/// painter's language: the app fills them from its catalog; the defaults are English.
public struct BookStrings: Sendable {
    public var stoneList = "Stone list"
    public var number = "No."
    public var smalti = "Smalti"
    public var tiles = "Tiles"
    public var buy = "Buy"
    public var area = "cm²"
    public var weight = "kg"
    public var altogether = "Altogether"
    public var glass = "glass"
    public var stone = "glass, or marble to match"
    public var gold = "gold leaf smalti"
    /// Gold smalti by shade, lightest first: pale, yellow, antique, dark.
    public var goldShades = ["Pale gold", "Yellow gold", "Antique gold", "Dark gold"]
    /// A gold numbered, lightest 1, when a book has more than four.
    public var goldNumber: @Sendable (Int) -> String = { "Gold \($0)" }
    public var note = "Codes are Orsoni smalti as Mosaic Workshop sells them, matched to each colour from photos: check them against samples before you order; ≈ marks the nearest where none is close. Counts include 15% spare for breakage."
    /// "S23" as ordered; "≈ S23" for a match that is only near.
    public var code: @Sendable (String, Bool) -> String = { code, near in near ? "≈ Orsoni \(code)" : "Orsoni \(code)" }
    public var decimal: @Sendable (Double, Int) -> String = { String(format: "%.\($1)f", $0) }
    public var count: @Sendable (Int) -> String = { "\($0)" }
    public var centimetres: @Sendable (Double) -> String = { String(format: "%.1f cm", $0) }
    public var size: @Sendable (Double, Double) -> String = { String(format: "%.0f × %.0f cm", $0, $1) }
    public var kilograms: @Sendable (Double) -> String = { String(format: "%.1f kg", $0) }
    public var hours: @Sendable (Int) -> String = { "\($0) h" }
    public var minutes: @Sendable (Int) -> String = { "\($0) min" }
    public var hoursRange: @Sendable (Int, Int) -> String = { "\($0)–\($1) h" }
    public var toolList = "Tools and materials"
    /// Each thing the book uses, by its pictogram's name (`StoneBook.kit`).
    public var tools: [String: String] = [
        "tiles": "Smalti, by the stone list", "nippers": "Wheeled mosaic nippers", "glasses": "Safety glasses", "gloves": "Work gloves, a pair", "mask": "Dust mask",
        "brush": "Brush and dustpan", "tub": "Small tubs, one a colour", "scissors": "Scissors", "mesh": "Fibreglass mosaic mesh, a sheet's size",
        "film": "Clear film, a sheet's size", "tape": "Masking tape", "glue": "PVA glue", "cloth": "Soft cloths", "knife": "Craft knife",
        "board": "Board: 18 mm exterior plywood", "thinset": "Tile adhesive (thinset), powder", "trowel": "Notched trowel, 4 mm",
        "grout": "Grout, powder", "float": "Rubber grout float", "sponge": "Sponges", "bucket": "Buckets", "level": "Spirit level",
        "cleat": "French cleat, with screws and wall fixings",
    ]
    /// The stones' cost, pounds, already rounded: "£680".
    public var pounds: @Sendable (Int) -> String = { "£\($0)" }
    public init() {}
}

extension StoneBook {
    enum PageKind: Sendable, Equatable {
        case cover, needs, method, map
        case opener(section: Int), cartoon(section: Int)
        /// `count` steps from `first`.
        case steps(first: Int, count: Int)
        case setting, finished
        case lesson(Lesson)
        case stones(part: Int, of: Int)
        case tools
    }

    static let stonesPerPage = 16

    /// Every page in order, and the page (1-based) each step is on.
    static func assemble(sections: Int, steps: [Step], stones: Int) -> (kinds: [PageKind], stepPage: [Int]) {
        var kinds: [PageKind] = [.cover, .needs] + Lesson.front.map { .lesson($0) } + [.method, .map]
        var stepPage = [Int](repeating: 0, count: steps.count)
        for s in 0..<sections {
            let idx = steps.indices.filter { steps[$0].section == s }
            guard !idx.isEmpty else { continue }
            kinds.append(.opener(section: s))
            kinds.append(.cartoon(section: s))
            for j in stride(from: 0, to: idx.count, by: BookLayout.stepsPerPage) {
                for i in idx[j..<min(j + BookLayout.stepsPerPage, idx.count)] { stepPage[i] = kinds.count + 1 }
                kinds.append(.steps(first: idx[j], count: min(BookLayout.stepsPerPage, idx.count - j)))
            }
        }
        kinds += Lesson.beforeSetting.map { .lesson($0) }
        kinds.append(.setting)
        kinds += Lesson.afterSetting.map { .lesson($0) }
        kinds.append(.finished)
        kinds += Lesson.afterFinished.map { .lesson($0) }
        let parts = max(1, (stones + stonesPerPage - 1) / stonesPerPage)
        for p in 0..<parts { kinds.append(.stones(part: p, of: parts)) }
        kinds.append(.tools)
        return (kinds, stepPage)
    }

    public var pageCount: Int { pageKinds.count }

    /// Page `number` (1-based) laid out.
    public func page(_ number: Int, strings: BookStrings = BookStrings()) -> BookPage {
        var c = PageCanvas()
        c.fill(.rect(0, 0, BookLayout.pageWidth, BookLayout.pageHeight), BookStyle.paper)
        switch pageKinds[number - 1] {
        case .cover: cover(&c, strings)
        case .needs: needs(&c, strings)
        case .method: method(&c, strings)
        case .map: map(&c)
        case .opener(let s): opener(&c, s, strings)
        case .cartoon(let s): cartoon(&c, s)
        case .steps(let first, let count): stepsPage(&c, first, count)
        case .setting: setting(&c, strings)
        case .finished: finished(&c)
        case .lesson(let l): lesson(&c, l, strings)
        case .stones(let part, let parts): stoneList(&c, part, parts, strings)
        case .tools: toolList(&c, strings)
        }
        if number > 1 {
            if case .cartoon = pageKinds[number - 1] {
                c.text("\(number)", BookLayout.pageWidth - BookLayout.margin, BookLayout.pageHeight - 6, 3.2, 500, BookStyle.muted, .end)
            } else {
                c.text("\(number)", BookLayout.pageWidth / 2, BookLayout.pageHeight - 6, 3.2, 500, BookStyle.muted, .middle)
            }
        }
        return c.page
    }

    // MARK: Drawing the mosaic

    struct Transform {
        var k: Double, ox: Double, oy: Double, cx0: Double, cy0: Double
        func callAsFunction(_ p: Point) -> Point { Point(ox + (p.x - cx0) * k, oy + (p.y - cy0) * k) }
    }

    /// How a piece is drawn: its fill, and its outline and the outline's width; nil leaves it out.
    typealias Style = (Piece) -> (fill: BookColor?, stroke: BookColor?, width: Double)?

    func colour(_ paint: Int) -> BookColor { BookColor(palette[paint]) }
    func colour(_ paint: Int, faded t: Double) -> BookColor { colour(paint).mixed(toward: BookStyle.paper, t) }
    var trueColour: Style { { p in (self.colour(p.paint), nil, 0) } }

    /// The pieces inside `crop` (canvas units; the whole canvas when nil) fitted into the box.
    @discardableResult
    func drawMosaic(_ c: inout PageCanvas, _ x: Double, _ y: Double, _ w: Double, _ h: Double, style: Style? = nil,
                    crop: (Double, Double, Double, Double)? = nil, grout drawGrout: Bool = true, radius: Double = 0)
        -> (Transform, box: (Double, Double, Double, Double)) {
        let style = style ?? trueColour
        let (cx0, cy0, cw, ch) = crop ?? (0, 0, width, height)
        let k = min(w / cw, h / ch)
        let ox = x + (w - cw * k) / 2, oy = y + (h - ch * k) / 2
        let tf = Transform(k: k, ox: ox, oy: oy, cx0: cx0, cy0: cy0)
        let box = (ox, oy, cw * k, ch * k)
        c.clip(.rect(ox, oy, cw * k, ch * k, radius: radius))
        if drawGrout { c.fill(.rect(ox, oy, cw * k, ch * k), BookColor(grout)) }
        let pad = 2 * spacing
        for p in pieces {
            guard p.centre.x >= cx0 - pad, p.centre.x <= cx0 + cw + pad, p.centre.y >= cy0 - pad, p.centre.y <= cy0 + ch + pad,
                  let s = style(p), s.fill != nil || s.stroke != nil else { continue }
            c.shape(.polygon(p.corners.map { tf($0) }), fill: s.fill, stroke: s.stroke, width: s.width)
        }
        c.endClip()
        return (tf, box)
    }

    func badge(_ c: inout PageCanvas, _ x: Double, _ y: Double, _ r: Double, _ paint: Int, size: Double? = nil) {
        let rgb = palette[paint]
        let l = 0.2126 * rgb.x + 0.7152 * rgb.y + 0.0722 * rgb.z
        c.shape(.circle(Point(x, y), r), fill: colour(paint), stroke: BookStyle.ink.with(alpha: 0.25), width: 0.2)
        c.text("\(paint + 1)", x, y + r * 0.36, size ?? r, 700, l < 0.45 ? BookStyle.white : BookStyle.ink, .middle)
    }

    /// Three tiles of a paint stacked a little askew: a pile to buy.
    func heap(_ c: inout PageCanvas, _ paint: Int, _ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        let side = min(w, h) * 0.62
        for (j, (dx, dy, rot)) in [(0.0, 0.32, -8.0), (0.22, 0.12, 6.0), (0.38, 0.36, -3.0)].enumerated() {
            let cx = x + dx * w + side / 2, cy = y + dy * h + side / 2
            let a = rot * .pi / 180
            let r = BookPath.rect(-side / 2, -side / 2, side, side, radius: side * 0.08)
                .mapped { Point(cx + $0.x * cos(a) - $0.y * sin(a), cy + $0.x * sin(a) + $0.y * cos(a)) }
            c.shape(r, fill: colour(paint).mixed(toward: BookColor(0, 0, 0), [0.22, 0.1, 0][j]),
                    stroke: BookColor(0, 0, 0, 0.18), width: 0.2)
        }
    }

    /// The mosaic small, faded, its sections marked; the current one outlined, a dot where the
    /// step is. Sections before `doneBefore` show nearly true.
    @discardableResult
    func minimap(_ c: inout PageCanvas, _ x: Double, _ y: Double, _ w: Double, current: Int? = nil, dot: Point? = nil, doneBefore: Int = 0) -> Double {
        let h = w * height / width
        c.shape(.rect(x - 0.8, y - 0.8, w + 1.6, h + 1.6), fill: BookStyle.white, stroke: BookStyle.ink, width: 0.25)
        c.image(minimaps[min(max(doneBefore, 0), minimaps.count - 1)], x, y, w, h)
        let k = w / width
        for col in 1..<max(columns, 1) {
            c.stroke(.line(Point(x + Double(col) * sectionWidth * k, y), Point(x + Double(col) * sectionWidth * k, y + h)), BookStyle.white, 0.5)
        }
        for row in 1..<max(rows, 1) {
            c.stroke(.line(Point(x, y + Double(row) * sectionHeight * k), Point(x + w, y + Double(row) * sectionHeight * k)), BookStyle.white, 0.5)
        }
        if let current {
            let r = sectionRect(current)
            c.stroke(.rect(x + r.x * k, y + r.y * k, r.w * k, r.h * k), BookStyle.ink, 0.7, round: false)
        }
        if let dot {
            c.shape(.circle(Point(x + dot.x * k, y + dot.y * k), 1.3), fill: BookStyle.gold, stroke: BookStyle.white, width: 0.4)
        }
        return h
    }

    /// The minimap's picture: each pixel the paint of the piece over it, faded (less in the
    /// sections already set).
    static func minimapImage(_ raster: (w: Int, h: Int, piece: [Int32]), _ pieces: [Piece], _ palette: [SIMD3<Double>],
                             doneBefore: Int) -> BookImage {
        var rgba = [UInt8](repeating: 255, count: raster.w * raster.h * 4)
        for i in 0..<(raster.w * raster.h) where raster.piece[i] >= 0 {
            let p = pieces[Int(raster.piece[i])]
            let col = BookColor(palette[p.paint]).mixed(toward: BookStyle.paper, p.section < doneBefore ? 0.15 : 0.72)
            rgba[4 * i] = UInt8((col.r * 255).rounded()); rgba[4 * i + 1] = UInt8((col.g * 255).rounded())
            rgba[4 * i + 2] = UInt8((col.b * 255).rounded())
        }
        return BookImage(width: raster.w, height: raster.h, rgba: rgba)
    }

    /// Which piece is under each pixel of the minimap (-1: a joint), 200 pixels across.
    static func rasterize(_ pieces: [Piece], width: Double, height: Double) -> (w: Int, h: Int, piece: [Int32]) {
        let w = 200, h = max(1, Int((200 * height / width).rounded()))
        let k = Double(w) / width
        var out = [Int32](repeating: -1, count: w * h)
        for (index, p) in pieces.enumerated() {
            var lo = Point(.infinity, .infinity), hi = -lo
            for q in p.corners { lo = pointwiseMin(lo, q); hi = pointwiseMax(hi, q) }
            let x0 = max(0, Int(lo.x * k)), x1 = min(w - 1, Int(hi.x * k)), y0 = max(0, Int(lo.y * k)), y1 = min(h - 1, Int(hi.y * k))
            guard x0 <= x1, y0 <= y1 else { continue }
            for y in y0...y1 {
                for x in x0...x1 where BookGeometry.contains(p.corners, Point((Double(x) + 0.5) / k, (Double(y) + 0.5) / k)) {
                    out[y * w + x] = Int32(index)
                }
            }
        }
        return (w, h, out)
    }

    func arrow(_ c: inout PageCanvas, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ color: BookColor = BookStyle.ink, _ w: Double = 0.9) {
        let a = atan2(y2 - y1, x2 - x1), h = 3.6
        c.stroke(.line(Point(x1, y1), Point(x2 - cos(a) * h * 0.6, y2 - sin(a) * h * 0.6)), color, w)
        c.fill(.polygon([Point(x2, y2), Point(x2 - h * cos(a - 0.45), y2 - h * sin(a - 0.45)),
                         Point(x2 - h * cos(a + 0.45), y2 - h * sin(a + 0.45))]), color)
    }

    func bounds(_ list: [Int]) -> (lo: Point, hi: Point) {
        var lo = Point(.infinity, .infinity), hi = -lo
        for i in list { for q in pieces[i].corners { lo = pointwiseMin(lo, q); hi = pointwiseMax(hi, q) } }
        return (lo, hi)
    }

    // MARK: Pages

    func cover(_ c: inout PageCanvas, _ strings: BookStrings) {
        let m = BookLayout.margin, pw = BookLayout.pageWidth
        c.text(title, m, 32, 15, 800, BookStyle.ink, face: .display)
        let h = 205.0, w = min(h * width / height, pw - 2 * m)
        let hh = w * height / width
        drawMosaic(&c, (pw - w) / 2, 44 + (h - hh) / 2, w, hh)
        let hours = hoursToSet, cost = Int((stonePounds / 10).rounded()) * 10
        let facts: [(BookIcon, String)] = [(.ruler, strings.size(widthMM / 10, heightMM / 10)), (.tiles, strings.count(pieces.count)),
                                           (.clock, strings.hoursRange(hours.lowerBound, hours.upperBound)),
                                           (.price, "≈ " + strings.pounds(cost)), (.pages, strings.count(pageCount))]
        // Each icon and figure as wide as they are (a semibold figure about 0.6 em a character),
        // with the room left shared out evenly round them: in equal fifths the size, the row's
        // longest, ran up against the tiles' icon.
        let widths = facts.map { 8 + 1.5 + Double($0.1.count) * 4.3 * 0.6 }
        let gap = max(2, (pw - 2 * m - widths.reduce(0, +)) / Double(facts.count))
        var x = m + gap / 2
        for ((icon, s), wide) in zip(facts, widths) {
            icon.draw(into: &c, x, 262.5, 8)
            c.text(s, x + 9.5, 268.3, 4.3, 600)
            x += wide + gap
        }
    }

    func needs(_ c: inout PageCanvas, _ strings: BookStrings) {
        let m = BookLayout.margin, pw = BookLayout.pageWidth
        let tools = kit(strings)
        var cw = (pw - 2 * m) / 6
        for (i, t) in tools.enumerated() {
            let x = m + Double(i % 6) * cw, y = 18 + Double(i / 6) * 29
            t.icon.draw(into: &c, x + cw / 2 - 8, y + 2.2, 16)
            c.text(t.amount, x + cw / 2, y + 23.4, 3.6, 400, BookStyle.ink, .middle)
        }
        // every stone, as a heap with its count to buy
        let rows = stones
        let y0 = 18 + Double((tools.count + 5) / 6) * 29 + 8
        c.stroke(.line(Point(m, y0 - 6), Point(pw - m, y0 - 6)), BookStyle.faint, 0.3)
        cw = (pw - 2 * m) / 4
        let rh = min(19.5, (BookLayout.pageHeight - 16 - y0) / Double(max(1, (rows.count + 3) / 4)))
        for (i, r) in rows.enumerated() {
            let x = m + Double(i % 4) * cw, y = y0 + Double(i / 4) * rh
            heap(&c, r.paint, x + 2, y, 15 * rh / 19.5, 14 * rh / 19.5)
            badge(&c, x + 21, y + 4.5, 2.6, r.paint, size: 2.4)
            c.text(strings.count(r.buy) + "x", x + 25.5, y + 12.5, 4.4, 400)
        }
    }

    /// The section the front pages show: the one with the most pieces.
    var sampleSection: Int {
        sections.indices.max { sections[$0].count != sections[$1].count ? sections[$0].count < sections[$1].count : $0 > $1 } ?? 0
    }

    func method(_ c: inout PageCanvas, _ strings: BookStrings) {
        let m = BookLayout.margin, pw = BookLayout.pageWidth
        let cw = (pw - 2 * m) / 2, ch = 82.0
        let s = sampleSection
        let r = sectionRect(s)
        let crop = (r.x + r.w * 0.15, r.y + r.h * 0.3, r.w * 0.7, r.h * 0.45)
        let outline: Style = { p in p.section == s ? (BookStyle.white, BookColor(hex: 0x9A9384), 0.25) : nil }
        let own: Style = { p in p.section == s ? (self.colour(p.paint), nil, 0) : nil }
        for i in 0..<6 {
            let x = m + Double(i % 2) * cw + 3, y = 18 + Double(i / 2) * (ch + 4)
            c.shape(.rect(x, y, cw - 6, ch), fill: nil, stroke: BookStyle.ink, width: 0.35)
            c.text("\(i + 1)", x + 4, y + 10, 8, 800, BookStyle.ink, face: .display)
            let bx = x + 14, by = y + 8, bw = cw - 30, bh = ch - 16
            switch i {
            case 0:     // the cartoon, taped down
                let (_, box) = drawMosaic(&c, bx, by, bw, bh, style: outline, crop: crop, grout: false)
                for (px, py) in [(box.0, box.1), (box.0 + box.2, box.1), (box.0, box.1 + box.3), (box.0 + box.2, box.1 + box.3)] {
                    let a = -30.0 * .pi / 180
                    c.fill(BookPath.rect(-3, -1.2, 6, 2.4).mapped { Point(px + $0.x * cos(a) - $0.y * sin(a), py + $0.x * sin(a) + $0.y * cos(a)) },
                           BookColor(hex: 0xEFE1B8, alpha: 0.9))
                }
            case 1:     // film over it
                let (_, box) = drawMosaic(&c, bx, by, bw, bh, style: outline, crop: crop, grout: false)
                c.shape(.rect(box.0 - 2, box.1 - 2, box.2 + 4, box.3 + 4), fill: BookColor(hex: 0xDBE7EF, alpha: 0.45),
                        stroke: BookColor(hex: 0x9FB6C6), width: 0.3)
                arrow(&c, box.0 + box.2 + 1, box.1 - 5, box.0 + box.2 - 8, box.1 + 4)
            case 2:     // mesh over that
                let (_, box) = drawMosaic(&c, bx, by, bw, bh, style: outline, crop: crop, grout: false)
                c.fill(.rect(box.0 - 2, box.1 - 2, box.2 + 4, box.3 + 4), BookColor(hex: 0xDBE7EF, alpha: 0.45))
                var mesh = BookPath()
                let step = 2.2
                for j in 0...Int((box.2 + 4) / step) {
                    mesh.elements += [.move(Point(box.0 - 2 + Double(j) * step, box.1 - 2)), .line(Point(box.0 - 2 + Double(j) * step, box.1 + box.3 + 2))]
                }
                for j in 0...Int((box.3 + 4) / step) {
                    mesh.elements += [.move(Point(box.0 - 2, box.1 - 2 + Double(j) * step)), .line(Point(box.0 + box.2 + 2, box.1 - 2 + Double(j) * step))]
                }
                c.stroke(mesh, BookColor(hex: 0xC9C2B0), 0.25, round: false)
            case 3:     // a dab of glue on each tile's back, set face up
                let inCrop = sections[s].filter { i in
                    let p = pieces[i].centre
                    return p.x >= crop.0 && p.x <= crop.0 + crop.2 && p.y >= crop.1 && p.y <= crop.1 + crop.3
                }
                let done = Set(inCrop.prefix(inCrop.count / 2).map { pieces[$0].centre })
                let (_, box) = drawMosaic(&c, bx, by, bw, bh, style: { p in done.contains(p.centre) ? (self.colour(p.paint), nil, 0) : outline(p) },
                                          crop: crop, grout: false)
                BookIcon.glue.draw(into: &c, box.0 + box.2 - 16, box.1 + 2, 14)
            case 4:     // a day to dry
                let (_, box) = drawMosaic(&c, bx, by, bw, bh, style: own, crop: crop, grout: false)
                BookIcon.clock.draw(into: &c, box.0 + box.2 / 2 - 9, box.1 + box.3 / 2 - 9, 18)
                c.fill(.rect(box.0 + box.2 / 2 - 8, box.1 + box.3 / 2 + 10, 16, 7, radius: 3.5), BookStyle.white)
                c.text(strings.hours(24), box.0 + box.2 / 2, box.1 + box.3 / 2 + 15, 4.4, 700, BookStyle.ink, .middle)
            default:    // the sheet lifted off the film
                let (_, box) = drawMosaic(&c, bx + 4, by - 3, bw - 8, bh - 4, style: own, crop: crop, grout: false)
                c.fill(.rect(bx, by + bh - 6, bw, 4), BookColor(hex: 0xDBE7EF, alpha: 0.6))
                arrow(&c, box.0 + box.2 + 3, box.1 + box.3, box.0 + box.2 + 3, box.1 + 6)
            }
        }
    }

    func map(_ c: inout PageCanvas) {
        let pw = BookLayout.pageWidth
        var h = 250.0, w = h * width / height
        if w > pw - 2 * BookLayout.margin { w = pw - 2 * BookLayout.margin; h = w * height / width }
        let x0 = (pw - w) / 2, y0 = 22.0
        let (tf, _) = drawMosaic(&c, x0, y0, w, h)
        let k = tf.k
        for col in 1..<max(columns, 1) {
            c.stroke(.line(Point(x0 + Double(col) * sectionWidth * k, y0), Point(x0 + Double(col) * sectionWidth * k, y0 + h)), BookStyle.ink, 0.5, dash: [2, 1.2], round: false)
        }
        for row in 1..<max(rows, 1) {
            c.stroke(.line(Point(x0, y0 + Double(row) * sectionHeight * k), Point(x0 + w, y0 + Double(row) * sectionHeight * k)), BookStyle.ink, 0.5, dash: [2, 1.2], round: false)
        }
        for s in sections.indices {
            let r = sectionRect(s)
            let cx = x0 + (r.x + r.w / 2) * k, cy = y0 + (r.y + r.h / 2) * k
            c.shape(.circle(Point(cx, cy), 6), fill: BookStyle.paper, stroke: BookStyle.ink, width: 0.6)
            c.text("\(s + 1)", cx, cy + 2.2, 6, 700, BookStyle.ink, .middle)
            if let first = steps.firstIndex(where: { $0.section == s }) {
                c.fill(.rect(cx - 5, cy + 8, 10, 4.2, radius: 2.1), BookStyle.paper)
                c.text("\(stepPage[first])", cx, cy + 11, 3, 600, BookStyle.ink, .middle)
            }
        }
    }

    func opener(_ c: inout PageCanvas, _ s: Int, _ strings: BookStrings) {
        let m = BookLayout.margin, pw = BookLayout.pageWidth
        c.text("\(s + 1)", m, 44, 34, 800, BookStyle.ink, face: .display)
        minimap(&c, pw - m - 40, 16, 40, current: s, doneBefore: s)
        let r = sectionRect(s)
        let pad = spacing * 1.5
        let crop = (r.x - pad, r.y - pad, r.w + 2 * pad, r.h + 2 * pad)
        let (tf, _) = drawMosaic(&c, m + 10, 70, pw - 2 * m - 20, 175, style: { p in
            p.section == s ? (self.colour(p.paint), nil, 0) : p.section < s ? (self.colour(p.paint, faded: 0.8), nil, 0) : nil
        }, crop: crop, grout: false)
        // the sheet's size, as a ruler gives it
        let (lo, hi) = bounds(sections[s])
        let a = tf(lo), b = tf(hi)
        var rule = BookPath()
        rule.elements = [.move(Point(a.x, b.y + 5)), .line(Point(b.x, b.y + 5)), .move(Point(a.x, b.y + 3.5)), .line(Point(a.x, b.y + 6.5)),
                         .move(Point(b.x, b.y + 3.5)), .line(Point(b.x, b.y + 6.5)),
                         .move(Point(b.x + 5, a.y)), .line(Point(b.x + 5, b.y)), .move(Point(b.x + 3.5, a.y)), .line(Point(b.x + 6.5, a.y)),
                         .move(Point(b.x + 3.5, b.y)), .line(Point(b.x + 6.5, b.y))]
        c.stroke(rule, BookStyle.ink, 0.35, round: false)
        c.text(strings.centimetres((hi.x - lo.x) * mm / 10), (a.x + b.x) / 2, b.y + 10.5, 3.6, 600, BookStyle.ink, .middle)
        c.text(strings.centimetres((hi.y - lo.y) * mm / 10), b.x + 8, (a.y + b.y) / 2, 3.6, 600, BookStyle.ink, .middle, rotation: 90)
        // what it takes: its pieces by paint
        var counts: [Int: Int] = [:], order: [Int] = []
        for i in sections[s] {
            if counts[pieces[i].paint] == nil { order.append(pieces[i].paint) }
            counts[pieces[i].paint, default: 0] += 1
        }
        var x = m, y = 264.0
        for p in order.sorted(by: { counts[$0]! != counts[$1]! ? counts[$0]! > counts[$1]! : $0 < $1 }) {
            if x > pw - m - 20 { x = m; y += 8 }
            badge(&c, x + 3, y, 3, p, size: 2.6)
            c.text(strings.count(counts[p]!) + "x", x + 7.5, y + 1.3, 3.4, 400)
            x += 21
        }
    }

    /// The section at true size, to lay the film and mesh over: every piece's outline and number.
    func cartoon(_ c: inout PageCanvas, _ s: Int) {
        let m = BookLayout.margin, pw = BookLayout.pageWidth, ph = BookLayout.pageHeight
        let (lo, hi) = bounds(sections[s])
        let k = mm
        let w = (hi.x - lo.x) * k, h = (hi.y - lo.y) * k
        let ox = (pw - w) / 2, oy = (ph - h) / 2 + 3
        func tf(_ p: Point) -> Point { Point(ox + (p.x - lo.x) * k, oy + (p.y - lo.y) * k) }
        for i in sections[s] {
            c.shape(.polygon(pieces[i].corners.map(tf)), fill: colour(pieces[i].paint, faded: 0.82), stroke: BookColor(hex: 0x3A3A3A), width: 0.18)
        }
        for i in sections[s] {
            let p = tf(pieces[i].centre)
            c.text("\(pieces[i].paint + 1)", p.x, p.y + 0.75, pieces[i].paint < 9 ? 2.1 : 1.8, 600, BookColor(hex: 0x222222), .middle)
        }
        // registration crosses, and a centimetre rule along two edges
        for (cx, cy) in [(ox - 5, oy - 5), (ox + w + 5, oy - 5), (ox - 5, oy + h + 5), (ox + w + 5, oy + h + 5)] {
            c.stroke(BookPath(elements: [.move(Point(cx - 2.5, cy)), .line(Point(cx + 2.5, cy)), .move(Point(cx, cy - 2.5)), .line(Point(cx, cy + 2.5))]),
                     BookStyle.ink, 0.25, round: false)
            c.stroke(.circle(Point(cx, cy), 1.3), BookStyle.ink, 0.25)
        }
        var ticks = BookPath()
        for i in 0...Int(w / 10) {
            ticks.elements += [.move(Point(ox + Double(i) * 10, oy - 8)), .line(Point(ox + Double(i) * 10, oy - 8 - (i % 5 == 0 ? 3.5 : 2)))]
        }
        for i in 0...Int(h / 10) {
            ticks.elements += [.move(Point(ox - 8, oy + Double(i) * 10)), .line(Point(ox - 8 - (i % 5 == 0 ? 3.5 : 2), oy + Double(i) * 10))]
        }
        c.stroke(ticks, BookStyle.ink, 0.25, round: false)
        // which section meets each edge
        let col = s % columns, row = s / columns
        for (dc, dr, x, y) in [(-1, 0, ox - 9, oy + h / 2), (1, 0, ox + w + 9, oy + h / 2), (0, -1, ox + w / 2, oy - 12), (0, 1, ox + w / 2, oy + h + 11)] {
            guard (0..<columns).contains(col + dc), (0..<rows).contains(row + dr) else { continue }
            c.stroke(.circle(Point(x, y), 3), BookStyle.ink, 0.35)
            c.text("\((row + dr) * columns + col + dc + 1)", x, y + 1.25, 3.4, 700, BookStyle.ink, .middle)
        }
        c.text("\(s + 1)", m, 14, 6, 800, BookStyle.ink, face: .display)
        c.text("1:1", pw - m, 13.5, 4, 700, BookStyle.ink, .end)
        c.fill(.rect(pw - m - 10, 15.5, 10, 1), BookStyle.ink)
    }

    func stepsPage(_ c: inout PageCanvas, _ first: Int, _ count: Int) {
        let m = BookLayout.margin, pw = BookLayout.pageWidth
        let half = (BookLayout.pageHeight - 2 * m) / Double(BookLayout.stepsPerPage)
        for j in 0..<BookLayout.stepsPerPage {
            if j < count { stepBlock(&c, first + j, m + Double(j) * half) }
            if j < BookLayout.stepsPerPage - 1 {
                let yy = m + Double(j + 1) * half - 3
                c.stroke(.line(Point(m, yy), Point(pw - m, yy)), BookStyle.faint, 0.3)
            }
        }
    }

    /// One step drawn at `y0`; returns where a point of the picture lands in its view.
    @discardableResult
    func stepBlock(_ c: inout PageCanvas, _ n: Int, _ y0: Double) -> Transform {
        let step = steps[n], s = step.section
        let x0 = BookLayout.margin
        let firstOfSection = steps.firstIndex { $0.section == s } ?? n
        c.text("\(n - firstOfSection + 1)", x0, y0 + 15, 15, 800, BookStyle.ink, face: .display)
        // the sheet it belongs to, as the map numbers it
        c.shape(.circle(Point(x0 + 5, y0 + 25), 4.2), fill: BookStyle.paper, stroke: BookStyle.ink, width: 0.5)
        c.text("\(s + 1)", x0 + 5, y0 + 26.6, 4.2, 700, BookStyle.ink, .middle)
        // the tray beside it is at true size
        c.text("1:1", x0 + 5, y0 + 38, 4, 700, BookStyle.ink, .middle)
        // the parts box: this step's pieces at true size, by paint
        let chunk = step.pieces.map { pieces[$0] }
        let (placed, boxH) = BookLayout.parts(chunk, mm: mm, x: BookLayout.partsX, y: y0, width: BookLayout.partsWidth)
        c.shape(.rect(BookLayout.partsX, y0, BookLayout.partsWidth, boxH), fill: BookStyle.white, stroke: BookStyle.ink, width: 0.35)
        for item in placed {
            switch item {
            case .badge(let paint, let at): badge(&c, at.x, at.y, 2.4, paint, size: 2.2)
            case .piece(let i, let corners):
                c.shape(.polygon(corners), fill: colour(chunk[i].paint),
                        stroke: BookColor(0, 0, 0, 0.2), width: 0.15)
            }
        }
        // the view: the section so far, this step's pieces set in
        let vy = y0 + BookLayout.partsHeight + 4, vw = BookLayout.viewWidth, vh = BookLayout.viewHeight
        let (lo, hi) = bounds(step.pieces)
        let f = frame(s)
        let cx = (f.loX + f.hiX) / 2
        let cy = min(max((lo.y + hi.y) / 2, f.loY + f.spanH / 2), f.hiY - f.spanH / 2)
        let crop = (cx - f.spanW / 2, cy - f.spanH / 2, f.spanW, f.spanH)
        let kk = min(vw / crop.2, vh / crop.3)
        let fw = crop.2 * kk, fh = crop.3 * kk
        c.fill(.rect(x0 + (vw - fw) / 2, vy + (vh - fh) / 2, fw, fh), BookColor(hex: 0xF2F2F2))
        let (tf, _) = drawMosaic(&c, x0, vy, vw, vh, style: { p in
            if p.step == n { return (self.colour(p.paint), BookStyle.gold, 0.55) }
            if p.section == s && p.step < n { return (self.colour(p.paint), nil, 0) }
            if p.section == s { return (BookStyle.white, BookColor(hex: 0xCFC8B9), 0.18) }
            if p.section < s { return (self.colour(p.paint, faded: 0.6), nil, 0) }
            return (BookColor(hex: 0xF7F4EE), nil, 0)
        }, crop: crop, grout: false)
        // the sheet's edge where it shows
        let r = sectionRect(s)
        let e0 = tf(Point(r.x, r.y)), e1 = tf(Point(r.x + r.w, r.y + r.h))
        c.clip(.rect(x0, vy, vw, vh))
        c.stroke(.rect(e0.x, e0.y, e1.x - e0.x, e1.y - e0.y), BookStyle.muted, 0.3, dash: [1.6, 1], round: false)
        c.endClip()
        // where we are
        let mw = 20.0, mh = mw * height / width
        minimap(&c, x0 + vw - mw - 3, vy + vh - mh - 3, mw, current: s, dot: Point(cx, cy), doneBefore: s)
        return tf
    }

    /// The sheets onto the board by the map, then grout: wordless.
    func setting(_ c: inout PageCanvas, _ strings: BookStrings) {
        let m = BookLayout.margin, pw = BookLayout.pageWidth
        let cw = (pw - 2 * m) / 2, ch = 62.0
        let next = sections.count / 2
        for i in 0..<8 {
            let x = m + Double(i % 2) * cw + 3, y = 18 + Double(i / 2) * (ch + 4)
            c.shape(.rect(x, y, cw - 6, ch), fill: nil, stroke: BookStyle.ink, width: 0.35)
            c.text("\(i + 1)", x + 4, y + 10, 8, 800, BookStyle.ink, face: .display)
            let cx = x + (cw - 6) / 2
            let h = ch - 16, w = h * width / height
            switch i {
            case 0:
                BookIcon.thinset.draw(into: &c, cx - 24, y + 14, 24); BookIcon.trowel.draw(into: &c, cx + 2, y + 14, 24)
            case 1:     // the sheets set by the map, the next one going in
                let (tf, _) = drawMosaic(&c, cx - w / 2, y + 8, w, h, style: { p in p.section < next ? (self.colour(p.paint), nil, 0) : nil }, grout: false)
                c.stroke(.rect(cx - w / 2, y + 8, w, h), BookStyle.muted, 0.3, dash: [1.5, 1], round: false)
                let r = sectionRect(next)
                let p = tf(Point(r.x + r.w / 2, r.y + r.h / 2))
                arrow(&c, p.x + 18, p.y + 14, p.x + 2, p.y + 2)
                c.shape(.circle(Point(p.x + 21, p.y + 17), 3.4), fill: BookStyle.paper, stroke: BookStyle.ink, width: 0.4)
                c.text("\(next + 1)", p.x + 21, p.y + 18.3, 3.6, 700, BookStyle.ink, .middle)
            case 2:
                BookIcon.clock.draw(into: &c, cx - 11, y + 14, 22)
                c.text(strings.hours(24), cx, y + 47, 4.4, 700, BookStyle.ink, .middle)
            case 3:
                BookIcon.grout.draw(into: &c, cx - 24, y + 14, 24); BookIcon.bucket.draw(into: &c, cx + 2, y + 14, 24)
            case 4:     // grout floated over the face
                drawMosaic(&c, cx - w / 2, y + 8, w, h)
                c.fill(.polygon([Point(cx - w / 2, y + 8 + h * 0.55), Point(cx + w / 2, y + 8 + h * 0.2), Point(cx + w / 2, y + 8 + h),
                                 Point(cx - w / 2, y + 8 + h)]), BookColor(grout, 0.85))
                BookIcon.float.draw(into: &c, cx + 4, y + 8 + h * 0.18, 20)
                arrow(&c, cx + 18, y + 14, cx + 8, y + 28)
            case 5:
                BookIcon.clock.draw(into: &c, cx - 24, y + 14, 24); BookIcon.sponge.draw(into: &c, cx + 2, y + 14, 24)
                c.text(strings.minutes(15), cx - 12, y + 47, 4.4, 700, BookStyle.ink, .middle)
            case 6:
                BookIcon.cloth.draw(into: &c, cx - 12, y + 14, 24)
            default:
                drawMosaic(&c, cx - w / 2, y + 8, w, h)
            }
        }
    }

    func finished(_ c: inout PageCanvas) {
        let pw = BookLayout.pageWidth
        var h = 240.0, w = h * width / height
        if w > pw - 2 * BookLayout.margin { w = pw - 2 * BookLayout.margin; h = w * height / width }
        drawMosaic(&c, (pw - w) / 2, 28, w, h)
    }

    /// Everything the book uses but the stones, and how much: the needs page's pictures, and the
    /// tools list's rows.
    func kit(_ strings: BookStrings) -> [(icon: BookIcon, amount: String)] {
        let n = strings.count(sections.count), one = strings.count(1) + "x"
        let thinset = widthMM * heightMM / 1e6 * 4.4      // kg: 4 kg a square metre, and a tenth over
        return [(.nippers, one), (.glasses, one), (.gloves, one), (.mask, one), (.brush, one), (.tub, strings.count(stones.count) + "x"),
                (.scissors, one), (.mesh, n + "x"), (.film, n + "x"), (.tape, one), (.glue, one), (.cloth, strings.count(3) + "x"),
                (.knife, one), (.board, strings.size(widthMM / 10 + 4, heightMM / 10 + 4)), (.thinset, strings.kilograms(thinset)),
                (.trowel, one), (.grout, strings.kilograms(groutKilograms)), (.float, one), (.sponge, strings.count(2) + "x"),
                (.bucket, strings.count(2) + "x"), (.level, one), (.cleat, one)]
    }

    /// The tools and materials by name, a page with words like the stone list.
    func toolList(_ c: inout PageCanvas, _ strings: BookStrings) {
        let m = BookLayout.margin, pw = BookLayout.pageWidth
        c.text(strings.toolList, m, 24, 8, 400, BookStyle.ink, face: .serif)
        var y = 34.0
        // the stones themselves first, every one of them counted
        let smalti = (icon: BookIcon.tiles, amount: strings.count(stones.reduce(0) { $0 + $1.buy }) + "x")
        for t in [smalti] + kit(strings) {
            c.stroke(.line(Point(m, y), Point(pw - m, y)), BookStyle.faint, 0.25)
            t.icon.draw(into: &c, m + 1, y + 1, 9)
            c.text(strings.tools[t.icon.rawValue] ?? t.icon.rawValue, m + 16, y + 6.8, 3.8, 600)
            c.text(t.amount, pw - m, y + 6.8, 3.6, 700, BookStyle.ink, .end)
            y += 10.5
        }
    }

    /// The one page with words: what to buy, with how much.
    func stoneList(_ c: inout PageCanvas, _ part: Int, _ parts: Int, _ strings: BookStrings) {
        let m = BookLayout.margin, pw = BookLayout.pageWidth
        let all = stones
        let rows = Array(all[min(part * StoneBook.stonesPerPage, all.count)..<min((part + 1) * StoneBook.stonesPerPage, all.count)])
        if part == 0 { c.text(strings.stoneList, m, 24, 8, 400, BookStyle.ink, face: .serif) }
        if parts > 1 { c.text("\(part + 1) / \(parts)", pw - m, 24, 3.4, 500, BookStyle.muted, .end) }
        let head = 36.0
        let columns: [(Double, String, BookText.Anchor)] = [(m + 22, strings.number, .start), (m + 34, strings.smalti, .start),
                                                            (m + 112, strings.tiles, .end), (m + 130, strings.buy, .end),
                                                            (m + 154, strings.area, .end), (pw - m, strings.weight, .end)]
        for (x, s, a) in columns { c.text(s, x, head, 2.9, 600, BookStyle.muted, a) }
        var y = head + 4
        for r in rows {
            c.stroke(.line(Point(m, y), Point(pw - m, y)), BookStyle.faint, 0.25)
            heap(&c, r.paint, m, y + 0.5, 16, 11)
            badge(&c, m + 25, y + 6, 2.6, r.paint, size: 2.4)
            let kind = r.kind == .gold ? strings.gold : r.kind == .stone ? strings.stone : strings.glass
            if let smalto = r.smalto {
                c.text(strings.code(smalto.code, r.distance > 0.06), m + 34, y + 5.6, 3.8, 600)
                let detail = [names[r.paint], kind].compactMap { $0 }.joined(separator: " · ")
                c.text(detail, m + 34, y + 9.6, 2.6, 400, BookStyle.muted)
            } else if let shade = r.goldShade {
                c.text(shade < strings.goldShades.count ? strings.goldShades[shade] : strings.goldNumber(shade - 3), m + 34, y + 5.6, 3.8, 600)
                let detail = [names[r.paint], kind].compactMap { $0 }.joined(separator: " · ")
                c.text(detail, m + 34, y + 9.6, 2.6, 400, BookStyle.muted)
            } else {
                c.text(names[r.paint] ?? kind, m + 34, y + 5.6, 3.8, 600)
                c.text(kind, m + 34, y + 9.6, 2.6, 400, BookStyle.muted)
            }
            c.text(strings.count(r.count), m + 112, y + 7.2, 3.6, 500, BookStyle.ink, .end)
            c.text(strings.count(r.buy), m + 130, y + 7.2, 3.6, 700, BookStyle.ink, .end)
            c.text(strings.decimal(r.areaCM2, 0), m + 154, y + 7.2, 3.6, 400, BookStyle.ink, .end)
            c.text(strings.decimal(r.kilograms, 2), pw - m, y + 7.2, 3.6, 600, BookStyle.ink, .end)
            y += 12.5
        }
        guard part == parts - 1 else { return }
        c.stroke(.line(Point(m, y), Point(pw - m, y)), BookStyle.ink, 0.4)
        c.text(strings.altogether, m + 34, y + 7, 3.8, 600)
        c.text(strings.count(all.reduce(0) { $0 + $1.count }), m + 112, y + 7, 3.6, 600, BookStyle.ink, .end)
        c.text(strings.count(all.reduce(0) { $0 + $1.buy }), m + 130, y + 7, 3.6, 700, BookStyle.ink, .end)
        c.text(strings.decimal(all.reduce(0) { $0 + $1.areaCM2 }, 0), m + 154, y + 7, 3.6, 600, BookStyle.ink, .end)
        c.text(strings.decimal(all.reduce(0) { $0 + $1.kilograms }, 1), pw - m, y + 7, 3.6, 700, BookStyle.ink, .end)
        // the note, wrapped by words to the page's width
        var line = "", ly = y + 20
        for word in strings.note.split(separator: " ") {
            let next = line.isEmpty ? String(word) : line + " " + word
            if next.count > 95, !line.isEmpty {
                c.text(line, m, ly, 2.9, 400, BookStyle.muted); ly += 4.4; line = String(word)
            } else {
                line = next
            }
        }
        if !line.isEmpty { c.text(line, m, ly, 2.9, 400, BookStyle.muted) }
    }
}

extension StoneBook {
    /// The pages a look at the book starts from: the front pages, the middle section's opener,
    /// cartoon and first two step pages, a later step page, and the closing pages.
    public var samplePages: Set<Int> {
        var want: Set<Int> = [1, 2, 3, 4]
        let openers = pageKinds.indices.filter { if case .opener = pageKinds[$0] { true } else { false } }.map { $0 + 1 }
        if let mid = openers.isEmpty ? nil : openers[openers.count / 2] {
            want.formUnion([mid, mid + 1, mid + 2, mid + 3, mid + 8].filter { $0 <= pageCount })
        }
        for (i, k) in pageKinds.enumerated() {
            switch k {
            case .setting, .finished, .stones, .tools, .lesson: want.insert(i + 1)
            default: break
            }
        }
        return want
    }
}
