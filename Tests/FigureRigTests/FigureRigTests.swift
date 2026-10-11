import Foundation
import Testing
@testable import FigureRig

private func scene(seed: UInt64 = 1, heading: Double = 0, timeline: String? = nil) throws -> FigureScene {
    let end = Point(300, 300) + headingVector(heading) * 90
    let actions = timeline ?? """
        {"do":"walk","path":"brook","to":1},
        {"do":"turn","heading":90},
        {"do":"cast","duration":1.2},{"do":"idle","duration":0.6}
        """
    return try JSONDecoder().decode(FigureScene.self, from: Data("""
        {"version":1,"seed":\(seed),"canvas":{"width":1100,"height":825},"display":"ipad13",
         "figureHeight":50,"paths":{"brook":"M300 300 L\(end.x) \(end.y)"},
         "actors":[{"id":"w1","at":{"path":"brook","t":0},"timeline":[\(actions)]}],
         "card":{"authors":"Eduardo Gastal and Manuel Oliveira","year":2011,
                 "title":"Domain Transform for Edge-Aware Image and Video Processing","at":0.4},"tail":0.5}
        """.utf8))
}
private func encoded<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return try encoder.encode(value)
}
private var repository: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}

@Suite("Figure engine v0")
struct FigureRigTests {
    @Test func committedBaselineDecodesAndPassesChecks() throws {
        let data = try Data(contentsOf: repository.appendingPathComponent("factory/specs/baseline.json"))
        let baseline = try JSONDecoder().decode(FigureSpec.self, from: data)
        let hero = try JSONDecoder().decode(FigureScene.self, from: Data(contentsOf: repository.appendingPathComponent("factory/scenes/hero.json")))
        let engine = try FigureEngine(spec: baseline, scene: hero)
        #expect(engine.checks((0..<engine.frameCount).map { engine.frame($0) }).allSatisfy { $0.pass })
    }

    @Test func defaultsAndPartialSpecs() throws {
        let decoder = JSONDecoder()
        let empty = try decoder.decode(FigureSpec.self, from: Data("{}".utf8))
        #expect(try encoded(empty) == encoded(FigureSpec()))
        let partial = try decoder.decode(FigureSpec.self, from: Data(#"{"ink":{"wobble":0},"figure":{"accent":null}}"#.utf8))
        #expect(partial.ink.wobble == 0); #expect(partial.ink.width == 0.035)
        #expect(partial.figure.accent == nil); #expect(partial.magic.colors == ["#C9A227", "#6E9A5B"])
    }

    @Test(arguments: [
        (#"{"figur":{}}"#, "figur"), (#"{"figure":{"headsize":0.16}}"#, "figure.headsize"),
        (#"{"motion":{"cadence":7}}"#, "motion.cadence"), (#"{"motion":{"headingSteps":4}}"#, "motion.headingSteps"),
        (#"{"ink":{"color":"brown"}}"#, "ink.color"), (#"{"magic":{"colors":[]}}"#, "magic.colors"),
        (#"{"figure":{"hands":"dott"}}"#, "figure.hands"), (#"{"card":{"size":10}}"#, "card.size"),
        (#"{"version":3}"#, "version"), (#"{"view":{"depth":null}}"#, "view.depth")
    ])
    func invalidSpecNamesItsField(input: String, field: String) {
        do {
            _ = try JSONDecoder().decode(FigureSpec.self, from: Data(input.utf8))
            Issue.record("accepted invalid \(field)")
        } catch { #expect(String(describing: error).contains(field)) }
    }

    @Test(arguments: [("M 0 0", "0.0"), ("M 0 0 L 0 0", "0.0"),
                      ("M 0 0 L 0.0000000001 0", "1e-10")])
    func refusedWalkPathNamesThePathAndLength(data: String, length: String) throws {
        var s = try scene()
        s.paths["brook"] = data
        do {
            _ = try FigureEngine(spec: FigureSpec(), scene: s)
            Issue.record("accepted an unwalkable path")
        } catch {
            #expect(String(describing: error) == "paths.brook: path: length \(length); expected a nonzero length greater than 1e-9")
        }
    }

    @Test func deterministicFramesMotionAndChecks() throws {
        let spec = FigureSpec(), s = try scene()
        let first = try FigureEngine(spec: spec, scene: s), second = try FigureEngine(spec: spec, scene: s)
        let changed = try FigureEngine(spec: spec, scene: scene(seed: 2))
        var frames: [FigureFrame] = [], other: [FigureFrame] = []
        for index in [0, 7, 29, 63, 100] {
            let a = first.frame(index), b = second.frame(index)
            #expect(FigureSVG.write(a, scene: s) == FigureSVG.write(b, scene: s))
            #expect(try encoded(a.actors) == encoded(b.actors))
            #expect(FigureSVG.write(a, scene: s) != FigureSVG.write(changed.frame(index), scene: s))
            frames.append(a); other.append(b)
        }
        #expect(try encoded(first.checks(frames)) == encoded(second.checks(other)))
        // Request order must not be hidden simulation state.
        #expect(FigureSVG.write(first.frame(7), scene: s) == FigureSVG.write(second.frame(7), scene: s))
    }

    @Test func plantedFeetStayStill() throws {
        let engine = try FigureEngine(spec: FigureSpec(), scene: scene())
        let walk = engine.actions[0]
        var contacts: [String: [Int: Point]] = [:], plantedSamples = 0
        for i in 0...Int(walk.end * 240) {
            let pose = engine.rig.pose(at: Double(i) / 240, quantized: false)
            for side in ["left", "right"] where pose.planted[side] == true {
                let point = pose.joints[side + "Ankle"]!, contact = pose.contacts[side]!
                if let old = contacts[side]?[contact] { #expect((point - old).length <= 1e-6); plantedSamples += 1 }
                contacts[side, default: [:]][contact] = point
            }
        }
        #expect(plantedSamples > 100)
    }

    @Test(arguments: stride(from: 0.0, to: 360.0, by: 45).map { $0 })
    func kneesBendForward(heading: Double) throws {
        let engine = try FigureEngine(spec: FigureSpec(), scene: scene(heading: heading, timeline: #"{"do":"idle","duration":1}"#))
        let pose = engine.rig.pose(at: 0, quantized: false), forward = Vector3(headingVector(heading), 0)
        for side in ["left", "right"] {
            let hip = pose.world[side + "Hip"]!, ankle = pose.world[side + "Ankle"]!, knee = pose.world[side + "Knee"]!
            let axis = (ankle - hip).unit, offset = knee - hip
            #expect((offset - axis * offset.dot(axis)).dot(forward) > 0)
            #expect(abs((knee - hip).length - engine.spec.figure.thigh * engine.rig.unit) < 1e-8)
            #expect(abs((ankle - knee).length - engine.spec.figure.shin * engine.rig.unit) < 1e-8)
        }
        #expect(pose.ikClamps == 0)
    }

    @Test func standingHeightIsNormalized() throws {
        var spec = FigureSpec()
        for height in [25.0, 50, 100] {
            for headSize in [0.10, 0.16, 0.26] {
                spec.figure.headSize = headSize
                var s = try scene(timeline: #"{"do":"idle","duration":1}"#); s.figureHeight = height
                let engine = try FigureEngine(spec: spec, scene: s), pose = engine.rig.pose(at: 0, quantized: false)
                let crown = pose.world["head"]!.z + headSize * engine.rig.unit / 2
                #expect(abs(crown - height) < 1e-10)
                #expect(abs(pose.origin.y - (pose.joints["head"]!.y - headSize * engine.rig.unit / 2) - height) < 1e-10)
            }
        }
    }

    @Test func headingStepsOnlyChangesDrawing() throws {
        var spec = FigureSpec(); spec.motion.headingSteps = 8
        let s = try scene(heading: 23)
        let snapped = try FigureEngine(spec: spec, scene: s)
        spec.motion.headingSteps = 0
        let unsnapped = try FigureEngine(spec: spec, scene: s)
        for i in 0..<snapped.frameCount {
            let a = snapped.pose(at: Double(i) / 24), b = unsnapped.pose(at: Double(i) / 24)
            #expect(abs(a.drawnHeading / 45 - (a.drawnHeading / 45).rounded()) < 1e-10)
            #expect(a.joints["leftAnkle"] == b.joints["leftAnkle"])
            #expect(a.joints["rightAnkle"] == b.joints["rightAnkle"])
        }
    }

    @Test func projectionLeavesTheMapPositionUnsquashed() throws {
        var spec = FigureSpec(); spec.view.depth = 0
        let engine = try FigureEngine(spec: spec, scene: scene(timeline: #"{"do":"idle","duration":1}"#))
        let pose = engine.pose(at: 0)
        #expect(pose.origin == Point(300, 300))
        #expect(pose.joints["head"]!.y > 200)
        #expect(abs(pose.joints["leftAnkle"]!.y - 300) < 1e-9)
    }

    @Test func posesOnTwosButParticlesAndCardUseFrameTime() throws {
        let engine = try FigureEngine(spec: FigureSpec(), scene: scene())
        #expect(try encoded(engine.frame(10).actors) == encoded(engine.frame(11).actors))
        #expect(engine.frame(10).time != engine.frame(11).time)
        #expect(engine.card.opacity(at: engine.frame(10).time) != engine.card.opacity(at: engine.frame(11).time))
        let release = engine.actions.first(where: { $0.kind == "cast" })!.release!
        let a = engine.magic.draw(at: release + 0.2), b = engine.magic.draw(at: release + 0.2 + 1 / 24)
        #expect(a.alive >= 24); #expect(try encoded(a.shapes) != encoded(b.shapes))
    }

    @Test func turnSpeedAndCastRelease() throws {
        let engine = try FigureEngine(spec: FigureSpec(), scene: scene())
        let turn = engine.actions.first(where: { $0.kind == "turn" })!
        var last = engine.rig.pose(at: turn.start, quantized: false)
        for i in 1...100 {
            let pose = engine.rig.pose(at: turn.start + (turn.end - turn.start) * Double(i) / 100, quantized: false)
            #expect(abs(headingDelta(last.heading, pose.heading)) / ((turn.end - turn.start) / 100) <= engine.spec.motion.turnRate + 1e-6)
            last = pose
        }
        let cast = engine.actions.first(where: { $0.kind == "cast" })!
        #expect(abs(cast.windUp! - cast.start - 1.2 * 0.25) < 1e-10)
        let pose = engine.rig.pose(at: cast.release!, quantized: false)
        #expect(pose.handsOpen); #expect(pose.joints["leftHand"]!.y < pose.joints["leftShoulder"]!.y)
        let burst = engine.magic.particles.filter { $0.birth == cast.release }
        #expect(burst.count == 24)
        #expect(burst.contains { ($0.start - pose.joints["leftHand"]!).length < 1 })
        #expect(burst.contains { ($0.start - pose.joints["rightHand"]!).length < 1 })
    }

    @Test func trailRateUsesFixedEmissionTimes() throws {
        for rate in [0.0, 2, 4, 8, 20] {
            var spec = FigureSpec(); spec.magic.trail = rate; spec.magic.burst = 0
            let engine = try FigureEngine(spec: spec, scene: scene()), walk = engine.actions[0]
            let emissions = engine.magic.particles
            #expect(emissions.count == max(0, Int(ceil((walk.end - walk.start) * rate)) - 1))
            for (i, particle) in emissions.enumerated() {
                #expect(abs(particle.birth - walk.start - Double(i + 1) / rate) < 1e-10)
                let pose = engine.rig.pose(at: particle.birth, quantized: false)
                #expect((particle.start - pose.joints[pose.swingFoot + "Ankle"]!).length <= particle.size * 0.1 / sqrt(2) + 1e-9)
            }
        }
    }

    @Test func magicLengthsNormalizeWhileSpeedUsesFigureHeights() throws {
        let s = try scene(timeline: #"{"do":"cast","duration":1.2}"#)
        var spec = FigureSpec(); spec.magic.trail = 0
        let a = try FigureEngine(spec: spec, scene: s)
        spec.figure.headSize = 0.26
        let b = try FigureEngine(spec: spec, scene: s)
        let first = try #require(a.magic.particles.first), second = try #require(b.magic.particles.first)
        #expect(abs(first.size / a.rig.unit - second.size / b.rig.unit) < 1e-10)
        #expect(first.velocity == second.velocity)
    }

    @Test func inkBoilAndUniformStroke() throws {
        var spec = FigureSpec(); spec.ink.boilFps = 0
        let engine = try FigureEngine(spec: spec, scene: scene())
        let pose = engine.pose(at: 0)
        #expect(try encoded(engine.ink.draw(pose, at: 0).shapes) == encoded(engine.ink.draw(pose, at: 10).shapes))
        spec.ink.boilFps = 8; spec.ink.pressure = 0; spec.ink.taper = 0
        let boiling = try FigureEngine(spec: spec, scene: scene())
        #expect(try encoded(boiling.ink.draw(pose, at: 0).shapes) != encoded(boiling.ink.draw(pose, at: 1).shapes))
        #expect(abs(boiling.ink.draw(pose, at: 0).minimumWidth - spec.ink.width * boiling.rig.unit) < 1e-10)
    }

    @Test func cardFitsAndHasAFullHold() throws {
        var spec = FigureSpec(); spec.card.backdrop = "paper"
        for position in ["top", "bottom", "topLeading", "bottomLeading"] {
            spec.card.position = position
            let engine = try FigureEngine(spec: spec, scene: scene()), card = engine.card
            #expect(card.titleLines.count <= 2)
            #expect(card.maximum.x - card.minimum.x <= engine.scene.canvas.width * 0.6 + spec.card.size / engine.scene.pointsPerUnit + 1e-9)
            #expect(card.hold >= 2); #expect(card.hold >= spec.card.holdBase + spec.card.perWord * Double(engine.scene.card.words))
            #expect(card.opacity(at: card.holdStart) == 1); #expect(card.opacity(at: card.end) == 0)
            #expect(card.minimum.x >= 0 && card.maximum.x <= 1100 && card.minimum.y >= 0 && card.maximum.y <= 825)
        }
    }

    @Test func svgPathsAndLengthSampling() throws {
        let line = try ArcPath("M 0,0 30,0 L 30,40")
        #expect(abs(line.length - 70) < 1e-10)
        #expect((line.sample(0.5).point - Point(30, 5)).length < 1e-10)
        let curve = try ArcPath("M0 0 Q50 100 100 0 C150 -100 200 100 250 0 Z")
        #expect(curve.points.first == curve.points.last); #expect(curve.length > 500)
        #expect(throws: FigureInputError.self) { try ArcPath("M0 0 l10 10") }
        #expect(throws: FigureInputError.self) { try ArcPath("M0 0 L") }
        #expect(svgNumber(-0.001) == "0.00"); #expect(svgNumber(1.234) == "1.23")
        #expect(xmlEscape("a&\"b") == "a&amp;&quot;b")
    }

    @Test func baselineGeometryChecksPassAndBadGeometryFails() throws {
        let engine = try FigureEngine(spec: FigureSpec(), scene: scene())
        let checks = engine.checks((0..<engine.frameCount).map { engine.frame($0) })
        #expect(checks.allSatisfy { $0.pass })
        for i in 0..<engine.frameCount {
            let pose = engine.pose(at: Double(i) / 24)
            #expect(pose.ikClamps == 0, "\(pose.action) at \(pose.poseTime)")
        }
        var s = try scene(); s.figureHeight = 200
        let oversized = try FigureEngine(spec: FigureSpec(), scene: s)
        #expect(oversized.checks([oversized.frame(0)]).first { $0.name == "figureHeight" }?.pass == false)
    }
}
