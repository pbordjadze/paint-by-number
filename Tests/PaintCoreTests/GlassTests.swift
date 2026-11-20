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
        #expect(back.x <= 0.46, "background glass is deep")
        #expect(subject.x >= 0.5, "subject glass is bright")
        let chroma = { (c: SIMD3<Float>) in (c.y * c.y + c.z * c.z).squareRoot() }
        #expect(chroma(subject) > chroma(back))
        // Weighed by chroma, the checker reads orange-red, never the mud of its mean.
        #expect(subject.y > 0.05, "a warm glass")
        #expect(back.y < 0 || chroma(back) < 0.06, "the sage stays green and quiet")
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

    // MARK: Glazing

    static func glasses(_ n: Int) -> [PaletteColor] {
        (0..<n).map { i in PaletteColor(oklab: SIMD3(0.3 + 0.1 * Float(i), 0.05, -0.02), space: .sRGB) }
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
        for n in 0..<data.count {
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
