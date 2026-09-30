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
    /// A painting just created in the create flow, opened once the flow has closed.
    @State private var pendingOpen: UUID?
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
        .fullScreenCover(isPresented: $isCreating, onDismiss: openPending) {
            CreateFlowView(demo: ShellDemo.current) { artwork in
                pendingOpen = artwork.id
                isCreating = false
            }
            .environment(library)
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
                .environment(library)
        }
        .onAppear(perform: restoreOpenArtwork)
        // Metal setup off the main thread while the gallery shows, so the first painting opens instantly.
        .task {
            RenderContext.prewarm()
            if ShellDemo.current?.isReadyOnAppear == true { DemoMode.markReady() }
        }
        .onChange(of: library.artworks.first?.id) { _, id in
            // Demo: open the painting as soon as it is ready.
            if ShellDemo.current == .galleryOpen, path.isEmpty, let id { path = [id] }
        }
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

    private func openPending() {
        guard let id = pendingOpen else { return }
        pendingOpen = nil
        path = [id]
    }

    /// Reopens the painting that was open when the app was last suspended.
    private func restoreOpenArtwork() {
        guard !didRestore else { return }
        didRestore = true
        guard !DemoMode.isActive, let id = UUID(uuidString: openArtwork), library.artwork(with: id) != nil else { return }
        path = [id]
    }
}
