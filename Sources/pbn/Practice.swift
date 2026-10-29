import Foundation
import PaintCore

/// `pbn practice`: the Tool Guide's practice picture (`RefinePractice`), written for `pbn refine`
/// to replay a page's gestures on, off the device: photo.ppm (the practice photo), template.pbnt
/// (the scene's template, for `--template`) and painting.ppm (the picture as the page shows it).
func runPractice(_ options: Options) throws {
    guard options.positional.count == 1, let scene = RefinePractice.Scene(rawValue: options.positional[0]), let out = options.out else {
        fail("usage: pbn practice painted|inked --out <dir>")
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
