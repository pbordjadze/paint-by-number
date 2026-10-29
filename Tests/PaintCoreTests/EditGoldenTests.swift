import Foundation
import Testing
@testable import PaintCore

/// What a saved list of edits makes, pinned with the editor's version (`TemplateEditor.version`).
/// `Fixtures/edits-v1.json` is a list as a painting's `refinements.json` keeps its `edits`
/// (`EditCoding`), of every kind of edit: draws with paints, with none to give and from before
/// paints, a split, a cell edge, a merge, a brush, a bend, a moved number, the eraser, the line
/// eraser, a fill, Only This Area, a repaint and a look, each of which changes the template it is
/// laid on (one draw cuts the writing in the disc). It is decoded and laid in order by
/// `EditTrail`, as the app lays a painting's, on `template-v2-writing.pbnt`: a frozen coloring
/// book with writing, so no change to the generator moves the pin.
///
/// A change to what the list makes fails `everyKindOfEditLaysAsPinned`: bump
/// `TemplateEditor.version` in the same commit and add the digest it prints to `pins` under the
/// new version (never edit a pin). The fixture is never regenerated: a new kind of edit (`Kind`'s
/// switch has no default, so it doesn't compile until it is named) joins in a fixture of its own,
/// laid on the same base and pinned beside this one.
///
/// The digest is FNV-1a (64-bit) of the result's bytes (`Template.encoded`) with every paint's
/// `rgb` zeroed. The editor decides with integer lattice arithmetic and with IEEE `+ - * /` and
/// square roots, which round alike on every platform, and the fixture's numbers are exact in
/// binary, so they decode alike; a paint's encoded `rgb` alone goes through libm's `pow`
/// (`ColorScience.okLabToEncoded`, from the OKLab the digest keeps), whose last bits may differ
/// between Apple's libm and glibc. CI runs this suite on Linux alone (`core`; the macOS jobs run
/// only `ColorNicknameV2Tests`), where the pin was made; it is meant to hold on Apple platforms
/// too, and has not been run there.
@Suite("Edit golden")
struct EditGoldenTests {
    /// The digest of `edits-v1.json` laid on the base, by editor version. 2's is 1's: none of the
    /// fixture's fills or erasures leaves a paint with no area (`BlankTemplateTests` pins that).
    static let pins: [Int: UInt64] = [1: 0x609c_c372_67f9_af85, 2: 0x609c_c372_67f9_af85]

    /// The kinds of edit, one per case of `TemplateEditor.Edit`.
    enum Kind: CaseIterable {
        case draw, split, cellEdge, merge, brush, reshape, moveLabel, erase, eraseLine, fill, paintArea, look, repaint
    }

    static func kind(_ edit: TemplateEditor.Edit) -> Kind {
        switch edit {
        case .draw: .draw
        case .split: .split
        case .cellEdge: .cellEdge
        case .merge: .merge
        case .brush: .brush
        case .reshape: .reshape
        case .moveLabel: .moveLabel
        case .erase: .erase
        case .eraseLine: .eraseLine
        case .fill: .fill
        case .paintArea: .paintArea
        case .look: .look
        case .repaint: .repaint
        }
    }

    /// FNV-1a over the template's bytes, its paints' `rgb` left out (see above).
    static func digest(_ template: Template) -> UInt64 {
        var t = template
        t.palette = t.palette.map { PaletteColor(oklab: $0.oklab, rgb: .zero) }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in t.encoded() { hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 }
        return hash
    }

    static func hex(_ value: UInt64) -> String { "0x" + String(value, radix: 16) }

    @Test func everyKindOfEditLaysAsPinned() throws {
        let base = try Template(encoded: TestFixtures.data("template-v2-writing.pbnt"))
        let edits = try JSONDecoder().decode([TemplateEditor.Edit].self, from: TestFixtures.data("edits-v1.json"))
        #expect(edits.count == 15)
        let kinds = Set(edits.map(Self.kind))
        #expect(kinds == Set(Kind.allCases), "missing from the fixture: \(Set(Kind.allCases).subtracting(kinds))")
        #expect(try JSONDecoder().decode([TemplateEditor.Edit].self, from: JSONEncoder().encode(edits)) == edits)

        var trail = EditTrail(base: base)
        let replay = try trail.move(to: edits)
        #expect(replay.made == edits.count && replay.left == 0, "every edit changes the template it is laid on")
        let result = trail.template
        expectValid(result)
        #expect(result.lineArt!.writingStrokes.count == 5, "the disc's two letters cut, every piece writing")

        #expect(Self.pins.keys.max() == TemplateEditor.version, "TemplateEditor.version \(TemplateEditor.version) has no pin")
        let digest = Self.digest(result)
        let pinned = Self.pins[TemplateEditor.version]
        #expect(
            digest == pinned,
            """
            edits-v1.json laid makes \(Self.hex(digest)), where editor version \(TemplateEditor.version) pinned \
            \(pinned.map(Self.hex) ?? "nothing"): a change to what edits make bumps TemplateEditor.version in the same \
            commit, and its digest joins `pins` under the new version
            """)
        // The same twice, and through the file.
        var again = EditTrail(base: base)
        try again.move(to: edits)
        let read = try Template(encoded: result.encoded())
        #expect(Self.digest(again.template) == digest && Self.digest(read) == digest)
    }
}
