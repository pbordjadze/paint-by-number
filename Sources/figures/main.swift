// figures render --spec <figure.json> --scene <scene.json> --out <directory>
// Outputs are deterministic review artifacts, never saved paintings. Paths in a scene are
// resolved beside that scene. A local background copy gives every output directory the
// same SVG references, and makes a review bundle portable.
import Foundation
import FigureRig

func run() throws {
    let args = Array(CommandLine.arguments.dropFirst())
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
    let out = URL(fileURLWithPath: outPath).standardizedFileURL, framesURL = out.appendingPathComponent("frames")
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
    // Re-rendering into an existing output must not leave old frames in the clip.
    for url in try fm.contentsOfDirectory(at: framesURL, includingPropertiesForKeys: nil) where url.pathExtension == "svg" || url.pathExtension == "png" {
        try fm.removeItem(at: url)
    }
    if let backgroundData, let backgroundName { try backgroundData.write(to: out.appendingPathComponent(backgroundName)) }
    var frames: [FigureFrame] = [], motion: [MotionFrame] = []
    for index in 0..<engine.frameCount {
        let frame = engine.frame(index); frames.append(frame)
        motion.append(MotionFrame(frame: index, time: frame.time, actors: frame.actors))
        let name = String(repeating: "0", count: max(0, 4 - String(index).count)) + String(index)
        try Data(FigureSVG.write(frame, scene: scene, background: background).utf8).write(to: framesURL.appendingPathComponent(name + ".svg"))
    }
    func write<T: Encodable>(_ value: T, _ name: String) throws {
        var data = try encoder.encode(value); data.append(10); try data.write(to: out.appendingPathComponent(name))
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
