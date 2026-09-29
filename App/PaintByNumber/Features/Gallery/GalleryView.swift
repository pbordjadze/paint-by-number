import SwiftUI

/// The gallery: paintings in progress and finished ones, as an adaptive grid of cards.
struct GalleryView: View {
    let namespace: Namespace.ID
    var onCreate: () -> Void

    @Environment(Library.self) private var library
    @AppStorage(SettingsKey.paperSize) private var paper: PDFExporter.Paper = .default(for: Locale.current.region)
    @State private var width: CGFloat = 0
    @State private var renaming: Artwork?
    @State private var renameText = ""
    @State private var restarting: Artwork?
    @State private var notice: Notice?

    private struct Notice: Equatable {
        var text: String
        var systemImage: String
        var id = UUID()
    }

    var body: some View {
        ScrollView {
            if !library.isEmpty {
                VStack(alignment: .leading, spacing: 36) {
                    let active = library.inProgress
                    if !active.isEmpty || !library.placeholders.isEmpty {
                        section("In Progress", count: active.count + library.placeholders.count) {
                            ForEach(library.placeholders) { PlaceholderCard(placeholder: $0) }
                            ForEach(active) { card($0) }
                        }
                    }
                    let finished = library.finished
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
            }
        }
        .overlay(alignment: .bottom) { toasts }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .animation(.snappy, value: library.artworks.map(\.id))
        .animation(.snappy, value: library.placeholders)
        .animation(.easeInOut(duration: 0.35), value: library.isEmpty)
        .alert("Rename Painting", isPresented: isPresent($renaming), presenting: renaming) { artwork in
            TextField("Title", text: $renameText)
                .submitLabel(.done)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { library.rename(artwork.id, to: renameText) }
        }
        .confirmationDialog("Start this painting over?", isPresented: isPresent($restarting), titleVisibility: .visible, presenting: restarting) { artwork in
            Button("Restart “\(artwork.title)”", role: .destructive) {
                Task { await library.restart(artwork.id) }
            }
        } message: { _ in
            Text("Every painted area will be cleared.")
        }
    }

    // MARK: Layout

    private var columnCount: Int {
        switch width {
        case ..<560: 2
        case ..<840: 3
        case ..<1140: 4
        default: 5
        }
    }

    private var horizontalPadding: CGFloat { width < 560 ? 20 : 32 }
    private var spacing: CGFloat { width < 560 ? 16 : 26 }

    private func section<Content: View>(_ title: LocalizedStringKey, count: Int, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.rounded(.title2, weight: .bold))
                Text(count, format: .number)
                    .font(.rounded(.title3, weight: .semibold))
                    .foregroundStyle(.tertiary)
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
        Button("Rename", systemImage: "pencil") {
            renameText = artwork.title
            renaming = artwork
        }
        Button("Duplicate", systemImage: "plus.square.on.square") {
            Task {
                do { try await library.duplicate(artwork.id) } catch { show("Couldn't duplicate the painting.", "exclamationmark.triangle") }
            }
        }
        Divider()
        ShareLink(
            item: PaintingImageFile(store: library.store, artwork: artwork),
            preview: SharePreview(artwork.title, image: previewImage(artwork))
        ) {
            Label(artwork.isComplete ? "Share Painting" : "Share Progress", systemImage: "square.and.arrow.up")
        }
        if artwork.isComplete {
            ShareLink(
                item: TimelapseVideoFile(store: library.store, artwork: artwork),
                preview: SharePreview("\(artwork.title) Time-lapse", image: previewImage(artwork))
            ) {
                Label("Share Time-lapse", systemImage: "timelapse")
            }
        }
        ShareLink(
            item: PrintableTemplateFile(store: library.store, artwork: artwork, paper: paper),
            preview: SharePreview("\(artwork.title) Template", image: previewImage(artwork))
        ) {
            Label("Print Template…", systemImage: "printer")
        }
        Button("Save to Photos", systemImage: "square.and.arrow.down") { saveToPhotos(artwork) }
        Divider()
        Button("Restart", systemImage: "arrow.counterclockwise") { restarting = artwork }
            .disabled(!artwork.isStarted)
        Button("Delete", systemImage: "trash", role: .destructive) {
            library.delete(artwork.id)
        }
    }

    private func previewImage(_ artwork: Artwork) -> Image {
        if let cached = ThumbnailCache.shared.cached(artwork) { return Image(decorative: cached, scale: 1) }
        return Image(systemName: "paintpalette")
    }

    private func saveToPhotos(_ artwork: Artwork) {
        let store = library.store
        Task {
            do {
                let png = try await Background.run { try ArtworkExporter.paintingPNG(store: store, artwork: artwork) }
                try await ArtworkExporter.saveToPhotos(png)
                show("Saved to Photos", "checkmark.circle.fill")
            } catch {
                show(error.localizedDescription, "exclamationmark.triangle")
            }
        }
    }

    private func show(_ text: String, _ systemImage: String) {
        let next = Notice(text: text, systemImage: systemImage)
        notice = next
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if notice?.id == next.id { notice = nil }
        }
    }

    // MARK: Toasts

    private var toasts: some View {
        VStack(spacing: 10) {
            if let notice {
                Toast(text: notice.text, systemImage: notice.systemImage)
            }
            if let deleted = library.recentlyDeleted {
                Toast(text: "Deleted “\(deleted.title)”", systemImage: "trash") {
                    Button("Undo") { library.undoDelete() }
                        .fontWeight(.semibold)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .animation(.snappy, value: library.recentlyDeleted?.id)
        .animation(.snappy, value: notice)
    }

    private func isPresent<T>(_ value: Binding<T?>) -> Binding<Bool> {
        Binding(get: { value.wrappedValue != nil }, set: { if !$0 { value.wrappedValue = nil } })
    }
}

/// A floating glass capsule message with an optional action.
struct Toast<Trailing: View>: View {
    let text: String
    let systemImage: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            Text(text)
                .lineLimit(2)
            trailing
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
        .glassEffect(.regular, in: .capsule)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .combine)
    }
}

extension Toast where Trailing == EmptyView {
    init(text: String, systemImage: String) {
        self.init(text: text, systemImage: systemImage) { EmptyView() }
    }
}
