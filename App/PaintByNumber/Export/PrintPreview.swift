#if UNRELEASED
import CoreGraphics
import Foundation
import os
import PaintCore
import SwiftUI
import UIKit

/// What Print's preview opens on: a painting's template, its title and the paint names it shows.
nonisolated struct PrintPreviewRequest: Identifiable, Sendable {
    let id = UUID()
    let template: Template
    let title: String
    let nicknames: [String?]

    init(template: Template, title: String, nicknames: [String?]) {
        self.template = template
        self.title = title
        self.nicknames = nicknames
    }

    /// A gallery card's: the saved painting's template, its key under the names it shows.
    @concurrent
    static func saved(store: ArtworkStore, artwork: Artwork) async throws -> PrintPreviewRequest {
        let template = try store.readTemplate(artwork.id)
        return PrintPreviewRequest(
            template: template, title: artwork.title,
            nicknames: ColorNameText.nicknames(for: template.palette, seed: artwork.nicknameSeed, version: artwork.nicknameVersion))
    }
}

/// Print (painting-company row 357): the pages as they will come out of the printer, on paper,
/// with the few layout choices a painter needs (the paper, which way it turns, how big the
/// picture prints, the color key), every one starting where Print… has always printed
/// (`PDFExporter.Layout(paper:)`). Painted shows the template's pages painted in, what the
/// painter will make; it never prints. Print hands the system's dialog the PDF the preview
/// shows, blank, and the preview closes once it has printed. SideStore and Debug builds, until
/// 1.3; the release's Print… opens the dialog straight away.
struct PrintPreviewSheet: View {
    let request: PrintPreviewRequest

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var layout: PDFExporter.Layout
    @State private var showsPainted = false
    /// The pages of the layout on screen, drawn for it (`Pages.key`).
    @State private var pages: Pages?
    @State private var page = 0
    @State private var job: TemplatePrintJob?
    @State private var preparing = false

    /// `showsPainted` and `across` open it on another view (the demo scenarios').
    init(request: PrintPreviewRequest, showsPainted: Bool = false, across: Int? = nil) {
        self.request = request
        _layout = State(initialValue: PDFExporter.Layout(paper: .default(for: Locale.current.region), across: across))
        _showsPainted = State(initialValue: showsPainted)
    }

    /// One drawing of the pages: what it was drawn for, and each page as a picture.
    struct Pages {
        var key: Key
        var images: [UIImage]
    }

    struct Key: Equatable {
        var layout: PDFExporter.Layout
        var painted: Bool
    }

    private var key: Key { Key(layout: layout, painted: showsPainted) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    preview
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
                Section {
                    choice("Paper", selection: $layout.paper, options: PDFExporter.Paper.allCases.map { ($0, paperName($0)) })
                        .accessibilityIdentifier("print-paper")
                    choice("Orientation", selection: orientation, options: [
                        (.portrait, Text("Portrait")), (.landscape, Text("Landscape")),
                    ])
                    .accessibilityIdentifier("print-orientation")
                    sizePicker
                    Toggle(isOn: $layout.colorKey) {
                        Text("Color Key")
                        Text("The paints, and the finished picture")
                    }
                    .accessibilityIdentifier("print-color-key")
                }
            }
            .navigationTitle("Print")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) { printButton }
        }
        .task(id: key) { await draw(key) }
        // Another paper or orientation has sizes of its own: back to the smallest.
        .onChange(of: layout.paper) { layout.across = nil }
        .onChange(of: layout.resolvedOrientation(for: request.template)) { layout.across = nil }
    }

    // MARK: The pages

    private var preview: some View {
        VStack(spacing: 12) {
            Picker("Preview", selection: $showsPainted) {
                Text("Blank").tag(false)
                Text("Painted").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 260)
            .accessibilityIdentifier("print-painted")
            TabView(selection: $page) {
                ForEach(Array((pages?.images ?? []).enumerated()), id: \.offset) { index, image in
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        // Paper, whatever the screen's appearance.
                        .background(Color.white)
                        .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
                        .shadow(color: .black.opacity(0.16), radius: 14, y: 8)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 18)
                        .accessibilityLabel(pageCaption(index))
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            // A page a hand's width on the iPad, where the sheet has the room.
            .frame(height: sizeClass == .regular ? 560 : 340)
            .overlay {
                if pages == nil { ProgressView() }
            }
            .opacity(pages?.key == key ? 1 : 0.6)
            .animation(.default, value: pages?.key == key)
            Text(caption)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var pageCount: Int { pages?.images.count ?? 0 }

    private func pageCaption(_ index: Int) -> String {
        let number = index + 1, total = pageCount
        return String(localized: "print.page", defaultValue: "Page \(number) of \(total)",
                      comment: "Print's preview: which page is shown; the arguments are its number and the number of pages")
    }

    /// Which page, and what it is: the sheets laid together, a sheet, the key.
    private var caption: String {
        guard pageCount > 0 else { return " " }
        let index = min(page, pageCount - 1)
        if showsPainted {
            return String(localized: "print.caption.painted", defaultValue: "As it looks once you’ve painted it",
                          comment: "Print's preview with Painted chosen: the pages are shown painted in (they print blank)")
        }
        // The layout of the pages on screen, which may still be the last one drawn.
        let sheets = PDFExporter.sheets(for: request.template, layout: pages?.key.layout ?? layout)
        if sheets.isTiled && index == 0 {
            let size = sizeText(sheets)
            return String(localized: "print.caption.tiled", defaultValue: "How the sheets tape together · \(size)",
                          comment: "Print's preview, the first page of a template printed on several sheets: a map of how they fit; the argument is the size of the whole picture, like 21 in × 16 in")
        }
        return pageCaption(index)
    }

    // MARK: The choices

    private var orientation: Binding<PDFExporter.Layout.Orientation> {
        Binding(get: { layout.resolvedOrientation(for: request.template) }, set: { layout.orientation = $0 })
    }

    private func paperName(_ paper: PDFExporter.Paper) -> Text {
        switch paper {
        case .letter: Text("Letter")
        case .a4: Text("A4")
        }
    }

    /// Two choices: side by side, or a menu at the accessibility sizes, where they don't fit
    /// beside their name.
    @ViewBuilder
    private func choice<Value: Hashable>(_ title: LocalizedStringKey, selection: Binding<Value>, options: [(Value, Text)]) -> some View {
        let picker = Picker(title, selection: selection) {
            ForEach(options.indices, id: \.self) { index in options[index].1.tag(options[index].0) }
        }
        if typeSize.isAccessibilitySize {
            picker.pickerStyle(.menu)
        } else {
            LabeledContent(title) {
                picker.pickerStyle(.segmented).labelsHidden().fixedSize()
            }
        }
    }

    private var sizes: [PDFExporter.Size] { PDFExporter.sizes(for: request.template, layout: layout) }

    private var sizePicker: some View {
        let sizes = self.sizes
        let chosen = sizes.first { $0.across == layout.across } ?? sizes[0]
        return Picker(selection: $layout.across) {
            ForEach(sizes.indices, id: \.self) { index in
                VStack(alignment: .leading) {
                    Text(sheetsText(sizes[index].sheets.count))
                    Text(sizeText(sizes[index].sheets))
                }
                .tag(sizes[index].across)
            }
        } label: {
            Text("Size")
            Text(sizeText(chosen.sheets))
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("print-size")
    }

    private func sheetsText(_ count: Int) -> String {
        count == 1
            ? String(localized: "print.onePage", defaultValue: "One Page",
                     comment: "Print's Size choice: the picture fitted to one sheet of paper")
            : String(localized: "pdf.sheets", defaultValue: "\(count) sheets",
                     comment: "How many sheets the template is printed on; the argument is the count")
    }

    /// The printed picture's size, in inches where they are used, centimetres elsewhere.
    private func sizeText(_ sheets: PDFExporter.Sheets) -> String {
        let inches = Locale.current.measurementSystem == .us
        func length(_ points: CGFloat) -> String {
            let value = Measurement(value: Double(points) / 72, unit: UnitLength.inches)
            return (inches ? value : value.converted(to: .centimeters))
                .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))))
        }
        let width = length(sheets.printed.width), height = length(sheets.printed.height)
        return String(localized: "print.size.dimensions", defaultValue: "\(width) × \(height)",
                      comment: "Print's Size choice: how big the picture prints, width by height; the arguments are lengths like 21 in or 53 cm")
    }

    // MARK: Printing

    private var printButton: some View {
        Button(action: startPrinting) {
            Label("Print", systemImage: "printer")
                .frame(maxWidth: .infinity)
                .opacity(preparing ? 0 : 1)
                .overlay { if preparing { ProgressView() } }
        }
        .buttonStyle(.glassProminent)
        .tint(Theme.signature)
        .controlSize(.large)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .disabled(preparing || !PrintSheet.isAvailable)
        .accessibilityIdentifier("print-go")
        // An iPad's dialog points at the button.
        .background {
            PrintSheet(job: job, onFinish: { finished in
                if job?.id == finished { job = nil }
            }, onPrinted: { _ in dismiss() })
        }
    }

    /// The blank pages of the layout chosen, to the system's dialog.
    private func startPrinting() {
        guard !preparing else { return }
        preparing = true
        var blank = layout
        blank.painted = false
        let request = request
        Task {
            defer { preparing = false }
            do {
                job = try await TemplatePrintJob.open(
                    template: request.template, title: request.title, nicknames: request.nicknames, layout: blank)
            } catch {
                Log.library.error("Preparing a template to print failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Draws `key`'s pages, keeping the last drawing on screen meanwhile.
    private func draw(_ key: Key) async {
        var drawn = key.layout
        drawn.painted = key.painted
        // A poster's many sheets are drawn smaller: each is the whole template under a clip.
        let count = PDFExporter.sheets(for: request.template, layout: drawn).count
        let images = await PrintPages.images(request, layout: drawn, longSide: count > 4 ? 800 : 1200)
        guard !Task.isCancelled else { return }
        pages = Pages(key: key, images: images.map { UIImage(cgImage: $0) })
        page = min(page, max(images.count - 1, 0))
        #if DEBUG
        if DemoMode.scenario?.hasPrefix("print-preview") == true { DemoMode.markReady() }
        #endif
    }
}

/// The preview's pages, drawn off the main actor.
nonisolated enum PrintPages {
    /// The document `layout` makes, each page drawn white at `longSide` pixels.
    @concurrent
    static func images(_ request: PrintPreviewRequest, layout: PDFExporter.Layout, longSide: CGFloat) async -> [CGImage] {
        let data = PDFExporter.document(for: request.template, title: request.title, layout: layout, nicknames: request.nicknames)
        guard let provider = CGDataProvider(data: data as CFData), let document = CGPDFDocument(provider) else {
            return []
        }
        var images: [CGImage] = []
        for number in 1...max(document.numberOfPages, 1) {
            guard !Task.isCancelled, let page = document.page(at: number), document.numberOfPages > 0 else { break }
            let box = page.getBoxRect(.mediaBox)
            let scale = longSide / max(box.width, box.height)
            let width = Int((box.width * scale).rounded()), height = Int((box.height * scale).rounded())
            guard let ctx = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { break }
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -box.minX, y: -box.minY)
            ctx.drawPDFPage(page)
            if let image = ctx.makeImage() { images.append(image) }
        }
        return images
    }
}

#if DEBUG
/// Demo scenarios of Print's preview, as the sheet a painting's More gives it, over the paper, on
/// The Great Wave: `print-preview` (with `-dark`, `-long-text`), `print-preview-painted` (Painted
/// chosen) and `print-preview-sheets` (the next size up, on several sheets).
struct PrintPreviewDemo: View {
    let scenario: String
    @State private var request: PrintPreviewRequest?

    var body: some View {
        Theme.paper.ignoresSafeArea()
            .sheet(item: $request) { request in
                PrintPreviewSheet(
                    request: request, showsPainted: scenario.hasPrefix("print-preview-painted"),
                    across: scenario.hasPrefix("print-preview-sheets") ? 2 : nil)
                    .pageSizedOnPad()
            }
            .task {
                guard let sample = Sample.named("great-wave"),
                      let draft = try? await ArtworkFactory.draft(sample: sample, photoMaxPixelSize: 560)
                else { return }
                request = PrintPreviewRequest(template: draft.template, title: sample.title, nicknames: [])
            }
    }
}
#endif
#endif
