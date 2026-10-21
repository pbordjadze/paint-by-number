import Foundation
import Testing
@testable import PaintCore

/// The Tool Guide's practice picture (`RefinePractice`): its photo and the templates the editor
/// makes of it.
@Suite("Refine practice")
struct RefinePracticeTests {
    static let photo = RefinePractice.photo()

    static func region(_ t: Template, _ x: Float, _ y: Float) throws -> Int {
        try #require(t.region(at: SIMD2(x, y) * Float(RefinePractice.height)))
    }

    @Test func thePhotoIsTheSameEveryTime() {
        #expect(Self.photo.width == RefinePractice.width && Self.photo.height == RefinePractice.height)
        #expect(RefinePractice.photo() == Self.photo)
    }

    /// Every outline lays: the picture's thirteen areas, each with a number, valid at the usual
    /// floor, and every paint used.
    @Test(arguments: RefinePractice.Scene.allCases)
    func theSceneIsATemplateEditsCanWorkOn(_ scene: RefinePractice.Scene) throws {
        let t = try RefinePractice.template(scene, photo: Self.photo)
        #expect(t.width == RefinePractice.width && t.height == RefinePractice.height)
        let report = t.validate(minLabelRadius: LabelSizing.minimumRadius)
        #expect(report.isValid, "\(report)")
        #expect(t.regions.count == 13)
        #expect(Set(t.regions.map(\.colorIndex)).count == t.palette.count, "every paint paints an area")
        #expect(try RefinePractice.template(scene, photo: Self.photo) == t)
        // The window's four panes are areas of their own, as Merge's page needs.
        let panes: [SIMD2<Float>] = [SIMD2(0.835, 0.845), SIMD2(0.865, 0.845), SIMD2(0.835, 0.875), SIMD2(0.865, 0.875)]
        #expect(try Set(panes.map { try Self.region(t, $0.x, $0.y) }).count == 4)
    }

    /// Painted, the moon, the roof and the sky are in their own paints; inked, the shapes keep the
    /// paint around them and only the hills' lines gave theirs.
    @Test func paintedGivesEachShapeItsColorAndInkedOnlyTheHills() throws {
        let painted = try RefinePractice.template(.painted, photo: Self.photo)
        let inked = try RefinePractice.template(.inked, photo: Self.photo)
        func paint(_ t: Template, _ p: SIMD2<Float>) throws -> UInt32 { t.regions[try Self.region(t, p.x, p.y)].colorIndex }
        let sky = SIMD2<Float>(0.3, 0.3), moon = SIMD2<Float>(1.04, 0.2), roof = SIMD2<Float>(0.88, 0.76), hill = SIMD2<Float>(0.6, 0.8)
        #expect(try Set([paint(painted, sky), paint(painted, moon), paint(painted, roof)]).count == 3)
        #expect(try paint(inked, moon) == paint(inked, sky))
        #expect(try paint(inked, roof) == paint(inked, hill))
        #expect(inked.palette.count == 3 && painted.palette.count > 6)
    }
}
