import CoreGraphics
import SwiftUI
import Testing
@testable import PaintByNumber

/// The making-of show's numbers are filled as their glyphs' outlines, never drawn as text, which
/// queues an accessibility label per draw when VoiceOver is on (painting-company row 320).
struct MakingOfNumberTests {
    @Test(arguments: [1, 7, 12, 30])
    func numbersAreCentredAndUpright(_ value: Int) {
        let size = MakingOfCanvas.digitSize
        let bounds = MakingOfCanvas.numberOutline(value).boundingRect
        #expect(!bounds.isEmpty, "\(value) has ink")
        #expect(bounds.width < size * CGFloat(String(value).count), "\(value) is as wide as its digits")
        // Centred across by its advance, as text anchored at its centre was.
        #expect(abs(bounds.midX) < size * 0.15)
        // Digits stand on the baseline, (ascent - descent) / 2 below the middle (about a third of
        // the size in New York), and reach up past the middle (y down); drawn upside down they
        // would hang below the baseline, all of them under the middle.
        #expect(bounds.maxY > 0 && bounds.maxY < size * 0.5)
        #expect(bounds.minY < -size * 0.15)
    }
}
