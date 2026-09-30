import Foundation
import Testing
@testable import PaintCore

@Suite("Template coding")
struct TemplateCodingTests {

    // MARK: - Fixtures

    static func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    /// `Fixtures/template-v1.pbnt` was written by the format-1 encoder at commit ccbbabe with
    /// `pbn trace Fixtures/shapes.ppm <dir>`: a 40×28 flat-color image (white background, a
    /// red square with a blue hole, two green squares touching diagonally, a yellow stripe
    /// along the bottom border). It pins the v1 layout: never regenerate it.
    @Test func decodesV1Fixture() throws {
        let data = try Self.fixture("template-v1.pbnt")
        #expect(data.count == 5558)
        let t = try Template(encoded: data)
        #expect(t.width == 40 && t.height == 28)
        #expect(t.palette.count == 5)
        #expect(t.regions.count == 6)
        #expect(t.edges.count == 7)
        #expect(t.points.count == 86)
        #expect(t.labels.count == 6)
        #expect(t.mesh.indices.count == 146 * 3)
        let report = t.validate()
        #expect(report.isValid, "\(report)")

        // The region map is exactly the 4-connected components of the source's colors.
        let image = try Netpbm.read(Self.fixture("shapes.ppm"))
        var classOf: [UInt32: UInt32] = [:]
        var classes = [UInt32](repeating: 0, count: image.width * image.height)
        for i in classes.indices {
            let key = UInt32(image.pixels[i * 4]) << 16 | UInt32(image.pixels[i * 4 + 1]) << 8 | UInt32(image.pixels[i * 4 + 2])
            classes[i] = classOf[key] ?? { let c = UInt32(classOf.count); classOf[key] = c; return c }()
        }
        let components = ConnectedComponents.label(Grid(width: image.width, height: image.height, storage: classes))
        #expect(t.regionMap == components.labels)
        #expect(t.regions.map(\.colorIndex) == components.classOf)
    }
}
