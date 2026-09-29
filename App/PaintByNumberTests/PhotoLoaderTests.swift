import Foundation
import PaintCore
import Testing
@testable import PaintByNumber

struct PhotoLoaderTests {
    @Test func decodesBundledSampleIntoDisplayP3() throws {
        let url = try #require(Bundle.main.url(forResource: "parrots", withExtension: "jpg"))
        let image = try PhotoLoader.load(url: url, maxPixelSize: 400)
        #expect(max(image.width, image.height) == 400)
        #expect(image.colorSpace == .displayP3)
        #expect(image.pixels.count == image.width * image.height * 4)
    }
}
