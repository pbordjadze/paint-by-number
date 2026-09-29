import SwiftUI

/// The app's main navigation: gallery → painting (zoom transition), the create flow and
/// settings.
struct AppShellView: View {
    @Environment(Library.self) private var library
    @Namespace private var zoom
    @State private var path: [UUID] = []
    @State private var isCreating = ShellDemo.current?.opensCreateFlow ?? false
    @State private var isShowingSettings = ShellDemo.current == .settings
    @State private var didRestore = false
    @SceneStorage("openArtwork") private var openArtwork = ""

    var body: some View {
        NavigationStack(path: $path) {
            GalleryView(namespace: zoom) { isCreating = true }
                .navigationTitle("Paint by Numbers")
                .navigationSubtitle(subtitle)
                .toolbar { toolbar }
                .navigationDestination(for: UUID.self) { id in
                    ArtworkPaintingView(artworkID: id) { path.removeAll { $0 == id } }
                        .navigationTransition(.zoom(sourceID: id, in: zoom))
                }
        }
        .fullScreenCover(isPresented: $isCreating) {
            CreateFlowView(demo: ShellDemo.current) { artwork in
                isCreating = false
                path = [artwork.id]
            }
            .environment(library)
            .navigationTransition(.zoom(sourceID: "create", in: zoom))
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
                .environment(library)
        }
        .onAppear(perform: restoreOpenArtwork)
        .onChange(of: path) { _, path in openArtwork = path.last?.uuidString ?? "" }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Settings", systemImage: "gearshape") { isShowingSettings = true }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("New Painting", systemImage: "plus") { isCreating = true }
                .buttonStyle(.glassProminent)
        }
        .matchedTransitionSource(id: "create", in: zoom)
    }

    private var subtitle: String {
        let active = library.inProgress.count + library.placeholders.count
        let finished = library.finished.count
        switch (active, finished) {
        case (0, 0): return ""
        case (_, 0): return active == 1 ? "1 painting in progress" : "\(active) paintings in progress"
        case (0, _): return finished == 1 ? "1 finished painting" : "\(finished) finished paintings"
        default: return "\(active) in progress · \(finished) finished"
        }
    }

    /// Reopens the painting that was open when the app was last suspended.
    private func restoreOpenArtwork() {
        guard !didRestore else { return }
        didRestore = true
        guard !DemoMode.isActive, let id = UUID(uuidString: openArtwork), library.artwork(with: id) != nil else { return }
        path = [id]
    }
}
