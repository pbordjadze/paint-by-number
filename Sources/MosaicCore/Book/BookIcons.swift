/// The book's pictograms, drawn so every page but the stone list stays wordless: each on a 24-unit
/// square, outlined in the book's ink.
enum BookIcon: String, CaseIterable {
    case nippers, mesh, glue, film, tape, board, trowel, float, sponge, bucket, thinset, grout, glasses
    case gloves, clock, cloth, ruler, tiles, pages

    private enum Part {
        /// An SVG path's data, its fill (nil: none) and stroke width (nil: the icon's).
        case path(String, fill: UInt32?, width: Double? = nil)
        case circle(Double, Double, Double, fill: UInt32?)
        case rect(Double, Double, Double, Double, radius: Double, fill: UInt32?, width: Double? = nil)
    }

    private var parts: [Part] {
        switch self {
        case .nippers:
            [.circle(9, 4.6, 3.2, fill: 0xE9E4DA), .circle(15, 4.6, 3.2, fill: 0xE9E4DA),
             .path("M9 4.6 L10.6 11 M15 4.6 L13.4 11", fill: nil, width: 0.8), .path("M10.6 11 L12 13 L13.4 11", fill: nil),
             .path("M12 13 Q8 17 6.5 22.5 M12 13 Q16 17 17.5 22.5", fill: nil, width: 2.2), .circle(12, 13, 0.9, fill: 0x1F2A52)]
        case .mesh:
            [.rect(3, 3, 18, 18, radius: 1, fill: nil)]
                + (1...4).map { i in .path("M\(3 + Double(i) * 3.6) 3 V21 M3 \(3 + Double(i) * 3.6) H21", fill: nil, width: 0.6) }
        case .glue:
            [.path("M8 9 H16 V21 Q16 22 15 22 H9 Q8 22 8 21 Z", fill: 0xFFFFFF), .path("M10 9 L11 4 H13 L14 9", fill: nil),
             .path("M12 4 V2", fill: nil)]
        case .film:
            [.path("M4 5 H18 L20 7 V20 H4 Z", fill: 0xEEF3F7), .path("M7 9 L11 13 M7 13 L9 15", fill: nil, width: 0.8)]
        case .tape:
            [.circle(11, 12, 7, fill: 0xF3EAD2), .circle(11, 12, 3, fill: nil), .path("M17.5 14 L22 15 L21.5 18 L16 17", fill: nil)]
        case .board:
            [.path("M3 8 L13 4 L21 8 L11 12 Z", fill: 0xECE6DA), .path("M3 8 V11 L11 15 L21 11 V8 M11 12 V15", fill: nil)]
        case .trowel:
            [.path("M4 15 H20 L20 18 L18.5 16.6 L17 18 L15.5 16.6 L14 18 L12.5 16.6 L11 18 L9.5 16.6 L8 18 L6.5 16.6 L5 18 L4 17 Z", fill: 0xE9E4DA),
             .path("M12 15 V10 M9 10 H15 Q16 10 16 8 V6", fill: nil)]
        case .float:
            [.rect(3, 13, 18, 6, radius: 1.5, fill: 0xE3DDD0), .path("M8 13 V9 Q8 7 10 7 H14 Q16 7 16 9 V13", fill: nil)]
        case .sponge:
            [.path("M4 9 Q4 6 7 6 H17 Q20 6 20 9 V16 Q20 19 17 19 H7 Q4 19 4 16 Z", fill: 0xF2DC8F),
             .circle(9, 11, 0.9, fill: nil), .circle(14, 14, 0.9, fill: nil), .circle(15.5, 10, 0.7, fill: nil)]
        case .bucket:
            [.path("M5 8 H19 L17 21 H7 Z", fill: 0xFFFFFF), .path("M5 8 Q12 1 19 8", fill: nil)]
        case .thinset:
            [.path("M5 6 H19 L18 21 H6 Z", fill: 0xCFCAC0), .path("M5 6 L8 3 H16 L19 6 M8 11 H16", fill: nil, width: 0.9)]
        case .grout:
            [.path("M6 6 H18 L17 21 H7 Z", fill: 0xD6CEC7), .path("M6 10 H18", fill: nil)]
        case .glasses:
            [.circle(7, 13, 4, fill: 0xEEF3F7), .circle(17, 13, 4, fill: 0xEEF3F7),
             .path("M11 13 Q12 11.5 13 13 M3 13 L1.5 9 M21 13 L22.5 9", fill: nil)]
        case .gloves:
            [.path("M7 22 V12 L5 8 Q4.6 6.4 6 6.6 L8 10 V4.5 Q8 3.4 9.2 3.4 Q10.4 3.4 10.4 4.5 V10 V3.6 Q10.4 2.5 11.6 2.5 Q12.8 2.5 12.8 3.6 V10 V4.4 Q12.8 3.3 14 3.3 Q15.2 3.3 15.2 4.4 V11 V6.4 Q15.2 5.4 16.3 5.4 Q17.4 5.4 17.4 6.4 V15 Q17.4 19 15 22 Z", fill: 0xCFE0D4)]
        case .clock:
            [.circle(12, 12, 9, fill: 0xFFFFFF), .path("M12 6 V12 L16 14", fill: nil)]
        case .cloth:
            [.path("M4 7 Q9 4 13 7 T21 7 V18 Q16 15 12 18 T4 18 Z", fill: 0xF4F1EA)]
        case .ruler:
            [.rect(2, 8, 20, 8, radius: 1, fill: 0xF3EAD2)]
                + (0..<7).map { i in .path("M\(4 + Double(i) * 2.6) 8 V\(i % 2 == 1 ? 11 : 12.5)", fill: nil, width: 0.7) }
        case .tiles:
            [0xC9A24A, 0x8C3B2F, 0x2C4A6B, 0xB9A98A, 0xC9A24A, 0x5D6E4A, 0x2C4A6B, 0xD8C9A6, 0x8C3B2F].enumerated().map { i, c in
                .rect(3 + Double(i % 3) * 6.3, 3 + Double(i / 3) * 6.3, 5.3, 5.3, radius: 0.6, fill: UInt32(c), width: 0.7)
            }
        case .pages:
            [.path("M6 3 H16 L19 6 V21 H6 Z", fill: 0xFFFFFF), .path("M9 9 H16 M9 12 H16 M9 15 H14", fill: nil, width: 0.8)]
        }
    }

    /// Draws the pictogram in a box `s` mm square at (x, y).
    func draw(into c: inout PageCanvas, _ x: Double, _ y: Double, _ s: Double) {
        let k = s / 24
        func f(_ p: SIMD2<Double>) -> SIMD2<Double> { SIMD2(x + p.x * k, y + p.y * k) }
        for part in parts {
            let path: BookPath, fill: UInt32?, width: Double?
            switch part {
            case .path(let d, let fl, let w): path = BookPath.svg(d); fill = fl; width = w
            case .circle(let cx, let cy, let r, let fl): path = BookPath.circle(SIMD2(cx, cy), r); fill = fl; width = nil
            case .rect(let rx, let ry, let rw, let rh, let r, let fl, let w): path = BookPath.rect(rx, ry, rw, rh, radius: r); fill = fl; width = w
            }
            c.page.items.append(.shape(path.mapped(f), fill: fill.map { BookColor(hex: $0) },
                                       stroke: BookStroke(color: BookStyle.ink, width: (width ?? 1.3) * k)))
        }
    }
}
