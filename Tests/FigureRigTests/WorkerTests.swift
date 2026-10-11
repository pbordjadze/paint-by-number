import Foundation
import Testing
@testable import FigureRig

private func workerScene(_ actors: String, paths: String = #""p":"M300 400 L390 400""#, props: String? = nil, version: Int = 2) throws -> FigureScene {
    let propField = props.map { ",\"props\":\($0)" } ?? ""
    return try JSONDecoder().decode(FigureScene.self, from: Data("""
        {"version":\(version),"canvas":{"width":1100,"height":825},"figureHeight":50,
         "paths":{\(paths)},"actors":[\(actors)]\(propField),
         "card":{"authors":"A","year":2011,"title":"B","at":0},"tail":3}
        """.utf8))
}
private func worker(_ id: String, holds: String? = nil, path: String = "p", timeline: String, t: Double = 0) -> String {
    """
    {"id":"\(id)",\(holds.map { "\"holds\":\"\($0)\"," } ?? "")
     "at":{"path":"\(path)","t":\(t)},"timeline":[\(timeline)]}
    """
}
private func workerBytes<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(value)
}
private func workerCheck(_ engine: FigureEngine, frames: [FigureFrame], name: String) throws -> FigureCheck {
    try #require(engine.checks(frames).first { $0.name == name })
}

@Suite("Figure engine v1 workers")
struct WorkerTests {
    @Test func versionsAndStrictDecoding() throws {
        let decoder = JSONDecoder()
        let v2 = try decoder.decode(FigureSpec.self, from: Data(#"{"version":2}"#.utf8))
        var v1 = FigureSpec(); v1.version = 2
        #expect(try workerBytes(v2) == workerBytes(v1))
        let idle = worker("a", timeline: #"{"do":"idle","duration":3}"#)
        for (actors, props, version, field) in [
            (idle, "[]", 1, "props"),
            (worker("a", holds: "brush", timeline: #"{"do":"idle"}"#), nil, 1, "holds"),
            (idle + "," + idle, "[]", 2, "actors[1].id"),
            (worker("", timeline: #"{"do":"idle"}"#), "[]", 2, "actors[0].id"),
            (worker("a", timeline: #"{"do":"ink","path":"p","from":0,"to":1}"#), "[]", 2, "holds: brush"),
            (worker("a", holds: "jar", timeline: #"{"do":"sweep","path":"p","to":1}"#), "[]", 2, "holds: broom"),
            (worker("a", holds: "stick", timeline: #"{"do":"idle"}"#), "[]", 2, "actors[0].holds"),
            (idle, #"[{"kind":"jar","at":{"path":"p"},"typo":1}]"#, 2, "props[0].typo"),
            (worker("a", holds: "brush", timeline: #"{"do":"ink","path":"p","from":1.1}"#), "[]", 2, "from")
        ] {
            do { _ = try workerScene(actors, props: props, version: version); Issue.record("accepted invalid \(field)") }
            catch { #expect(String(describing: error).contains(field), "\(error)") }
        }
        let unknown = try workerScene(idle, props: #"[{"kind":"jar","at":{"path":"missing"}}]"#)
        #expect(throws: FigureInputError.self) { try FigureEngine(spec: FigureSpec(), scene: unknown) }
    }

    @Test func brushTracksCurvesInBothDirectionsAndEveryHeading() throws {
        for heading in stride(from: 0.0, to: 360, by: 45) {
            let end = Point(300, 400) + headingVector(heading) * 60
            for reverse in [false, true] {
                for depth in [0.0, 0.5, 1.0] {
                    var spec = FigureSpec(); spec.view.depth = depth
                    let from = reverse ? 1 : 0, to = reverse ? 0 : 1
                    let actor = worker("a", holds: "brush", timeline: """
                        {"do":"ink","path":"p","from":\(from),"to":\(to)},{"do":"idle","duration":1}
                        """)
                    let s = try workerScene(actor, paths: "\"p\":\"M300 400 L\(end.x) \(end.y)\"")
                    let engine = try FigureEngine(spec: spec, scene: s)
                    let frames = (0..<engine.frameCount).map { i in
                        let time = Double(i) / Double(spec.motion.fps)
                        return FigureFrame(time: time, actors: [engine.pose(at: time)], shapes: [], particles: 0, minimumInkWidth: 1)
                    }
                    #expect(try workerCheck(engine, frames: frames, name: "brushTip").pass, "heading \(heading), depth \(depth), reverse \(reverse)")
                    #expect(try workerCheck(engine, frames: frames, name: "propGrip").pass)
                    #expect(try workerCheck(engine, frames: frames, name: "footSlide").pass)
                    #expect(try workerCheck(engine, frames: frames, name: "elbowReverse").pass)
                    #expect(try workerCheck(engine, frames: frames, name: "ikClamps").pass)
                    for frame in frames where frame.actors[0].action == "ink" {
                        let pose = frame.actors[0]
                        #expect((pose.prop!.tip - pose.inkPathPoint!).length < 1e-7)
                        #expect(abs((pose.world["rightHand"]! - pose.world["rightElbow"]!).length - spec.figure.forearm * engine.rig.unit) < 1e-7)
                    }
                }
            }
        }
        let s = try workerScene(worker("curve", holds: "brush", timeline: #"{"do":"ink","path":"p","from":0.2,"to":0.8}"#),
            paths: #""p":"M300 400 C320 395 350 415 400 405""#)
        let engine = try FigureEngine(spec: FigureSpec(), scene: s)
        #expect(try workerCheck(engine, frames: (0..<engine.frameCount).map { engine.frame($0) }, name: "brushTip").pass)
    }

    @Test func inkGrowsPersistsAndSamplingOrderDoesNotMatter() throws {
        let s = try workerScene(worker("a", holds: "brush", timeline: #"{"do":"ink","path":"p","from":0.15,"to":0.85},{"do":"idle","duration":1}"#))
        let engine = try FigureEngine(spec: FigureSpec(), scene: s), rig = engine.rig, ink = engine.ink
        #expect(ink.laidInk(rig, at: 0).shapes.isEmpty)
        let half = ink.laidInk(rig, at: rig.actions[0].duration / 2).shapes
        let end = ink.laidInk(rig, at: rig.actions[0].timing.end + 0.1).shapes
        #expect(!half.isEmpty)
        #expect(half[0].subpaths[0].map(\.x).max()! < end[0].subpaths[0].map(\.x).max()!)
        #expect(try workerBytes(end) == workerBytes(ink.laidInk(rig, at: engine.duration).shapes))
        let first = FigureSVG.write(engine.frame(10), scene: s)
        _ = engine.frame(engine.frameCount - 1)
        #expect(first == FigureSVG.write(engine.frame(10), scene: s))
        let a = rig.pose(at: rig.actions[0].duration / 2)
        let target = a.inkPathPoint!, left = headingVector(a.heading).normal
        #expect((a.origin - target).dot(left) < -6.9)
    }

    @Test func sweepHasTwoLowGripsAndOneSwingPerFootfall() throws {
        var spec = FigureSpec(); spec.motion.onTwos = false; spec.motion.ease = 0
        let s = try workerScene(worker("s", holds: "broom", timeline: #"{"do":"sweep","path":"p","to":1}"#))
        let engine = try FigureEngine(spec: spec, scene: s)
        let frames = (0..<engine.frameCount).map { engine.frame($0) }
        #expect(try workerCheck(engine, frames: frames, name: "propGrip").pass)
        #expect(try workerCheck(engine, frames: frames, name: "elbowReverse").pass)
        #expect(try workerCheck(engine, frames: frames, name: "footSlide").pass)
        for frame in frames where frame.actors[0].action == "sweep" {
            let pose = frame.actors[0], prop = try #require(pose.prop)
            #expect(prop.grips.count == 2)
            #expect(pose.world["rightHand"]!.z < pose.world["pelvis"]!.z + s.figureHeight * 0.12)
            #expect(pose.world["leftHand"]!.z < pose.world["chest"]!.z)
        }
        let interval = 1 / spec.motion.cadence
        let a = engine.rig.pose(at: interval * 0.25, quantized: false)
        let b = engine.rig.pose(at: interval * 0.75, quantized: false)
        let c = engine.rig.pose(at: interval * 1.25, quantized: false)
        let da = (a.world["rightHand"]! - a.world["pelvis"]!).xy.unit
        let db = (b.world["rightHand"]! - b.world["pelvis"]!).xy.unit
        let dc = (c.world["rightHand"]! - c.world["pelvis"]!).xy.unit
        #expect(da.y > 0 && db.y < 0)
        #expect((da - dc).length < 1e-7)
        var partial = s
        let step = spec.motion.step * spec.normalizationScale * s.figureHeight
        partial.paths["p"] = "M300 400 L\(300 + step * 2.1) 400"
        let short = try Rig(spec: spec, scene: partial)
        // The final partial stride keeps a complete broom swing, like its complete footfall.
        for (time, expected) in [(2.25 * interval, da), (2.75 * interval, db)] {
            let pose = short.pose(at: time, quantized: false)
            let direction = (pose.world["rightHand"]! - pose.world["pelvis"]!).xy.unit
            #expect((direction - expected).length < 1e-7)
        }
    }

    @Test func allPropsHoldAndGroundShapesScale() throws {
        for kind in PropKind.allCases {
            let s = try workerScene(worker("a", holds: kind.rawValue, timeline: #"{"do":"walk","path":"p","to":1},{"do":"turn","heading":90},{"do":"cast","duration":1.2}"#),
                props: "[{\"kind\":\"\(kind.rawValue)\",\"at\":{\"path\":\"p\",\"t\":0.8}}]")
            let engine = try FigureEngine(spec: FigureSpec(), scene: s)
            #expect(!engine.ground.shapes.isEmpty)
            let frames = (0..<engine.frameCount).map { engine.frame($0) }
            #expect(try workerCheck(engine, frames: frames, name: "propGrip").pass)
            let pose = engine.pose(at: 1), prop = try #require(pose.prop)
            #expect(prop.kind == kind)
            let axis = (pose.world["rightHand"]! - pose.world["rightElbow"]!).unit
            let projected = Point(axis.x, axis.y * engine.spec.view.depth - axis.z * engine.spec.view.heightScale)
            #expect((prop.axis - projected).length < 1e-8)
        }
    }

    @Test func actorsSortByFeetWithStableTiesAndKeepIndependentStreams() throws {
        let idle = #"{"do":"idle","duration":3}"#
        let a = worker("near", timeline: idle, t: 1)
        let b = worker("far", timeline: #"{"do":"walk","path":"p","to":0.5},{"do":"idle","duration":1}"#)
        let s = try workerScene(a + "," + b + "," + worker("middle", timeline: idle, t: 0.5), paths: #""p":"M300 400 L300 500""#)
        let engine = try FigureEngine(spec: FigureSpec(), scene: s), frame = engine.frame(0)
        #expect(frame.actors.map(\.id) == ["near", "far", "middle"])
        let farDrawing = engine.inks[1].draw(frame.actors[1], at: 0).shapes
        #expect(try workerBytes(Array(frame.shapes.prefix(farDrawing.count))) == workerBytes(farDrawing))
        var one = s; one.actors = [s.actors[1]]
        let alone = try FigureEngine(spec: FigureSpec(), scene: one)
        #expect(try workerBytes(alone.pose(at: 1)) == workerBytes(engine.rigs[1].pose(at: 1)))
        #expect(try workerBytes(alone.ink.draw(alone.pose(at: 1), at: 1).shapes) == workerBytes(engine.inks[1].draw(engine.rigs[1].pose(at: 1), at: 1).shapes))
        #expect(!alone.magic.draw(at: 1).shapes.isEmpty)
        #expect(try workerBytes(alone.magic.draw(at: 1).shapes) == workerBytes(engine.magics[1].draw(at: 1).shapes))
        let tieScene = try workerScene(worker("first", timeline: idle) + "," + worker("second", timeline: idle))
        let tie = try FigureEngine(spec: FigureSpec(), scene: tieScene)
        let tied = tie.frame(0), firstDrawing = tie.ink.draw(tied.actors[0], at: 0).shapes
        #expect(try workerBytes(Array(tied.shapes.prefix(firstDrawing.count))) == workerBytes(firstDrawing))
        #expect(try workerBytes(tie.inks[0].draw(tied.actors[0], at: 0).shapes) != workerBytes(tie.inks[1].draw(tied.actors[1], at: 0).shapes))
        #expect(try workerCheck(tie, frames: [tied], name: "actorSeparation").pass == false)
        #expect(try workerCheck(engine, frames: [frame], name: "actorSeparation").pass)
    }

    @Test func geometryChecksDetectPerturbedTipsAndGrips() throws {
        let s = try workerScene(worker("a", holds: "brush", timeline: #"{"do":"ink","path":"p","from":0,"to":1}"#))
        let engine = try FigureEngine(spec: FigureSpec(), scene: s), good = engine.frame(10)
        for name in ["brushTip", "propGrip"] {
            var pose = good.actors[0]
            if name == "brushTip" { pose.prop!.tip.x += 1 } else { pose.prop!.grips["right"]!.x += 1 }
            let bad = FigureFrame(time: good.time, actors: [pose], shapes: good.shapes, particles: good.particles, minimumInkWidth: good.minimumInkWidth)
            #expect(try workerCheck(engine, frames: [bad], name: name).pass == false)
        }
    }

    @Test func committedWorkersPassAndRepeatExactly() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let decoder = JSONDecoder()
        let spec = try decoder.decode(FigureSpec.self, from: Data(contentsOf: root.appendingPathComponent("factory/specs/baseline.json")))
        let scene = try decoder.decode(FigureScene.self, from: Data(contentsOf: root.appendingPathComponent("factory/scenes/workers.json")))
        let a = try FigureEngine(spec: spec, scene: scene), b = try FigureEngine(spec: spec, scene: scene)
        let frames = (0..<a.frameCount).map { a.frame($0) }
        #expect(a.checks(frames).allSatisfy { $0.pass })
        for i in [0, 10, a.frameCount / 2, a.frameCount - 1] {
            #expect(FigureSVG.write(a.frame(i), scene: scene) == FigureSVG.write(b.frame(i), scene: scene))
            #expect(try workerBytes(a.frame(i).actors) == workerBytes(b.frame(i).actors))
        }
        #expect(try workerBytes(a.checks(frames)) == workerBytes(b.checks(frames)))
        #expect(a.duration == a.rigs.map(\.duration).max())
    }
}
