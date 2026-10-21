import Foundation
import PaintCore
import Testing
@testable import PaintByNumber

/// What Refine's queue is made of: the changes to the generator's inputs, the history Undo steps
/// through, and what the painter is told.
struct RefineEditsTests {
    static let found: [SIMD2<Float>] = [SIMD2(0.1, 0.1), SIMD2(0.3, 0.1), SIMD2(0.3, 0.15), SIMD2(0.1, 0.15)]

    /// A change lands on the refinements as they are, whatever came before it: a marked line
    /// comes and goes, a found line is turned off and on again (found a little differently the
    /// second time, as when a painting is regenerated).
    @Test func changesLandOnTheRefinementsAsTheyAre() {
        var refinements = TemplateRefinements()
        refinements.edits = [.draw(points: [SIMD2(1, 2), SIMD2(3, 4)], closed: false)]

        let marked = TemplateRefinements.textLine(from: SIMD2(0.1, 0.1), to: SIMD2(0.4, 0.2))
        RefineChange.markText(marked).apply(to: &refinements)
        #expect(refinements.addedText == [marked])
        RefineChange.unmarkText(marked).apply(to: &refinements)
        RefineChange.unmarkText(marked).apply(to: &refinements)
        #expect(refinements.addedText.isEmpty)

        RefineChange.toggleFound(Self.found).apply(to: &refinements)
        #expect(refinements.hiddenText == [Self.found])
        RefineChange.toggleFound(Self.found.map { $0 + SIMD2(0.004, 0.001) }).apply(to: &refinements)
        #expect(refinements.hiddenText.isEmpty)
        #expect(refinements.edits.count == 1, "A change to the generator's inputs touched the edits")
    }

    /// Undo goes back a step at a time, and a new change leaves nothing to redo; the steps kept
    /// are bounded, the newest ones.
    @Test func theHistoryIsBounded() {
        var history = RefineHistory()
        var refinements = TemplateRefinements()
        for k in 0..<(RefineHistory.limit + 20) {
            history.push(refinements)
            refinements.edits.append(.eraseLine(at: SIMD2(Float(k), 0), reach: 8))
        }
        #expect(history.undo.count == RefineHistory.limit)
        #expect(history.undo.last?.edits.count == RefineHistory.limit + 19)
        #expect(history.undo.first?.edits.count == 20)
        history.redo = [refinements]
        history.push(refinements)
        #expect(history.redo.isEmpty)
        #expect(RefineHistory(opening: refinements).opening == refinements)
    }

    /// Each kind of declined edit has its own words, and a count of edits left out reads right in
    /// the singular and the plural.
    @Test func notesSayWhatHappened() {
        #expect(RefineNote.Kind(declined: .draw(points: [])) == .notDrawn)
        #expect(RefineNote.Kind(declined: .erase(path: [], radius: 1)) == .notErased)
        #expect(RefineNote.Kind(declined: .eraseLine(at: .zero)) == .notErased)
        #expect(RefineNote.Kind(declined: .fill(at: .zero, color: .zero)) == .notFilled)
        #expect(RefineNote.Kind(declined: .split(points: [])) == .notSplit)
        #expect(RefineNote.Kind(declined: .cellEdge(points: [])) == .notDivided)
        #expect(RefineNote.Kind(declined: .paintArea(at: .zero, color: .zero)) == .notRecolored)
        let kinds: [RefineNote.Kind] = [.notDrawn, .notErased, .notFilled, .notSplit, .notDivided, .tooSmall, .left(1), .left(3)]
        let texts = kinds.map { RefineNote(kind: $0).text }
        #expect(texts.allSatisfy { !$0.isEmpty } && Set(texts).count == kinds.count)
        #expect(RefineNote(kind: .tooSmall).text == "That shape is too small for a number.")
        #expect(RefineNote(kind: .left(1)).text.hasPrefix("1 edit no longer fits"))
        #expect(RefineNote(kind: .left(3)).text.hasPrefix("3 edits no longer fit"))
        #expect(RefineNote(kind: .tooSmall) != RefineNote(kind: .tooSmall), "Two notes are one note")
    }
}
