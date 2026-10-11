// figures render --spec <figure.json> --scene <scene.json> --out <directory>
// figures reveal <snapshot-dir> <out-dir> [--seed left|center|strongest] [--steps K]
// Reveal writes a PGM arrival-time field and JSON worker path per consecutive present
// pbn snapshot pair; default seed left, default steps 12. See RevealField for thresholds.
// Outputs are deterministic review artifacts, never saved paintings. Paths in a scene are
// resolved beside that scene. A local background copy gives every output directory the
// same SVG references, and makes a review bundle portable.
import Foundation
import FigureRig

func reveal(_ args: [String]) throws {
    guard args.count >= 3, (args.count - 3) % 2 == 0 else {
        throw FigureInputError("usage: figures reveal <snapshot-dir> <out-dir> [--seed left|center|strongest] [--steps K]")
    }
    var seed = RevealField.Seed.left, steps = 12, seen = Set<String>()
    for i in stride(from: 3, to: args.count, by: 2) {
        guard seen.insert(args[i]).inserted else { throw FigureInputError("duplicate option \(args[i])") }
        switch args[i] {
        case "--seed":
            guard let value = RevealField.Seed(rawValue: args[i + 1]) else {
                throw FigureInputError("reveal.seed: expected left, center or strongest")
            }
            seed = value
        case "--steps":
            guard let value = Int(args[i + 1]), value > 0 else {
                throw FigureInputError("reveal.steps: expected a positive integer")
            }
            steps = value
        default: throw FigureInputError("unknown option \(args[i])")
        }
    }
    let snapshots = RevealSnapshots.present(in: URL(fileURLWithPath: args[1]))
    guard snapshots.count >= 2 else { throw FigureInputError("reveal: expected at least two named pbn snapshots") }
    let output = try OutputDirectory(args[2]), out = output.url
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    // Prepare every pair before writing, so a malformed later snapshot cannot leave
    // a partial new bundle in the output directory.
    var outputs: [(String, Data, Data)] = []
    var previous = try RevealSnapshots.read(Data(contentsOf: snapshots[0]))
    for i in 1..<snapshots.count {
        let next = try RevealSnapshots.read(Data(contentsOf: snapshots[i]))
        let field = try RevealField.make(from: previous, to: next, seed: seed)
        let name = snapshots[i - 1].deletingPathExtension().lastPathComponent + "-" + snapshots[i].deletingPathExtension().lastPathComponent
        var json = try encoder.encode(field.metadata(steps: steps)); json.append(10)
        outputs.append((name, field.encodedPGM(), json)); previous = next
    }
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    for (name, pgm, json) in outputs {
        try pgm.write(to: output.child(name + ".pgm"))
        try json.write(to: output.child(name + ".json"))
    }
    print("\(outputs.count) reveal fields; \(out.path)")
}

func run() throws {
    let args = Array(CommandLine.arguments.dropFirst())
    if args == ["--help"] || args == ["-h"] || args == ["render", "--help"] || args == ["reveal", "--help"] {
        print("""
        usage: figures render --spec <figure.json> --scene <scene.json> --out <directory>
               figures reveal <snapshot-dir> <out-dir> [--seed left|center|strongest] [--steps K]
        Output directories must be outside the repository, with no symlinked children.
        """)
        return
    }
    if args.first == "reveal" { try reveal(args); return }
    guard args.first == "render", args.count == 7 else {
        throw FigureInputError("usage: figures render --spec S --scene C --out D")
    }
    var options: [String: String] = [:]
    for index in stride(from: 1, to: args.count, by: 2) {
        guard ["--spec", "--scene", "--out"].contains(args[index]), options[args[index]] == nil else {
            throw FigureInputError("unknown or duplicate option \(args[index])")
        }
        options[args[index]] = args[index + 1]
    }
    guard let specPath = options["--spec"], let scenePath = options["--scene"], let outPath = options["--out"] else {
        throw FigureInputError("expected --spec, --scene and --out")
    }
    let specData = try Data(contentsOf: URL(fileURLWithPath: specPath))
    let sceneURL = URL(fileURLWithPath: scenePath).standardizedFileURL
    let sceneData = try Data(contentsOf: sceneURL)
    let decoder = JSONDecoder(), encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let spec = try decoder.decode(FigureSpec.self, from: specData), scene = try decoder.decode(FigureScene.self, from: sceneData)
    let engine = try FigureEngine(spec: spec, scene: scene)
    let output = try OutputDirectory(outPath), out = output.url, framesURL = try output.child("frames")
    let fm = FileManager.default
    var background: String?
    var backgroundData: Data?, backgroundName: String?
    if let name = scene.background {
        let url = sceneURL.deletingLastPathComponent().appendingPathComponent(name).standardizedFileURL
        guard fm.fileExists(atPath: url.path) else { throw FigureInputError("background: file does not exist: \(url.path)") }
        backgroundData = try Data(contentsOf: url)
        backgroundName = "background." + (url.pathExtension.isEmpty ? "png" : url.pathExtension.lowercased())
        background = "../" + backgroundName!
    }
    try fm.createDirectory(at: framesURL, withIntermediateDirectories: true)
    try output.removePreviousFrames()
    if let backgroundData, let backgroundName { try backgroundData.write(to: output.child(backgroundName)) }
    var frames: [FigureFrame] = [], motion: [MotionFrame] = []
    for index in 0..<engine.frameCount {
        let frame = engine.frame(index); frames.append(frame)
        motion.append(MotionFrame(frame: index, time: frame.time, actors: frame.actors))
        try Data(FigureSVG.write(frame, scene: scene, background: background).utf8).write(to: output.child("frames/" + frameName(index) + ".svg"))
    }
    func write<T: Encodable>(_ value: T, _ name: String) throws {
        var data = try encoder.encode(value); data.append(10); try data.write(to: output.child(name))
    }
    try write(engine.manifest(specSHA256: FigureSHA256.digest(Array(specData)), sceneSHA256: FigureSHA256.digest(Array(sceneData))), "manifest.json")
    try write(motion, "motion.json"); try write(engine.checks(frames), "checks.json")
    print("\(engine.frameCount) frames, \(engine.duration) s; \(out.path)")
}

do { try run() }
catch {
    FileHandle.standardError.write(Data("figures: \(error)\n".utf8))
    exit(1)
}
