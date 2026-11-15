import Foundation
import PaintCore
import Testing
@testable import MakingOf

/// `Fixtures/show-small/`: the stage pictures and the coloring-book template of a 144 x 96 crop of
/// the parrots photo, at 216 x 144 (its commit message has the recipe), and `inputs-small.json`,
/// what `making_of_inputs.py` makes of them.
struct SmallShow {
    let directory: URL
    let pictures: ShowPictures
    let template: Template
    let show: ShowTemplate
    let spec: ShowSpec
    let expected: ExpectedInputs

    /// The seed the fixture was made with.
    static let seed: UInt64 = 7

    init() throws {
        directory = try #require(Bundle.module.url(forResource: "show-small", withExtension: nil, subdirectory: "Fixtures"))
        pictures = try ShowPictures(directory: directory)
        template = try Template(encoded: Data(contentsOf: directory.appendingPathComponent("template.pbnt")))
        show = ShowTemplate(template, width: pictures.width, height: pictures.height)
        spec = try ShowSpec(json: shippedSpecData())
        expected = try JSONDecoder().decode(ExpectedInputs.self, from: Data(contentsOf: directory.appendingPathComponent("inputs-small.json")))
    }

    /// `making_of_inputs.py`'s JSON, as far as the tests read it (its `inputs` are the Python's own:
    /// the size, the timing and the template's lines as its show keeps them).
    struct ExpectedInputs: Decodable {
        struct Trace: Decodable {
            /// How many merged regions the simplified picture has.
            var labels: Int
        }

        var seed: UInt64
        /// [time, x, y, paint] each.
        var seeds: [[Double]]
        /// The palette picture's colors, `r << 16 | g << 8 | b`, ascending.
        var paints: [UInt32]
        var trace: Trace

        var paintSeeds: [PaintSeed] { seeds.map { PaintSeed(time: $0[0], x: $0[1], y: $0[2], paint: Int($0[3])) } }
    }
}
