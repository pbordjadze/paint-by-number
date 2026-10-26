import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import PaintByNumber

/// Where the preview's picture is, as the create flow reads it to move the picture from
/// (`PreviewPictureProbe`): in the window's coordinates, wherever the comparison's view sits.
@MainActor
struct PreviewPictureTests {
    @Test func theProbeFitsThePhotoInTheComparisonsFrame() {
        let probe = PreviewPictureProbe()
        #expect(probe.picture == nil)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 1000))
        // A container moved down the screen, as a pushed screen's content is.
        let container = UIView(frame: CGRect(x: 0, y: 62, width: 800, height: 938))
        window.addSubview(container)
        let comparison = UIView(frame: CGRect(x: 20, y: 38, width: 400, height: 200))

        // Not in a window (yet): nowhere to move from.
        probe.anchor(comparison, aspect: 2)
        #expect(probe.picture == nil)

        // The comparison takes the photo's shape: the picture is its frame, in the window.
        container.addSubview(comparison)
        #expect(probe.picture == CGRect(x: 20, y: 100, width: 400, height: 200))

        // The enlarged preview's frame is the whole page: the picture is fitted inside it.
        comparison.frame = CGRect(x: 0, y: -62, width: 400, height: 800)
        #expect(probe.picture == CGRect(x: 0, y: 300, width: 400, height: 200))

        // Not laid out, or no photo: nowhere to move from.
        comparison.frame = .zero
        #expect(probe.picture == nil)
        comparison.frame = CGRect(x: 0, y: 0, width: 400, height: 200)
        probe.anchor(comparison, aspect: 0)
        #expect(probe.picture == nil)
    }
}
