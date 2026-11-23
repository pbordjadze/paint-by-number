#if UNRELEASED
import CoreGraphics
import Foundation
import PaintCore
import SwiftUI
import os

/// A painting on a mode's shelf, as the frame's gallery sees it.
struct ModeShelfItem: Identifiable, Equatable {
    let id: UUID
    let title: String
    let isComplete: Bool
    /// Written by a newer app: its card offers Delete alone, since everything else would read or
    /// rewrite files this version doesn't understand.
    var needsNewerApp = false
}

extension Artwork {
    /// The painting as the frame's gallery sees it.
    var shelfItem: ModeShelfItem {
        ModeShelfItem(id: id, title: title, isComplete: isComplete, needsNewerApp: needsNewerApp)
    }
}

/// What the frame's card menu does with a painting: the mode's answers.
struct ModeCardActions {
    /// Gives the painting the painter's name for it (trimmed, never empty).
    let rename: (UUID, String) -> Void
    /// Deletes it, once the painter confirmed it.
    let delete: (UUID) -> Void
    /// The painting as it stands, as a picture to share.
    let picture: (UUID) async -> CGImage?
    /// Print's preview of its numbered sheet; nil for a mode that keeps none to print.
    var print: ((UUID) async throws -> PrintPreviewRequest)?
}

/// The frame's gallery (`ModeShell` rule 2, widened toward Paint by Mosaic's: painting-company
/// row 379): the shelf's paintings in two sections, In Progress then Finished, each newest first
/// as the shelf has them; search by name; and on every card the frame's menu, Rename, Share,
/// Print… (where the mode keeps a numbered sheet and the device can print) and Delete. What a card
/// looks like is the mode's (`card`); an empty shelf is the mode's own page, never this.
struct ModeGallery<Card: View>: View {
    let items: [ModeShelfItem]
    let actions: ModeCardActions
    /// Delete's question: Delete Print, Delete Window.
    let deleteTitle: Text
    /// The narrowest a card is, on a compact width and on a regular one.
    var minimumWidth: (compact: CGFloat, regular: CGFloat) = (150, 220)
    let card: (ModeShelfItem) -> Card

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var search = ""
    @State private var renaming: ModeShelfItem?
    @State private var renameText = ""
    @State private var deleting: ModeShelfItem?
    @State private var sharedFile: URL?
    @State private var printPreview: PrintPreviewRequest?
    @State private var preparing: Task<Void, Never>?

    init(items: [ModeShelfItem], actions: ModeCardActions, deleteTitle: Text,
         minimumWidth: (compact: CGFloat, regular: CGFloat) = (150, 220),
         @ViewBuilder card: @escaping (ModeShelfItem) -> Card) {
        self.items = items
        self.actions = actions
        self.deleteTitle = deleteTitle
        self.minimumWidth = minimumWidth
        self.card = card
    }

    private var shown: [ModeShelfItem] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? items : items.filter { $0.title.localizedStandardContains(query) }
    }

    var body: some View {
        let visible = shown
        let inProgress = visible.filter { !$0.isComplete }
        let finished = visible.filter(\.isComplete)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if !inProgress.isEmpty { section(Text("In Progress"), inProgress) }
                if !finished.isEmpty { section(Text("Finished"), finished) }
            }
            .padding(20)
        }
        .overlay {
            if visible.isEmpty && !items.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .searchable(text: $search)
        .alert(Text("Rename"), isPresented: present($renaming), presenting: renaming) { item in
            TextField("Title", text: $renameText)
                .submitLabel(.done)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty, name != item.title { actions.rename(item.id, name) }
            }
        }
        .sheet(item: $printPreview) { request in
            PrintPreviewSheet(request: request)
        }
        .background {
            ActivityShareSheet(item: sharedFile) {
                if let sharedFile { ArtworkExporter.removeExport(at: sharedFile) }
                sharedFile = nil
            }
        }
        .onDisappear {
            preparing?.cancel()
            preparing = nil
        }
    }

    private func section(_ title: Text, _ items: [ModeShelfItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            title
                .font(.display(.title3))
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: sizeClass == .compact ? minimumWidth.compact : minimumWidth.regular),
                                         spacing: 22)],
                      spacing: 26) {
                ForEach(items) { item in
                    card(item)
                        .contextMenu { menu(for: item) }
                        // On the card: on iPad the question is a popover on what it asks about.
                        .confirmationDialog(deleteTitle, isPresented: asksToDelete(item), titleVisibility: .visible) {
                            Button("Delete", role: .destructive) { actions.delete(item.id) }
                        }
                }
            }
        }
    }

    @ViewBuilder
    private func menu(for item: ModeShelfItem) -> some View {
        if !item.needsNewerApp {
            Button("Rename", systemImage: "pencil") {
                renameText = item.title
                renaming = item
            }
            Divider()
            Button("Share", systemImage: "square.and.arrow.up") { share(item) }
            if actions.print != nil, PrintSheet.isAvailable {
                Button("Print…", systemImage: "printer") { preparePrint(item) }
            }
            Divider()
        }
        Button("Delete", systemImage: "trash", role: .destructive) { deleting = item }
    }

    /// Writes the picture to a file, then opens the share sheet on it (handed a file ready, the
    /// sheet's tile shows it: `GalleryView.share`'s reason). One at a time.
    private func share(_ item: ModeShelfItem) {
        guard preparing == nil else { return }
        preparing = Task {
            defer { preparing = nil }
            guard let picture = await actions.picture(item.id), !Task.isCancelled else { return }
            do {
                let title = item.title
                sharedFile = try await Background.run {
                    guard let png = ImageCodec.pngData(picture) else { throw CocoaError(.fileWriteUnknown) }
                    return try ArtworkExporter.temporaryFile(png, name: ArtworkExporter.fileName(title), pathExtension: "png")
                }
            } catch {
                Log.library.error("Preparing a mode's painting to share failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Print…: the numbered sheet's preview, once its template is read. One at a time.
    private func preparePrint(_ item: ModeShelfItem) {
        guard preparing == nil, let make = actions.print else { return }
        preparing = Task {
            defer { preparing = nil }
            do {
                let request = try await make(item.id)
                if !Task.isCancelled { printPreview = request }
            } catch {
                Log.library.error("Preparing a mode's painting to print failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func asksToDelete(_ item: ModeShelfItem) -> Binding<Bool> {
        Binding(get: { deleting?.id == item.id }, set: { if !$0, deleting?.id == item.id { deleting = nil } })
    }

    private func present(_ item: Binding<ModeShelfItem?>) -> Binding<Bool> {
        Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } })
    }
}
#endif
