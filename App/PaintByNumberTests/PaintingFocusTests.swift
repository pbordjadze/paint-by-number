import SwiftUI
import Testing
@testable import PaintByNumber

/// The painting screen publishes a `PaintingFocus` at every render: it must compare equal while
/// nothing the Paint menu shows changes, or each render rebuilds the menu and renders again.
@MainActor
struct PaintingFocusTests {
    private let session = PaintingSession(template: Fixtures.mosaic)
    private let controller = CanvasController()

    private func focus(numbers: Bool = true, photo: Bool? = false, feedback: Bool = false) -> PaintingFocus {
        PaintingFocus(
            session: session, controller: controller, showsNumbers: .constant(numbers),
            showsPhoto: photo.map { .constant($0) }, isGivingFeedback: feedback, giveFeedback: {})
    }

    @Test func aRenderWithNothingChangedPublishesAnEqualFocus() {
        #expect(focus() == focus())
    }

    @Test func whatTheMenuShowsMakesItANewFocus() {
        #expect(focus() != focus(numbers: false), "Show Numbers")
        #expect(focus() != focus(photo: true), "Show Photo")
        #expect(focus() != focus(photo: nil), "no photo to show")
        #expect(focus() != focus(feedback: true), "feedback mode")
        let other = PaintingFocus(
            session: PaintingSession(template: Fixtures.mosaic), controller: controller,
            showsNumbers: .constant(true), showsPhoto: .constant(false), isGivingFeedback: false, giveFeedback: {})
        #expect(focus() != other, "another painting")
    }
}
