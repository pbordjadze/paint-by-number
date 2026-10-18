import Foundation
import Testing
@testable import MakingOf

/// The same hand-made cases as `SpriteDrawTests` in `tools/tests/test_making_of_show.py`.
@Suite struct SpritesTests {
    private let metrics = SpriteMetrics(top: 40, foot: 180, cx: 95)
    private let crew: ShowSpec.Crew

    init() throws {
        crew = try ShowSpec(json: shippedSpecData()).crew
    }

    private func state(
        x: Double = 100, y: Double = 200, lift: Double = 0, row: Row = .right, frame: Double = 3, sx: Double = 1,
        sy: Double = 1, tilt: Double = -4, alpha: Double = 1
    ) -> PetState {
        PetState(x: x, y: y, lift: lift, row: row, scaleX: sx, scaleY: sy, tilt: tilt, alpha: alpha, frameValue: frame)
    }

    private func draw(_ state: PetState? = nil, since: Double = 1, fade: Double = 1, height: Double = 70) -> SpriteDraw? {
        SpriteDraw.make(
            id: "a", state: state ?? self.state(), since: since, fade: fade, height: height, pictureHeight: 400,
            metrics: metrics, crew: crew)
    }

    @Test func theRotationIsClockwiseWhereTheTiltIsPillows() throws {
        // facing right leans forward at -4 (Pillow turns counter-clockwise); SwiftUI's rotationEffect wants +4
        let right = try #require(draw()), left = try #require(draw(state(row: .left, tilt: 4))), upright = try #require(draw(state(tilt: 0)))
        #expect(right.rotation == 4 && left.rotation == -4 && upright.rotation == 0)
    }

    @Test func theTiltsSignIsTheFixturesAndTheSpritesTheReverse() throws {
        // the plan fixture's tilt, facing right at speed: negative; the sprite turns the other way
        let fixture = try PlanFixture.load()
        let plan = try CrewPlan(fixture.inputs.crewInputs, spec: fixture.spec)
        var leaning = 0
        for pet in plan.pets {
            for i in stride(from: 0, to: 600, by: 3) {
                let t = Double(i) / 30
                let s = pet.state(at: t)
                guard let d = SpriteDraw.make(
                    id: pet.id, state: s, since: t - pet.appear, fade: 1, height: fixture.inputs.petHeight,
                    pictureHeight: fixture.inputs.size[1], metrics: metrics, crew: fixture.spec.crew)
                else { continue }
                #expect(d.rotation == -s.tilt)
                if s.row == .right && s.tilt < -1 { #expect(d.rotation > 1); leaning += 1 }
                if s.row == .left && s.tilt > 1 { #expect(d.rotation < -1); leaning += 1 }
            }
        }
        #expect(leaning > 0)
    }

    @Test func theCellIsScaledSoItsBodyIsTheHeight() throws {
        let d = try #require(draw())
        let depth = 0.9 + 0.16 * 0.5
        #expect(abs(d.scaleX - 70 * depth / 140) < 1e-15)
        #expect(d.scaleX == d.scaleY)
        // one lower in the picture is a little bigger; below it, as big as it gets
        let low = try #require(draw(state(y: 380))), bottom = try #require(draw(state(y: 400)))
        let below = try #require(draw(state(y: 900))), above = try #require(draw(state(y: -50)))
        #expect(low.scaleX > d.scaleX && below.scaleX == bottom.scaleX && above.scaleX < d.scaleX)
    }

    @Test func squashScalesEachAxisAndLiftRaisesTheSpriteNotTheShadow() throws {
        let air = try #require(draw(state(lift: 6, row: .idle, frame: 2, sx: 1.1, sy: 0.9, tilt: 0)))
        #expect(abs(air.scaleX / air.scaleY - 1.1 / 0.9) < 1e-12)
        #expect(air.x == 100 && air.y == 194)
        #expect(air.shadow.x == 100 && air.shadow.y == 200)
        let ground = try #require(draw())
        #expect(air.shadow.halfWidth < ground.shadow.halfWidth && air.shadow.alpha < ground.shadow.alpha)
        #expect(abs(ground.shadow.height - ground.shadow.halfWidth * 0.42) < 1e-12)
    }

    @Test func aFrameWrapsToItsRow() throws {
        for (row, count) in [(Row.idle, 6), (.right, 8), (.left, 8), (.wave, 4), (.busy, 6), (.review, 6)] {
            #expect(row.frameCount == count)
            let d = try #require(draw(state(row: row, frame: 13)))
            #expect(d.frame == 13 % count)
        }
        let before = try #require(draw(state(row: .wave, frame: -1)))
        #expect(before.frame == 3)
    }

    @Test func rowsAreTheSheetsRows() {
        // the create-pet v2 contract: idle, right, left, wave, then busy and review after the unused rows
        #expect([Row.idle, .right, .left, .wave, .busy, .review].map(\.atlasRow) == [0, 1, 2, 3, 7, 8])
    }

    @Test func itFadesInPopsAndIsNotDrawnWhenItCannotBeSeen() throws {
        #expect(draw(since: -0.1) == nil)
        #expect(draw(since: 0) == nil)
        #expect(draw(fade: 0) == nil)
        #expect(draw(state(alpha: 0)) == nil)
        let half = try #require(draw(since: 0.09)), popping = try #require(draw(since: 0.1)), settled = try #require(draw(since: 2))
        #expect(abs(half.alpha - 0.5) < 1e-12)
        #expect(popping.scaleX > settled.scaleX)            // swelling as it appears
        #expect(settled.alpha == 1)
        #expect(abs(try #require(draw(fade: 0.25)).alpha - 0.25) < 1e-12)
    }

    @Test func metricsAreReadStrictly() throws {
        let table = try SpriteMetrics.table(json: shippedMetricsData())
        let spec = try ShowSpec(json: shippedSpecData())
        #expect(table.count == 25 && Set(spec.crew.pets).isSubset(of: table.keys))
        for (id, m) in table {
            #expect(0 <= m.top && m.top < m.foot && m.foot < SpriteMetrics.cell.height && 0 <= m.cx && m.cx < SpriteMetrics.cell.width, "\(id)")
        }
        #expect(table["dinotopia"] == SpriteMetrics(top: 6, foot: 201, cx: 90.12758642643408))

        func decode(_ json: String) throws -> [String: SpriteMetrics] { try SpriteMetrics.table(json: Data(json.utf8)) }
        let ok = #"{"version":1,"cell":[192,208],"pets":{"a":{"top":10,"foot":100,"cx":90.5}}}"#
        #expect(try decode(ok) == ["a": SpriteMetrics(top: 10, foot: 100, cx: 90.5)])
        for bad in [
            ok.replacingOccurrences(of: #""version":1"#, with: #""version":2"#),
            ok.replacingOccurrences(of: "[192,208]", with: "[128,128]"),
            ok.replacingOccurrences(of: #""top":10"#, with: #""top":100"#),
            ok.replacingOccurrences(of: #""foot":100"#, with: #""foot":208"#),
            ok.replacingOccurrences(of: #""cx":90.5"#, with: #""cx":192"#),
            ok.replacingOccurrences(of: #""top":10"#, with: #""top":-1"#),
            #"{"version":1,"cell":[192,208]}"#, "not json",
        ] {
            #expect(throws: (any Error).self, "\(bad)") { try decode(bad) }
        }
    }
}
