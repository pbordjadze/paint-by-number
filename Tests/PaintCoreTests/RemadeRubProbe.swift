import Foundation
import Testing
@testable import PaintCore

/// A measurement, not a check: how many eraser rubs made on one template find their line on the
/// same photo's template made again, before and after `TemplateEditor.reanchored`
/// (painting-company row 322). Runs only with `REMADE_RUB_A` and `REMADE_RUB_B` set to two
/// `template.pbnt` files (`pbn generate` of one photo at two settings, as a coloring book):
/// `PBN_MOUNT=<their folder> PBN_ENV="REMADE_RUB_A REMADE_RUB_B" REMADE_RUB_A=a.pbnt REMADE_RUB_B=b.pbnt`
/// `tools/swift.sh test --filter RemadeRubProbe`.
/// Each rub is the app test's (`CreateModelTests.refined`): 6 units across the middle of a drawn
/// edge of more than 6 points, radius 4, scaled to B's canvas.
@Suite("Remade rub probe")
struct RemadeRubProbe {
    @Test func rubsFindTheirLines() throws {
        let env = ProcessInfo.processInfo.environment
        guard let a = env["REMADE_RUB_A"], let b = env["REMADE_RUB_B"] else { return }
        let made = try Template(encoded: Data(contentsOf: URL(fileURLWithPath: a)))
        let remade = try Template(encoded: Data(contentsOf: URL(fileURLWithPath: b)))
        let art = try #require(made.lineArt)
        let scale = SIMD2(Float(remade.width) / Float(made.width), Float(remade.height) / Float(made.height))
        var tried = 0, madeThere = 0, before = 0, after = 0
        var missed: [Double] = []
        for (e, edge) in made.edges.enumerated() where edge.pointCount > 6 && art.edgeLayers[e] != LineLayer.color.rawValue
            && edge.right != BoundaryEdge.outside {
            guard tried < 300 else { break }
            let middle = made.points[Int(edge.pointStart + edge.pointCount / 2)]
            let rub = TemplateEditor.Edit.erase(path: [middle - SIMD2(3, 0), middle + SIMD2(3, 0)], radius: 4)
            guard try TemplateEditor.apply(rub, to: made).outcome.changed else { continue }
            tried += 1
            madeThere += 1
            let scaled = rub.scaled(x: scale.x, y: scale.y)
            if try TemplateEditor.apply(scaled, to: remade).outcome.changed { before += 1; after += 1; continue }
            var trail = EditTrail(base: remade)
            if try trail.move(to: [scaled]).made == 1 { after += 1; continue }
            // How far the nearest ink is from a rub still left out (nil: none within 64 units).
            if case .erase(let path, _) = scaled, var work = try? EditWork(remade),
               let step = work.nearestInk(to: path.map(Lattice.point), within: 64 * Lattice.unit) {
                let d = Lattice.double(step)
                missed.append((d.x * d.x + d.y * d.y).squareRoot())
            } else {
                missed.append(.infinity)
            }
        }
        print("REMADE_RUB rubs \(madeThere): found their line \(before) before, \(after) after re-anchoring; the rest's nearest ink \(missed.sorted().map { $0.isFinite ? String(format: "%.1f", $0) : "none" })")
    }
}
