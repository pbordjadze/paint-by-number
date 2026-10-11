import Foundation
import Testing
@testable import FigureRig

private func reviewScene(heading: Double = 0, slope: Double? = nil, walking: Bool = false) throws -> FigureScene {
    let tangent = headingVector(heading + (slope ?? 0)), end = Point(300, 400) + tangent * 90
    var scene = try JSONDecoder().decode(FigureScene.self, from: Data("""
        {"canvas":{"width":1100,"height":825},"figureHeight":50,
         "paths":{"p":"M300 400 L\(end.x) \(end.y)"},
         "actors":[{"id":"w","at":{"path":"p","t":0},"timeline":[
         {"do":"\(walking ? "walk" : "cast")",\(walking ? "\"path\":\"p\",\"to\":1" : "\"duration\":1.2")}]}],
         "card":{"authors":"A","year":2011,"title":"B","at":0}}
        """.utf8))
    if slope != nil {
        scene.actors[0].timeline.insert(try JSONDecoder().decode(FigureScene.Action.self,
            from: Data("{\"do\":\"turn\",\"heading\":\(heading)}".utf8)), at: 0)
    }
    return scene
}

@Suite("v0 review regressions")
struct ReviewFixTests {
    @Test func legReachAcrossStepsDepthsSlopesAndHeadings() throws {
        var failures: [String] = []
        for step in [0.08, 0.12, 0.18, 0.26, 0.32, 0.4] {
            for depth in [0.0, 0.1, 0.25, 0.5, 0.75, 1.0] {
                for slope in [-30.0, -15, 0, 15, 30] {
                    for heading in stride(from: 0.0, to: 360, by: 22.5) {
                        var spec = FigureSpec(); spec.motion.step = step; spec.view.depth = depth
                        let rig = try Rig(spec: spec, scene: reviewScene(heading: heading, slope: slope, walking: true))
                        for i in 0...120 {
                            let pose = rig.pose(at: rig.duration * Double(i) / 120, quantized: false)
                            if pose.ikClamps != 0 {
                                failures.append("step \(step), depth \(depth), slope \(slope), heading \(heading), t \(pose.poseTime)")
                                break
                            }
                        }
                    }
                }
            }
        }
        #expect(failures.isEmpty, "\(failures.count) failed combinations; \(failures.prefix(5))")
        // All headings as path directions, including straight toward the viewer.
        for heading in stride(from: 0.0, to: 360, by: 22.5) {
            var spec = FigureSpec(); spec.motion.step = 0.4
            let rig = try Rig(spec: spec, scene: reviewScene(heading: heading, walking: true))
            #expect((0...240).allSatisfy { rig.pose(at: rig.duration * Double($0) / 240, quantized: false).ikClamps == 0 })
        }
        var s = try reviewScene(walking: true)
        s.paths["p"] = "M80 610 C300 520 520 700 760 600"; s.figureHeight = 70
        s.actors[0].timeline[0].to = 0.6
        let example = try Rig(spec: FigureSpec(), scene: s)
        #expect((0...500).allSatisfy { example.pose(at: example.duration * Double($0) / 500, quantized: false).ikClamps == 0 })
    }

    @Test func reversedJointsFailGeometryChecks() throws {
        let s = try reviewScene(), engine = try FigureEngine(spec: FigureSpec(), scene: s)
        let frame = engine.frame(0)
        for (name, check) in [("Knee", "kneeReverse"), ("Elbow", "elbowReverse")] {
            var pose = frame.actors[0]
            let root = pose.world["left" + (name == "Knee" ? "Hip" : "Shoulder")]!
            let end = pose.world["left" + (name == "Knee" ? "Ankle" : "Hand")]!
            let axis = (end - root).unit, joint = pose.world["left" + name]!
            let projection = root + axis * (joint - root).dot(axis)
            pose.world["left" + name] = projection * 2 - joint
            let bad = FigureFrame(time: frame.time, actors: [pose], shapes: frame.shapes,
                                  particles: frame.particles, minimumInkWidth: frame.minimumInkWidth)
            #expect(engine.checks([bad]).first { $0.name == check }?.pass == false)
        }
    }

    @Test func elbowsStayContinuousThroughCast() throws {
        for heading in stride(from: 0.0, to: 360, by: 22.5) {
            let rig = try Rig(spec: FigureSpec(), scene: reviewScene(heading: heading))
            var previous = rig.pose(at: 0, quantized: false), jump = 0.0
            for i in 1...288 {
                let pose = rig.pose(at: Double(i) / 240, quantized: false)
                for side in ["left", "right"] {
                    jump = max(jump, (pose.world[side + "Elbow"]! - previous.world[side + "Elbow"]!).length)
                }
                previous = pose
            }
            #expect(jump / rig.scene.figureHeight < 0.02, "heading \(heading), jump \(jump)")
        }
    }

    @Test func releaseReadsFacingViewer() throws {
        let rig = try Rig(spec: FigureSpec(), scene: reviewScene(heading: 90))
        let pose = rig.pose(at: rig.actions[0].timing.release!, quantized: false)
        let crown = pose.joints["head"]!.y - rig.spec.figure.headSize * rig.unit / 2
        #expect(pose.joints["leftHand"]!.y < crown)
        #expect(pose.joints["rightHand"]!.y < crown)
        let spread = abs(pose.joints["leftHand"]!.x - pose.joints["rightHand"]!.x)
        let shoulders = abs(pose.joints["leftShoulder"]!.x - pose.joints["rightShoulder"]!.x)
        #expect(spread >= 2 * shoulders)
    }

    @Test func kerchiefLeavesMiddleOfFaceClear() throws {
        var spec = FigureSpec(); spec.figure.accent = "#C9A227"
        let rig = try Rig(spec: spec, scene: reviewScene(heading: 90))
        let pose = rig.pose(at: 0, quantized: false)
        let ink = InkRenderer(spec: spec, unit: rig.unit, seed: 1)
        spec.figure.headwear = "none"
        let bare = InkRenderer(spec: spec, unit: rig.unit, seed: 1).draw(pose, at: 0).shapes
        let covered = ink.draw(pose, at: 0).shapes
        let headwear = covered.filter { shape in !bare.contains { $0.subpaths == shape.subpaths } }
        #expect(!headwear.isEmpty)
        let head = pose.joints["head"]!, third = spec.figure.headSize * rig.unit / 6
        #expect(headwear.flatMap { $0.subpaths.flatMap { $0 } }.allSatisfy { $0.y < head.y - third })
    }

    @Test func bounceDoesNotRescaleStandingFigure() throws {
        for bounce in [0.0, 0.03, 0.08] {
            var spec = FigureSpec(); spec.motion.bounce = bounce
            let rig = try Rig(spec: spec, scene: reviewScene())
            let pose = rig.pose(at: 0, quantized: false)
            let crown = pose.world["head"]!.z + spec.figure.headSize * rig.unit / 2
            #expect(abs(crown / rig.scene.figureHeight - 1) < 1e-10)
            #expect(abs(spec.normalizationScale - FigureSpec().normalizationScale) < 1e-10)
        }
    }

    @Test func leanAndHunchPreserveBones() throws {
        for lean in [-5.0, 0, 20] {
            for hunch in [0.0, 0.1, 0.6] {
                var spec = FigureSpec(); spec.motion.lean = lean; spec.figure.hunch = hunch
                #expect(spec.normalizationScale == FigureSpec().normalizationScale)
                let rig = try Rig(spec: spec, scene: reviewScene(walking: true))
                let pose = rig.pose(at: rig.actions[0].duration / 2, quantized: false)
                #expect(abs((pose.world["chest"]! - pose.world["pelvis"]!).length / rig.unit - spec.figure.torso) < 1e-10)
                #expect(abs((pose.world["neck"]! - pose.world["chest"]!).length / rig.unit - spec.figure.neck) < 1e-10)
            }
        }
    }

    @Test func actionErrorUsesJSONPath() throws {
        do {
            _ = try JSONDecoder().decode(FigureScene.self, from: Data("""
                {"canvas":{},"paths":{},"actors":[{"id":"w","at":{"path":"p"},
                 "timeline":[{"do":"idle"},{"do":"dance"}]}],"card":{"authors":"A","year":1,"title":"B"}}
                """.utf8))
            Issue.record("accepted unknown action")
        } catch { #expect(String(describing: error).contains("actors[0].timeline[1].do")) }
    }
}

@Suite("Ink and final stride regressions")
struct InkAndStrideTests {
    @Test func inkHairpinFillRule() throws {
        var spec = FigureSpec(); spec.ink.wobble = 0; spec.ink.pressure = 0; spec.ink.taper = 0
        let s = try reviewScene(), rig = try Rig(spec: spec, scene: s)
        var pose = rig.pose(at: 0, quantized: false)
        pose.joints["leftShoulder"] = Point(400, 200)
        pose.joints["leftElbow"] = Point(500, 200)
        pose.joints["leftHand"] = Point(413.39746, 250)
        let ink = InkRenderer(spec: spec, unit: rig.unit, seed: 1)
        let hairpin = try #require(ink.draw(pose, at: 0).shapes.first { $0.subpaths.joined().contains { $0.x > 490 } })
        let frame = FigureFrame(time: 0, actors: [pose], shapes: [hairpin], particles: 0, minimumInkWidth: 1)
        let svg = FigureSVG.write(frame, scene: s)
        #expect(svg.contains("fill-rule=\"nonzero\""))
        var glyph = hairpin; glyph.layer = "card"
        let card = FigureFrame(time: 0, actors: [pose], shapes: [glyph], particles: 0, minimumInkWidth: 1)
        #expect(FigureSVG.write(card, scene: s).contains("fill-rule=\"evenodd\""))
        // The Python pixel regression requests this actual ink contour for rasterization.
        if let folder = ProcessInfo.processInfo.environment["FIGURE_TEST_ARTIFACTS"] {
            try Data(svg.utf8).write(to: URL(fileURLWithPath: folder).appendingPathComponent("hairpin.svg"))
        }
    }

    @Test func lastPartialStrideGetsAnEasedSwing() throws {
        var spec = FigureSpec(); spec.motion.ease = 0
        var s = try reviewScene(walking: true)
        let step = spec.motion.step * spec.normalizationScale * s.figureHeight
        s.paths["p"] = "M300 400 L\(300 + step * 2.1) 400"
        let rig = try Rig(spec: spec, scene: s), walk = rig.actions[0]
        let interval = 1 / spec.motion.cadence
        #expect(abs(walk.duration - 3 * interval) < 1e-10)
        // Around the middle of the final swing the foot must remain on its eased arc.
        let middle = rig.pose(at: 2.5 * interval, quantized: false)
        #expect(middle.planted["left"] == false)
        let before = rig.pose(at: 2.49 * interval, quantized: false)
        let after = rig.pose(at: 2.51 * interval, quantized: false)
        #expect((after.joints["leftAnkle"]! - before.joints["leftAnkle"]!).length / s.figureHeight < 0.01)
    }

    @Test func rigDrawsClampedAnkle() throws {
        // Force an unreachable target to exercise the renderer's fallback, independently
        // of the supported-spec sweep (which must never clamp).
        var spec = FigureSpec(); spec.figure.thigh = 0.01; spec.figure.shin = 0.01
        let rig = try Rig(spec: spec, scene: reviewScene(walking: true))
        let pose = try #require((0...120).map { rig.pose(at: rig.duration * Double($0) / 120, quantized: false) }
            .first { $0.ikClamps > 0 })
        for side in ["left", "right"] {
            let knee = pose.world[side + "Knee"]!, ankle = pose.world[side + "Ankle"]!
            #expect(abs((ankle - knee).length / rig.unit - spec.figure.shin) < 1e-8)
            let projected = Point(ankle.x, pose.origin.y + (ankle.y - pose.origin.y) * spec.view.depth - ankle.z * spec.view.heightScale)
            #expect((pose.joints[side + "Ankle"]! - projected).length < 1e-8)
        }
    }

    @Test func clampedAnklePreservesBothBoneLengths() throws {
        for target in [Vector3(0, 0, -10), Vector3(0, 0, -0.01), Vector3(0, 0, 0)] {
            let root = Vector3(0, 0, 0), leg = twoBone(root, target, 0.23, 0.12, Vector3(1, 0, 0))
            #expect(leg.clamped)
            #expect(abs((leg.joint - root).length - 0.23) < 1e-8)
            #expect(abs((leg.end - leg.joint).length - 0.12) < 1e-8)
        }
    }
}
