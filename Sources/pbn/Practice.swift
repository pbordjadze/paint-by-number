import Foundation
import PaintCore

/// `pbn practice`: the Tool Guide's practice picture (`RefinePractice`), written for `pbn refine`
/// to replay a page's gestures on, off the device: photo.ppm (the practice photo), template.pbnt
/// (the scene's template, for `--template`) and painting.ppm (the picture as the page shows it).
func runPractice(_ options: Options) throws {
    if options.positional == ["note"], let out = options.out { return try runPracticeNote(out) }
    guard options.positional.count == 1, let scene = RefinePractice.Scene(rawValue: options.positional[0]), let out = options.out else {
        fail("usage: pbn practice painted|inked|note --out <dir>")
    }
    let outDir = URL(fileURLWithPath: out)
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    let photo = RefinePractice.photo()
    let template: Template
    do { template = try RefinePractice.template(scene, photo: photo) } catch { fail("the practice picture can't be made: \(error)") }
    try writePPM(photo, "photo.ppm", in: outDir)
    try template.encoded().write(to: outDir.appendingPathComponent("template.pbnt"))
    try writePPM(bookRaster(template), "painting.ppm", in: outDir)
    print("\(scene.rawValue): \(template.regions.count) areas, \(template.palette.count) paints, \(template.width)×\(template.height)")
}

/// `pbn practice note`: Writing's practice picture (`RefinePracticeNote`), for `pbn generate` as
/// the app makes it: photo.ppm, edges.pgm (`--edges`), writing.json (`--writing`: the lines the
/// app "found") and missed.json (the pencil line it didn't, as a painter's drag marks it: add it
/// to writing.json's lines to see the marked template).
func runPracticeNote(_ out: String) throws {
    let outDir = URL(fileURLWithPath: out)
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    try writePPM(RefinePracticeNote.photo(), "photo.ppm", in: outDir)
    let input = RefinePracticeNote.lineArt()
    var pgm = Data("P5\n\(input.edges.width) \(input.edges.height)\n255\n".utf8)
    pgm.append(contentsOf: input.edges.values)
    try pgm.write(to: outDir.appendingPathComponent("edges.pgm"))
    func json(_ lines: [[SIMD2<Float>]]) throws -> Data {
        try JSONEncoder().encode(lines.map { $0.map { [$0.x, $0.y] } })
    }
    try json(input.writing).write(to: outDir.appendingPathComponent("writing.json"))
    try json([RefinePracticeNote.missedText]).write(to: outDir.appendingPathComponent("missed.json"))
    print("note: \(input.writing.count) lines found, 1 missed")
}
