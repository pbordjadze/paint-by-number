import SwiftUI

/// The gallery in the focused window, for the app's own menu bar commands: Settings…, New
/// Painting (⌘N) and Search Paintings (⌘F), the shortcuts iPadOS apps share (Mac QA,
/// painting-company row 263).
///
/// Equatable by what the menu shows, not by its closures, as `PaintingFocus` is.
struct GalleryFocus: Equatable {
    let openSettings: () -> Void
    let newPainting: () -> Void
    let search: () -> Void
    /// Another screen is over the shelf (a painting, the create flow, a sheet): only Settings stays.
    let isCovered: Bool

    nonisolated static func == (lhs: GalleryFocus, rhs: GalleryFocus) -> Bool {
        lhs.isCovered == rhs.isCovered
    }
}

extension FocusedValues {
    @Entry var gallery: GalleryFocus?
}

struct GalleryCommands: Commands {
    @FocusedValue(\.gallery) private var gallery

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            // No ⌘,: iPadOS keeps it for its own Settings app, over a menu command and over a key
            // command that asks for priority alike (the Mac's checks, painting-company row 263).
            Button("Settings…") { gallery?.openSettings() }
                .disabled(gallery == nil)
        }
        CommandGroup(replacing: .newItem) {
            Button("Paint") { gallery?.newPainting() }
                .keyboardShortcut("n")
                .disabled(gallery?.isCovered != false)
        }
        CommandGroup(after: .pasteboard) {
            Button("Search Paintings") { gallery?.search() }
                .keyboardShortcut("f")
                .disabled(gallery?.isCovered != false)
        }
    }
}
