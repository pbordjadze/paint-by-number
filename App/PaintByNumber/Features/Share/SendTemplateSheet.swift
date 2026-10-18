import CoreGraphics
import Foundation
import os
import PaintCore
import SwiftUI

/// "Send Template…": the page someone else will paint, blank, with the Original Photo switch (on
/// unless the painter turns it off; Paul, October 18: "maybe on by default"), then the share
/// sheet with the `.moonlight` file (`ArtworkExporter.sharedPainting`), deleted once it closes.
/// Present it as a sheet.
struct SendTemplateSheet: View {
    let artwork: Artwork
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var includesPhoto = true
    @State private var preview: CGImage?
    @State private var isPreparing = false
    @State private var file: URL?
    @State private var failed = false

    var body: some View {
        // Scrolls when large text makes the sheet's content taller than its detent.
        ScrollView {
            VStack(spacing: 22) {
                page
                VStack(spacing: 4) {
                    Text("Send Template")
                        .font(.display(.title3))
                    Text(artwork.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .multilineTextAlignment(.center)
                if canIncludePhoto {
                    Toggle(isOn: $includesPhoto) {
                        Label("Original Photo", systemImage: "photo.on.rectangle")
                    }
                    .accessibilityIdentifier("send-photo")
                    .disabled(isPreparing)
                }
                Text(explanation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if failed {
                    Text("The painting couldn’t be prepared for sending.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
                HStack(spacing: 12) {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(.glass)
                        .keyboardShortcut(.cancelAction)
                    Button(action: send) {
                        if isPreparing {
                            ProgressView()
                                .accessibilityLabel(Text("Preparing…"))
                        } else {
                            Text("Send…")
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.signature)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isPreparing)
                    .accessibilityIdentifier("send-template")
                }
            }
            .padding(28)
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background {
            ActivityShareSheet(items: file.map { [$0] } ?? []) { completed in finishSharing(completed: completed) }
        }
        .task { await loadPreview() }
        // Swiped away with the file made: it mustn't stay behind.
        .onDisappear { removeFile() }
    }

    /// The blank page, on its own paper in either appearance.
    @ViewBuilder
    private var page: some View {
        Group {
            if let preview {
                Image(decorative: preview, scale: 1)
                    .resizable()
                    .scaledToFit()
            } else {
                Color(white: 0.96)
                    .aspectRatio(artwork.aspectRatio, contentMode: .fit)
            }
        }
        .frame(maxHeight: 220)
        .clipShape(.rect(cornerRadius: 10))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .accessibilityElement()
        .accessibilityLabel(Text(String(
            localized: "send.preview", defaultValue: "A blank copy of “\(artwork.title)”",
            comment: "VoiceOver label of the page shown in Send Template; the argument is the painting's title")))
    }

    /// The painting's photo can go with it: the painter's own, or the library picture it came from.
    private var canIncludePhoto: Bool {
        library.store.hasSource(artwork.id) || artwork.sampleName != nil
    }

    private var explanation: String {
        if !canIncludePhoto {
            String(localized: "send.explanation.noPhoto",
                   defaultValue: "They get a blank copy of this page to paint, your changes to the drawing included.",
                   comment: "Send Template's note when the painting has no photo to send")
        } else if includesPhoto {
            String(localized: "send.explanation.photo",
                   defaultValue: "They get a blank copy of this page to paint, your changes to the drawing included, and your photo to peek at.",
                   comment: "Send Template's note with the Original Photo switch on")
        } else {
            String(localized: "send.explanation.drawingOnly",
                   defaultValue: "They get a blank copy of this page to paint, your changes to the drawing included. Your photo stays on this device.",
                   comment: "Send Template's note with the Original Photo switch off")
        }
    }

    private func loadPreview() async {
        let store = library.store, id = artwork.id
        preview = await Background.run {
            (try? store.readTemplate(id)).flatMap { TemplateRasterizer.image($0, style: .thumbnail, maxPixelSize: 800) }
        }
        #if DEBUG
        if ShellDemo.current?.sendsTemplate == true { DemoMode.markReady() }
        #endif
    }

    /// Writes the file off the main actor; the share sheet presents once it is there.
    private func send() {
        guard !isPreparing else { return }
        isPreparing = true
        failed = false
        let store = library.store, artwork = self.artwork, sendsPhoto = self.includesPhoto && canIncludePhoto
        Task {
            do {
                file = try await Background.run {
                    let data = try ArtworkExporter.sharedPainting(store: store, artwork: artwork, includesPhoto: sendsPhoto)
                    return try ArtworkExporter.temporaryFile(
                        data, name: ArtworkExporter.templateName(title: artwork.title), pathExtension: SharedPaintingCodec.fileExtension)
                }
            } catch {
                Log.library.error("Preparing a template to send failed: \(String(describing: error), privacy: .public)")
                failed = true
            }
            isPreparing = false
        }
    }

    /// Sent, the sheet closes; backed out, it stays for another try or Cancel.
    private func finishSharing(completed: Bool) {
        removeFile()
        if completed { dismiss() }
    }

    private func removeFile() {
        guard let file else { return }
        self.file = nil
        Task { await Background.run { ArtworkExporter.removeExport(at: file) } }
    }
}
