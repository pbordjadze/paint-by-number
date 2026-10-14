import Foundation
import Testing
@testable import MakingOf

/// The crew planned from the fixture's inputs, against what `making_of_pets.py` planned from them.
@Suite struct CrewPlanReplayTests {
    private let fixture: PlanFixture
    private let plan: CrewPlan

    init() throws {
        fixture = try PlanFixture.load()
        plan = try CrewPlan(fixture.inputs.crewInputs, spec: fixture.spec)
    }

    private func kind(_ step: Int) -> Stop.Kind {
        switch step {
        case -1: .appear
        case -2: .wave
        case -3: .exit
        default: .job(step)
        }
    }

    private func compare(_ d: inout Differences, _ what: String, _ line: Polyline?, _ points: [[Double]]?) {
        guard let line, let points else {
            d.equal("\(what) is a line", line == nil, points == nil)
            return
        }
        d.equal("\(what) points", line.points.count, points.count)
        for (j, (a, b)) in zip(line.points, points).enumerated() {
            d.close("\(what) point \(j) x", a.x, b[0], within: 1e-6)
            d.close("\(what) point \(j) y", a.y, b[1], within: 1e-6)
        }
    }

    @Test func stopsAndWalksReplay() {
        var d = Differences()
        d.equal("pets", plan.pets.map(\.id), fixture.plan.pets.map(\.id))
        for (pet, want) in zip(plan.pets, fixture.plan.pets) {
            let who = pet.id
            d.close("\(who) appears", pet.appear, want.appear, within: 1e-6)
            d.equal("\(who) stops", pet.stops.count, want.stops.count)
            for (n, (stop, ws)) in zip(pet.stops, want.stops).enumerated() {
                let at = "\(who) stop \(n)"
                d.equal("\(at) kind", stop.kind, kind(ws.step))
                d.close("\(at) arrives", stop.arrive, ws.arrive, within: 1e-6)
                d.close("\(at) leaves", stop.leave, ws.leave ?? .infinity, within: 1e-6)
                d.close("\(at) x", stop.x, ws.x, within: 1e-6)
                d.close("\(at) y", stop.y, ws.y, within: 1e-6)
                compare(&d, "\(at) line", stop.path, ws.path)
            }
            d.equal("\(who) walks", pet.walks.count, want.walks.count)
            for (n, (walk, ww)) in zip(pet.walks, want.walks).enumerated() {
                let at = "\(who) walk \(n)"
                d.close("\(at) leaves", walk.leave, ww.leave, within: 1e-6)
                d.close("\(at) arrives", walk.arrive, ww.arrive, within: 1e-6)
                d.close("\(at) length", walk.length, ww.length, within: 1e-6)
                d.close("\(at) distance", walk.distance, ww.distance, within: 1e-6)
                d.close("\(at) hurry", walk.hurry, ww.hurry, within: 1e-6)
                d.close("\(at) before", walk.before, ww.before, within: 1e-6)
                d.close("\(at) bend", walk.bend, ww.bend, within: 1e-6)
            }
        }
        #expect(d.count == 0, "\(d.report)")
    }

    @Test func visitsAndTracesReplay() {
        var d = Differences()
        d.equal("steps", plan.visits.count, fixture.plan.visits.count)
        for (k, (visits, want)) in zip(plan.visits, fixture.plan.visits).enumerated() {
            d.equal("step \(k) visits", visits.count, want.count)
            for (n, (v, w)) in zip(visits, want).enumerated() {
                d.close("step \(k) visit \(n) time", v.time, w[0], within: 1e-6)
                d.close("step \(k) visit \(n) x", v.x, w[1], within: 1e-6)
                d.close("step \(k) visit \(n) y", v.y, w[2], within: 1e-6)
            }
        }
        d.equal("traces", plan.traces.count, fixture.plan.traces.count)
        for (n, (trace, want)) in zip(plan.traces, fixture.plan.traces).enumerated() {
            d.equal("trace \(n) stroke", trace.stroke, want.stroke)
            d.close("trace \(n) start", trace.start, want.start, within: 1e-6)
            d.close("trace \(n) duration", trace.duration, want.duration, within: 1e-6)
            compare(&d, "trace \(n)", trace.line, want.points)
        }
        #expect(d.count == 0, "\(d.report)")
    }

    /// Positions within 1e-4 px and the rest within 1e-5; sprite rows exactly. A frame is a float
    /// cut down to a whole number, so it may differ by one where the float sits within 1e-6 of a
    /// whole number: there the two languages' last bits decide which side it falls on.
    @Test func statesReplay() throws {
        var d = Differences()
        var tolerated = 0
        #expect(fixture.states.pets.count == plan.pets.count)
        for (pet, rows) in zip(plan.pets, fixture.states.pets) {
            for (i, want) in rows.enumerated() {
                let at = "\(pet.id) at sample \(i)"
                let s = pet.state(at: Double(i) / Double(fixture.states.fps))
                d.equal("\(at) row", s.row.rawValue, want.row)
                d.close("\(at) x", s.x, want.x, within: 1e-4)
                d.close("\(at) y", s.y, want.y, within: 1e-4)
                d.close("\(at) lift", s.lift, want.lift, within: 1e-4)
                d.close("\(at) sx", s.scaleX, want.sx, within: 1e-5)
                d.close("\(at) sy", s.scaleY, want.sy, within: 1e-5)
                d.close("\(at) tilt", s.tilt, want.tilt, within: 1e-5)
                d.close("\(at) alpha", s.alpha, want.alpha, within: 1e-5)
                if s.frame != want.frame {
                    if abs(s.frameValue - s.frameValue.rounded()) <= 1e-6 && abs(s.frame - want.frame) == 1 {
                        tolerated += 1
                    } else {
                        d.equal("\(at) frame (\(s.frameValue))", s.frame, want.frame)
                    }
                }
            }
        }
        #expect(d.count == 0, "\(d.report)")
        #expect(tolerated <= 5, "\(tolerated) frames fell on the other side of a whole number")
    }

    @Test func fixtureCoversTheWholeShow() {
        let end = fixture.spec.timing.intro + 6 * fixture.spec.timing.step + fixture.spec.timing.outro
        #expect(fixture.states.fps == 30)
        #expect(fixture.states.pets.allSatisfy { $0.count == Int((end * 30).rounded()) + 1 })
        #expect(fixture.plan.pets.count == 3)
    }
}

/// What the show relies on, whatever the draws were.
@Suite struct CrewPlanInvariantTests {
    private let fixture: PlanFixture
    private let spec: ShowSpec
    private let inputs: CrewInputs
    private let plan: CrewPlan
    private let end: Double

    init() throws {
        fixture = try PlanFixture.load()
        spec = fixture.spec
        inputs = fixture.inputs.crewInputs
        plan = try CrewPlan(inputs, spec: spec)
        end = spec.timing.intro + 6 * spec.timing.step + spec.timing.outro
    }

    /// A walk bends to one side, so it is longer than the straight line its time was planned for,
    /// and the pet hurries to arrive on time: by (1 + 2/3 bend^2) at most, 1.7 % at the bend's
    /// most (0.16).
    @Test func noWalkToAJobIsFasterThanWalkingPace() {
        let h = inputs.petHeight
        let dt = 1.0 / 120
        for pet in plan.pets {
            let walkOff = pet.walks[pet.walks.count - 1].leave
            var previous = pet.state(at: 0)
            var fastest = 0.0
            var t = dt
            while t < walkOff {
                let s = pet.state(at: t)
                fastest = max(fastest, norm(s.x - previous.x, s.y - previous.y) / dt / h)
                previous = s
                t += dt
            }
            #expect(fastest <= spec.crew.walk * 1.02, "\(pet.id) walks \(fastest) heights a second")
            #expect(fastest > 0.5 * spec.crew.walk, "\(pet.id) never walks")
        }
        for pet in plan.pets {
            for (walk, stop) in zip(pet.walks, pet.stops.dropFirst()) {
                guard case .job = stop.kind else { continue }
                #expect(walk.hurry >= 1 && walk.hurry <= 1.02, "\(pet.id) hurries \(walk.hurry) times to a job")
            }
        }
    }

    /// Pets are 0.7 heights wide and one high; one is out of the way once it has faded.
    @Test func petsNeverOverlap() {
        struct Box {
            var x0, x1, y0, y1: Double

            func overlaps(_ o: Box) -> Bool {
                x0 < o.x1 && o.x0 < x1 && y0 < o.y1 && o.y0 < y1
            }
        }
        let h = inputs.petHeight
        for i in 0...Int(end * 30) {
            let t = Double(i) / 30
            var boxes: [Box] = []
            for pet in plan.pets {
                let s = pet.state(at: t)
                if s.alpha > 0.5 {
                    boxes.append(Box(x0: s.x - 0.35 * h, x1: s.x + 0.35 * h, y0: s.y - s.lift - h, y1: s.y - s.lift))
                }
            }
            for a in boxes.indices {
                for b in boxes.indices where b > a {
                    #expect(!boxes[a].overlaps(boxes[b]), "two pets overlap at \(t) s")
                }
            }
        }
    }

    @Test func everyPetLeavesTheFrameBeforeTheShowEnds() {
        let h = inputs.petHeight
        for pet in plan.pets {
            let exit = pet.lastStop
            #expect(exit.kind == .exit)
            #expect(exit.arrive < end - 0.3, "\(pet.id) is gone by \(exit.arrive) s")
            let outside = exit.x + 0.35 * h < 0 || exit.x - 0.35 * h > inputs.width
                || exit.y < 0 || exit.y - h > inputs.frameHeight
            #expect(outside, "\(pet.id) ends at \(exit.x), \(exit.y)")
            #expect(pet.state(at: end).alpha == 0)
        }
    }

    @Test func linesAreDrawnByWalking() {
        #expect(!plan.traces.isEmpty)
        let drawn = plan.pets.flatMap(\.stops).compactMap(\.path)
        for trace in plan.traces {
            #expect(drawn.contains(trace.line))
            #expect(trace.stroke < inputs.strokes.count)
            #expect(trace.start >= spec.timing.intro + Double(CrewPlan.inkStep) * spec.timing.step)
            #expect(trace.start + trace.duration <= spec.timing.intro + Double(CrewPlan.inkStep + 1) * spec.timing.step)
        }
    }

    @Test func jobsAreSharedAcrossThePicture() {
        for k in 0..<6 {
            let jobs = plan.pets.flatMap(\.stops).filter { $0.kind == .job(k) }
            #expect(jobs.count >= plan.pets.count, "step \(k + 1) has \(jobs.count) jobs")
            #expect(Set(jobs.map { Int($0.x / inputs.width * 3) }).count >= 2, "step \(k + 1) is worked in one place")
        }
    }

    @Test func everyStepSpreadsFromWhereThePetsWork() {
        #expect(plan.visits.count == 6)
        #expect(plan.visits.allSatisfy { !$0.isEmpty })
        for (k, visits) in plan.visits.enumerated() {
            let start = spec.timing.intro + Double(k) * spec.timing.step
            #expect(visits.allSatisfy { $0.time >= start && $0.time <= start + spec.timing.step })
        }
    }
}

@Suite struct CrewPlanContractTests {
    private func inputs(_ edit: (inout CrewInputs) -> Void = { _ in }) throws -> CrewInputs {
        var inputs = try PlanFixture.load().inputs.crewInputs
        edit(&inputs)
        return inputs
    }

    @Test func samePlanTwice() throws {
        let spec = try PlanFixture.load().spec
        let a = try CrewPlan(inputs(), spec: spec)
        let b = try CrewPlan(inputs(), spec: spec)
        #expect(a == b)
        let other = try CrewPlan(inputs { $0.seed += 1 }, spec: spec)
        #expect(other != a)
        #expect(other.pets.map(\.id) == a.pets.map(\.id))
    }

    @Test func aShowWithNothingToDoStillPlays() throws {
        let spec = try PlanFixture.load().spec
        let bare = try CrewPlan(inputs { $0.candidates = Array(repeating: [], count: 6); $0.strokes = [] }, spec: spec)
        #expect(bare.traces.isEmpty)
        #expect(bare.visits.count == 6)
        for pet in bare.pets {
            #expect(pet.stops.map(\.kind) == [.appear, .wave, .exit])
            #expect(pet.state(at: -1).alpha == 0)
            #expect(pet.state(at: 5).row == .idle || pet.state(at: 5).row == .review)
            #expect(pet.state(at: 100).alpha == 0)
        }
    }

    @Test func badInputsThrow() throws {
        let spec = try PlanFixture.load().spec
        let bad: [(String, (inout CrewInputs) -> Void)] = [
            ("no pets", { $0.pets = [] }),
            ("five steps of spots", { $0.candidates.removeLast() }),
            ("a flat picture", { $0.height = 0 }),
            ("a pet of no height", { $0.petHeight = 0 }),
            ("a step of no time", { $0.step = 0 }),
            ("a spot at infinity", { $0.candidates[0].append(Point(.infinity, 1)) }),
            ("a stroke that is not a number", { $0.strokes[0][0] = Point(.nan, 1) }),
            ("an enormous crew", { $0.pets = Array(repeating: $0.pets[0], count: 21) }),
        ]
        for (what, edit) in bad {
            #expect(throws: CrewInputsError.self, "\(what) should throw") { try CrewPlan(inputs(edit), spec: spec) }
        }
    }

    @Test func stateIsAFunctionOfTheTime() throws {
        let plan = try CrewPlan(inputs(), spec: PlanFixture.load().spec)
        let times = (0..<400).map { Double(($0 * 7919) % 2000) / 100 }       // out of order
        for pet in plan.pets {
            let first = times.map { pet.state(at: $0) }
            let again = times.reversed().map { pet.state(at: $0) }
            #expect(first == again.reversed())
        }
    }
}
