import Foundation
import Testing
@testable import FigureRig
#if os(Linux)
import Glibc
#endif

private let auditRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private func auditScene(_ timeline: String = #"{"do":"idle","duration":0.1}"#, holds: String = "brush") throws -> FigureScene {
    try JSONDecoder().decode(FigureScene.self, from: Data("""
    {"version":2,"canvas":{"width":1100,"height":825},"figureHeight":50,
     "paths":{"p":"M300 400 L390 400","q":"M390 393 L480 393"},
     "actors":[{"id":"a","holds":"\(holds)","at":{"path":"p","t":0},"timeline":[\(timeline)]}],
     "card":{"authors":"A","year":1973,"title":"B"},"tail":0.1}
    """.utf8))
}
private func auditCheck(_ engine: FigureEngine, _ frame: FigureFrame, _ name: String) throws -> FigureCheck {
    try #require(engine.checks([frame]).first { $0.name == name })
}
private func auditFolder() throws -> URL {
    let base = ProcessInfo.processInfo.environment["FACTORY_TEST_OUT"] ?? "/root/factory-out/F22/tests"
    let url = URL(fileURLWithPath: base).appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
private func auditCLI(_ args: [String], in folder: URL) throws -> (Int32, Process.TerminationReason, String) {
    let binary = ProcessInfo.processInfo.environment["FIGURES_BIN"] ??
        URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("figures").path
    let log = folder.appendingPathComponent(UUID().uuidString + ".log")
    _ = FileManager.default.createFile(atPath: log.path, contents: nil)
    let handle = try FileHandle(forWritingTo: log)
    #if os(Linux)
    // Foundation.Process needs a CFSocket wakeup pair, unavailable in some Linux
    // sandboxes. POSIX spawn/wait exercises the real CLI without that dependency.
    var actions = posix_spawn_file_actions_t()
    #expect(posix_spawn_file_actions_init(&actions) == 0)
    defer { posix_spawn_file_actions_destroy(&actions) }
    #expect(posix_spawn_file_actions_adddup2(&actions, handle.fileDescriptor, STDOUT_FILENO) == 0)
    #expect(posix_spawn_file_actions_adddup2(&actions, handle.fileDescriptor, STDERR_FILENO) == 0)
    var argv = ([binary] + args).map { strdup($0) } + [nil]
    var env = ProcessInfo.processInfo.environment.map { strdup($0.key + "=" + $0.value) } + [nil]
    defer { for pointer in argv + env { if let pointer { free(pointer) } } }
    var pid: pid_t = 0
    let result = argv.withUnsafeMutableBufferPointer { arguments in
        env.withUnsafeMutableBufferPointer { environment in
            posix_spawn(&pid, binary, &actions, nil, arguments.baseAddress!, environment.baseAddress!)
        }
    }
    guard result == 0 else { throw FigureInputError("could not launch figures at \(binary): errno \(result)") }
    var status: Int32 = 0
    while waitpid(pid, &status, 0) == -1 {
        guard errno == EINTR else { throw FigureInputError("waitpid: errno \(errno)") }
    }
    let reason: Process.TerminationReason = status & 0x7f == 0 ? .exit : .uncaughtSignal
    let code = reason == .exit ? status >> 8 : status & 0x7f
    #else
    let process = Process()
    process.executableURL = URL(fileURLWithPath: binary)
    process.arguments = args; process.currentDirectoryURL = folder
    process.standardOutput = handle; process.standardError = handle
    try process.run(); process.waitUntilExit()
    let code = process.terminationStatus, reason = process.terminationReason
    #endif
    try handle.close()
    return (code, reason, String(decoding: try Data(contentsOf: log), as: UTF8.self))
}
private func auditRenderArgs(_ out: URL, scene: URL? = nil) -> [String] {
    ["render", "--spec", auditRoot.appendingPathComponent("factory/specs/baseline.json").path,
     "--scene", (scene ?? auditRoot.appendingPathComponent("factory/scenes/hero.json")).path, "--out", out.path]
}

@Suite("F22 geometry audit regressions")
struct AuditGeometryTests {
    @Test func drawnPropAttachmentsAreIndependentOfGripMetadata() throws {
        for (kind, action) in [("brush", "ink"), ("broom", "sweep"), ("jar", "walk"), ("mortar", "walk")] {
            let scene = try auditScene("{\"do\":\"\(action)\",\"path\":\"p\",\"to\":1}", holds: kind)
            let engine = try FigureEngine(spec: FigureSpec(), scene: scene), good = engine.frame(10)
            #expect(try auditCheck(engine, good, "propGrip").pass)
            for damage in ["base", "axis", "missingGrip", "missingProp", "leftGrip", "leftHand"] {
                if damage.hasPrefix("left") && kind != "broom" { continue }
                var pose = good.actors[0]
                switch damage {
                case "base": pose.prop!.base.x += 10
                case "axis": pose.prop!.axis.x += 2
                case "missingGrip": pose.prop!.grips.removeValue(forKey: "right")
                case "missingProp": pose.prop = nil
                case "leftGrip": pose.prop!.grips.removeValue(forKey: "left")
                default: pose.joints["leftHand"]!.x += 10
                }
                // Re-render from the damaged base/axis; grip metadata remains untouched.
                var shapes = engine.ink.draw(pose, at: good.time).shapes
                if let prop = pose.prop { shapes += engine.ink.heldProp(prop, at: good.time).shapes }
                let bad = FigureFrame(time: good.time, actors: [pose], shapes: shapes,
                                      particles: 0, minimumInkWidth: good.minimumInkWidth)
                // Jar/mortar attach at their base, so changing only their axis cannot move the grip.
                if damage == "axis" && ["jar", "mortar"].contains(kind) { continue }
                #expect(try auditCheck(engine, bad, "propGrip").pass == false, "\(kind): \(damage)")
            }
        }
    }

    @Test func newWalkAfterInkResetsOffsetAndSamePathKeepsIt() throws {
        for switched in [true, false] {
            let scene = try auditScene("""
            {"do":"ink","path":"p","from":0,"to":\(switched ? 1 : 0.5)},
            {"do":"walk","path":"\(switched ? "q" : "p")","to":1},{"do":"idle","duration":1}
            """)
            let rig = try Rig(spec: FigureSpec(), scene: scene)
            let final = rig.pose(at: rig.duration, quantized: false)
            #expect(abs(final.origin.y - 393) < 1e-8)
            #expect(abs((final.joints["leftAnkle"]!.y + final.joints["rightAnkle"]!.y) / 2 - 393) < 1e-8)
            #expect(abs(rig.actions[1].lateralOffset - (switched ? 0 : 7)) < 1e-8)
            let boundary = rig.actions[0].timing.end
            #expect((rig.pose(at: boundary - 1e-8, quantized: false).origin - rig.pose(at: boundary, quantized: false).origin).length < 1e-5)
        }
    }

    @Test func citationsWrapWithoutUnlimitedCompression() throws {
        var scene = try auditScene()
        scene.card.authors = "David Douglas and Thomas Peucker"
        scene.card.title = "Algorithms for the reduction of the number of points required to represent a digitized line or its caricature"
        let real = try FigureEngine(spec: FigureSpec(), scene: scene)
        #expect(real.card.titleLines.count >= 2)
        #expect(try auditCheck(real, real.frame(0), "cardSize").pass)
        #expect(try auditCheck(real, real.frame(0), "cardOnScreen").pass)
        #expect(real.card.minimumSizePoints >= 11)
        scene.card.title = Array(repeating: "A", count: 150).joined(separator: " ")
        let long = try FigureEngine(spec: FigureSpec(), scene: scene)
        #expect(long.card.titleLines.count > 2)
        #expect(try auditCheck(long, long.frame(0), "cardSize").pass)
        #expect(long.card.minimumSizePoints >= 11)
        scene.card.authors = Array(repeating: "Long Author Name", count: 40).joined(separator: " ")
        scene.card.title = "B"
        let authors = try FigureEngine(spec: FigureSpec(), scene: scene)
        #expect(authors.card.maximum.y - authors.card.minimum.y > real.card.maximum.y - real.card.minimum.y)
        #expect(authors.card.authorLines.count > 2)
        #expect(authors.card.minimumSizePoints >= 11)
        if let output = ProcessInfo.processInfo.environment["FIGURE_TEST_ARTIFACTS"] {
            for (name, engine) in [("douglas-peucker", real), ("150-word-title", long), ("long-authors", authors)] {
                let index = Int(ceil((engine.card.holdStart + 0.1) * Double(engine.spec.motion.fps)))
                try Data(FigureSVG.write(engine.frame(index), scene: engine.scene).utf8)
                    .write(to: URL(fileURLWithPath: output).appendingPathComponent(name + ".svg"))
            }
        }
        // A single unbreakable word may use bounded compression; at 11 pt it must fail cardSize.
        var spec = FigureSpec(); spec.card.size = 11
        scene.card.authors = "A"; scene.card.title = String(repeating: "W", count: 150)
        let squeezed = try FigureEngine(spec: spec, scene: scene)
        #expect(try auditCheck(squeezed, squeezed.frame(0), "cardSize").pass == false)
        #expect(squeezed.card.minimumSizePoints == spec.card.size * CardLayout.minimumHorizontalScale)
        #expect(squeezed.card.maximum.x > scene.canvas.width)
    }
}

@Suite("F22 CLI audit regressions", .serialized)
struct AuditCLITests {
    @Test func helpListsBothCommandsAndSucceeds() throws {
        let folder = try auditFolder()
        let (status, reason, message) = try auditCLI(["--help"], in: folder)
        #expect(status == 0 && reason == .exit)
        #expect(message.contains("render") && message.contains("reveal"))
    }
    @Test func hugeFiniteProbesExitWithFieldErrorsWithoutSignals() throws {
        let folder = try auditFolder()
        let original = try String(contentsOf: auditRoot.appendingPathComponent("factory/scenes/hero.json"), encoding: .utf8)
        try FileManager.default.copyItem(at: auditRoot.appendingPathComponent("factory/scenes/hero-painted.png"),
                                        to: folder.appendingPathComponent("hero-painted.png"))
        for (needle, replacement, field) in [("\"height\": 825", "\"height\": 1e300", "canvas.height"),
                ("\"duration\": 0.6", "\"duration\": 1e300", "actors[0].timeline[3].duration"),
                ("830 565", "1e300 565", "paths.brook")] {
            let scene = folder.appendingPathComponent(field + ".json")
            try Data(original.replacingOccurrences(of: needle, with: replacement).utf8).write(to: scene)
            let (status, reason, message) = try auditCLI(auditRenderArgs(folder.appendingPathComponent(field), scene: scene), in: folder)
            #expect(status != 0 && reason == .exit, "\(field): status \(status), reason \(reason)")
            #expect(message.contains(field))
            #expect(!message.contains("Signal") && !message.contains("Fatal error"))
        }
    }
    @Test func renderRefusesSymlinkChildrenAndPreservesUnrelatedFrames() throws {
        let fm = FileManager.default, folder = try auditFolder(), out = folder.appendingPathComponent("out")
        let victim = folder.appendingPathComponent("victim")
        try fm.createDirectory(at: out, withIntermediateDirectories: true)
        try fm.createDirectory(at: victim, withIntermediateDirectories: true)
        let marker = victim.appendingPathComponent("unrelated.svg")
        try Data("keep".utf8).write(to: marker)
        try fm.createSymbolicLink(at: out.appendingPathComponent("frames"), withDestinationURL: victim)
        let (status, _, message) = try auditCLI(auditRenderArgs(out), in: folder)
        #expect(status != 0 && message.contains("symlink"))
        #expect(fm.fileExists(atPath: marker.path))
        try fm.removeItem(at: out.appendingPathComponent("frames"))
        try fm.createDirectory(at: out.appendingPathComponent("frames"), withIntermediateDirectories: true)
        for name in ["notes.svg", "photo.png", "9999.svg"] {
            try Data("keep".utf8).write(to: out.appendingPathComponent("frames/" + name))
        }
        #expect(try auditCLI(auditRenderArgs(out), in: folder).0 == 0)
        #expect(try auditCLI(auditRenderArgs(out), in: folder).0 == 0)
        for name in ["notes.svg", "photo.png", "9999.svg"] {
            #expect(try Data(contentsOf: out.appendingPathComponent("frames/" + name)) == Data("keep".utf8))
        }
        // A shorter rerun removes exactly the prior run's stale frame files, including PNGs.
        try Data("old png".utf8).write(to: out.appendingPathComponent("frames/0279.png"))
        let scene = folder.appendingPathComponent("short.json")
        // Write a short scene without relying on FigureScene being Encodable.
        try Data(#"{"canvas":{},"paths":{"p":"M300 400 L390 400"},"actors":[{"id":"a","at":{"path":"p"},"timeline":[{"do":"idle","duration":0.1}]}],"card":{"authors":"A","year":1,"title":"B"},"tail":0}"#.utf8).write(to: scene)
        #expect(try auditCLI(auditRenderArgs(out, scene: scene), in: folder).0 == 0)
        #expect(!fm.fileExists(atPath: out.appendingPathComponent("frames/0279.svg").path))
        #expect(!fm.fileExists(atPath: out.appendingPathComponent("frames/0279.png").path))
    }
    @Test func renderAndRevealRefuseRepositoryOutputsAndSymlinkFiles() throws {
        let folder = try auditFolder(), fm = FileManager.default
        let snapshots = folder.appendingPathComponent("snapshots")
        try fm.createDirectory(at: snapshots, withIntermediateDirectories: true)
        for (name, value) in [("structure.pgm", UInt8(0)), ("line-art.pgm", UInt8(255))] {
            try (Data("P5\n1 1\n255\n".utf8) + Data([value])).write(to: snapshots.appendingPathComponent(name))
        }
        for args in [auditRenderArgs(auditRoot), ["reveal", snapshots.path, auditRoot.path]] {
            let result = try auditCLI(args, in: folder)
            #expect(result.0 != 0 && result.2.contains("repository"))
        }
        for command in ["render", "reveal"] {
            let out = folder.appendingPathComponent(command)
            try fm.createDirectory(at: out, withIntermediateDirectories: true)
            let victim = folder.appendingPathComponent(command + "-victim")
            try Data("keep".utf8).write(to: victim)
            let child = command == "render" ? "checks.json" : "structure-line-art.json"
            try fm.createSymbolicLink(at: out.appendingPathComponent(child), withDestinationURL: victim)
            let args = command == "render" ? auditRenderArgs(out) : ["reveal", snapshots.path, out.path]
            let result = try auditCLI(args, in: folder)
            #expect(result.0 != 0 && result.2.contains("symlink"))
            #expect(try Data(contentsOf: victim) == Data("keep".utf8))
        }
    }
}

@Suite("Frozen version 2 workers")
struct WorkerDigestTests {
    @Test func workersDigests() throws {
        let decoder = JSONDecoder(), encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let specData = try Data(contentsOf: auditRoot.appendingPathComponent("factory/specs/baseline.json"))
        let sceneData = try Data(contentsOf: auditRoot.appendingPathComponent("factory/scenes/workers.json"))
        let spec = try decoder.decode(FigureSpec.self, from: specData)
        let scene = try decoder.decode(FigureScene.self, from: sceneData)
        let engine = try FigureEngine(spec: spec, scene: scene)
        let frames = (0..<engine.frameCount).map { engine.frame($0) }
        let svg = frames.flatMap { Array(FigureSVG.write($0, scene: scene, background: "../background.svg").utf8) }
        func digest<T: Encodable>(_ value: T) throws -> String {
            var data = try encoder.encode(value); data.append(10)
            return FigureSHA256.digest(Array(data))
        }
        // Captured by F21 from the unchanged 1.0.0 CLI, before the audit fixes.
        #expect(FigureSHA256.digest(svg) == "f9fa42e7e51df518a59a4e1656d9f03d55c60ab7a06fb18d8e80de2cdcb1d041")
        #expect(try digest(frames.enumerated().map { MotionFrame(frame: $0.offset, time: $0.element.time, actors: $0.element.actors) }) == "a4b0a22ac84020ed7e0f5363ecd5f9688db5755a8dbd149b93f4a0c4ccbe06af")
        #expect(try digest(engine.checks(frames)) == "687b8504dfdba5108a6b5ee50b1038cf26702dc457d8ac769697d48c15ea4684")
        #expect(try digest(engine.manifest(specSHA256: FigureSHA256.digest(Array(specData)),
                                          sceneSHA256: FigureSHA256.digest(Array(sceneData)))) ==
                "e9e0fc6480efef32b6d46dc2ded459aab86fe865b750327ef32ac95896d30046")
    }
}

@Suite("F22 bounded scene work")
struct AuditLimitTests {
    @Test func boundedDecodedFieldsNameTheirErrors() throws {
        for (json, field) in [
            (#"{"width":1e300}"#, "width"), (#"{"height":1e300}"#, "height"),
            (#"{"width":1e-300}"#, "width")
        ] {
            do {
                _ = try JSONDecoder().decode(FigureScene.Canvas.self, from: Data(json.utf8))
                Issue.record("accepted \(json)")
            } catch { #expect(error is FigureInputError && String(describing: error).contains(field)) }
        }
        for json in [#"{"do":"idle","duration":1e300}"#, #"{"do":"turn","heading":1e300}"#] {
            #expect(throws: FigureInputError.self) {
                try JSONDecoder().decode(FigureScene.Action.self, from: Data(json.utf8))
            }
        }
        for path in ["M0 0 L1e300 0", "M0 0 C0 1e300 1 0 2 0", "M-1000000 0 L1000000 0"] {
            #expect(throws: FigureInputError.self) { try ArcPath(path) }
        }
        // Repeated small curves stay below the length limit but exceed the flattening budget.
        let curves = "M0 0" + String(repeating: " C0 100 100 100 100 0 C100 -100 0 -100 0 0", count: 1000)
        do { _ = try ArcPath(curves); Issue.record("accepted excessive flattened points") }
        catch { #expect(error is FigureInputError && String(describing: error).contains("path.points")) }
    }
    @Test func mutableScenesAndDerivedCountsAreValidatedBeforePlanning() throws {
        for (field, change) in [
            ("canvas.height/width", { (s: inout FigureScene) in s.canvas.width = 1 }),
            ("figureHeight", { (s: inout FigureScene) in s.figureHeight = 1e300 }),
            ("tail", { (s: inout FigureScene) in s.tail = 1e300 }),
            ("card.at", { (s: inout FigureScene) in s.card.at = 1e300 }),
            ("actors[0].timeline[0].gaitCount", { (s: inout FigureScene) in
                s.figureHeight = 0.01; s.actors[0].timeline[0].kind = "walk"
                s.actors[0].timeline[0].path = "p"; s.actors[0].timeline[0].to = 1
            }),
            ("actors[0].timeline[1].duration", { (s: inout FigureScene) in
                s.actors[0].timeline[0].duration = 2000
                s.actors[0].timeline.append(s.actors[0].timeline[0])
            })
        ] {
            var scene = try auditScene(); change(&scene)
            do { _ = try FigureEngine(spec: FigureSpec(), scene: scene); Issue.record("accepted \(field)") }
            catch { #expect(error is FigureInputError && String(describing: error).contains(field), "\(error)") }
        }
        var spec = FigureSpec(); spec.motion.fps = Int.max
        do { _ = try FigureEngine(spec: spec, scene: auditScene()); Issue.record("accepted huge frame count") }
        catch { #expect(error is FigureInputError && String(describing: error).contains("frameCount")) }
        // Enough distance for fewer than 10,000 strides but too many fixed-rate heading samples.
        var scene = try auditScene(#"{"do":"walk","path":"p","to":1}"#)
        scene.paths["p"] = "M300 400 L100300 400"
        do { _ = try FigureEngine(spec: FigureSpec(), scene: scene); Issue.record("accepted excessive walk duration") }
        catch { #expect(error is FigureInputError && String(describing: error).contains("duration")) }
    }
}
