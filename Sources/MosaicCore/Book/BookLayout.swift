/// The stone book's page geometry, in millimetres on A4.
enum BookLayout {
    static let pageWidth = 210.0, pageHeight = 297.0
    static let margin = 12.0
    /// The parts box's room: up to three rows of pieces at true size.
    static let partsHeight = 42.0
    /// A section's sheet fits an A4 page at 1:1 with room for its rulers.
    static let sectionMaxWidth = 186.0, sectionMaxHeight = 262.0
    static let stepsPerPage = 2
    /// A step's block: half the page's room less the gap between the two.
    static let stepHeight = (pageHeight - 2 * margin) / Double(stepsPerPage) - 6
    /// The step view below the parts box: the frame every step of a section is drawn through.
    static let viewWidth = pageWidth - 2 * margin
    static let viewHeight = stepHeight - partsHeight - 6
    static let partsX = margin + 26
    static let partsWidth = pageWidth - margin - partsX

    enum Placed {
        case badge(paint: Int, at: SIMD2<Double>)
        /// The step's `index`th piece as it sits in the picture, its corners in millimetres on the page.
        case piece(index: Int, corners: [SIMD2<Double>])
    }

    /// Where each of a step's pieces sits in its parts box, true size and turned as
    /// they sit in the picture, grouped by paint (the most used first), each group led by its paint's
    /// badge; and the box's height.
    static func parts(_ pieces: [StoneBook.Piece], mm: Double, x bx: Double, y y0: Double, width bw: Double) -> (placed: [Placed], height: Double) {
        var order: [Int] = [], groups: [Int: [Int]] = [:]
        for (i, p) in pieces.enumerated() {
            if groups[p.paint] == nil { order.append(p.paint) }
            groups[p.paint, default: []].append(i)
        }
        // most pieces first; equal counts keep their first appearance
        let paints = order.enumerated().sorted { a, b in
            let ca = groups[a.element]!.count, cb = groups[b.element]!.count
            return ca != cb ? ca > cb : a.offset < b.offset
        }.map(\.element)
        var gx = bx + 3, gy = y0 + 3, rowH = 0.0
        var placed: [Placed] = []
        for paint in paints {
            if gx + 5 + 14 > bx + bw - 3 { gx = bx + 3; gy += rowH + 2.5; rowH = 0 }
            placed.append(.badge(paint: paint, at: SIMD2(gx + 2.4, gy + 2.4)))
            gx += 6.5
            for i in groups[paint]! {
                // turned as it sits in the picture, so a newcomer matches it to its outline at a glance
                var lo = SIMD2<Double>(.infinity, .infinity)
                for c in pieces[i].corners { lo = pointwiseMin(lo, c) }
                let shape = pieces[i].corners.map { ($0 - lo) * mm }
                var hi = SIMD2<Double>(0, 0)
                for c in shape { hi = pointwiseMax(hi, c) }
                let w = hi.x, h = hi.y
                if gx + w > bx + bw - 3 { gx = bx + 3 + 6.5; gy += rowH + 2.5; rowH = 0 }
                let at = SIMD2(gx, gy)
                placed.append(.piece(index: i, corners: shape.map { $0 + at }))
                gx += w + 1.8
                rowH = max(rowH, h)
            }
            gx += 4
        }
        return (placed, gy + rowH + 3 - y0)
    }

    static func partsFit(_ pieces: [StoneBook.Piece], mm: Double) -> Bool {
        parts(pieces, mm: mm, x: partsX, y: 0, width: partsWidth).height <= partsHeight
    }
}
