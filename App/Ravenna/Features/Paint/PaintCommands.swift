import SwiftUI

/// The painting in the focused window, for menu bar commands and keyboard shortcuts.
///
/// Equatable by what the menu shows, not by its closure: a focused value that never compares equal
/// counts as changed at every render of the painting screen, which rebuilt the Paint menu every
/// time and kept the screen rendering 30 to 70 times a second, enough to hang the UI tests
/// (`StartHandoffUITests`, October 19).
struct PaintingFocus: Equatable {
    let session: PaintingSession
    let controller: CanvasController
    let showsNumbers: Binding<Bool>
    /// Nil when the painting has no photo to show.
    let showsPhoto: Binding<Bool>?
    /// Feedback mode: painting is off, so are the commands.
    let isGivingFeedback: Bool
    let giveFeedback: () -> Void
    /// What the two toggles showed when this focus was made: their bindings read the current state,
    /// so an older focus would always agree with a newer one.
    private let shown: (numbers: Bool, photo: Bool?)

    init(
        session: PaintingSession, controller: CanvasController, showsNumbers: Binding<Bool>,
        showsPhoto: Binding<Bool>?, isGivingFeedback: Bool, giveFeedback: @escaping () -> Void
    ) {
        self.session = session
        self.controller = controller
        self.showsNumbers = showsNumbers
        self.showsPhoto = showsPhoto
        self.isGivingFeedback = isGivingFeedback
        self.giveFeedback = giveFeedback
        shown = (showsNumbers.wrappedValue, showsPhoto?.wrappedValue)
    }

    nonisolated static func == (lhs: PaintingFocus, rhs: PaintingFocus) -> Bool {
        lhs.session === rhs.session && lhs.controller === rhs.controller
            && lhs.isGivingFeedback == rhs.isGivingFeedback
            && lhs.shown.numbers == rhs.shown.numbers && lhs.shown.photo == rhs.shown.photo
    }
}

extension FocusedValues {
    @Entry var painting: PaintingFocus?
}
