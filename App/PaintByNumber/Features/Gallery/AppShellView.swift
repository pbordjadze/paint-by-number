import CoreTransferable
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// The app's main navigation: gallery → painting (zoom transition), the create flow and
/// settings.
struct AppShellView: View {
    @Environment(Library.self) private var library
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Namespace private var zoom
    @State private var path: [UUID] = []
    /// The gallery's Show filter, remembered per window, and the text of its search field.
    @SceneStorage("galleryFilter") private var filter: GalleryFilter = .all
    #if DEBUG
    @State private var search = ShellDemo.current?.searchText ?? ""
    @State private var isCreating = ShellDemo.current?.opensCreateFlow ?? false
    @State private var isShowingSettings = ShellDemo.current?.opensSettings ?? false
    #else
    @State private var search = ""
    @State private var isCreating = false
    @State private var isShowingSettings = false
    #endif
    @State private var droppedPhoto: Data?
    @State private var droppedTitle: String?
    /// A file opened from another app (share sheet, Files), waiting for the library and the
    /// screen to be free for the create flow.
    @State private var incomingImage: IncomingImage?
    @State private var isReadingFile = false
    /// The time-lapse a gallery card's menu is making. Its sheet is presented here, beside
    /// the settings sheet, so a file that arrives meanwhile can close it before the create flow opens.
    @State private var timelapse: TimelapseRequest?
    /// Changes with every file opened, so a create flow already on screen restarts on it.
    @State private var flowID = UUID()
    @State private var isDropTargeted = false
    @State private var didRestore = false
    /// A painting just created in the create flow, opened once the flow has closed.
    @State private var pendingOpen: UUID?
    @SceneStorage("openArtwork") private var openArtwork = ""

    var body: some View {
        // Read here, not only in the cover's content: a presentation runs its content with the
        // state the last body pass read, and a body that never reads these isn't run again when
        // they change with `isCreating`, so the flow would open without the photo (or keep its
        // old identity).
        let flowPhoto = droppedPhoto
        let flowTitle = droppedTitle
        let flowIdentity = flowID
        NavigationStack(path: $path) {
            GalleryView(namespace: zoom, query: query, timelapse: $timelapse) { isCreating = true }
                // Photos dragged in from another app (Split View, Slide Over) start a painting.
                .dropDestination(for: DroppedPhoto.self) { photos, _ in
                    guard let photo = photos.first, !isCreating else { return false }
                    droppedPhoto = photo.data
                    isCreating = true
                    return true
                } isTargeted: { isDropTargeted = $0 }
                .overlay { if isDropTargeted { DropHighlight().transition(.opacity) } }
                .animation(.easeOut(duration: 0.2), value: isDropTargeted)
                .navigationTitle("Paint by Moonlight")
                .navigationSubtitle(subtitle)
                .toolbar { toolbar }
                .searchable(text: $search, prompt: Text("Search paintings"))
                .navigationDestination(for: UUID.self) { id in
                    ArtworkPaintingView(artworkID: id) { path.removeAll { $0 == id } }
                        .navigationTransition(.zoom(sourceID: id, in: zoom))
                }
        }
        .fullScreenCover(isPresented: $isCreating, onDismiss: {
            droppedPhoto = nil
            droppedTitle = nil
            openPending()
        }) {
            CreateFlowView(openingSample: launchSample, droppedPhoto: flowPhoto, droppedTitle: flowTitle) { artwork in
                pendingOpen = artwork.id
                isCreating = false
            }
            .id(flowIdentity)
            .environment(library)
        }
        .sheet(isPresented: $isShowingSettings, onDismiss: presentIncomingImage) {
            SettingsView(advancedFullScreen: horizontalSizeClass == .regular)
                .environment(library)
        }
        .sheet(item: $timelapse, onDismiss: presentIncomingImage) { request in
            TimelapseExportSheet(request: request)
        }
        .onAppear(perform: restoreOpenArtwork)
        // "Open in Paint by Moonlight" from the share sheet or Files.
        .onOpenURL(perform: openFile)
        .onChange(of: library.placeholders.isEmpty) { presentIncomingImage() }
        // Metal setup off the main thread while the gallery shows, so the first painting opens instantly.
        .task {
            RenderContext.prewarm()
            #if DEBUG
            if ShellDemo.current?.isReadyOnAppear == true { DemoMode.markReady() }
            if let file = DemoMode.openFileURL { openFile(file) }
            #endif
        }
        #if DEBUG
        .onAppear { if ShellDemo.current?.showsFavoritesOnly == true { filter = .favorites } }
        .onChange(of: library.artworks.first?.id) { _, id in
            // Demo: open the painting as soon as it is ready.
            if ShellDemo.current == .galleryOpen, path.isEmpty, let id { path = [id] }
        }
        .onChange(of: library.placeholders) { _, placeholders in
            // Demo: open the damaged painting once it has been seeded (and damaged).
            guard ShellDemo.current == .galleryDamaged, placeholders.isEmpty, path.isEmpty,
                  let id = library.artworks.first?.id else { return }
            path = [id]
        }
        #endif
        .onChange(of: path) { _, path in openArtwork = path.last?.uuidString ?? "" }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Settings", systemImage: "gearshape") { isShowingSettings = true }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Show", selection: $filter) {
                    Label("All", systemImage: "square.grid.2x2").tag(GalleryFilter.all)
                    Label("Favorites", systemImage: "heart").tag(GalleryFilter.favorites)
                }
                .pickerStyle(.inline)
            } label: {
                Label("Show", systemImage: filter == .all
                      ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
            }
            // The filled icon says a filter is on; VoiceOver hears which one.
            .accessibilityValue(filter == .all ? Text("All") : Text("Favorites"))
            .disabled(library.artworks.isEmpty)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("New Painting", systemImage: "plus") { isCreating = true }
                .buttonStyle(.glassProminent)
                .tint(Theme.signature)
        }
    }

    private var query: GalleryQuery { GalleryQuery(filter: filter, search: search) }

    /// Counts what the gallery shows, so a filter or a search is visible in the numbers.
    private var subtitle: String {
        let active = library.inProgress(matching: query).count + (query.isActive ? 0 : library.placeholders.count)
        let finished = library.finished(matching: query).count
        switch (active, finished) {
        case (0, 0):
            return ""
        case (_, 0):
            return String(localized: "gallery.subtitle.inProgress", defaultValue: "\(active) paintings in progress",
                          comment: "Gallery subtitle when every painting is still in progress; the argument is how many")
        case (0, _):
            return String(localized: "gallery.subtitle.finished", defaultValue: "\(finished) finished paintings",
                          comment: "Gallery subtitle when every painting is finished; the argument is how many")
        default:
            let activeText = String(localized: "gallery.subtitle.count.inProgress", defaultValue: "\(active) in progress",
                                    comment: "First part of the gallery subtitle: how many paintings are in progress")
            let finishedText = String(localized: "gallery.subtitle.count.finished", defaultValue: "\(finished) finished",
                                      comment: "Second part of the gallery subtitle: how many paintings are finished")
            return String(localized: "gallery.subtitle.both", defaultValue: "\(activeText) · \(finishedText)",
                          comment: "Gallery subtitle with both counts; the arguments are the in-progress part and the finished part")
        }
    }

    /// The sample the create flow opens on (demo scenarios; none in Release builds).
    private var launchSample: Sample? {
        #if DEBUG
        return ShellDemo.current?.previewSample
        #else
        return nil
        #endif
    }

    /// Starts a painting from a file another app opened in this one. Only the first of several
    /// files opens (one painting per create flow); the others' inbox copies are just deleted.
    private func openFile(_ url: URL) {
        guard url.isFileURL else { return }
        guard !isReadingFile else {
            Task { await IncomingFile.discard(url) }
            return
        }
        isReadingFile = true
        Task {
            incomingImage = await IncomingFile.take(url)
            presentIncomingImage()
        }
    }

    /// Opens the create flow on the file once nothing stands in its way: on a cold launch the
    /// first-launch samples are still being made, and the settings or time-lapse sheet has to
    /// close first (its `onDismiss` comes back here; dismissing the time-lapse sheet cancels its
    /// render). An open painting is dismissed (it saves as it disappears) and a create flow
    /// already on screen starts over on the new photo.
    private func presentIncomingImage() {
        guard let image = incomingImage, library.placeholders.isEmpty else { return }
        guard !isShowingSettings, timelapse == nil else {
            isShowingSettings = false
            timelapse = nil
            return
        }
        incomingImage = nil
        isReadingFile = false
        // A saved painting would otherwise reopen over this flow on a cold launch.
        didRestore = true
        path.removeAll()
        droppedPhoto = image.data
        droppedTitle = image.title
        flowID = UUID()
        isCreating = true
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
        #if DEBUG
        guard !DemoMode.isActive else { return }
        #endif
        guard let id = UUID(uuidString: openArtwork), library.artwork(with: id) != nil else { return }
        path = [id]
    }
}

/// Image data dropped from another app.
nonisolated struct DroppedPhoto: Transferable, Sendable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { DroppedPhoto(data: $0) }
    }
}

/// Shown over the gallery while a photo is dragged over it.
private struct DropHighlight: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 8]))
            .background(Color.accentColor.opacity(0.06), in: .rect(cornerRadius: 28, style: .continuous))
            .overlay {
                Label("Drop to Create a Painting", systemImage: "photo.badge.plus")
                    .font(.display(.title3, weight: .semibold))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                    .glassEffect(.regular, in: .capsule)
            }
            .padding(16)
            .allowsHitTesting(false)
    }
}
