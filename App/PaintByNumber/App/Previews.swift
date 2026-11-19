#if DEBUG
import PaintCore
import SwiftUI
import TipKit

// Xcode previews of the screens looked at most, for a picture of one in about 30 seconds instead
// of a CI screenshot run (painting-company row 365). The Mac renders them through Xcode's agent
// bridge, `RenderPreview` on this file with a preview's line (its overrides give dark appearance
// and every Dynamic Type size); the recipe is painting-company's `mac/README.md` › Xcode's MCP
// bridge. Most are the demo scenarios themselves (catalogs: `PaintDemoView`, `MakingOfDemoView`,
// `AboutPaintingDemo`, `PrintPreviewDemo`), which build their own painting as a `-demo` launch
// does; the rest take plain values. A preview named for a scenario is that scenario. Debug only,
// like the demos.

#Preview("paint-progress") {
    PaintDemoView(scenario: "paint-progress").previewEnvironment()
}

#Preview("paint-book-progress") {
    PaintDemoView(scenario: "paint-book-progress").previewEnvironment()
}

#Preview("paint-complete") {
    PaintDemoView(scenario: "paint-complete").previewEnvironment()
}

#Preview("paint-palette") {
    PaintDemoView(scenario: "paint-palette").previewEnvironment()
}

#Preview("about-painting") {
    AboutPaintingDemo(scenario: "about-painting").previewEnvironment()
}

#Preview("print-preview") {
    PrintPreviewDemo(scenario: "print-preview").previewEnvironment()
}

#Preview("making-of") {
    MakingOfDemoView(scenario: "making-of").previewEnvironment()
}

#Preview("gallery-empty") {
    NavigationStack { EmptyGalleryView(onCreate: {}) }.previewEnvironment()
}

#Preview("settings") {
    SettingsView().previewEnvironment()
}

#Preview("unlock") {
    Theme.paper.ignoresSafeArea()
        .sheet(isPresented: .constant(true)) { UnlockSheet() }
        .previewEnvironment()
}

#Preview("fine-tune") {
    Theme.paper.ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            FineTuneSheet(settings: GenerationSettings(), paints: 24, onCut: { _ in })
        }
        .previewEnvironment()
}

#Preview("length-chip") {
    VStack(spacing: 24) {
        LengthChip(regionCount: 406, length: .relaxed, progress: nil, onPick: { _ in }, onFineTune: {})
        LengthChip(regionCount: 406, length: .relaxed, progress: 0.4, onPick: { _ in })
    }
    .padding()
    .previewEnvironment()
}

/// What the app hands every screen (`PaintByNumberApp`): a library of its own in a temporary
/// folder, never the painter's, and Unlimited Paintings from the demos' stand-in store, so a
/// preview buys nothing.
private struct PreviewEnvironment: ViewModifier {
    @State private var library = Library(store: ArtworkStore(
        root: FileManager.default.temporaryDirectory.appending(path: "PreviewLibrary", directoryHint: .isDirectory)))
    @State private var paintings = UnlockStoreStub.paintingsForLaunch()

    func body(content: Content) -> some View {
        content
            .environment(library)
            .environment(paintings)
            .tint(Theme.accent)
            .tipImageStyle(Theme.accent)
    }
}

extension View {
    fileprivate func previewEnvironment() -> some View { modifier(PreviewEnvironment()) }
}
#endif
