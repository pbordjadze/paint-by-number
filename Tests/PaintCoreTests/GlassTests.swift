import Foundation
import Testing
@testable import PaintCore

/// Stained Glass (painting-company row 366): a window leaded by the painter's lines over a photo
/// (`GlassWindow`), the glasses it suggests (`GlassPalette`) and free glazing's file (`Glazing`).
/// The photo is 240 × 180: its left half a smooth sage, out of focus; its right half a sharp
/// orange and dark-red checker, the subject.
@Suite("Stained Glass")
struct GlassTests {
    static let width = 240, height = 180
    static let sage = SIMD4<UInt8>(120, 140, 110, 255)
    static let orange = SIMD4<UInt8>(240, 120, 20, 255), wine = SIMD4<UInt8>(120, 20, 30, 255)

    static func photo() -> RGBAImage {
        var p = RGBAImage(width: width, height: height, fill: sage)
        for y in 0..<height { for x in width / 2..<width { p[x, y] = (x / 3 + y / 3) % 2 == 0 ? orange : wine } }
        return p
    }

    /// One line down the middle and one across the right half: three pieces.
    static let lines: [[SIMD2<Float>]] = [
        [SIMD2(120, 0), SIMD2(120, 60), SIMD2(120, 120), SIMD2(120, 180)],
        [SIMD2(120, 90), SIMD2(180, 90), SIMD2(240, 90)],
    ]

    static func window(_ lines: [[SIMD2<Float>]] = lines, joining: Float? = nil) throws -> GlassWindow.Leaded {
        try GlassWindow.leaded(photo: photo(), width: width, height: height, colorSpace: .sRGB, lines: lines, joining: joining)
    }

    static func region(at x: Int, _ y: Int, in t: Template) -> Int { Int(t.regionMap[x, y]) }

    @Test func linesLeadAValidWindow() throws {
        let w = try Self.window()
        expectValid(w.template)
        #expect(w.template.regions.count == 3)
        #expect(w.verdicts.count == 2)
        #expect(w.suggestion.ofRegion.count == 3 && w.suggestion.isBackground.count == 3)
        #expect(w.template.palette.count == w.suggestion.glasses.count)
        for r in w.template.regions.indices {
            #expect(Int(w.template.regions[r].colorIndex) == w.suggestion.ofRegion[r])
        }
        // Geometry is the lines' alone: the right half's two pieces are split at y = 90.
        let top = Self.region(at: 200, 40, in: w.template), bottom = Self.region(at: 200, 140, in: w.template)
        let left = Self.region(at: 40, 90, in: w.template)
        #expect(Set([top, bottom, left]).count == 3)
    }

    @Test func theSameLinesGiveTheSameWindow() throws {
        let a = try Self.window(), b = try Self.window()
        #expect(a.template.encoded() == b.template.encoded())
        #expect(a.suggestion == b.suggestion)
    }

    /// The smooth half is background (deep, quiet glass); the sharp checker is the subject, and
    /// its glass is brighter and richer than the photo's mean there.
    @Test func backgroundIsFoundByFocus() throws {
        let w = try Self.window()
        let t = w.template, s = w.suggestion
        let left = Self.region(at: 40, 90, in: t), right = Self.region(at: 200, 40, in: t)
        #expect(s.isBackground[left])
        #expect(!s.isBackground[right])
        let back = s.glasses[s.ofRegion[left]], subject = s.glasses[s.ofRegion[right]]
        let chroma = { (c: SIMD3<Float>) in (c.y * c.y + c.z * c.z).squareRoot() }
        #expect(back.x <= 0.54, "background glass is deep")
        #expect(chroma(back) >= 0.06, "and still colored glass, never khaki")
        #expect(subject.x >= 0.5, "subject glass is bright")
        #expect(chroma(subject) > chroma(back))
        // Weighed by chroma, the checker reads orange-red, never the mud of its mean.
        #expect(subject.y > 0.05, "a warm glass")
        #expect(back.y < 0 || chroma(back) < 0.06, "the sage stays green and quiet")
    }

    /// Every glass a window suggests, lit, stays well clear of unlit glass's dark: a black photo
    /// and a khaki one still give glass that reads glazed.
    @Test func everyGlassIsClearOfUnlitGlass() {
        let unlit = ColorScience.encodedToOKLab(GlassTexture.unlitBase, space: .sRGB).x
        for c in [SIMD3<Float>(0.08, 0, 0), SIMD3(0.45, -0.005, 0.03), SIMD3(0.6, 0.002, 0.001), SIMD3(0.98, 0, 0)] {
            for background in [false, true] {
                let g = GlassPalette.glass(c, background: background)
                #expect(g.x >= unlit + 0.15, "glass from \(c) is too dark: \(g)")
                #expect(g.x <= 0.84, "glass from \(c) blows out lit: \(g)")
            }
        }
    }

    /// A raw line stopping short of the frame is joined to it, and closes a piece.
    @Test func endsShortOfTheLeadAreJoined() throws {
        let short: [[SIMD2<Float>]] = [[SIMD2(120, 4), SIMD2(120, 90), SIMD2(120, 176)]]
        let open = try Self.window(short)
        let joined = try Self.window(short, joining: 8)
        expectValid(joined.template)
        #expect(open.template.regions.count == 1)
        #expect(joined.template.regions.count == 2)
    }

    /// Leading a line at a time is the window `leaded` makes, and each line says which pieces
    /// it closed: none for the first, which closes the left half and the right.
    @Test func leadingALineAtATimeSaysWhatItClosed() throws {
        var leading = try GlassWindow.Leading(photo: Self.photo(), width: Self.width, height: Self.height, colorSpace: .sRGB)
        let first = leading.add(Self.lines[0])
        #expect(first.verdict.isMade && Set(first.closed).count == 2)
        let whisker = leading.add([SIMD2(30, 30), SIMD2(60, 50)])
        #expect(whisker.verdict.isMade && whisker.closed.isEmpty, "a line closing nothing stays as lead")
        let second = leading.add(Self.lines[1])
        #expect(second.closed.count == 2, "the right half, cut in two")
        #expect(leading.lines.count == 3)
        let all = try GlassWindow.leaded(
            photo: Self.photo(), width: Self.width, height: Self.height, colorSpace: .sRGB,
            lines: [Self.lines[0], [SIMD2(30, 30), SIMD2(60, 50)], Self.lines[1]])
        #expect(leading.window().template.encoded() == all.template.encoded())
    }

    /// The lead a photo suggests goes round what stands out in it, and is the ground the painter
    /// starts from: nothing to undo, and the window is valid.
    @Test func theSuggestedLeadGoesRoundTheSubject() throws {
        var photo = RGBAImage(width: Self.width, height: Self.height, fill: Self.sage)
        for y in 0..<Self.height {
            for x in 0..<Self.width where hypot(Float(x - 160), Float(y - 90)) < 50 { photo[x, y] = Self.orange }
        }
        let leading = try GlassWindow.Leading.suggested(photo: photo, width: Self.width, height: Self.height, colorSpace: .sRGB)
        let t = leading.template
        expectValid(t)
        #expect(t.regions.count >= 2)
        #expect(!leading.canUndo && leading.lines.isEmpty)
        #expect(Self.region(at: 160, 90, in: t) != Self.region(at: 30, 90, in: t), "the disc is a piece of its own")
        // Lead runs round the disc's edge; the broad sage and the disc are cut into panes besides.
        let round = leading.lead.joined().filter { abs(hypot($0.x - 160, $0.y - 90) - 50) < 8 }
        #expect(round.count >= 20)
        #expect(t.regions.count > 2, "broad glass is cut into panes")
    }

    /// A piece too narrow for heavy lead joins the neighbour it shares the most lead with; wide
    /// pieces stay apart.
    @Test func aNarrowPieceJoinsItsNeighbour() throws {
        var leading = try GlassWindow.Leading(photo: Self.photo(), width: Self.width, height: Self.height, colorSpace: .sRGB)
        leading.add([SIMD2(0, 90), SIMD2(240, 90)])
        leading.add([SIMD2(0, 95), SIMD2(240, 95)])
        leading.add([SIMD2(120, 0), SIMD2(120, 90)])
        let t = leading.template
        #expect(t.regions.count == 4)
        let pieces = GlassLeadSuggestion.pieces(of: t, narrowest: 6)
        let strip = Self.region(at: 60, 92, in: t), below = Self.region(at: 60, 150, in: t)
        let left = Self.region(at: 60, 40, in: t), right = Self.region(at: 180, 40, in: t)
        #expect(pieces[strip] == pieces[below], "the strip shares the most lead with the piece below")
        #expect(Set([pieces[left], pieces[right], pieces[below]]).count == 3)
        #expect(GlassLeadSuggestion.pieces(of: t, narrowest: 1) == Array(0..<t.regions.count))
    }

    /// A tap takes a line of lead away, junction to junction, and Undo puts it back.
    @Test func eraseTakesALineAndUndoPutsItBack() throws {
        var leading = try GlassWindow.Leading(photo: Self.photo(), width: Self.width, height: Self.height, colorSpace: .sRGB)
        for line in Self.lines { leading.add(line) }
        let three = leading.template.encoded()
        #expect(leading.template.regions.count == 3)
        let erased = leading.erase(at: SIMD2(200, 90), reach: 4)
        #expect(erased)
        #expect(leading.template.regions.count == 2)
        let bare = leading.erase(at: SIMD2(60, 40), reach: 4)
        #expect(!bare, "nothing to take on bare glass")
        try leading.undo()
        #expect(leading.template.encoded() == three)
        try leading.undo()
        #expect(leading.lines.count == 1)
    }

    // MARK: Framing by hand

    /// From the top border down and across to the right border: the top right piece is framed,
    /// and the left piece, only grazed, isn't.
    @Test func aStrokeFromTheLeadRoundAChunkFramesItsPieces() throws {
        let t = try Self.window().template
        let none = [Bool](repeating: false, count: t.regions.count)
        let stroke: [SIMD2<Float>] = [SIMD2(100, 0), SIMD2(100, 100), SIMD2(240, 100)]
        let framed = GlassFraming.framed(by: stroke, in: t, framed: none, reach: 3)
        #expect(framed == [Self.region(at: 200, 40, in: t)])
    }

    /// A stroke must leave the leaded part and come back to it, and part something off.
    @Test func aStrokeThatClosesNothingFramesNothing() throws {
        let t = try Self.window().template
        let none = [Bool](repeating: false, count: t.regions.count)
        // Starting in the middle of the bare window.
        #expect(GlassFraming.framed(by: [SIMD2(60, 90), SIMD2(100, 100), SIMD2(240, 100)], in: t, framed: none, reach: 3).isEmpty)
        // Along the border, parting nothing off.
        #expect(GlassFraming.framed(by: [SIMD2(10, 1), SIMD2(200, 1)], in: t, framed: none, reach: 3).isEmpty)
    }

    /// Every piece can be framed, the last too: a stroke across the last bare piece frames it,
    /// though there is nothing left to part it from.
    @Test func everyPieceCanBeFramedStrokeByStroke() throws {
        let t = try Self.window().template
        var framed = [Bool](repeating: false, count: t.regions.count)
        let topRight = Self.region(at: 200, 40, in: t), bottomRight = Self.region(at: 200, 140, in: t)
        let left = Self.region(at: 40, 90, in: t)
        func lay(_ stroke: [SIMD2<Float>]) -> [Int] {
            let new = GlassFraming.framed(by: stroke, in: t, framed: framed, reach: 3)
            for r in new { framed[r] = true }
            return new
        }
        #expect(lay([SIMD2(100, 0), SIMD2(100, 100), SIMD2(240, 100)]) == [topRight])
        #expect(lay([SIMD2(130, 88), SIMD2(110, 120), SIMD2(110, 180)]) == [bottomRight])
        // The left piece, alone now: from the top border straight down to the bottom one.
        #expect(lay([SIMD2(40, 0), SIMD2(40, 180)]) == [left])
        #expect(framed.allSatisfy { $0 })
    }

    /// A finger dragged past the canvas's edge walls nothing out there.
    @Test func aStrokePastTheEdgeIsSafe() throws {
        let t = try Self.window().template
        let none = [Bool](repeating: false, count: t.regions.count)
        let stroke: [SIMD2<Float>] = [SIMD2(-20, -20), SIMD2(100, 0), SIMD2(100, 100), SIMD2(260, 100), SIMD2(300, 220)]
        #expect(GlassFraming.framed(by: stroke, in: t, framed: none, reach: 3) == [Self.region(at: 200, 40, in: t)])
    }

    /// Pieces already framed are leaded: a stroke may start from them, and they are never framed
    /// again.
    @Test func framedPiecesAreLeadToStartFrom() throws {
        let t = try Self.window().template
        let topRight = Self.region(at: 200, 40, in: t), bottomRight = Self.region(at: 200, 140, in: t)
        var framed = [Bool](repeating: false, count: t.regions.count)
        framed[topRight] = true
        // From the framed piece's bottom edge round the bottom right piece to the bottom border.
        let stroke: [SIMD2<Float>] = [SIMD2(130, 88), SIMD2(110, 120), SIMD2(110, 180)]
        #expect(GlassFraming.framed(by: stroke, in: t, framed: framed, reach: 3) == [bottomRight])
    }

    @Test func noLinesIsOnePiece() throws {
        let w = try Self.window([])
        expectValid(w.template)
        #expect(w.template.regions.count == 1 && w.suggestion.glasses.count == 1)
    }

    @Test func offeredAddsTheClassicsNotAlreadyThere() throws {
        let t = try Self.window().template
        let offered = GlassPalette.offered(for: t)
        #expect(Array(offered.prefix(t.palette.count)) == t.palette)
        #expect(offered.count > t.palette.count && offered.count <= t.palette.count + GlassPalette.classics.count)
        // A window whose own glass is cobalt is not offered cobalt again.
        let c = GlassPalette.classics[0]
        let cobalt = ColorScience.encodedToOKLab(SIMD3(Float(c.x), Float(c.y), Float(c.z)) / 255, space: .sRGB)
        var blue = t
        blue.palette = [PaletteColor(oklab: cobalt, space: .sRGB)]
        #expect(GlassPalette.offered(for: blue).count == GlassPalette.classics.count)
    }

    // MARK: The glass

    @Test func litGlassGlowsInsideAndUnlitStaysDark() throws {
        let t = try Self.window().template
        let texture = GlassTexture(template: t)
        let r = t.regions.indices.max { t.regions[$0].area < t.regions[$1].area }!
        let glass = SIMD3<Float>(0.8, 0.3, 0.2)
        var lit = [UInt8](repeating: 0, count: t.width * t.height * 4), unlit = lit
        texture.paint(r, rgb: glass, lit: true, into: &lit)
        texture.paint(r, rgb: glass, lit: false, into: &unlit)
        var inside = [Int](), edge = [Int](), outside = 0
        for y in 0..<t.height {
            for x in 0..<t.width {
                let i = y * t.width + x
                guard Self.region(at: x, y, in: t) == r else { outside += Int(lit[i * 4 + 3]); continue }
                let k = Int(t.regionMap[x, y])
                let border = x == 0 || y == 0 || x == t.width - 1 || y == t.height - 1
                    || Int(t.regionMap[x - 1, y]) != k || Int(t.regionMap[x + 1, y]) != k
                if border { edge.append(Int(lit[i * 4])) } else { inside.append(Int(lit[i * 4])) }
                #expect(unlit[i * 4] < lit[i * 4], "unlit glass is darker than lit")
            }
        }
        #expect(outside == 0, "only the piece is painted")
        let mean = { (v: [Int]) in Double(v.reduce(0, +)) / Double(max(1, v.count)) }
        #expect(mean(inside) > mean(edge) + 10, "lit glass glows deep in its piece")
        // The same window, the same glass.
        var again = [UInt8](repeating: 0, count: lit.count)
        GlassTexture(template: t).paint(r, rgb: glass, lit: true, into: &again)
        #expect(again == lit)
    }

    /// The fields the canvas paints the glass from: the lead's distance 1 on a piece's edge and
    /// growing inside it, and the same shade, depth and grain `paint` uses (a lit pixel's red is
    /// its glass by the shade plus the warm light by the depth).
    @Test func fieldsAreWhatPaintUses() throws {
        let t = try Self.window().template
        let texture = GlassTexture(template: t)
        let fields = texture.fields()
        #expect(fields.count == t.width * t.height * 4)
        let r = t.regions.indices.max { t.regions[$0].area < t.regions[$1].area }!
        let glass = SIMD3<Float>(0.8, 0.3, 0.2)
        var lit = [UInt8](repeating: 0, count: t.width * t.height * 4)
        texture.paint(r, rgb: glass, lit: true, into: &lit)
        var deepest: Float = 0
        for y in 1..<(t.height - 1) {
            for x in 1..<(t.width - 1) where Self.region(at: x, y, in: t) == r {
                let i = y * t.width + x
                let k = Int(t.regionMap[x, y])
                if Int(t.regionMap[x - 1, y]) != k || Int(t.regionMap[x + 1, y]) != k {
                    #expect(fields[i * 4] <= 1.5, "a piece's edge is next to its lead")
                }
                deepest = max(deepest, fields[i * 4])
                let red = glass.x * fields[i * 4 + 1] + GlassTexture.warm.x * fields[i * 4 + 2]
                #expect(abs(Float(lit[i * 4]) - min(255, max(0, red * 255))) <= 1.5)
            }
        }
        #expect(deepest > 3, "the lead's distance grows inside a piece")
    }

    // MARK: Glazing

    static func glasses(_ n: Int) -> [PaletteColor] {
        (0..<n).map { i in PaletteColor(oklab: SIMD3(0.3 + 0.1 * Float(i), 0.05, -0.02), space: .sRGB) }
    }

    /// Each piece's real glass pane (`GlassPaneOutlines`) lies off the lead the canvas casts from
    /// the same field, and the lead round an island piece is a hole in the pane round it.
    @Test func panesStayOffTheLeadAndRoundIslands() throws {
        // The two lines, and a closed loop in the left half: an island piece.
        var loop: [SIMD2<Float>] = []
        for k in 0...24 {
            let a = Float(k) / 24 * 2 * .pi
            loop.append(SIMD2(60 + 22 * cos(a), 90 + 22 * sin(a)))
        }
        let t = try Self.window(Self.lines + [loop], joining: 4).template
        let texture = GlassTexture(template: t)
        let inset: Float = 3
        let panes = GlassPaneOutlines.outlines(of: t, texture: texture, inset: inset, minimumArea: 4)
        #expect(panes.count == t.regions.count)
        func inside(_ p: SIMD2<Float>, _ rings: [[SIMD2<Float>]]) -> Bool {
            var crossings = 0
            for ring in rings {
                for i in ring.indices {
                    let a = ring[i], b = ring[(i + 1) % ring.count]
                    if (a.y > p.y) != (b.y > p.y), p.x < a.x + (p.y - a.y) / (b.y - a.y) * (b.x - a.x) { crossings += 1 }
                }
            }
            return crossings % 2 == 1
        }
        for r in t.regions.indices {
            #expect(!panes[r].isEmpty, "piece \(r) has a pane")
            for y in 0..<t.height {
                for x in 0..<t.width where inside(SIMD2(Float(x) + 0.5, Float(y) + 0.5), panes[r]) {
                    #expect(Int(t.regionMap[x, y]) == r)
                    // Within the half pixel tracing and rounding may round off.
                    #expect(texture.lead[y * t.width + x] - 0.5 > inset - 1.5)
                }
            }
        }
        let island = Self.region(at: 60, 90, in: t), around = Self.region(at: 20, 20, in: t)
        #expect(island != around)
        #expect(panes[around].count == 2, "the pane round the island has a hole")
        #expect(inside(SIMD2(60.5, 90.5), panes[island]) && !inside(SIMD2(60.5, 90.5), panes[around]))
        #expect(inside(SIMD2(20.5, 20.5), panes[around]))
    }

    @Test func glazingRoundTrips() throws {
        var g = Glazing(pieces: 4, offered: Self.glasses(5))
        #expect(g.glazedCount == 0)
        g.glass[1] = 3
        g.glass[3] = 0
        let back = try Glazing(encoded: g.encoded(), pieces: 4)
        #expect(back == g && back.glazedCount == 2)
        // The glasses are the ones the window was made with, whatever is suggested now.
        #expect(back.offered == Self.glasses(5))
        // Readers ignore trailing bytes: fields are only ever appended.
        #expect(try Glazing(encoded: g.encoded() + Data([1, 2, 3]), pieces: 4) == g)
    }

    /// The frames ride at the file's end; a file from before them has its glazed pieces framed.
    @Test func framesRoundTripAndOlderFilesFrameTheirGlazedPieces() throws {
        var g = Glazing(pieces: 4, offered: Self.glasses(3))
        g.glass[2] = 1
        g.framed[0] = true
        let data = g.encoded()
        let back = try Glazing(encoded: data, pieces: 4)
        #expect(back.framed == [true, false, false, false])
        #expect((0..<4).map(back.isFramed) == [true, false, true, false])
        let older = try Glazing(encoded: data.dropLast(4 + 4), pieces: 4)
        #expect(older.framed == [false, false, true, false])
        // A frame count that isn't the window's is a corrupt file.
        var wrong = data.dropLast(4 + 4)
        withUnsafeBytes(of: UInt32(9)) { wrong.append(contentsOf: $0) }
        #expect(throws: Glazing.CodingError.corrupt) { try Glazing(encoded: wrong + Data(repeating: 1, count: 9), pieces: 4) }
    }

    @Test func aGlassPastTheOfferedReadsAsNone() throws {
        var g = Glazing(pieces: 3, offered: Self.glasses(3))
        g.glass = [2, 7, -5]
        let back = try Glazing(encoded: g.encoded(), pieces: 3)
        #expect(back.glass == [2, Glazing.none, Glazing.none])
    }

    @Test func glazingIsReadAsHostile() throws {
        var g = Glazing(pieces: 3, offered: Self.glasses(3))
        g.glass = [0, 1, 2]
        let data = g.encoded()
        // Cut anywhere but where the frames begin (a file from before them ends there, and a few
        // trailing bytes are ignored), it is corrupt.
        let framesAt = data.count - 4 - 3
        for n in 0..<data.count where n < framesAt || n >= framesAt + 4 {
            #expect(throws: Glazing.CodingError.self) { try Glazing(encoded: data.prefix(n), pieces: 3) }
        }
        var bad = data
        bad[0] ^= 0xFF
        #expect(throws: Glazing.CodingError.corrupt) { try Glazing(encoded: bad, pieces: 3) }
        var newer = data
        newer.replaceSubrange(4..<8, with: withUnsafeBytes(of: UInt32(9)) { Data($0) })
        #expect(throws: Glazing.CodingError.newerVersion(9)) { try Glazing(encoded: newer, pieces: 3) }
        var huge = data
        huge.replaceSubrange(8..<12, with: withUnsafeBytes(of: UInt32.max) { Data($0) })
        #expect(throws: Glazing.CodingError.corrupt) { try Glazing(encoded: huge, pieces: 3) }
        #expect(throws: Glazing.CodingError.otherWindow) { try Glazing(encoded: data, pieces: 4) }
        var hugeOffer = data
        hugeOffer.replaceSubrange(18..<22, with: withUnsafeBytes(of: UInt32.max) { Data($0) })
        #expect(throws: Glazing.CodingError.corrupt) { try Glazing(encoded: hugeOffer, pieces: 3) }
        var notANumber = data
        notANumber.replaceSubrange(22..<26, with: withUnsafeBytes(of: Float.nan) { Data($0) })
        #expect(throws: Glazing.CodingError.corrupt) { try Glazing(encoded: notANumber, pieces: 3) }
        // A slice not starting at zero reads the same.
        let sliced = (Data([9, 9]) + data).dropFirst(2)
        #expect(try Glazing(encoded: sliced, pieces: 3) == g)
    }
}
