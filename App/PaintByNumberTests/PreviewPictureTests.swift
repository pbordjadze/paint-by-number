import CoreGraphics
import Foundation
import Testing
@testable import PaintByNumber

/// Where the preview's picture is, as the create flow reads it to move the picture from
/// (`PreviewPictureProbe`).
@MainActor
struct PreviewPictureTests {
    @Test func theProbeFitsThePhotoInTheComparisonsFrame() {
        let probe = PreviewPictureProbe()
        #expect(probe.picture == nil)

        // The comparison takes the photo's shape: the picture is its frame.
        probe.measured(frame: CGRect(x: 20, y: 100, width: 400, height: 200), aspect: 2)
        #expect(probe.picture == CGRect(x: 20, y: 100, width: 400, height: 200))

        // The enlarged preview's frame is the whole page: the picture is fitted inside it.
        probe.measured(frame: CGRect(x: 0, y: 0, width: 400, height: 800), aspect: 2)
        #expect(probe.picture == CGRect(x: 0, y: 300, width: 400, height: 200))

        // Not laid out (yet): nowhere to move from.
        probe.measured(frame: .zero, aspect: 2)
        #expect(probe.picture == nil)
        probe.measured(frame: CGRect(x: 0, y: 0, width: 400, height: 200), aspect: 0)
        #expect(probe.picture == nil)
    }
}
