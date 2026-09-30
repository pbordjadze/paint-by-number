import SwiftUI

/// The painting in the focused window, for menu bar commands and keyboard shortcuts.
struct PaintingFocus {
    let session: PaintingSession
    let controller: CanvasController
    let showsNumbers: Binding<Bool>
}

extension FocusedValues {
    @Entry var painting: PaintingFocus?
}

/// The Paint menu (iPadOS menu bar and the ⌘ shortcut overlay). Single keys act like tool
/// keys in drawing apps; the painting screen has no text input for them to collide with.
/// Undo and redo come from the window's undo manager (see `PaintChromeState`).
struct PaintCommands: Commands {
    @FocusedValue(\.painting) private var painting

    var body: some Commands {
        CommandMenu("Paint") {
            Group {
                Button("Next Color") { step(1) }
                    .keyboardShortcut("]", modifiers: [])
                Button("Previous Color") { step(-1) }
                    .keyboardShortcut("[", modifiers: [])
                Button("Show Hint") { painting?.controller.showHint() }
                    .keyboardShortcut("h", modifiers: [])
                    .disabled(painting?.session.isComplete ?? true)
                Divider()
                Toggle("Show Numbers", isOn: painting?.showsNumbers ?? .constant(true))
                    .keyboardShortcut("n", modifiers: [])
                Divider()
                Button("Zoom In") { painting?.controller.zoom(by: 2) }
                    .keyboardShortcut("+")
                Button("Zoom Out") { painting?.controller.zoom(by: 0.5) }
                    .keyboardShortcut("-")
                Button("Zoom to Fit") { painting?.controller.zoomToFit() }
                    .keyboardShortcut("0")
            }
            .disabled(painting == nil)
        }
    }

    /// Selects the next (or previous) color that still has regions to paint.
    private func step(_ delta: Int) {
        guard let session = painting?.session, session.paletteCount > 0 else { return }
        let n = session.paletteCount
        var color = session.selectedColor ?? (delta > 0 ? n - 1 : 0)
        for _ in 0..<n {
            color = (color + delta + n) % n
            if !session.isColorComplete(color) { break }
        }
        guard color != session.selectedColor else { return }
        session.select(color: color)
        FeedbackEngine.shared.selectionChanged()
    }
}
