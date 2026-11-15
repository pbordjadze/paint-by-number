import Foundation
import Testing
@testable import PaintCore

/// How an edit is kept in a file (`TemplateEditor.Edit`'s coding): the shape is pinned by literal
/// JSON, because files written today must read the same in every later build.
@Suite("Edit coding")
struct EditCodingTests {
    typealias Edit = TemplateEditor.Edit

    static let edits: [Edit] = [
        .draw(points: [SIMD2(15, -4), SIMD2(18.5, 30.25), SIMD2(15, 71)], closed: false),
        .draw(points: [SIMD2(1, 1), SIMD2(9, 1), SIMD2(9, 9), SIMD2(1, 9)], closed: true),
        .erase(path: [SIMD2(55, 44), SIMD2(65, 44.5)], radius: 3),
        .eraseLine(at: SIMD2(10, 72), reach: 5),
        .fill(at: SIMD2(140, 55), color: SIMD3(0.7, -0.125, 0.0625)),
    ]

    private func encode(_ edits: [Edit]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(edits), as: UTF8.self)
    }

    private func decode(_ json: String) throws -> [Edit] {
        try JSONDecoder().decode([Edit].self, from: Data(json.utf8))
    }

    @Test func roundTrips() throws {
        let json = try encode(Self.edits)
        #expect(try decode(json) == Self.edits)
        // Every point is a Float's own, whatever its digits.
        var rng = SplitMix64(seed: 9)
        let random: [Edit] = (0..<50).map { _ in
            .draw(
                points: (0..<6).map { _ in SIMD2(rng.nextFloat() * 1100, rng.nextFloat() * 800) }, closed: rng.nextFloat() < 0.5)
        }
        #expect(try decode(try encode(random)) == random)
    }

    /// The shape of a file: never to change (a reader of today reads these).
    @Test func theShapeIsPinned() throws {
        let json = try encode(Self.edits)
        #expect(json == """
            [{"closed":false,"kind":"draw","points":[[15,-4],[18.5,30.25],[15,71]]},\
            {"closed":true,"kind":"draw","points":[[1,1],[9,1],[9,9],[1,9]]},\
            {"kind":"erase","points":[[55,44],[65,44.5]],"radius":3},\
            {"kind":"eraseLine","points":[[10,72]],"reach":5},\
            {"color":[0.7,-0.125,0.0625],"kind":"fill","points":[[140,55]]}]
            """)
    }

    /// Fields the kind has defaults for may be left out, as `pbn edit`'s files do.
    @Test func missingFieldsTakeTheirDefaults() throws {
        let decoded = try decode(
            #"[{"kind":"draw","points":[[1,2],[3,4]]},{"kind":"erase","points":[[5,6]]},{"kind":"eraseLine","points":[[7,8]]}]"#)
        #expect(decoded == [
            .draw(points: [SIMD2(1, 2), SIMD2(3, 4)], closed: false),
            .erase(path: [SIMD2(5, 6)], radius: 4),
            .eraseLine(at: SIMD2(7, 8), reach: TemplateEditor.tapReach),
        ])
    }

    /// A reader skips what it does not know, and fails an edit it cannot read, which a list of them
    /// can leave out on its own (the app's `Lossy`).
    @Test func unknownFieldsAreSkippedAndUnreadableEditsFail() throws {
        #expect(try decode(#"[{"kind":"eraseLine","points":[[7,8]],"reach":2,"someday":[1,2,3]}]"#)
            == [.eraseLine(at: SIMD2(7, 8), reach: 2)])
        for json in [
            #"{"kind":"smudge","points":[[1,2]]}"#,
            #"{"kind":"fill","points":[[1,2]]}"#,
            #"{"kind":"fill","points":[[1,2]],"color":[0.5,0]}"#,
            #"{"kind":"fill","points":[],"color":[0.5,0,0]}"#,
            #"{"kind":"eraseLine","points":[]}"#,
            #"{"kind":"draw"}"#,
            #"{"points":[[1,2]]}"#,
        ] {
            #expect(throws: DecodingError.self, "\(json)") { try JSONDecoder().decode(Edit.self, from: Data(json.utf8)) }
        }
    }

    /// Every kind has its name, the one its file keeps it under.
    @Test func everyKindHasItsName() throws {
        let names = ["draw", "split", "cellEdge", "merge", "brush", "reshape", "moveLabel", "erase", "eraseLine", "fill", "paintArea",
                     "look", "repaint"]
        #expect(Edit.Kind.allCases.map(\.rawValue) == names)
        for edit in Self.edits {
            let object = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(edit)) as? [String: Any]
            #expect(object?["kind"] as? String == edit.kind.rawValue)
        }
        #expect(Edit.merge(points: []).kind == .merge && Edit.look(.sepia, strength: 1).kind == .look)
    }

    /// A paint's number stands for its color only to a decoder handed the palette (`pbn edit`);
    /// a `color` beside it wins, and a number the palette lacks fails the edit. The app hands no
    /// palette, so a file of its own without a `color` fails as ever.
    @Test func aPaintNumberNeedsThePalette() throws {
        let palette = [SIMD3<Float>(0.25, 0.0625, -0.125), SIMD3<Float>(0.75, -0.0625, 0.125)]
            .map { PaletteColor(oklab: $0, space: .sRGB) }
        let decoder = JSONDecoder()
        decoder.userInfo[Edit.paletteKey] = palette
        let json = """
            [{"kind":"fill","points":[[1,2]],"paint":2},{"kind":"paintArea","points":[[1,2]],"paint":1},\
            {"kind":"brush","points":[[1,2],[3,4]],"radius":6,"paint":2},\
            {"kind":"fill","points":[[1,2]],"paint":1,"color":[0.5,0,0]}]
            """
        #expect(try decoder.decode([Edit].self, from: Data(json.utf8)) == [
            .fill(at: SIMD2(1, 2), color: palette[1].oklab),
            .paintArea(at: SIMD2(1, 2), color: palette[0].oklab),
            .brush(path: [SIMD2(1, 2), SIMD2(3, 4)], radius: 6, color: palette[1].oklab),
            .fill(at: SIMD2(1, 2), color: SIMD3(0.5, 0, 0)),
        ])
        for json in [#"{"kind":"fill","points":[[1,2]],"paint":3}"#, #"{"kind":"fill","points":[[1,2]],"paint":0}"#] {
            #expect(throws: DecodingError.self, "\(json)") { try decoder.decode(Edit.self, from: Data(json.utf8)) }
        }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Edit.self, from: Data(#"{"kind":"fill","points":[[1,2]],"paint":2}"#.utf8)) }
        // The fields a brush and a look need are needed with a palette too.
        for json in [#"{"kind":"brush","points":[[1,2]],"paint":1}"#, #"{"kind":"look","points":[],"look":"sepia"}"#] {
            #expect(throws: DecodingError.self, "\(json)") { try decoder.decode(Edit.self, from: Data(json.utf8)) }
        }
    }
}
