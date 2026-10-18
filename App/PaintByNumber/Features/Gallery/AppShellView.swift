import CoreTransferable
import Foundation
import os
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The app's main navigation: gallery → painting (zoom transition), the create flow,
/// settings and The Marginarium.
struct AppShellView: View {
    @Environment(Library.self) private var library
    @Environment(\.horizontalSizeClass) private var sizeClass
    #if UNRELEASED
    /// The Marginarium is in Debug and SideStore builds only for now (`UNRELEASED`): the release
    /// leaves out its code, its chapters and its drawings (the target's Release
    /// `EXCLUDED_SOURCE_FILE_NAMES`, `ci/check_release.sh`).
    @AppStorage(SettingsKey.showsMarginarium) private var showsMarginarium = false
    #endif
    @Namespace private var zoom
    @State private var path: [UUID] = []
    /// The gallery's Show filter, remembered per window, and the text of its search field.
    @SceneStorage("galleryFilter") private var filter: GalleryFilter = .all
    #if DEBUG
    @State private var search = ShellDemo.current?.searchText ?? ""
    @State private var isCreating = ShellDemo.current?.opensCreateFlow ?? false
    @State private var isShowingSettings = ShellDemo.current?.opensSettings ?? false
    @State private var isShowingMarginarium = ShellDemo.current?.opensMarginarium ?? false
    #else
    @State private var search = ""
    @State private var isCreating = false
    @State private var isShowingSettings = false
    @State private var isShowingMarginarium = false
    #endif
    @State private var droppedPhoto: Data?
    @State private var droppedTitle: String?
    /// The draft the create flow continues, read off the main actor by the gallery's row.
    @State private var resumedDraft: Drafts.Opened?
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
    /// Start Painting's hand-off to the painting it makes: the painting opens under the create
    /// flow's cover, which dissolves into it. Passed through the environment to the flow and to
    /// the painting (`StartHandoff`).
    @State private var handoff = StartHandoff()
    @SceneStorage("openArtwork") private var openArtwork = ""
    #if DEBUG
    /// The `gallery-open` demo opens its painting once: the gallery's other seeds land later, and
    /// one landing after the painting was closed must not open it again.
    @State private var demoOpenedPainting = false
    #endif

    var body: some View {
        // Read here, not only in the cover's content: a presentation runs its content with the
        // state the last body pass read, and a body that never reads these isn't run again when
        // they change with `isCreating`, so the flow would open without the photo (or keep its
        // old identity).
        let flowPhoto = droppedPhoto
        let flowTitle = droppedTitle
        let flowDraft = resumedDraft
        let flowIdentity = flowID
        NavigationStack(path: $path) {
            GalleryView(
                namespace: zoom, query: query, timelapse: $timelapse, onCreate: { isCreating = true },
                onContinueDraft: continueDraft)
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
                    // The zoom is for pushes from a card and for the way back to it; the painting
                    // Start Painting makes is pushed under the cover (`startPainting`).
                    ArtworkPaintingView(artworkID: id) { path.removeAll { $0 == id } }
                        .navigationTransition(.zoom(sourceID: id, in: zoom))
                }
        }
        .environment(\.startHandoff, handoff)
        .fullScreenCover(isPresented: $isCreating, onDismiss: {
            droppedPhoto = nil
            droppedTitle = nil
            resumedDraft = nil
            handoff.reset()
        }) {
            CreateFlowView(
                openingSample: launchSample, droppedPhoto: flowPhoto, droppedTitle: flowTitle, resuming: flowDraft,
                onStart: startPainting
            )
            .id(flowIdentity)
            .environment(library)
            .environment(\.startHandoff, handoff)
            // The flow draws its own background and leaves the cover clear, so that it can fade to
            // the painting opened beneath it.
            .presentationBackground(.clear)
        }
        .onChange(of: handoff.isFinished) { _, finished in
            if finished { endCreateFlow() }
        }
        .sheet(isPresented: $isShowingSettings, onDismiss: presentIncomingImage) {
            SettingsView()
                .environment(library)
        }
        #if UNRELEASED
        .sheet(isPresented: $isShowingMarginarium, onDismiss: presentIncomingImage) {
            if UIDevice.current.userInterfaceIdiom == .pad, sizeClass == .regular {
                MarginariumView()
                    .presentationSizing(.page)
            } else {
                MarginariumView()
            }
        }
        #endif
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
            guard ShellDemo.current == .galleryOpen, !demoOpenedPainting, path.isEmpty, let id else { return }
            demoOpenedPainting = true
            path = [id]
        }
        .onChange(of: library.placeholders) { _, placeholders in
            // Demo: open the damaged painting once it has been seeded (and damaged).
            guard ShellDemo.current == .galleryDamaged, placeholders.isEmpty, path.isEmpty,
                  let id = library.artworks.first?.id else { return }
            path = [id]
        }
        #endif
        .onChange(of: path) { _, path in openArtwork = path.last?.uuidString ?? "" }
        // The shelf's tips wait while anything covers it, and have their moment when it is uncovered.
        .onChange(of: isCovered, initial: true) { _, covered in
            PaintTips.desk.isCovered = covered
            if covered {
                if isCreating { PaintTips.used(.shelfNewPainting) }
            } else {
                PaintTips.shelfMoment(library)
            }
        }
    }

    /// A screen over the shelf: the create flow, Settings, the time-lapse's sheet, the Marginarium.
    private var isCovered: Bool {
        isCreating || isShowingSettings || timelapse != nil || isShowingMarginarium
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Settings", systemImage: "gearshape") { isShowingSettings = true }
                // Where the tips can be turned off: hung below the gear.
                .barTip(.shelfSettings)
        }
        #if UNRELEASED
        if showsMarginarium {
            ToolbarItem(placement: .topBarLeading) {
                Button("The Marginarium", systemImage: "book.pages") { isShowingMarginarium = true }
            }
        }
        #endif
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
        // An empty gallery's own New Painting is the only one.
        if !isBare {
            ToolbarItem(placement: .topBarTrailing) {
                Button("New Painting", systemImage: "plus") { isCreating = true }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.signature)
                    .barTip(.shelfNewPainting)
            }
        }
    }

    /// Nothing to show at all: the gallery is its empty state (`GalleryView`).
    private var isBare: Bool { library.isEmpty && library.drafts.current == nil }

    private var query: GalleryQuery { GalleryQuery(filter: filter, search: search) }

    /// Counts what the gallery shows, so a filter or a search is visible in the numbers.
    private var subtitle: String {
        GalleryCounts(
            inProgress: library.inProgress(matching: query).count,
            ready: library.readyToPaint(matching: query).count + (query.isActive ? 0 : library.placeholders.count),
            finished: library.finished(matching: query).count
        ).subtitle
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
    /// first-launch samples are still being made, and the settings, Marginarium or time-lapse
    /// sheet has to close first (its `onDismiss` comes back here; dismissing the time-lapse sheet
    /// cancels its render). An open painting is dismissed (it saves as it disappears) and a
    /// create flow already on screen starts over on the new photo. Not handled (untested): the
    /// gallery's rename and delete dialogs and the painting screen's own sheets can be up when a
    /// file arrives, and may keep the create flow from presenting.
    private func presentIncomingImage() {
        guard let image = incomingImage, library.placeholders.isEmpty else { return }
        guard !isShowingSettings, !isShowingMarginarium, timelapse == nil else {
            isShowingSettings = false
            isShowingMarginarium = false
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
        resumedDraft = nil
        // A hand-off still under way belonged to the flow this one replaces.
        handoff.reset()
        flowID = UUID()
        isCreating = true
    }

    /// Opens the create flow on the draft the gallery's row read.
    private func continueDraft(_ opened: Drafts.Opened) {
        resumedDraft = opened
        isCreating = true
    }

    /// Start Painting has saved `artwork`. The cover stays up, showing the create flow's picture;
    /// the painting is pushed beneath it, and the flow dissolves into it once its canvas has drawn
    /// (`StartHandoff`). The push is the usual one, its zoom run unseen under the opaque cover: with
    /// no animation at all the edge swipe back never worked (`StartHandoffUITests`).
    private func startPainting(_ artwork: Artwork) {
        guard handoff.begin(artwork.id) else { return }
        guard StartHandoffLogic.shouldPush(artwork.id, onto: path) else { return }
        path = [artwork.id]
    }

    /// The flow has dissolved into the painting: the cover goes without a slide.
    private func endCreateFlow() {
        let wasCovering = isCreating
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { isCreating = false }
        // The cover's `onDismiss` resets the hand-off; with no cover up it never comes.
        if !wasCovering { handoff.reset() }
    }

    /// Reopens the painting that was open when the app was last suspended.
    private func restoreOpenArtwork() {
        guard !didRestore else { return }
        didRestore = true
        #if DEBUG
        guard !DemoMode.isActive else { return }
        #endif
        let guardian = ReopenGuard()
        guard guardian.mayReopen() else {
            Log.library.error("The painting reopened at the last launch never settled; showing the gallery")
            openArtwork = ""
            return
        }
        guard let id = UUID(uuidString: openArtwork), library.artwork(with: id) != nil else { return }
        guardian.begin()
        path = [id]
        Task {
            try? await Task.sleep(for: ReopenGuard.settleDelay)
            guardian.settled()
        }
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
