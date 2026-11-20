import Foundation

/// The book's lessons: wordless pages for someone who has never held nippers, each a grid of
/// panels, a ✓ or ✗ on the ones that show a right and a wrong way. They came from a newcomer's
/// walk through the book (painting-company row 367): the front ones before the first sheet, the
/// bed and the grout before the sheets go onto the board, hanging after the finished picture.
extension StoneBook {
    public enum Lesson: Sendable, CaseIterable {
        case safety, sorting, faces, cutting, shaping, gluing, reading, mending
        case bed, pressing, grouting
        case hanging

        static let front: [Lesson] = [.safety, .sorting, .faces, .cutting, .shaping, .gluing, .reading, .mending]
        static let beforeSetting: [Lesson] = [.bed, .pressing, .grouting]
        static let afterFinished: [Lesson] = [.hanging]
    }

    struct Panel {
        var x: Double, y: Double, w: Double, h: Double
        var cx: Double { x + w / 2 }
        var cy: Double { y + h / 2 + 3 }
    }

    static let okColour = BookColor(hex: 0x4E7D4A), noColour = BookColor(hex: 0xB0412E)

    /// The page's panels, numbered, `columns` across and `rows` down.
    func panels(_ c: inout PageCanvas, _ count: Int, rows: Int, columns: Int = 2) -> [Panel] {
        let m = BookLayout.margin, pw = BookLayout.pageWidth
        let cw = (pw - 2 * m) / Double(columns), top = 18.0
        let ch = (BookLayout.pageHeight - top - 16) / Double(rows) - 4
        return (0..<count).map { i in
            let x = m + Double(i % columns) * cw + 3, y = top + Double(i / columns) * (ch + 4)
            c.shape(.rect(x, y, cw - 6, ch, radius: 3), fill: BookStyle.white, stroke: BookStyle.faint, width: 0.3)
            c.text("\(i + 1)", x + 5, y + 10, 7, 700)
            return Panel(x: x, y: y, w: cw - 6, h: ch)
        }
    }

    /// ✓ or ✗ in the panel's top corner.
    func mark(_ c: inout PageCanvas, _ p: Panel, ok: Bool) {
        let x = p.x + p.w - 9, y = p.y + 9
        c.fill(.circle(Point(x, y), 4.6), ok ? StoneBook.okColour : StoneBook.noColour)
        if ok {
            c.stroke(BookPath(elements: [.move(Point(x - 2.2, y + 0.2)), .line(Point(x - 0.6, y + 1.9)), .line(Point(x + 2.3, y - 1.6))]), BookStyle.white, 1)
        } else {
            c.stroke(BookPath(elements: [.move(Point(x - 1.8, y - 1.8)), .line(Point(x + 1.8, y + 1.8)), .move(Point(x + 1.8, y - 1.8)), .line(Point(x - 1.8, y + 1.8))]), BookStyle.white, 1)
        }
    }

    /// A smalto seen from above, turned `degrees`.
    func smalto(_ c: inout PageCanvas, _ cx: Double, _ cy: Double, _ w: Double, _ h: Double, _ fill: BookColor, degrees: Double = 0) {
        let a = degrees * .pi / 180
        c.shape(BookPath.rect(-w / 2, -h / 2, w, h, radius: min(w, h) * 0.12).mapped { Point(cx + $0.x * cos(a) - $0.y * sin(a), cy + $0.x * sin(a) + $0.y * cos(a)) },
                fill: fill, stroke: BookColor(0, 0, 0, 0.3), width: 0.25)
    }

    /// A smalto seen from the side: its body, and a gold leaf face on top or underneath.
    func sideStone(_ c: inout PageCanvas, _ x: Double, _ y: Double, _ w: Double, _ h: Double, _ fill: BookColor, gold: Bool? = nil) {
        c.shape(.rect(x, y, w, h, radius: 0.6), fill: fill, stroke: BookColor(0, 0, 0, 0.3), width: 0.25)
        if let up = gold {
            c.fill(.rect(x, up ? y : y + h - 1.2, w, 1.2), BookColor(hex: 0xE2BE55))
        }
    }

    /// The nippers seen from above, their wheels at the top, `s` mm tall.
    func nippers(_ c: inout PageCanvas, _ x: Double, _ y: Double, _ s: Double) { BookIcon.nippers.draw(into: &c, x, y, s) }

    /// The paints most used, gold or not, for the lessons' stones.
    var lessonPaints: [Int] {
        let st = stones
        return st.isEmpty ? [0] : st.map(\.paint)
    }

    var goldPaint: Int? { stones.first { $0.kind == .gold }?.paint }

    /// The median piece of the sample section, in millimetres, its corners about its centre.
    var typicalPiece: [Point] {
        let own = sections[sampleSection].map { pieces[$0] }.sorted { $0.area < $1.area }
        guard let p = own.isEmpty ? pieces.first : own[own.count / 2] else { return [] }
        return p.corners.map { ($0 - p.centre) * mm }
    }

    var largestPiece: [Point] {
        guard let p = sections[sampleSection].map({ pieces[$0] }).max(by: { $0.area < $1.area }) else { return typicalPiece }
        return p.corners.map { ($0 - p.centre) * mm }
    }

    /// The finished panel's weight, kg: the stones, an 18 mm plywood board, the bed and the grout.
    public var hangingKilograms: Double {
        let m2 = widthMM * heightMM / 1e6
        return stones.reduce(0) { $0 + $1.kilograms } + m2 * (10.8 + 4) + groutKilograms
    }

    /// How much a panel's drawing is enlarged about the panel's middle: the drawings are made at
    /// a size that leaves room, then grown to fill their panel.
    static let lessonZoom = 1.4

    func lesson(_ c: inout PageCanvas, _ lesson: Lesson, _ strings: BookStrings) {
        var d = PageCanvas()
        let p: [Panel] = switch lesson {
        case .safety: safety(&d)
        case .sorting: sorting(&d)
        case .faces: faces(&d, strings)
        case .cutting: cutting(&d)
        case .shaping: shaping(&d)
        case .gluing: gluing(&d, strings)
        case .reading: reading(&d)
        case .mending: mending(&d, strings)
        case .bed: bed(&d, strings)
        case .pressing: pressing(&d, strings)
        case .grouting: grouting(&d, strings)
        case .hanging: hanging(&d, strings)
        }
        // each drawing grown about its panel's middle; the panel, its number and its mark stay
        let k = StoneBook.lessonZoom
        var current: Panel?
        for item in d.page.items {
            let at: Point? = switch item {
            case .shape(let path, _, _), .clip(let path): path.elements.lazy.compactMap { e -> Point? in if case .move(let q) = e { q } else { nil } }.first
            case .text(let t): t.at
            case .image(_, let o, _): o
            case .endClip: nil
            }
            if let at {
                current = p.first { at.x >= $0.x - 0.5 && at.x <= $0.x + $0.w + 0.5 && at.y >= $0.y - 0.5 && at.y <= $0.y + $0.h + 0.5 }
                if let q = current, at.y < q.y + 16, at.x < q.x + 12 || at.x > q.x + q.w - 16 { c.page.items.append(item); current = nil; continue }
            }
            guard let q = current else { c.page.items.append(item); continue }
            let o = Point(q.cx, q.cy)
            func f(_ v: Point) -> Point { o + (v - o) * k }
            switch item {
            case .shape(let path, let fill, var stroke):
                if var st = stroke { st.width *= k; st.dash = st.dash.map { $0 * k }; stroke = st }
                c.page.items.append(.shape(path.mapped(f), fill: fill, stroke: stroke))
            case .clip(let path): c.page.items.append(.clip(path.mapped(f)))
            case .text(var t): t.at = f(t.at); t.size *= k; c.page.items.append(.text(t))
            case .image(let image, let origin, let size): c.page.items.append(.image(image, origin: f(origin), size: size * k))
            case .endClip: c.page.items.append(.endClip)
            }
        }
    }

    // MARK: Before the first sheet

    func shards(_ c: inout PageCanvas, _ cx: Double, _ cy: Double, _ r: Double, _ paint: Int) {
        for i in 0..<9 {
            let a = Double(i) * 0.7 + 0.3, d = r * (0.55 + 0.45 * Double(i % 3) / 2)
            let px = cx + cos(a) * d, py = cy + sin(a) * d
            c.fill(.polygon([Point(px, py), Point(px + 1.6, py + 0.5), Point(px + 0.4, py + 1.4)]), colour(paint))
        }
    }

    func safety(_ c: inout PageCanvas) -> [Panel] {
        let p = panels(&c, 6, rows: 3)
        let paint = lessonPaints[0]
        // glasses on before the first cut
        BookIcon.glasses.draw(into: &c, p[0].cx - 22, p[0].cy - 12, 22); nippers(&c, p[0].cx + 2, p[0].cy - 14, 26)
        mark(&c, p[0], ok: true)
        // cut inside a clear bag: the chips stay in it
        c.shape(.rect(p[1].cx - 18, p[1].cy - 22, 36, 40, radius: 3), fill: BookColor(hex: 0xDBE7EF, alpha: 0.5), stroke: BookColor(hex: 0x9FB6C6), width: 0.4)
        nippers(&c, p[1].cx - 12, p[1].cy - 18, 26)
        for i in 0..<6 { c.fill(.polygon([Point(p[1].cx - 12 + Double(i) * 4.5, p[1].cy + 14), Point(p[1].cx - 10 + Double(i) * 4.5, p[1].cy + 15.5), Point(p[1].cx - 11.5 + Double(i) * 4.5, p[1].cy + 16.5)]), colour(paint)) }
        mark(&c, p[1], ok: true)
        // chips fly from bare nippers
        nippers(&c, p[2].cx - 13, p[2].cy - 16, 26)
        shards(&c, p[2].cx, p[2].cy - 12, 24, paint)
        mark(&c, p[2], ok: false)
        // never sweep chips with a hand
        BookIcon.gloves.draw(into: &c, p[3].cx - 14, p[3].cy - 16, 26)
        shards(&c, p[3].cx + 6, p[3].cy + 10, 10, paint)
        mark(&c, p[3], ok: false)
        // a brush and a pan
        BookIcon.brush.draw(into: &c, p[4].cx - 14, p[4].cy - 20, 24)
        shards(&c, p[4].cx + 4, p[4].cy + 10, 10, paint)
        mark(&c, p[4], ok: true)
        // a mask while powder is poured
        BookIcon.mask.draw(into: &c, p[5].cx - 26, p[5].cy - 14, 22)
        BookIcon.thinset.draw(into: &c, p[5].cx, p[5].cy - 16, 20); BookIcon.grout.draw(into: &c, p[5].cx + 16, p[5].cy - 8, 14)
        for i in 0..<10 { c.fill(.circle(Point(p[5].cx + 6 + Double(i % 5) * 3, p[5].cy + 8 + Double(i / 5) * 3), 0.6), BookStyle.muted) }
        mark(&c, p[5], ok: true)
        return p
    }

    /// Each bag as it comes, its code on it, into a tub with the book's badge.
    func sorting(_ c: inout PageCanvas) -> [Panel] {
        let st = Array(stones.prefix(8))
        let p = panels(&c, max(1, st.count), rows: 4)
        for (i, s) in st.enumerated() {
            let q = p[i]
            // the bag
            let bx = q.cx - 28, by = q.cy - 13
            c.shape(.polygon([Point(bx, by + 3), Point(bx + 20, by + 3), Point(bx + 18.5, by + 24), Point(bx + 1.5, by + 24)]),
                    fill: BookColor(hex: 0xEEF3F7, alpha: 0.8), stroke: BookColor(hex: 0x9FB6C6), width: 0.35)
            for k in 0..<5 { smalto(&c, bx + 4.5 + Double(k % 3) * 5.5, by + 14 + Double(k / 3) * 5, 4.4, 3.6, colour(s.paint), degrees: Double(k * 17 % 30) - 15) }
            c.fill(.rect(bx + 3, by + 5, 14, 5, radius: 1), BookStyle.white)
            c.text(s.smalto?.code ?? "Au", bx + 10, by + 8.7, 3.2, 700, BookStyle.ink, .middle)
            arrow(&c, bx + 23, q.cy, bx + 31, q.cy)
            // the tub, its badge on the front
            let tx = bx + 34
            c.shape(.polygon([Point(tx, by + 7), Point(tx + 22, by + 7), Point(tx + 20.5, by + 24), Point(tx + 1.5, by + 24)]),
                    fill: BookStyle.white, stroke: BookStyle.ink, width: 0.5)
            heap(&c, s.paint, tx + 4, by + 1, 14, 9)
            badge(&c, tx + 11, by + 17.5, 3.6, s.paint, size: 3.4)
        }
        return p
    }

    func faces(_ c: inout PageCanvas, _ strings: BookStrings) -> [Panel] {
        let p = panels(&c, 6, rows: 3)
        let glass = colour(lessonPaints[0])
        // gold leaf face up, glue under
        sideStone(&c, p[0].cx - 16, p[0].cy - 4, 32, 10, BookColor(hex: 0x7A6A40), gold: true)
        c.fill(.circle(Point(p[0].cx, p[0].cy + 8), 1.6), BookColor(hex: 0xF4F1EA)); c.stroke(.circle(Point(p[0].cx, p[0].cy + 8), 1.6), BookStyle.muted, 0.2)
        c.fill(.rect(p[0].cx - 24, p[0].cy + 9.6, 48, 1.4), BookColor(hex: 0xC9C2B0))
        arrow(&c, p[0].cx + 22, p[0].cy - 18, p[0].cx + 12, p[0].cy - 6)
        mark(&c, p[0], ok: true)
        // gold face down: the leaf is glued away
        sideStone(&c, p[1].cx - 16, p[1].cy - 4, 32, 10, BookColor(hex: 0x7A6A40), gold: false)
        c.fill(.rect(p[1].cx - 24, p[1].cy + 9.6, 48, 1.4), BookColor(hex: 0xC9C2B0))
        mark(&c, p[1], ok: false)
        // a smalto at true size beside the usual piece: the piece comes out of one stone
        let piece = typicalPiece
        smalto(&c, p[2].cx - 10, p[2].cy, 10, 15, glass)
        c.shape(.polygon(piece.map { Point(p[2].cx + 14 + $0.x, p[2].cy + $0.y) }), fill: glass, stroke: BookStyle.gold, width: 0.5)
        arrow(&c, p[2].cx - 3, p[2].cy, p[2].cx + 6, p[2].cy)
        mark(&c, p[2], ok: true)
        // a piece bigger than a stone: two stones, a joint between them
        let big = largestPiece
        c.stroke(.polygon(big.map { Point(p[3].cx + $0.x, p[3].cy + $0.y) }), BookStyle.gold, 0.5)
        var lo = Point(.infinity, .infinity), hi = -lo
        for q in big { lo = pointwiseMin(lo, q); hi = pointwiseMax(hi, q) }
        let half = (hi.x - lo.x - 1) / 2
        smalto(&c, p[3].cx + lo.x + half / 2, p[3].cy + (lo.y + hi.y) / 2, half, hi.y - lo.y - 1, glass)
        smalto(&c, p[3].cx + lo.x + half * 1.5 + 1, p[3].cy + (lo.y + hi.y) / 2, half, hi.y - lo.y - 1, glass)
        mark(&c, p[3], ok: true)
        // the printer's scale: 5 cm on the page is 5 cm on the ruler
        let x0 = p[4].cx - 25, y0 = p[4].cy
        c.stroke(.line(Point(x0, y0), Point(x0 + 50, y0)), BookStyle.ink, 0.6, round: false)
        for k in 0...5 { c.stroke(.line(Point(x0 + Double(k) * 10, y0 - 2.5), Point(x0 + Double(k) * 10, y0 + 2.5)), BookStyle.ink, 0.4, round: false) }
        c.text(strings.centimetres(5), p[4].cx, y0 + 9, 3.6, 700, BookStyle.ink, .middle)
        BookIcon.ruler.draw(into: &c, p[4].cx - 12, y0 - 26, 24)
        mark(&c, p[4], ok: true)
        // a stone narrower than half a centimetre is left out: the grout fills it
        smalto(&c, p[5].cx - 12, p[5].cy, 3, 14, glass, degrees: 20)
        smalto(&c, p[5].cx + 8, p[5].cy, 10, 14, glass)
        let a = Point(p[5].cx - 20, p[5].cy - 12), b = Point(p[5].cx - 4, p[5].cy + 12)
        c.stroke(BookPath(elements: [.move(a), .line(b), .move(Point(b.x, a.y)), .line(Point(a.x, b.y))]), StoneBook.noColour, 0.8)
        mark(&c, p[5], ok: true)
        return p
    }

    /// The jaws, a stone in them.
    func jaws(_ c: inout PageCanvas, _ cx: Double, _ cy: Double, _ depth: Double, _ fill: BookColor) {
        // two wheels seen from the side, the stone between their edges
        c.shape(.circle(Point(cx, cy - 7), 6.5), fill: BookColor(hex: 0xE9E4DA), stroke: BookStyle.ink, width: 0.5)
        c.shape(.circle(Point(cx, cy + 7), 6.5), fill: BookColor(hex: 0xE9E4DA), stroke: BookStyle.ink, width: 0.5)
        sideStone(&c, cx - depth, cy - 3.5, 22, 7, fill)
        c.shape(.circle(Point(cx, cy - 7), 6.5), fill: nil, stroke: BookStyle.ink, width: 0.5)
    }

    func cutting(_ c: inout PageCanvas) -> [Panel] {
        let p = panels(&c, 6, rows: 3)
        let glass = colour(lessonPaints[0])
        // the stone's edge just into the jaws
        jaws(&c, p[0].cx - 6, p[0].cy, 3, glass); mark(&c, p[0], ok: true)
        // pushed deep in: it shatters
        jaws(&c, p[1].cx - 6, p[1].cy, 14, glass); shards(&c, p[1].cx + 10, p[1].cy - 4, 12, lessonPaints[0]); mark(&c, p[1], ok: false)
        // the wheels across the line you want: it breaks along them
        smalto(&c, p[2].cx - 14, p[2].cy, 12, 16, glass)
        c.stroke(.line(Point(p[2].cx - 14, p[2].cy - 10), Point(p[2].cx - 14, p[2].cy + 10)), BookStyle.ink, 0.4, dash: [1.2, 0.8])
        arrow(&c, p[2].cx - 4, p[2].cy, p[2].cx + 4, p[2].cy)
        smalto(&c, p[2].cx + 10, p[2].cy, 6, 16, glass); smalto(&c, p[2].cx + 18, p[2].cy, 6, 16, glass)
        // a corner: two cuts
        smalto(&c, p[3].cx - 16, p[3].cy, 12, 16, glass)
        c.stroke(BookPath(elements: [.move(Point(p[3].cx - 22, p[3].cy - 2)), .line(Point(p[3].cx - 12, p[3].cy - 8))]), BookStyle.ink, 0.4, dash: [1.2, 0.8])
        c.text("1", p[3].cx - 24, p[3].cy - 3, 3, 700)
        c.stroke(BookPath(elements: [.move(Point(p[3].cx - 22, p[3].cy + 3)), .line(Point(p[3].cx - 12, p[3].cy + 8))]), BookStyle.ink, 0.4, dash: [1.2, 0.8])
        c.text("2", p[3].cx - 24, p[3].cy + 6, 3, 700)
        arrow(&c, p[3].cx - 6, p[3].cy, p[3].cx + 2, p[3].cy)
        c.shape(.polygon([Point(p[3].cx + 6, p[3].cy - 2), Point(p[3].cx + 14, p[3].cy - 8), Point(p[3].cx + 18, p[3].cy - 8), Point(p[3].cx + 18, p[3].cy + 8),
                          Point(p[3].cx + 14, p[3].cy + 8), Point(p[3].cx + 6, p[3].cy + 3)]), fill: glass, stroke: BookColor(0, 0, 0, 0.3), width: 0.25)
        // squeeze the handles gently, close to their ends
        nippers(&c, p[4].cx - 14, p[4].cy - 18, 30)
        arrow(&c, p[4].cx - 18, p[4].cy + 10, p[4].cx - 9, p[4].cy + 8)
        arrow(&c, p[4].cx + 18, p[4].cy + 10, p[4].cx + 9, p[4].cy + 8)
        // check it on its outline in the cartoon
        let piece = typicalPiece
        c.shape(.polygon(piece.map { Point(p[5].cx + $0.x * 1.6, p[5].cy + $0.y * 1.6) }), fill: BookStyle.white, stroke: BookColor(hex: 0x9A9384), width: 0.4)
        c.shape(.polygon(piece.map { Point(p[5].cx + 1 + $0.x * 1.45, p[5].cy - 1 + $0.y * 1.45) }), fill: glass.with(alpha: 0.85), stroke: BookColor(0, 0, 0, 0.3), width: 0.25)
        mark(&c, p[5], ok: true)
        return p
    }

    func shaping(_ c: inout PageCanvas) -> [Panel] {
        let p = panels(&c, 6, rows: 3)
        let glass = colour(lessonPaints[0])
        let piece = typicalPiece.map { $0 * 1.6 }
        // a curve is nibbled: small bites, one after another
        for k in 0..<3 {
            let x = p[0].x + 16 + Double(k) * 22, y = p[0].cy
            var pts: [Point] = [Point(x - 6, y - 8), Point(x + 6, y - 8), Point(x + 6, y + 8), Point(x - 6, y + 8)]
            for j in 0..<k { pts[1].x -= 2.5; pts[2].x -= Double(j + 1) * 1.2 }
            c.shape(.polygon(pts), fill: glass, stroke: BookColor(0, 0, 0, 0.3), width: 0.25)
            c.text("\(k + 1)", x, y + 14, 3, 700, BookStyle.ink, .middle)
        }
        // too big for its outline: nip again
        c.shape(.polygon(piece.map { Point(p[1].cx + $0.x, p[1].cy + $0.y) }), fill: BookStyle.white, stroke: BookColor(hex: 0x9A9384), width: 0.4)
        c.shape(.polygon(piece.map { Point(p[1].cx + 2 + $0.x * 1.3, p[1].cy + $0.y * 1.3) }), fill: glass.with(alpha: 0.8), stroke: BookColor(0, 0, 0, 0.3), width: 0.25)
        mark(&c, p[1], ok: false)
        nippers(&c, p[1].cx + 14, p[1].cy + 2, 14)
        // too small: to the spares, cut another
        c.shape(.polygon(piece.map { Point(p[2].cx - 8 + $0.x, p[2].cy + $0.y) }), fill: BookStyle.white, stroke: BookColor(hex: 0x9A9384), width: 0.4)
        c.shape(.polygon(piece.map { Point(p[2].cx - 8 + $0.x * 0.6, p[2].cy + $0.y * 0.6) }), fill: glass.with(alpha: 0.85), stroke: BookColor(0, 0, 0, 0.3), width: 0.25)
        arrow(&c, p[2].cx + 4, p[2].cy, p[2].cx + 14, p[2].cy)
        BookIcon.bucket.draw(into: &c, p[2].cx + 15, p[2].cy - 10, 18)
        mark(&c, p[2], ok: false)
        // a millimetre between stones, as the cartoon's lines show
        let zx = p[3].cx, zy = p[3].cy
        smalto(&c, zx - 9, zy, 16, 20, glass); smalto(&c, zx + 9, zy, 16, 20, glass)
        c.stroke(.line(Point(zx - 1, zy + 13), Point(zx - 1, zy + 16)), BookStyle.ink, 0.3); c.stroke(.line(Point(zx + 1, zy + 13), Point(zx + 1, zy + 16)), BookStyle.ink, 0.3)
        c.text("1 mm", zx, zy + 20, 3, 700, BookStyle.ink, .middle)
        mark(&c, p[3], ok: true)
        // touching: no room for the grout
        smalto(&c, p[4].cx - 8, p[4].cy, 16, 20, glass); smalto(&c, p[4].cx + 8, p[4].cy, 16, 20, glass)
        mark(&c, p[4], ok: false)
        // gaps wide as a stone
        smalto(&c, p[5].cx - 13, p[5].cy, 16, 20, glass); smalto(&c, p[5].cx + 13, p[5].cy, 16, 20, glass)
        mark(&c, p[5], ok: false)
        return p
    }

    func gluing(_ c: inout PageCanvas, _ strings: BookStrings) -> [Panel] {
        let p = panels(&c, 6, rows: 3)
        let glass = colour(lessonPaints[0])
        // the mesh cut a centimetre past the sheet's edge
        let r = (p[0].cx - 22, p[0].cy - 16, 44.0, 32.0)
        c.shape(.rect(r.0 - 4, r.1 - 4, r.2 + 8, r.3 + 8), fill: BookColor(hex: 0xF7F4EE), stroke: BookColor(hex: 0xC9C2B0), width: 0.4)
        c.stroke(.rect(r.0, r.1, r.2, r.3), BookStyle.ink, 0.4, dash: [1.6, 1], round: false)
        c.text(strings.centimetres(1), p[0].cx, r.1 + r.3 + 9, 3, 700, BookStyle.ink, .middle)
        // the layers: cartoon, film, mesh, glue, stone
        let lx = p[1].cx - 26, ly = p[1].cy + 10
        c.fill(.rect(lx, ly, 52, 2.4), BookStyle.white); c.stroke(.rect(lx, ly, 52, 2.4), BookStyle.muted, 0.2)
        c.fill(.rect(lx, ly - 1.4, 52, 1.4), BookColor(hex: 0xDBE7EF, alpha: 0.9))
        c.stroke(.line(Point(lx, ly - 2.2), Point(lx + 52, ly - 2.2)), BookColor(hex: 0xA79F8C), 0.6, dash: [1.4, 0.8], round: false)
        for k in 0..<3 {
            let sx = lx + 4 + Double(k) * 16
            c.fill(.circle(Point(sx + 6, ly - 3.4), 1.2), BookColor(hex: 0xF4F1EA))
            sideStone(&c, sx, ly - 11.4, 12, 7, glass)
        }
        // a dot of glue on the stone's back
        smalto(&c, p[2].cx, p[2].cy, 18, 24, glass.mixed(toward: BookColor(0, 0, 0), 0.15))
        c.shape(.circle(Point(p[2].cx, p[2].cy), 2), fill: BookColor(hex: 0xF4F1EA), stroke: BookStyle.muted, width: 0.25)
        mark(&c, p[2], ok: true)
        // too much: it squeezes up the joint, where the grout should go
        sideStone(&c, p[3].cx - 15, p[3].cy - 6, 14, 8, glass); sideStone(&c, p[3].cx + 1, p[3].cy - 6, 14, 8, glass)
        c.fill(.rect(p[3].cx - 20, p[3].cy + 2, 40, 1.4), BookColor(hex: 0xC9C2B0))
        c.fill(.polygon([Point(p[3].cx - 1.5, p[3].cy + 2), Point(p[3].cx + 1.5, p[3].cy + 2), Point(p[3].cx + 0.8, p[3].cy - 7), Point(p[3].cx - 0.8, p[3].cy - 7)]), BookColor(hex: 0xF4F1EA))
        c.stroke(.polygon([Point(p[3].cx - 1.5, p[3].cy + 2), Point(p[3].cx + 1.5, p[3].cy + 2), Point(p[3].cx + 0.8, p[3].cy - 7), Point(p[3].cx - 0.8, p[3].cy - 7)]), BookStyle.muted, 0.2)
        mark(&c, p[3], ok: false)
        // pressed down onto the mesh, on its outline
        sideStone(&c, p[4].cx - 8, p[4].cy - 2, 16, 8, glass)
        c.fill(.rect(p[4].cx - 20, p[4].cy + 6, 40, 1.4), BookColor(hex: 0xC9C2B0))
        arrow(&c, p[4].cx, p[4].cy - 16, p[4].cx, p[4].cy - 4)
        // wiped before it dries
        BookIcon.cloth.draw(into: &c, p[5].cx - 12, p[5].cy - 14, 24)
        BookIcon.clock.draw(into: &c, p[5].cx - 14, p[5].cy + 12, 10)
        c.text(strings.minutes(10), p[5].cx - 2, p[5].cy + 19, 3.2, 700)
        return p
    }

    /// How to read a step: the parts, where they go, which sheet.
    func reading(_ c: inout PageCanvas) -> [Panel] {
        let p = panels(&c, 6, rows: 3)
        guard let n = steps.indices.first(where: { steps[$0].section == sampleSection && steps[$0].pieces.count >= 3 }) else { return p }
        let step = steps[n], first = pieces[step.pieces[0]]
        // a badge is a tub: pick up from that one
        badge(&c, p[0].cx - 16, p[0].cy, 5, first.paint, size: 4.6)
        arrow(&c, p[0].cx - 9, p[0].cy, p[0].cx + 2, p[0].cy)
        c.shape(.polygon([Point(p[0].cx + 5, p[0].cy - 10), Point(p[0].cx + 29, p[0].cy - 10), Point(p[0].cx + 27, p[0].cy + 10), Point(p[0].cx + 7, p[0].cy + 10)]),
                fill: BookStyle.white, stroke: BookStyle.ink, width: 0.5)
        heap(&c, first.paint, p[0].cx + 9, p[0].cy - 8, 16, 10); badge(&c, p[0].cx + 17, p[0].cy + 5, 3, first.paint, size: 2.8)
        // a shape in the box, at true size, goes where the gold outline is
        let shape = first.corners.map { ($0 - first.centre) * mm }
        c.shape(.polygon(shape.map { Point(p[1].cx - 16 + $0.x, p[1].cy + $0.y) }), fill: colour(first.paint), stroke: BookColor(0, 0, 0, 0.2), width: 0.15)
        c.shape(.polygon(shape.map { Point(p[1].cx + 16 + $0.x, p[1].cy + $0.y) }), fill: colour(first.paint), stroke: BookStyle.gold, width: 0.6)
        c.stroke(.line(Point(p[1].cx - 8, p[1].cy), Point(p[1].cx + 8, p[1].cy)), BookStyle.muted, 0.4, dash: [1, 1])
        // gold: this step; coloured: set already; white: still to come
        let f = frame(sampleSection)
        let crop = ((f.loX + f.hiX) / 2 - f.spanW / 4, (f.loY + f.hiY) / 2 - f.spanH / 4, f.spanW / 2, f.spanH / 2)
        let lo = bounds(step.pieces).lo, hi = bounds(step.pieces).hi
        let ccrop = (min(max((lo.x + hi.x) / 2 - crop.2 / 2, f.loX), f.hiX - crop.2), min(max((lo.y + hi.y) / 2 - crop.3 / 2, f.loY), f.hiY - crop.3), crop.2, crop.3)
        let mw2 = (p[2].w - 16) / StoneBook.lessonZoom, mh2 = (p[2].h - 22) / StoneBook.lessonZoom
        drawMosaic(&c, p[2].cx - mw2 / 2, p[2].cy - mh2 / 2, mw2, mh2, style: { q in
            if q.step == n { return (self.colour(q.paint), BookStyle.gold, 0.55) }
            if q.section == self.sampleSection && q.step < n { return (self.colour(q.paint), nil, 0) }
            if q.section == self.sampleSection { return (BookStyle.white, BookColor(hex: 0xCFC8B9), 0.18) }
            return nil
        }, crop: ccrop, grout: false)
        // the number by the steps counts within the sheet; the circle is the sheet
        c.text("1", p[3].cx - 18, p[3].cy + 6, 15, 800, BookStyle.ink, face: .display)
        c.shape(.circle(Point(p[3].cx + 10, p[3].cy), 6), fill: BookStyle.paper, stroke: BookStyle.ink, width: 0.6)
        c.text("\(sampleSection + 1)", p[3].cx + 10, p[3].cy + 2.2, 6, 700, BookStyle.ink, .middle)
        // the corner map: the sheet you are on, the dot where the step is
        let mw = 34.0
        minimap(&c, p[4].cx - mw / 2, p[4].cy - mw * height / width / 2, mw, current: sampleSection, dot: Point((lo.x + hi.x) / 2, (lo.y + hi.y) / 2), doneBefore: sampleSection)
        // a circle at the cartoon's edge is the next sheet: its first page
        c.stroke(.rect(p[5].cx - 28, p[5].cy - 14, 30, 28), BookStyle.muted, 0.4, dash: [1.6, 1], round: false)
        c.shape(.circle(Point(p[5].cx + 10, p[5].cy), 4.4), fill: BookStyle.paper, stroke: BookStyle.ink, width: 0.5)
        c.text("\(min(sampleSection + 2, sections.count))", p[5].cx + 10, p[5].cy + 1.6, 4.4, 700, BookStyle.ink, .middle)
        arrow(&c, p[5].cx + 16, p[5].cy, p[5].cx + 26, p[5].cy)
        BookIcon.pages.draw(into: &c, p[5].cx + 27, p[5].cy - 8, 16)
        return p
    }

    func mending(_ c: inout PageCanvas, _ strings: BookStrings) -> [Panel] {
        let p = panels(&c, 4, rows: 2)
        let glass = colour(lessonPaints[0])
        // a stone in the wrong place: a blade under it, lift it off the mesh
        c.fill(.rect(p[0].cx - 30, p[0].cy + 8, 60, 1.6), BookColor(hex: 0xC9C2B0))
        sideStone(&c, p[0].cx - 4, p[0].cy - 4, 18, 9, glass)
        BookIcon.knife.draw(into: &c, p[0].cx - 32, p[0].cy - 10, 28)
        arrow(&c, p[0].cx + 5, p[0].cy - 10, p[0].cx + 5, p[0].cy - 26)
        // a broken one to the spares
        smalto(&c, p[1].cx - 22, p[1].cy - 3, 8, 14, glass, degrees: 12); smalto(&c, p[1].cx - 13, p[1].cy + 3, 7, 12, glass, degrees: -20)
        arrow(&c, p[1].cx - 4, p[1].cy, p[1].cx + 8, p[1].cy)
        BookIcon.bucket.draw(into: &c, p[1].cx + 10, p[1].cy - 14, 26)
        // a new one cut, a fresh dot of glue
        smalto(&c, p[2].cx - 6, p[2].cy, 18, 24, glass.mixed(toward: BookColor(0, 0, 0), 0.15))
        c.shape(.circle(Point(p[2].cx - 6, p[2].cy), 2), fill: BookColor(hex: 0xF4F1EA), stroke: BookStyle.muted, width: 0.25)
        BookIcon.glue.draw(into: &c, p[2].cx + 10, p[2].cy - 14, 24)
        // back on its outline, the day's wait again
        BookIcon.clock.draw(into: &c, p[3].cx - 12, p[3].cy - 18, 24)
        c.text(strings.hours(24), p[3].cx, p[3].cy + 16, 4.4, 700, BookStyle.ink, .middle)
        return p
    }

    // MARK: The board

    func bed(_ c: inout PageCanvas, _ strings: BookStrings) -> [Panel] {
        let p = panels(&c, 6, rows: 3)
        let bed = BookColor(hex: 0xCFCAC0)
        // the board wiped clean and damp
        c.shape(.rect(p[0].cx - 28, p[0].cy - 12, 56, 26, radius: 1), fill: BookColor(hex: 0xECE6DA), stroke: BookStyle.ink, width: 0.4)
        BookIcon.sponge.draw(into: &c, p[0].cx - 4, p[0].cy - 18, 20)
        // three of powder to one of water, by the cup
        for k in 0..<3 { BookIcon.thinset.draw(into: &c, p[1].x + 10 + Double(k) * 13, p[1].cy - 10, 14) }
        c.text("+", p[1].x + 52, p[1].cy, 6, 700)
        BookIcon.bucket.draw(into: &c, p[1].x + 58, p[1].cy - 10, 14)
        c.text("3 : 1", p[1].cx, p[1].cy + 16, 4.4, 700, BookStyle.ink, .middle)
        // stirred, left, stirred again
        BookIcon.bucket.draw(into: &c, p[2].cx - 28, p[2].cy - 12, 22)
        BookIcon.clock.draw(into: &c, p[2].cx, p[2].cy - 12, 18)
        c.text(strings.minutes(10), p[2].cx + 9, p[2].cy + 14, 4, 700, BookStyle.ink, .middle)
        // as thick as peanut butter: a ridge stands
        c.fill(.rect(p[3].cx - 26, p[3].cy + 6, 52, 2), BookColor(hex: 0xECE6DA))
        for k in 0..<5 { c.fill(.polygon([Point(p[3].cx - 24 + Double(k) * 10, p[3].cy + 6), Point(p[3].cx - 19 + Double(k) * 10, p[3].cy - 4), Point(p[3].cx - 14 + Double(k) * 10, p[3].cy + 6)]), bed) }
        mark(&c, p[3], ok: true)
        // runny: it slumps flat
        c.fill(.rect(p[4].cx - 26, p[4].cy + 6, 52, 2), BookColor(hex: 0xECE6DA))
        c.fill(.polygon([Point(p[4].cx - 26, p[4].cy + 6), Point(p[4].cx - 26, p[4].cy + 3.5), Point(p[4].cx + 26, p[4].cy + 3), Point(p[4].cx + 26, p[4].cy + 6)]), bed)
        mark(&c, p[4], ok: false)
        // combed with the notched edge, one sheet's room at a time
        let bx = p[5].cx - 28, by = p[5].cy - 14
        c.shape(.rect(bx, by, 56, 30, radius: 1), fill: BookColor(hex: 0xECE6DA), stroke: BookStyle.ink, width: 0.4)
        c.clip(.rect(bx + 2, by + 2, 26, 26))
        c.fill(.rect(bx + 2, by + 2, 26, 26), bed)
        for k in 0..<12 { c.stroke(.line(Point(bx + Double(k) * 4 - 24, by + 30), Point(bx + Double(k) * 4 + 6, by)), BookColor(hex: 0xA9A397), 0.7, round: false) }
        c.endClip()
        BookIcon.trowel.draw(into: &c, bx + 30, by + 4, 22)
        return p
    }

    func pressing(_ c: inout PageCanvas, _ strings: BookStrings) -> [Panel] {
        let p = panels(&c, 6, rows: 3)
        let glass = colour(lessonPaints[0]), bed = BookColor(hex: 0xCFCAC0)
        func layers(_ q: Panel, meshDown: Bool) {
            c.fill(.rect(q.cx - 28, q.cy + 6, 56, 4), BookColor(hex: 0xD8CBA8))
            c.fill(.rect(q.cx - 28, q.cy + 3, 56, 3), bed)
            for k in 0..<4 {
                let sx = q.cx - 26 + Double(k) * 13.5
                sideStone(&c, sx, meshDown ? q.cy - 5 : q.cy - 3.8, 12, 7, glass)
            }
            c.stroke(.line(Point(q.cx - 28, meshDown ? q.cy + 2.6 : q.cy - 5.4), Point(q.cx + 28, meshDown ? q.cy + 2.6 : q.cy - 5.4)),
                     BookColor(hex: 0xA79F8C), 0.6, dash: [1.4, 0.8], round: false)
        }
        // mesh down into the bed, stones up
        layers(p[0], meshDown: true); mark(&c, p[0], ok: true)
        // never upside down
        layers(p[1], meshDown: false); mark(&c, p[1], ok: false)
        // pressed in with the float, over the whole sheet
        layers(p[2], meshDown: true)
        BookIcon.float.draw(into: &c, p[2].cx - 10, p[2].cy - 24, 20)
        arrow(&c, p[2].cx + 16, p[2].cy - 20, p[2].cx + 16, p[2].cy - 8)
        // the next sheet a joint away from the last, its edge on the line
        smalto(&c, p[3].cx - 15, p[3].cy, 28, 30, glass.mixed(toward: BookStyle.paper, 0.2))
        smalto(&c, p[3].cx + 15, p[3].cy, 28, 30, glass)
        c.text("1 mm", p[3].cx, p[3].cy + 22, 3, 700, BookStyle.ink, .middle)
        mark(&c, p[3], ok: true)
        // bed pushed up a joint: picked out before it sets
        sideStone(&c, p[4].cx - 15, p[4].cy - 6, 14, 8, glass); sideStone(&c, p[4].cx + 1, p[4].cy - 6, 14, 8, glass)
        c.fill(.rect(p[4].cx - 20, p[4].cy + 2, 40, 3), bed)
        c.fill(.rect(p[4].cx - 0.9, p[4].cy - 6, 1.8, 8), bed)
        BookIcon.knife.draw(into: &c, p[4].cx + 2, p[4].cy - 26, 18)
        BookIcon.clock.draw(into: &c, p[4].cx - 14, p[4].cy + 12, 10)
        c.text(strings.minutes(30), p[4].cx - 2, p[4].cy + 19, 3.2, 700)
        // checked flat
        BookIcon.level.draw(into: &c, p[5].cx - 16, p[5].cy - 16, 32)
        return p
    }

    func grouting(_ c: inout PageCanvas, _ strings: BookStrings) -> [Panel] {
        let p = panels(&c, 6, rows: 3)
        let glass = colour(lessonPaints[0]), g = BookColor(grout)
        // stirred to toothpaste: a blob holds on the trowel
        BookIcon.trowel.draw(into: &c, p[0].cx - 14, p[0].cy - 10, 28)
        c.fill(.circle(Point(p[0].cx, p[0].cy - 6), 5), g)
        mark(&c, p[0], ok: true)
        // pushed into the joints diagonally, the float at a slant
        for k in 0..<3 { for j in 0..<2 { smalto(&c, p[1].cx - 18 + Double(k) * 13, p[1].cy - 6 + Double(j) * 13, 12, 12, glass) } }
        c.fill(.polygon([Point(p[1].cx - 25, p[1].cy - 13), Point(p[1].cx - 5, p[1].cy - 13), Point(p[1].cx - 25, p[1].cy + 8)]), g.with(alpha: 0.85))
        arrow(&c, p[1].cx - 20, p[1].cy + 12, p[1].cx + 6, p[1].cy - 14)
        // the sponge wrung nearly dry
        BookIcon.sponge.draw(into: &c, p[2].cx - 12, p[2].cy - 14, 24); mark(&c, p[2], ok: true)
        // dripping: it washes the grout out
        BookIcon.sponge.draw(into: &c, p[3].cx - 12, p[3].cy - 18, 24)
        for k in 0..<4 { c.fill(.circle(Point(p[3].cx - 6 + Double(k) * 4, p[3].cy + 8 + Double(k % 2) * 3), 1), BookColor(hex: 0x9FB6C6)) }
        mark(&c, p[3], ok: false)
        // a film dries on the stones: buffed off with a dry cloth
        for k in 0..<3 { smalto(&c, p[4].cx - 26 + Double(k) * 13, p[4].cy, 12, 12, glass.mixed(toward: g, 0.45)) }
        arrow(&c, p[4].cx + 14, p[4].cy, p[4].cx + 20, p[4].cy)
        BookIcon.cloth.draw(into: &c, p[4].cx + 20, p[4].cy - 10, 18)
        BookIcon.clock.draw(into: &c, p[4].cx - 14, p[4].cy + 12, 10)
        c.text(strings.hours(1), p[4].cx - 2, p[4].cy + 19, 3.2, 700)
        // three days before it is lifted
        BookIcon.clock.draw(into: &c, p[5].cx - 12, p[5].cy - 18, 24)
        c.text(strings.hours(72), p[5].cx, p[5].cy + 16, 4.4, 700, BookStyle.ink, .middle)
        return p
    }

    // MARK: On the wall

    func hanging(_ c: inout PageCanvas, _ strings: BookStrings) -> [Panel] {
        let p = panels(&c, 6, rows: 3)
        // heavy: two people lift it
        BookIcon.person.draw(into: &c, p[0].cx - 30, p[0].cy - 16, 28); BookIcon.person.draw(into: &c, p[0].cx + 2, p[0].cy - 16, 28)
        c.text(strings.kilograms(hangingKilograms), p[0].cx, p[0].cy + 20, 4.4, 700, BookStyle.ink, .middle)
        // a cleat: one strip on the board's back, one on the wall, hooked
        let x = p[1].cx, y = p[1].cy
        c.shape(.rect(x - 4, y - 22, 4, 44), fill: BookColor(hex: 0xD8CBA8), stroke: BookStyle.ink, width: 0.4)       // the wall
        c.shape(.polygon([Point(x, y - 12), Point(x + 6, y - 12), Point(x + 6, y - 2), Point(x, y + 4)]), fill: BookColor(hex: 0xECE6DA), stroke: BookStyle.ink, width: 0.4)
        c.shape(.rect(x + 14, y - 22, 4, 44), fill: BookColor(hex: 0xECE6DA), stroke: BookStyle.ink, width: 0.4)     // the board
        c.shape(.polygon([Point(x + 14, y - 16), Point(x + 8, y - 10), Point(x + 8, y - 4), Point(x + 14, y - 4)]), fill: BookColor(hex: 0xECE6DA), stroke: BookStyle.ink, width: 0.4)
        // into a stud, not the plaster alone
        c.shape(.rect(p[2].cx - 26, p[2].cy - 18, 52, 36), fill: BookColor(hex: 0xF4F1EA), stroke: BookStyle.ink, width: 0.4)
        c.shape(.rect(p[2].cx - 6, p[2].cy - 18, 12, 36), fill: BookColor(hex: 0xD8CBA8), stroke: nil)
        BookIcon.screw.draw(into: &c, p[2].cx - 8, p[2].cy - 12, 16)
        mark(&c, p[2], ok: true)
        // level
        BookIcon.level.draw(into: &c, p[3].cx - 16, p[3].cy - 16, 32)
        // up together
        let w = 30.0, h = w * height / width
        drawMosaic(&c, p[4].cx - w / 2, p[4].cy - h / 2, w, h)
        arrow(&c, p[4].cx + w / 2 + 4, p[4].cy + 8, p[4].cx + w / 2 + 4, p[4].cy - 8)
        // on the wall
        let k = StoneBook.lessonZoom
        c.fill(.rect(p[5].cx - (p[5].w - 8) / 2 / k, p[5].cy - (p[5].h - 22) / 2 / k, (p[5].w - 8) / k, (p[5].h - 22) / k), BookColor(hex: 0xF1EDE4))
        let hh = (p[5].h - 34) / k, ww = hh * width / height
        drawMosaic(&c, p[5].cx - ww / 2, p[5].cy - hh / 2, ww, hh)
        return p
    }
}
