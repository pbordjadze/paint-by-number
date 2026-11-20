import Foundation
import MosaicKit
import Testing
@testable import MosaicCore

/// Set in Stone's book (`StoneBook`): pieces a mosaicist can cut, joints filled as a mosaicist
/// would, every piece set once in a step that fits its page, and the stones to buy.
@Suite("Stone book")
struct StoneBookTests {
    typealias P = SIMD2<Double>

    static func hodegetria() throws -> Mosaic {
        let url = TemplateTests.mosaics.appendingPathComponent("hodegetria-standard.json")
        return try JSONDecoder().decode(Mosaic.self, from: Data(contentsOf: url))
    }

    static let book: StoneBook = {
        let m = try! hodegetria()
        return StoneBook(mosaic: m, title: "Hodegetria", names: [String?](repeating: nil, count: m.palette.count))
    }()

    static func convex(_ p: [P]) -> Bool {
        var sign = 0.0
        for i in p.indices {
            let c = BookGeometry.cross(p[i], p[(i + 1) % p.count], p[(i + 2) % p.count])
            if abs(c) < 1e-9 { continue }
            if sign == 0 { sign = c } else if (c > 0) != (sign > 0) { return false }
        }
        return true
    }

    @Test func aNotchedTileIsCutIntoConvexPieces() {
        // an L: a real notch, not one to trim away
        let l: [P] = [P(0, 0), P(20, 0), P(20, 8), P(8, 8), P(8, 20), P(0, 20)]
        let pieces = BookPieces.cuttable(l, medianArea: 100, joint: 0.5, minimumWidth: 2)
        #expect(pieces.count == 2)
        for p in pieces { #expect(Self.convex(p)) }
        let total = pieces.map(BookGeometry.area).reduce(0, +)
        #expect(total < BookGeometry.area(l) && total > 0.85 * BookGeometry.area(l), "the cut costs only a joint")
        // a slight notch is trimmed: the tile becomes its hull
        let nick: [P] = [P(0, 0), P(10, 0), P(10, 10), P(5, 9.8), P(0, 10)]
        #expect(BookPieces.cuttable(nick, medianArea: 100, joint: 0.5, minimumWidth: 2).count == 1)
    }

    @Test func insetAndFlatKeepAConvexPiece() {
        let square: [P] = [P(0, 0), P(10, 0), P(10, 10), P(0, 10)]
        let inner = try! #require(BookGeometry.inset(square, by: 1))
        #expect(abs(BookGeometry.area(inner) - 64) < 1e-9)
        #expect(BookGeometry.inset(square, by: 6) == nil)
        let tilted: [P] = [P(0, 0), P(8, 6), P(5, 10), P(-3, 4)]   // a 10 × 5 rectangle turned
        let flat = BookGeometry.flat(tilted)
        let hi = flat.reduce(P(0, 0)) { pointwiseMax($0, $1) }
        #expect(abs(hi.y - 5) < 1e-9 && abs(hi.x - 10) < 1e-9, "lying on its long side")
    }

    @Test func fillersCloseAWideJointWithoutTouchingTheTiles() {
        // two squares 30 units apart: the room between them is filled; a joint keeps clear
        let tiles: [[P]] = [[P(0, 0), P(20, 0), P(20, 20), P(0, 20)], [P(50, 0), P(70, 0), P(70, 20), P(50, 20)]]
        let fillers = BookPieces.fillers(tiles, width: 70, height: 20, pixel: 0.5, joint: 1, minimumWidth: 4, targetArea: 150)
        #expect(fillers.count >= 2)
        let filled = fillers.map { BookGeometry.area($0.corners) }.reduce(0, +)
        #expect(filled > 0.6 * 30 * 18, "most of the gap is stone, \(filled)")
        for f in fillers {
            #expect(Self.convex(f.corners))
            for c in f.corners { #expect(c.x >= 20.4 && c.x <= 49.6, "a joint from each tile") }
        }
        let byX = fillers.sorted { BookGeometry.centre($0.corners).x < BookGeometry.centre($1.corners).x }
        #expect(byX.first?.neighbour == 0 && byX.last?.neighbour == 1, "each cut from the stone beside it")
    }

    @Test func everyPieceIsSetOnceInAStepThatFits() {
        let b = Self.book
        var seen = [Int](repeating: 0, count: b.pieces.count)
        for (n, step) in b.steps.enumerated() {
            #expect(!step.pieces.isEmpty)
            for i in step.pieces {
                seen[i] += 1
                #expect(b.pieces[i].section == step.section && b.pieces[i].step == n)
            }
            if step.pieces.count > 1 { #expect(BookLayout.partsFit(step.pieces.map { b.pieces[$0] }, mm: b.mm)) }
        }
        #expect(seen.allSatisfy { $0 == 1 })
        for p in b.pieces { #expect(Self.convex(p.corners)) }
    }

    @Test func theHodegetriaIsSetAtTrueSize() {
        let b = Self.book
        #expect(abs(b.widthMM - 700) < 30 && abs(b.heightMM - 940) < 30, "\(b.widthMM) × \(b.heightMM)")
        #expect(b.columns * b.rows == 16)
        // each section fits an A4 page at 1:1
        #expect(b.widthMM / Double(b.columns) <= BookLayout.sectionMaxWidth && b.heightMM / Double(b.rows) <= BookLayout.sectionMaxHeight)
        #expect(b.fillerCount > 0)
        let covered = b.pieces.map(\.area).reduce(0, +) / (b.width * b.height)
        #expect(covered > 0.7, "the joints are a mosaicist's, not the engine's: \(covered)")
        #expect(b.pageCount > 200)
    }

    @Test func eachStoneHasItsOwnSmalto() {
        let stones = Self.book.stones
        let codes = stones.compactMap(\.smalto?.code)
        #expect(Set(codes).count == codes.count)
        #expect(stones.map(\.count).reduce(0, +) == Self.book.pieces.count)
        for s in stones { #expect(s.buy >= s.count && s.kilograms > 0) }
        #expect(Smalti.orsoni.count == 97 && !Smalti.orsoni.contains { $0.code == "S47" })
    }

    @Test func theBookIsTheSameEveryTime() throws {
        let m = try Self.hodegetria()
        let again = StoneBook(mosaic: m, title: "Hodegetria", names: [String?](repeating: nil, count: m.palette.count))
        #expect(again.pieces == Self.book.pieces && again.steps == Self.book.steps)
    }

    @Test func everyKindOfPageLaysOut() {
        let b = Self.book
        var kinds = Set<String>()
        for n in 1...b.pageCount {
            let name = "\(b.pageKinds[n - 1])".split(separator: "(").first.map(String.init) ?? ""
            guard !kinds.contains(name) else { continue }
            kinds.insert(name)
            let page = b.page(n)
            #expect(page.items.count > 2, "page \(n)")
            #expect(page.svg().hasPrefix("<svg"))
        }
        #expect(kinds.count == 10, "\(kinds)")
        // the stone list is the only page with words
        let last = b.page(b.pageCount)
        #expect(last.items.contains { if case .text(let t) = $0 { t.string == BookStrings().altogether } else { false } })
    }

    @Test func aBiggerTileMakesABiggerMosaic() throws {
        let m = try Self.hodegetria()
        let big = StoneBook(mosaic: m, title: "", names: [String?](repeating: nil, count: m.palette.count), options: .init(tileFace: 2.25))
        #expect(abs(big.widthMM / Self.book.widthMM - 2.25.squareRoot() / 1.5.squareRoot()) < 1e-6)
    }
}
