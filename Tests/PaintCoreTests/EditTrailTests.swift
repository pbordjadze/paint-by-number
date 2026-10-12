import Foundation
import Testing
@testable import PaintCore

/// A template with the painter's edits laid on it, in order (`EditTrail`), on the editor's scenes
/// (`TemplateEditorTests`): that it is the editor's own result, that taking an edit back or
/// putting it back costs no editing, that edits which no longer fit are left out and counted, and
/// that a list laid again gives the same template.
@Suite("Edit trail")
struct EditTrailTests {
    typealias Edit = TemplateEditor.Edit

    /// Five edits that are each made, in this order, on the editor's scene.
    static let edits: [Edit] = [
        .draw(points: [SIMD2(15, -4), SIMD2(18.5, 30.25), SIMD2(15, 71)]),
        .draw(points: [SIMD2(100, 25), SIMD2(110.5, 31), SIMD2(104.1, 40)]),
        .erase(path: [SIMD2(55, 44), SIMD2(65, 44.5)], radius: 3),
        .fill(at: SIMD2(140, 55), color: SIMD3(0.7, -0.1, 0.1)),
        .eraseLine(at: SIMD2(10, 72), reach: 5),
    ]

    /// A line that doubles back on itself, which the editor declines.
    static let doublingBack: Edit = .draw(points: [SIMD2(100, 10), SIMD2(100, 30), SIMD2(100, 20)])

    /// An eraser over bare paper, which has nothing to change.
    static let overPaper: Edit = .erase(path: [SIMD2(150, 130)], radius: 2)

    /// The template `edits` make one after another, edit by edit, as the editor does.
    static func laid(_ edits: [Edit], on base: Template = TemplateEditorTests.scene) throws -> Template {
        try edits.reduce(base) { try TemplateEditor.apply($1, to: $0).template }
    }

    @Test func anEditAddedIsTheEditorsResult() throws {
        var trail = EditTrail(base: TemplateEditorTests.scene)
        #expect(trail.template == trail.base && trail.edits.isEmpty)
        for (k, edit) in Self.edits.enumerated() {
            #expect(trail.add(edit) == .made(tooSmall: false))
            #expect(trail.edits == Array(Self.edits.prefix(k + 1)))
        }
        let expected = try Self.laid(Self.edits)
        #expect(trail.template == expected)
        expectValid(trail.template)
    }

    /// Taking an edit back, or putting it back, lays nothing when the template is kept.
    @Test func undoAndRedoNeedNoEditing() throws {
        var trail = EditTrail(base: TemplateEditorTests.scene)
        for edit in Self.edits { trail.add(edit) }
        let full = trail.template

        var replay = try trail.move(to: Array(Self.edits.prefix(4)))
        #expect(replay == EditTrail.Replay(), "taking back one edit laid some")
        let four = try Self.laid(Array(Self.edits.prefix(4)))
        #expect(trail.template == four)
        replay = try trail.move(to: Array(Self.edits.prefix(3)))
        #expect(replay == EditTrail.Replay())
        let three = try Self.laid(Array(Self.edits.prefix(3)))
        #expect(trail.template == three)

        // Putting back lays only what is new.
        replay = try trail.move(to: Array(Self.edits.prefix(4)))
        #expect(replay.made == 1 && replay.left == 0)
        replay = try trail.move(to: Self.edits)
        #expect(replay.made == 1)
        #expect(trail.template == full)

        // All the way back is the base, exactly, and forward again is the same template.
        replay = try trail.move(to: [])
        #expect(replay == EditTrail.Replay() && trail.template == trail.base && trail.edits.isEmpty)
        replay = try trail.move(to: Self.edits)
        #expect(replay.made == Self.edits.count && trail.template == full)
    }

    /// An edit taken out of the middle is laid again from there: what comes before it is not.
    @Test func aListChangedInTheMiddleIsLaidFromWhereItParts() throws {
        var trail = EditTrail(base: TemplateEditorTests.scene)
        for edit in Self.edits { trail.add(edit) }
        var target = Self.edits
        target.remove(at: 2)
        let replay = try trail.move(to: target)
        #expect(replay.made + replay.left == 2, "laid more than the edits after the one taken out")
        let expected = try Self.laid(target)
        #expect(trail.template == expected)
        #expect(trail.edits == target)
        expectValid(trail.template)
    }

    @Test func anEditThatDoesNothingIsNotAdded() throws {
        var trail = EditTrail(base: TemplateEditorTests.scene)
        trail.add(Self.edits[0])
        let before = trail.template
        if case .declined = trail.add(Self.doublingBack) {} else { Issue.record("a line that doubles back was made") }
        #expect(trail.add(Self.overPaper) == .nothing)
        // A tap off the canvas has no shape to fill.
        if case .declined = trail.add(.fill(at: SIMD2(1e9, -1e9), color: SIMD3(0.5, 0, 0))) {} else { Issue.record("a fill off the canvas was made") }
        #expect(trail.template == before && trail.edits == [Self.edits[0]])
        // Nor does it spoil the way back.
        #expect(try trail.move(to: []) == EditTrail.Replay())
        #expect(trail.template == trail.base)
    }

    /// A list laid on a base it does not fit keeps what fits, and counts the rest.
    @Test func editsThatNoLongerFitAreLeftOutAndCounted() throws {
        var trail = EditTrail(base: TemplateEditorTests.scene)
        var list = Self.edits
        list.insert(Self.doublingBack, at: 1)
        list.append(Self.overPaper)
        let replay = try trail.move(to: list)
        #expect(replay.made == Self.edits.count && replay.left == 2 && replay.tooSmall == 0)
        #expect(trail.edits == list, "the edits that did nothing stay in the list")
        let expected = try Self.laid(Self.edits)
        #expect(trail.template == expected)
        // Laid again on another trail, the same list gives the same template and the same count.
        var again = EditTrail(base: TemplateEditorTests.scene)
        #expect(try again.move(to: list) == replay)
        #expect(again.template == trail.template && again.template.encoded() == trail.template.encoded())
    }

    /// A shape too small for a number is drawn as a stroke; the trail says so.
    @Test func aShapeTooSmallForANumberIsReported() throws {
        let tiny: [SIMD2<Float>] = [SIMD2(99.2, 24.2), SIMD2(100.8, 24.2), SIMD2(100.8, 25.8), SIMD2(99.2, 25.8)]
        var trail = EditTrail(base: TemplateEditorTests.scene)
        #expect(trail.add(.draw(points: tiny, closed: true)) == .made(tooSmall: true))
        var other = EditTrail(base: TemplateEditorTests.scene)
        #expect(try other.move(to: trail.edits).tooSmall == 1)
        #expect(other.template == trail.template)
    }

    /// Only the newest few templates are kept, however many edits there are.
    @Test func snapshotsAreBounded() throws {
        var trail = EditTrail(base: TemplateEditorTests.scene)
        var list: [Edit] = []
        for k in 0..<(EditTrail.snapshotsKept + 6) {
            let x = Float(12 + 10 * k)
            list.append(.draw(points: [SIMD2(x, 100), SIMD2(x + 4, 112)]))
        }
        for edit in list { trail.add(edit) }
        #expect(trail.edits.count == list.count)
        #expect(trail.snapshotCount <= EditTrail.snapshotsKept)
        // Further back than the kept ones, the way back is laid from the base.
        let back = Array(list.prefix(3))
        let replay = try trail.move(to: back)
        let backTo3 = try Self.laid(back)
        #expect(replay.made == 3 && trail.template == backTo3)
        #expect(trail.snapshotCount <= EditTrail.snapshotsKept)
        _ = try trail.move(to: list)
        #expect(trail.snapshotCount <= EditTrail.snapshotsKept)
        let everything = try Self.laid(list)
        #expect(trail.template == everything)
    }

    @Test func aCancelledMoveLeavesTheTrailAsItWas() throws {
        var trail = EditTrail(base: TemplateEditorTests.scene)
        trail.add(Self.edits[0])
        let before = trail
        do {
            try trail.move(to: Self.edits, cancel: CancellationCheck { true })
            Issue.record("a cancelled move went through")
        } catch is CancellationError {}
        #expect(trail.edits == before.edits && trail.template == before.template)
        #expect(try trail.move(to: Self.edits).made == Self.edits.count - 1)
    }

    /// A template without line art has nothing to edit: every edit is declined, none is lost.
    @Test func aClassicTemplateDeclinesEveryEdit() throws {
        var classic = TemplateEditorTests.scene
        classic.lineArt = nil
        var trail = EditTrail(base: classic)
        if case .declined = trail.add(Self.edits[0]) {} else { Issue.record("an edit was made without line art") }
        let replay = try trail.move(to: Self.edits)
        #expect(replay.made == 0 && replay.left == Self.edits.count && trail.template == classic)
    }
}
