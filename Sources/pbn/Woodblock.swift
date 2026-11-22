import Foundation
import PaintCore

/// `pbn woodblock`: a Woodblock print (painting-company row 375) from a template, off the device:
/// the plan's blocks (the key block's drawing, a block per paint light to dark, the bokashi), each
/// carved, inked and rubbed in full by `WoodblockBench`, the print as it comes off the last
/// block, and once more rubbed lightly, a pass of the baren each.
struct WoodblockReport: Encodable {
    var blocks: [String]
    var inks: [String]
    var standing: [Int]
    var grid: [Int]
}

func runWoodblock(_ options: Options) throws {
    guard let path = options.positional.first, let out = options.out, let data = FileManager.default.contents(atPath: path) else {
        fail("usage: pbn woodblock <template.pbnt> --out <dir>")
    }
    let template: Template
    do { template = try Template(encoded: data) } catch { fail("cannot decode \(path): \(error)") }
    let outDir = URL(fileURLWithPath: out)
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    let plan = WoodblockPlan(template: template)
    let fields = plan.blocks.indices.map { WoodblockField(plan: plan, block: $0) }
    for (name, passes) in [("print.ppm", 0), ("print-light.ppm", 1)] {
        var bench = WoodblockBench(plan: plan)
        while !bench.isDone(in: plan) {
            let field = fields[bench.block]
            if bench.step == .rub && passes > 0 {
                for y in stride(from: Float(0), to: Float(bench.height), by: 6) {
                    bench.rub(from: SIMD2(0, y), to: SIMD2(Float(bench.width), y), radius: 4)
                }
                bench.peel(plan: plan, field: field)
            } else {
                bench.finishStep(plan: plan, field: field)
            }
            if bench.step == .ink, !bench.isDone(in: plan), plan.blocks[bench.block].kind == .bokashi {
                bench.startInked(field: fields[bench.block])
            }
        }
        try writePPM(bench.print(), name, in: outDir)
    }
    let report = WoodblockReport(
        blocks: plan.blocks.map { $0.kind == .color ? "\($0.number)" : "\($0.kind)" },
        inks: plan.blocks.map { b in b.ink.indices.map { String(format: "%02x", Int(b.ink[$0] * 255 + 0.5)) }.joined() },
        standing: fields.map(\.standing), grid: [plan.grid.width, plan.grid.height])
    let json = try jsonEncoder().encode(report)
    try json.write(to: outDir.appendingPathComponent("woodblock.json"))
    print(String(data: json, encoding: .utf8)!)
}
