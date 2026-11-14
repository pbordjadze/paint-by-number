import Testing
@testable import PaintByNumber

/// Refine's state without its screen (`RefineModel`): which tool is the finger's as tools and
/// groups are picked, and what Undo takes back first.
@MainActor
struct RefineModelTests {
    /// A tool picked keeps the one before it for the Pencil, and a group comes back on the tool
    /// last picked in it, a new one on its first.
    @Test func aGroupComesBackOnItsLastTool() {
        let refine = RefineModel(model: CreateModel(), practice: nil)
        #expect(refine.tool == .pen)
        #expect(refine.group == .ink)
        refine.pick(.eraser)
        #expect(refine.tool == .eraser)
        #expect(refine.previousTool == .pen)
        refine.choose(.paint)
        #expect(refine.tool == .bucket)
        #expect(refine.group == .paint)
        refine.choose(.ink)
        #expect(refine.tool == .eraser)
        #expect(refine.group == .ink)
    }

    /// Undo while a curve waits to be bent takes the curve back and leaves the flow's history
    /// alone.
    @Test func undoTakesBackACurveWaitingToBeBent() {
        let refine = RefineModel(model: CreateModel(), practice: nil)
        refine.curve = (SIMD2<Float>(0.1, 0.1), SIMD2<Float>(0.5, 0.5))
        refine.trace = [SIMD2<Float>(0.2, 0.2)]
        refine.undo()
        #expect(refine.curve == nil)
        #expect(refine.trace == nil)
    }
}
