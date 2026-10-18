import Foundation
import SwiftUI

/// The gallery: paintings in progress, ready to paint (nobody has painted on them yet) and
/// finished, each section an adaptive grid of cards.
struct GalleryView: View {
    let namespace: Namespace.ID
    /// The Show filter and the search text: what the gallery lists.
    let query: GalleryQuery
    /// The time-lapse being made; the app shell presents its sheet.
    @Binding var timelapse: TimelapseRequest?
    var onCreate: () -> Void
    /// The painter chose to continue refining the create flow's draft.
    var onContinueDraft: (Drafts.Opened) -> Void
    /// Whether a rename, restart or delete question (or the restart's failure) is up; set false
    /// by the shell to close it, as a photo shared in from another app does.
    @Binding var isAsking: Bool

    @Environment(Library.self) private var library
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var width: CGFloat = 0
    @State private var renaming: Artwork?
    @State private var renameText = ""
    @State private var restarting: Artwork?
    @State private var deleting: Artwork?
    @State private var restartFailed = false
    @State private var isOpeningDraft = false

    var body: some View {
        ScrollView {
            if !isBare {
                VStack(alignment: .leading, spacing: 36) {
                    if let draft = shownDraft {
                        DraftRow(
                            draft: draft, photo: library.drafts.store.url(.source), isCompact: width < 560,
                            isOpening: isOpeningDraft, onContinue: continueDraft, onDiscard: { library.drafts.discard() }
                        )
                        .transition(.opacity)
                    }
                    // A painting nobody has painted on is ready to paint, not in progress.
                    let active = library.inProgress(matching: query)
                    if !active.isEmpty {
                        section("In Progress", count: active.count) {
                            ForEach(active) { card($0) }
                        }
                    }
                    let ready = library.readyToPaint(matching: query)
                    let preparing = shownPlaceholders
                    if !ready.isEmpty || !preparing.isEmpty {
                        section("Ready to Paint", count: ready.count + preparing.count, tip: .shelfStarter) {
                            ForEach(preparing) { PlaceholderCard(placeholder: $0) }
                            ForEach(ready) { card($0) }
                        }
                    }
                    let finished = library.finished(matching: query)
                    if !finished.isEmpty {
                        section("Finished", count: finished.count) {
                            ForEach(finished) { card($0) }
                        }
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 6)
                .padding(.bottom, 56)
            }
        }
        .scrollDisabled(isBare)
        // An empty scroll view collapses; keep the paper (and the empty state) full size.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper)
        .overlay {
            if isBare {
                EmptyGalleryView(onCreate: onCreate)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else if isNarrowedToNothing {
                narrowedEmptyState
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) { toasts }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        // The shelf's tips: a visit begins, the library changes under it (its pages come into view,
        // one is painted or finished), tips are switched on.
        .onAppear {
            PaintTips.desk.enter(.shelf)
            PaintTips.shelfMoment(library)
        }
        .onDisappear { PaintTips.desk.leave(.shelf) }
        .onChange(of: library.tipFacts) { PaintTips.shelfMoment(library) }
        .onChange(of: PaintTips.desk.answers) { PaintTips.shelfMoment(library) }
        // Deleting, filtering, searching and (un)favoriting all move cards.
        .animation(reduceMotion ? nil : .snappy, value: shownIDs)
        .animation(reduceMotion ? nil : .snappy, value: library.placeholders)
        .animation(reduceMotion ? nil : .snappy, value: shownDraft?.photoID)
        .animation(.easeInOut(duration: 0.35), value: isBare)
        .alert("This painting can’t be restarted.", isPresented: $restartFailed) {}
        // A photo shared in from another app can't present over a question: the shell closes it.
        .onChange(of: hasQuestion) { _, asks in isAsking = asks }
        .onChange(of: isAsking) { _, asks in
            guard !asks else { return }
            renaming = nil
            restarting = nil
            deleting = nil
            restartFailed = false
        }
        .alert("Rename Painting", isPresented: isPresent($renaming), presenting: renaming) { artwork in
            TextField("Title", text: $renameText)
                .submitLabel(.done)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { library.rename(artwork.id, to: renameText) }
        }
        #if DEBUG
        .task(id: library.finished.first?.id) {
            // Demo: share the finished painting's time-lapse once it is ready.
            if ShellDemo.current?.sharesTimelapse == true, timelapse == nil, let artwork = library.finished.first {
                shareTimelapse(artwork)
            }
        }
        #endif
    }

    // MARK: Query

    /// Paintings still being prepared belong to no selection: they show only while nothing is narrowed.
    private var shownPlaceholders: [Library.Placeholder] { query.isActive ? [] : library.placeholders }

    private var shownIDs: [UUID] {
        (library.inProgress(matching: query) + library.readyToPaint(matching: query) + library.finished(matching: query)).map(\.id)
    }

    /// There are paintings or a draft, but the filter or the search hides every one.
    private var isNarrowedToNothing: Bool { shownIDs.isEmpty && shownPlaceholders.isEmpty && shownDraft == nil }

    /// The create flow's draft belongs to no selection either: it shows while nothing is narrowed.
    private var shownDraft: CreateDraft? { query.isActive ? nil : library.drafts.current }

    /// Nothing to list, not even a draft: the invitation to the first painting shows instead.
    private var isBare: Bool { library.isEmpty && library.drafts.current == nil }

    @ViewBuilder
    private var narrowedEmptyState: some View {
        if query.isSearching {
            ContentUnavailableView.search(text: query.search)
        } else {
            ContentUnavailableView(
                "No Favorites", systemImage: "heart",
                description: Text("Touch and hold a painting, then choose Favorite."))
        }
    }

    // MARK: Layout

    /// Cards of roughly 240–330 pt: three across a portrait iPad, four or five in landscape.
    private var columnCount: Int {
        switch width {
        case ..<560: 2
        case ..<1100: 3
        case ..<1300: 4
        default: 5
        }
    }

    /// The system's own margin, where the large title and its subtitle sit (16 pt on compact
    /// widths, 20 pt on regular ones), so the cards start where they do.
    private var horizontalPadding: CGFloat { sizeClass == .compact ? 16 : 20 }
    private var spacing: CGFloat { width < 560 ? 16 : 26 }

    /// `tip` is a tip inline under the header while it has the turn (a popover would have nothing to
    /// point at).
    private func section<Content: View>(
        _ title: LocalizedStringKey, count: Int, tip: TipID? = nil, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.display(.title2))
                Text(count, format: .number)
                    .font(.display(.title3, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            if let tip, PaintTips.desk.turn == tip {
                GentleTipView(id: tip)
                    .transition(.opacity)
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .top), count: columnCount),
                alignment: .leading, spacing: spacing + 8
            ) {
                content()
            }
        }
        // A fade, with nothing moving but the cards making room, under Reduce Motion as well.
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: PaintTips.desk.turn)
    }

    /// The tips a card carries: touching and holding the first painting shown, and the first
    /// finished one's time-lapse.
    private func tips(of artwork: Artwork) -> [TipID] {
        var ids: [TipID] = []
        if shownIDs.first == artwork.id { ids.append(.shelfHold) }
        if library.finished(matching: query).first?.id == artwork.id { ids.append(.shelfTimeLapse) }
        return ids
    }

    private func card(_ artwork: Artwork) -> some View {
        NavigationLink(value: artwork.id) {
            ArtworkCard(artwork: artwork, namespace: namespace)
        }
        .buttonStyle(PressableCardStyle())
        .cardTip(tips(of: artwork))
        // The grid builds cards beyond the screen's edge too: a tip waits for its card to be mostly
        // in view, or it would point off the screen.
        .onScrollVisibilityChange(threshold: 0.6) { visible in PaintTips.desk.anchor(tips(of: artwork), present: visible) }
        .onDisappear { PaintTips.desk.anchor(tips(of: artwork), present: false) }
        .contextMenu { menu(for: artwork) }
        // A confirmation dialog is a popover on the view that carries it, so each card carries the
        // two its menu asks for and the popover points at it, where one on the whole gallery
        // pointed at its middle. `restarting` and `deleting` still say which painting is pending.
        .confirmationDialog(
            "Start this painting over?", isPresented: isPending($restarting, artwork), titleVisibility: .visible,
            presenting: restarting
        ) { pending in
            Button(String(localized: "gallery.restart.confirm", defaultValue: "Restart “\(pending.title)”",
                          comment: "Destructive button of the restart confirmation; the argument is the painting's title"),
                   role: .destructive) {
                Task { if await !library.restart(pending.id) { restartFailed = true } }
            }
        } message: { _ in
            Text("Every painted area will be cleared.")
        }
        .confirmationDialog(
            "Delete this painting?", isPresented: isPending($deleting, artwork), titleVisibility: .visible, presenting: deleting
        ) { pending in
            // Undoable for a few seconds afterwards (the toast's Undo).
            Button(DeleteConfirmation.buttonTitle(for: pending), role: .destructive) { library.delete(pending.id) }
        } message: { pending in
            DeleteConfirmationMessage(artwork: pending)
        }
    }

    private var hasQuestion: Bool { renaming != nil || restarting != nil || deleting != nil || restartFailed }

    // MARK: Actions

    /// Reads the draft off the main actor, then opens the create flow on it.
    private func continueDraft() {
        guard !isOpeningDraft else { return }
        isOpeningDraft = true
        Task {
            if let opened = await library.drafts.open() { onContinueDraft(opened) }
            isOpeningDraft = false
        }
    }

    @ViewBuilder
    private func menu(for artwork: Artwork) -> some View {
        if artwork.needsNewerApp {
            // Everything else would read or rewrite files this version doesn't understand.
            deleteButton(for: artwork)
        } else {
            editingMenu(for: artwork)
        }
    }

    @ViewBuilder
    private func editingMenu(for artwork: Artwork) -> some View {
        if artwork.isFavorite {
            Button("Unfavorite", systemImage: "heart.slash") {
                PaintTips.used(.shelfHold)
                library.setFavorite(artwork.id, false)
            }
        } else {
            Button("Favorite", systemImage: "heart") {
                PaintTips.used(.shelfHold)
                library.setFavorite(artwork.id, true)
            }
        }
        Divider()
        Button("Rename", systemImage: "pencil") {
            PaintTips.used(.shelfHold)
            renameText = artwork.title
            renaming = artwork
        }
        Divider()
        ShareLink(
            item: PaintingImageFile(store: library.store, artwork: artwork),
            preview: SharePreview(artwork.title, image: previewImage(artwork))
        ) {
            if artwork.isComplete {
                Label("Share Painting", systemImage: "square.and.arrow.up")
            } else {
                Label("Share Progress", systemImage: "square.and.arrow.up")
            }
        }
        if artwork.isComplete {
            Button("Share Time-lapse", systemImage: "timelapse") {
                PaintTips.used(.shelfHold)
                PaintTips.used(.shelfTimeLapse)
                shareTimelapse(artwork)
            }
        }
        ShareLink(
            item: PrintableTemplateFile(
                store: library.store, artwork: artwork, paper: .default(for: Locale.current.region)),
            preview: SharePreview(ArtworkExporter.templateName(title: artwork.title), image: previewImage(artwork))
        ) {
            Label("Print Template…", systemImage: "printer")
        }
        Divider()
        Button("Restart", systemImage: "arrow.counterclockwise") {
            PaintTips.used(.shelfHold)
            restarting = artwork
        }
        .disabled(!artwork.isStarted)
        deleteButton(for: artwork)
    }

    private func deleteButton(for artwork: Artwork) -> some View {
        Button("Delete", systemImage: "trash", role: .destructive) {
            PaintTips.used(.shelfHold)
            deleting = artwork
        }
    }

    private func previewImage(_ artwork: Artwork) -> Image {
        if let cached = ThumbnailCache.shared.bestCached(artwork) { return Image(decorative: cached, scale: 1) }
        return Image(systemName: "paintpalette")
    }

    private func shareTimelapse(_ artwork: Artwork) {
        timelapse = TimelapseRequest(title: artwork.title, source: .saved(store: library.store, artwork: artwork))
    }

    // MARK: Toasts

    private var toasts: some View {
        VStack(spacing: 10) {
            if let failed = library.latestWriteFailure?.artwork {
                Toast(text: saveFailedText(failed), systemImage: "exclamationmark.triangle") {
                    Button("Retry") { library.retrySaving(failed.id) }
                        .fontWeight(.semibold)
                }
            }
            if let deleted = library.recentlyDeleted {
                Toast(text: deletedText(deleted), systemImage: "trash") {
                    Button("Undo") { library.undoDelete() }
                        .fontWeight(.semibold)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .animation(.snappy, value: library.latestWriteFailure?.artwork.id)
        .animation(.snappy, value: library.recentlyDeleted?.id)
        // VoiceOver users hear what the toasts show, and that their action is there to find.
        .onChange(of: library.latestWriteFailure?.artwork.id) {
            guard let failed = library.latestWriteFailure?.artwork else { return }
            Announcer.announce(saveFailedText(failed))
        }
        .onChange(of: library.recentlyDeleted?.id) {
            guard let deleted = library.recentlyDeleted else { return }
            Announcer.announce(deletedText(deleted))
        }
    }

    private func saveFailedText(_ artwork: Artwork) -> String {
        String(localized: "gallery.toast.saveFailed", defaultValue: "Couldn’t save “\(artwork.title)”",
               comment: "Toast when a painting's progress couldn't be written to disk; the argument is the painting's title")
    }

    private func deletedText(_ artwork: Artwork) -> String {
        String(localized: "gallery.toast.deleted", defaultValue: "Deleted “\(artwork.title)”",
               comment: "Toast after deleting a painting, next to an Undo button; the argument is the painting's title")
    }

    private func isPresent<T>(_ value: Binding<T?>) -> Binding<Bool> {
        Binding(get: { value.wrappedValue != nil }, set: { if !$0 { value.wrappedValue = nil } })
    }

    /// Whether `value` holds this card's painting: its dialog is up on this card and on no other.
    private func isPending(_ value: Binding<Artwork?>, _ artwork: Artwork) -> Binding<Bool> {
        Binding(
            get: { value.wrappedValue?.id == artwork.id },
            set: { if !$0, value.wrappedValue?.id == artwork.id { value.wrappedValue = nil } })
    }
}
