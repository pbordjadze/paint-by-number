import Testing
@testable import PaintCore

/// A Portrait photo's depth and mattes (`PhotoDepth`): nearness spread from the camera's
/// disparity, laid on a template's canvas, cut into planes far to near with the sky farthest,
/// each region given its plane, and kept with a painting as hostile input.
struct PhotoDepthTests {
    /// A left-to-right ramp of nearness, its top quarter sky.
    private static func ramp(width: Int = 64, height: Int = 48, sky: Bool = true) -> PhotoDepth {
        var near = Grid<UInt8>(width: width, height: height, repeating: 0)
        var matte = Grid<UInt8>(width: width, height: height, repeating: 0)
        for y in 0..<height {
            for x in 0..<width {
                near[x, y] = UInt8(x * 255 / (width - 1))
                if y < height / 4 { matte[x, y] = 255 }
            }
        }
        return PhotoDepth(nearness: near, sky: sky ? matte : nil)!
    }

    @Test func disparityIsSpreadAndUnreadPointsAreFar() throws {
        var d = Grid<Float>(width: 10, height: 10, repeating: 0)
        for i in d.storage.indices { d.storage[i] = Float(i) / 10 }
        d.storage[0] = .nan
        d.storage[99] = 1_000 // a stray reading doesn't flatten the rest
        let near = try #require(PhotoDepth.nearness(disparity: d))
        #expect(near.storage[0] == 0)
        #expect(near.storage[98] == 255)
        #expect(near.storage[50] > 100 && near.storage[50] < 160)
        #expect(PhotoDepth.nearness(disparity: Grid(width: 2, height: 1, storage: [.nan, .nan])) == nil)
    }

    @Test func planesShareThePixelsAndTheSkyIsFarthest() {
        let depth = Self.ramp()
        let planes = depth.planes(count: 3)
        var counts = [0, 0, 0]
        for y in 12..<48 { for x in 0..<64 { counts[Int(planes[x, y])] += 1 } }
        // Below the sky, a ramp cut in three: about a third each, near on the right.
        #expect(counts.allSatisfy { abs($0 - 768) <= 64 })
        #expect(planes[0, 30] == 0 && planes[63, 30] == 2)
        for x in 0..<64 { #expect(planes[x, 0] == 0, "the sky is the farthest plane") }
        #expect(depth.planes(count: 1).storage.allSatisfy { $0 == 0 })
    }

    @Test func layingKeepsTheMapsInStep() {
        let depth = Self.ramp()
        let laid = depth.laid(width: 128, height: 96)
        #expect(laid.nearness.width == 128 && laid.sky?.height == 96)
        #expect(laid.nearness[0, 50] < 8 && laid.nearness[127, 50] > 247)
        #expect(laid.sky![60, 2] == 255 && laid.sky![60, 90] == 0)
        #expect(depth.laid(width: 64, height: 48) == depth)
    }

    @Test func regionsTakeTheirPlaneAndTheSky() {
        // Three regions: the sky band, the far left and the near right below it.
        let w = 64, h = 48
        var map = RegionMap(width: w, height: h, repeating: 0)
        for y in 12..<h { for x in 0..<w { map[x, y] = x < 32 ? 1 : 2 } }
        let depth = Self.ramp()
        #expect(depth.regionPlanes(of: map, regions: 3, count: 2) == [0, 0, 1])
        #expect(depth.skyRegions(of: map, regions: 3) == [true, false, false])
        #expect(Self.ramp(sky: false).skyRegions(of: map, regions: 3) == [false, false, false])
    }

    @Test func itKeepsAndReadsAsHostileInput() throws {
        let depth = Self.ramp(width: 9, height: 7)
        let bytes = depth.encoded()
        #expect(try PhotoDepth(decoding: bytes) == depth)
        #expect(throws: PhotoDepth.CodingError.notDepth) { try PhotoDepth(decoding: Array(bytes.prefix(3))) }
        var newer = bytes
        newer[4] = 9
        #expect(throws: PhotoDepth.CodingError.newerVersion) { try PhotoDepth(decoding: newer) }
        #expect(throws: PhotoDepth.CodingError.damaged) { try PhotoDepth(decoding: Array(bytes.dropLast())) }
        var huge = bytes
        huge[8] = 0x7f // a width of billions
        #expect(throws: PhotoDepth.CodingError.damaged) { try PhotoDepth(decoding: huge) }
        var flags = bytes
        flags[13] = 0xff
        #expect(throws: PhotoDepth.CodingError.damaged) { try PhotoDepth(decoding: flags) }
        // Any truncation is refused, never a crash.
        for n in 0..<bytes.count { #expect((try? PhotoDepth(decoding: Array(bytes.prefix(n)))) == nil) }
    }

    /// `depth-v1.bin`, written once by hand to the layout of version 1 (5 × 4, a sky and a skin
    /// matte, no hair) and never regenerated: a print keeps decoding its depth in every build.
    @Test func theFirstFormatKeepsDecoding() throws {
        let depth = try PhotoDepth(decoding: [UInt8](TestFixtures.data("depth-v1.bin")))
        #expect(depth.nearness.width == 5 && depth.nearness.height == 4)
        #expect(depth.nearness[3, 2] == 186)
        #expect(depth.sky?[2, 0] == 255 && depth.sky?[2, 1] == 0)
        #expect(depth.hair == nil)
        #expect(depth.skin?[4, 3] == 200 && depth.skin?[0, 0] == 0)
    }
}
