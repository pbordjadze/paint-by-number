import Foundation
import SwiftUI

/// The gallery: paintings in progress and finished ones, as an adaptive grid of cards.
struct GalleryView: View {
    let namespace: Namespace.ID
    /// The Show filter and the search text: what the gallery lists.
    let query: GalleryQuery
    /// The time-lapse being made; the app shell presents its sheet.
    @Binding var timelapse: TimelapseRequest?
    var onCreate: () -> Void

    @Environment(Library.self) private var library
    @State private var width: CGFloat = 0
    @State private var renaming: Artwork?
    @State private var renameText = ""
    @State private var restarting: Artwork?
    @State private var deleting: Artwork?

    var body: some View {
        ScrollView {
            if !library.isEmpty {
                VStack(alignment: .leading, spacing: 36) {
                    let active = library.inProgress(matching: query)
                    let preparing = shownPlaceholders
                    if !active.isEmpty || !preparing.isEmpty {
                        section("In Progress", count: active.count + preparing.count) {
                            ForEach(preparing) { PlaceholderCard(placeholder: $0) }
                            ForEach(active) { card($0) }
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
        .scrollDisabled(library.isEmpty)
        // An empty scroll view collapses; keep the paper (and the empty state) full size.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper)
        .overlay {
            if library.isEmpty {
                EmptyGalleryView(onCreate: onCreate)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else if isNarrowedToNothing {
                narrowedEmptyState
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) { toasts }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        // Deleting, filtering, searching and (un)favoriting all move cards.
        .animation(.snappy, value: shownIDs)
        .animation(.snappy, value: library.placeholders)
        .animation(.easeInOut(duration: 0.35), value: library.isEmpty)
        .alert("Rename Painting", isPresented: isPresent($renaming), presenting: renaming) { artwork in
            TextField("Title", text: $renameText)
                .submitLabel(.done)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { library.rename(artwork.id, to: renameText) }
        }
        .confirmationDialog("Start this painting over?", isPresented: isPresent($restarting), titleVisibility: .visible, presenting: restarting) { artwork in
            Button(String(localized: "gallery.restart.confirm", defaultValue: "Restart “\(artwork.title)”",
                          comment: "Destructive button of the restart confirmation; the argument is the painting's title"),
                   role: .destructive) {
                Task { await library.restart(artwork.id) }
            }
        } message: { _ in
            Text("Every painted area will be cleared.")
        }
        .confirmationDialog("Delete this painting?", isPresented: isPresent($deleting), titleVisibility: .visible, presenting: deleting) { artwork in
            // Undoable for a few seconds afterwards (the toast's Undo).
            Button(String(localized: "gallery.delete.confirm", defaultValue: "Delete “\(artwork.title)”",
                          comment: "Destructive button of the delete confirmation; the argument is the painting's title"),
                   role: .destructive) { library.delete(artwork.id) }
        } message: { artwork in
            if artwork.isComplete {
                Text(String(localized: "gallery.delete.message.finished", defaultValue: "“\(artwork.title)” is finished.",
                            comment: "Delete confirmation message for a finished painting; the argument is its title"))
            } else if artwork.isStarted {
                let percent = ProgressCaption.percentText(artwork)
                Text(String(localized: "gallery.delete.message.started", defaultValue: "“\(artwork.title)” is \(percent) painted.",
                            comment: "Delete confirmation message for a painting in progress; the arguments are its title and the formatted percentage painted, e.g. 42%"))
            } else {
                Text(String(localized: "gallery.delete.message.notStarted", defaultValue: "“\(artwork.title)” hasn’t been started yet.",
                            comment: "Delete confirmation message for a painting nobody has painted on; the argument is its title"))
            }
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
        (library.inProgress(matching: query) + library.finished(matching: query)).map(\.id)
    }

    /// The library has paintings, but the filter or the search hides every one.
    private var isNarrowedToNothing: Bool { shownIDs.isEmpty && shownPlaceholders.isEmpty }

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

    private var horizontalPadding: CGFloat { width < 560 ? 20 : 32 }
    private var spacing: CGFloat { width < 560 ? 16 : 26 }

    private func section<Content: View>(_ title: LocalizedStringKey, count: Int, @ViewBuilder content: () -> Content) -> some View {
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

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .top), count: columnCount),
                alignment: .leading, spacing: spacing + 8
            ) {
                content()
            }
        }
    }

    private func card(_ artwork: Artwork) -> some View {
        NavigationLink(value: artwork.id) {
            ArtworkCard(artwork: artwork, namespace: namespace)
        }
        .buttonStyle(PressableCardStyle())
        .contextMenu { menu(for: artwork) }
    }

    // MARK: Actions

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
            Button("Unfavorite", systemImage: "heart.slash") { library.setFavorite(artwork.id, false) }
        } else {
            Button("Favorite", systemImage: "heart") { library.setFavorite(artwork.id, true) }
        }
        Divider()
        Button("Rename", systemImage: "pencil") {
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
            Button("Share Time-lapse", systemImage: "timelapse") { shareTimelapse(artwork) }
        }
        ShareLink(
            item: PrintableTemplateFile(
                store: library.store, artwork: artwork, paper: .default(for: Locale.current.region)),
            preview: SharePreview(ArtworkExporter.templateName(title: artwork.title), image: previewImage(artwork))
        ) {
            Label("Print Template…", systemImage: "printer")
        }
        Divider()
        Button("Restart", systemImage: "arrow.counterclockwise") { restarting = artwork }
            .disabled(!artwork.isStarted)
        deleteButton(for: artwork)
    }

    private func deleteButton(for artwork: Artwork) -> some View {
        Button("Delete", systemImage: "trash", role: .destructive) { deleting = artwork }
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
}
