import Foundation
import PaintCore
import Testing
@testable import PaintByNumber

/// Saved progress: its encoding, readers that know their version, and carrying it onto a
/// regenerated template.
@MainActor
struct PaintProgressTests {
    let template = Fixtures.mosaic

    @Test func progressSurvivesEncoding() throws {
        let session = PaintingSession(template: template)
        session.paint([3, 1, 4, 1, 5, 9, 2, 6], from: .zero, animated: false)
        let data = session.progress.encoded()
        let decoded = try PaintProgress(encoded: data)
        #expect(decoded == session.progress)
        #expect(decoded.log.map(\.region) == [3, 1, 4, 5, 9, 2, 6])
        let restored = try PaintingSession(template: template, progress: decoded)
        #expect(restored.remainingByColor == session.remainingByColor)
        #expect(throws: (any Error).self) { try PaintProgress(encoded: data.prefix(10)) }
    }

    @Test func progressDecodingIsVersionAware() throws {
        var progress = PaintProgress(regionCount: 4)
        progress.activeSeconds = 12
        progress.paint(2)
        progress.paint(0)
        // Layout: magic, version, region count (UInt32 each), seconds (Double), stroke count,
        // then (region UInt32, time Float) per stroke.
        let data = progress.encoded()
        func patched<T: BitwiseCopyable>(at offset: Int, _ value: T) -> Data {
            var bytes = data
            withUnsafeBytes(of: value) { bytes.replaceSubrange(offset..<(offset + $0.count), with: $0) }
            return bytes
        }
        #expect(try PaintProgress(encoded: data + Data([1, 2, 3])) == progress)
        #expect(throws: PaintProgress.CodingError.newerVersion(2)) { try PaintProgress(encoded: patched(at: 4, UInt32(2))) }
        #expect(throws: PaintProgress.CodingError.corrupt) { try PaintProgress(encoded: patched(at: 4, UInt32(0))) }
        #expect(throws: PaintProgress.CodingError.corrupt) { try PaintProgress(encoded: patched(at: 0, UInt32(0))) }
        // A huge region count is rejected before anything is allocated.
        #expect(throws: PaintProgress.CodingError.corrupt) { try PaintProgress(encoded: patched(at: 8, UInt32.max)) }
        #expect(throws: PaintProgress.CodingError.corrupt) { try PaintProgress(encoded: patched(at: 20, UInt32.max)) }
        // So is a count above what the caller's template has: a tiny file cannot claim the canvas cap.
        let claimsCap = patched(at: 8, UInt32(Template.maxCanvasArea))
        #expect(throws: PaintProgress.CodingError.tooManyRegions(Template.maxCanvasArea)) {
            try PaintProgress(encoded: claimsCap, maxRegionCount: 4)
        }
        #expect(throws: PaintProgress.CodingError.tooManyRegions(4)) { try PaintProgress(encoded: data, maxRegionCount: 3) }
        #expect(try PaintProgress(encoded: data, maxRegionCount: 4) == progress)
        // The second stroke repeats the first region.
        #expect(throws: PaintProgress.CodingError.corrupt) { try PaintProgress(encoded: patched(at: 32, UInt32(2))) }

        let nan = try PaintProgress(encoded: patched(at: 12, Double.nan))
        #expect(nan.activeSeconds == 0)
        #expect(nan.log.map(\.region) == [2, 0])
        let negative = try PaintProgress(encoded: patched(at: 28, Float(-5)))
        #expect(negative.log.map(\.time) == [0, 12])
    }

    @Test func remappedCarriesProgressAcrossTemplates() {
        let old = Fixtures.stripes(), new = Fixtures.stripes(count: 6, stripeWidth: 10)
        var progress = PaintProgress(regionCount: 3)
        progress.activeSeconds = 5
        progress.paint(2)
        progress.activeSeconds = 9
        progress.paint(0)

        // Each old stripe became two new ones, which take its place in the painting order.
        let remapped = progress.remapped(from: old, to: new)
        #expect(remapped.regionCount == 6)
        #expect(remapped.log.map(\.region) == [4, 5, 0, 1])
        #expect(remapped.log.map(\.time) == [5, 5, 9, 9])
        #expect(remapped.activeSeconds == 9)
        #expect(!remapped.isPainted(2) && !remapped.isPainted(3))

        #expect(progress.remapped(from: old, to: old) == progress)
        // Progress that doesn't belong to `old` can't be carried.
        #expect(PaintProgress(regionCount: 5).remapped(from: old, to: new) == PaintProgress(regionCount: 6))
    }
}
