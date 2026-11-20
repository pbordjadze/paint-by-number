import Foundation
import MosaicCore
import MosaicKit
import os
import PaintCore
import SwiftUI
import UIKit

/// What Set in Stone opens on: a saved mosaic's tiles, its title and its paints' names.
nonisolated struct SetInStoneRequest: Identifiable, Sendable {
    let id = UUID()
    let mosaic: Mosaic
    let title: String
    let names: [String?]

    /// A gallery card's; nil when the mosaic has no tiles saved (one sent from another device).
    @concurrent
    static func saved(store: ArtworkStore, artwork: Artwork) async throws -> SetInStoneRequest? {
        guard let mosaic = try store.readMosaic(artwork.id), !mosaic.tiles.isEmpty else { return nil }
        let template = try store.readTemplate(artwork.id)
        let names = ColorNameText.nicknames(for: template.palette, seed: ColorNickname.seed(for: artwork.id), version: artwork.nicknameVersion)
        return SetInStoneRequest(
            mosaic: mosaic, title: artwork.title,
            names: (0..<mosaic.palette.count).map { $0 < names.count ? names[$0] : nil })
    }

    /// Whether a saved mosaic can be set in stone: its tiles are on disk.
    static func isAvailable(store: ArtworkStore, artwork: Artwork) -> Bool {
        FileManager.default.fileExists(atPath: store.url(.mosaic, of: artwork.id).path)
    }
}

/// Set in Stone (painting-company row 367), Paint by Mosaic's counterpart to Paint by Moonlight's
/// Print: the book for setting the mosaic in real stone (`StoneBook`), page by page as it prints,
/// with the one choice it needs, how big a tile is, which sets the mosaic's size, its full-size
/// pages and the stone to buy. Print hands the system's dialog the whole book; Share saves the PDF.
/// SideStore and Debug builds; the release keeps Print Template….
struct SetInStoneSheet: View {
    let request: SetInStoneRequest

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var face = TileSize.standard.face
    @State private var book: StoneBook?
    @State private var page = 1
    @State private var preparing = false
    @State private var shared: URL?
    @State private var printing: StonePrintJob?
    /// The PDF being made for Print or Share: let go when the sheet closes.
    @State private var work: Task<Void, Never>?

    /// How big a tile is: the median tile's side, as a mosaicist names a tessera's size.
    enum TileSize: CaseIterable {
        case small, standard, large
        var side: Double { switch self { case .small: 1.0; case .standard: 1.2; case .large: 1.5 } }
        var face: Double { side * side * 1.5 / 1.44 }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    preview
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
                Section {
                    tilePicker
                }
            }
            .navigationTitle(String(localized: "stone.title", defaultValue: "Set in Stone", bundle: .ravenna,
                                    comment: "Set in Stone's sheet: its title (a book for setting the mosaic in real stone)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done", bundle: .ravenna)) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(String(localized: "stone.share", defaultValue: "Share", bundle: .ravenna,
                                  comment: "Set in Stone's sheet: shares or saves the book as a PDF"),
                           systemImage: "square.and.arrow.up", action: share)
                        .disabled(book == nil || preparing)
                        .accessibilityIdentifier("stone-share")
                }
            }
            .safeAreaInset(edge: .bottom) { printButton }
        }
        .task(id: face) { await layOut(face) }
        .onDisappear { work?.cancel() }
        .background {
            ActivityShareSheet(item: shared) {
                if let shared { ArtworkExporter.removeExport(at: shared) }
                shared = nil
            }
        }
    }

    // MARK: The pages

    private var preview: some View {
        VStack(spacing: 12) {
            TabView(selection: $page) {
                if let book {
                    ForEach(1...book.pageCount, id: \.self) { n in
                        StonePageView(book: book, number: n)
                            .accessibilityLabel(pageCaption(n, of: book.pageCount))
                            .tag(n)
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            // The page as large as the sheet has room for beside the picker and Print.
            .containerRelativeFrame(.vertical) { height, _ in height * (sizeClass == .regular ? 0.72 : 0.55) }
            .overlay { if book == nil { ProgressView() } }
            .id(face)
            Text(caption)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func pageCaption(_ number: Int, of total: Int) -> String {
        String(localized: "stone.page", defaultValue: "Page \(number) of \(total)", bundle: .ravenna,
               comment: "Set in Stone's preview: which page of the book is shown; the arguments are its number and the number of pages")
    }

    private var caption: String {
        guard let book else { return " " }
        return pageCaption(page, of: book.pageCount)
    }

    // MARK: The choice

    private var tilePicker: some View {
        LabeledContent {
            Picker(String(localized: "stone.tiles", defaultValue: "Tiles", bundle: .ravenna,
                          comment: "Set in Stone's one choice: how big each tile of the mosaic is"),
                   selection: $face) {
                ForEach(TileSize.allCases, id: \.self) { size in
                    Text(Self.length(size.side, digits: size.side == size.side.rounded() ? 0 : 1)).tag(size.face)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .accessibilityIdentifier("stone-tiles")
        } label: {
            Text(String(localized: "stone.tiles", defaultValue: "Tiles", bundle: .ravenna,
                        comment: "Set in Stone's one choice: how big each tile of the mosaic is"))
            if let book {
                Text(Self.size(book.widthMM / 10, book.heightMM / 10))
            }
        }
    }

    nonisolated static func length(_ centimetres: Double, digits: Int) -> String {
        Measurement(value: centimetres, unit: UnitLength.centimeters)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(digits))))
    }

    nonisolated static func size(_ width: Double, _ height: Double) -> String {
        let w = length(width, digits: 0), h = length(height, digits: 0)
        return String(localized: "stone.size", defaultValue: "\(w) × \(h)", bundle: .ravenna,
                      comment: "Set in Stone: how big the mosaic comes out in stone, width by height; the arguments are lengths like 70 cm")
    }

    // MARK: Printing and sharing

    private var printButton: some View {
        Button(action: startPrinting) {
            Label(String(localized: "stone.print", defaultValue: "Print", bundle: .ravenna,
                         comment: "Set in Stone's sheet: prints the book"), systemImage: "printer")
                .frame(maxWidth: .infinity)
                .opacity(preparing ? 0 : 1)
                .overlay { if preparing { ProgressView() } }
        }
        .buttonStyle(.glassProminent)
        .tint(Theme.signature)
        .controlSize(.large)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .disabled(book == nil || preparing || !UIPrintInteractionController.isPrintingAvailable)
        .accessibilityIdentifier("stone-print")
        .background {
            StonePrintSheet(job: printing) { printing = nil }
        }
    }

    private func startPrinting() {
        guard let book, !preparing else { return }
        preparing = true
        let name = request.title
        work = Task {
            defer { preparing = false }
            let pdf = await StoneBookWork.render(book)
            if !pdf.isEmpty, !Task.isCancelled { printing = StonePrintJob(name: name, pdf: pdf) }
        }
    }

    private func share() {
        guard let book, !preparing else { return }
        preparing = true
        let title = request.title
        work = Task {
            defer { preparing = false }
            let pdf = await StoneBookWork.render(book)
            guard !pdf.isEmpty, !Task.isCancelled else { return }
            do {
                shared = try ArtworkExporter.temporaryFile(pdf, name: Self.fileName(title), pathExtension: "pdf")
            } catch {
                Log.library.error("Saving the stone book failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    nonisolated static func fileName(_ title: String) -> String {
        String(localized: "stone.fileName", defaultValue: "\(title) in Stone", bundle: .ravenna,
               comment: "The Set in Stone book's PDF file name; the argument is the mosaic's title")
    }


    private func layOut(_ face: Double) async {
        let request = request
        let made = await StoneBookWork.make(request, face: face)
        guard !Task.isCancelled else { return }
        book = made
        page = min(page, made.pageCount)
    }

}

/// Set in Stone's work, off the main actor: laying the book out, drawing its pages.
nonisolated enum StoneBookWork {
    @concurrent
    static func make(_ request: SetInStoneRequest, face: Double) async -> StoneBook {
        StoneBook(mosaic: request.mosaic, title: request.title, names: request.names, options: .init(tileFace: face))
    }

    @concurrent
    static func render(_ book: StoneBook) async -> Data {
        StoneBookRenderer.pdf(book, strings: .ravenna)
    }

    @concurrent
    static func image(_ book: StoneBook, _ number: Int) async -> UIImage {
        StoneBookRenderer.image(book, page: number, strings: .ravenna, width: 900)
    }
}

/// One page of the book, drawn when it comes into view.
private struct StonePageView: View {
    let book: StoneBook
    let number: Int
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.white
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
            }
        }
        .aspectRatio(BookPage.size.x / BookPage.size.y, contentMode: .fit)
        .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
        .shadow(color: .black.opacity(0.16), radius: 14, y: 8)
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .onDisappear { image = nil }
        .task {
            image = await StoneBookWork.image(book, number)
            #if DEBUG
            if number == 1, ShellDemo.current?.setsInStone == true { DemoMode.markReady() }
            #endif
        }
    }
}

/// A book to print, once: its id tells a new job from the one already shown.
struct StonePrintJob: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let pdf: Data
}

/// The system's print dialog for the book, from the view it lies behind (an iPad's points at it).
private struct StonePrintSheet: UIViewControllerRepresentable {
    let job: StonePrintJob?
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.onFinish = onFinish
        guard let job, controller.shown != job.id else { return }
        controller.shown = job.id
        Task { @MainActor [weak controller] in controller?.present(job) }
    }

    final class Controller: UIViewController {
        var onFinish: (() -> Void)?
        var shown: UUID?

        func present(_ job: StonePrintJob) {
            guard let view = viewIfLoaded, view.window != nil else { shown = nil; onFinish?(); return }
            let info = UIPrintInfo.printInfo()
            info.outputType = .general
            info.jobName = job.name
            let printer = UIPrintInteractionController.shared
            printer.printInfo = info
            printer.printingItem = job.pdf
            let done: UIPrintInteractionController.CompletionHandler = { [weak self] _, _, _ in
                Task { @MainActor in
                    self?.shown = nil
                    self?.onFinish?()
                }
            }
            let opened = traitCollection.userInterfaceIdiom == .pad
                ? printer.present(from: view.bounds, in: view, animated: true, completionHandler: done)
                : printer.present(animated: true, completionHandler: done)
            if !opened { shown = nil; onFinish?() }
        }
    }
}

extension BookStrings {
    /// The book's words and units in the painter's language.
    nonisolated static var ravenna: BookStrings {
        var s = BookStrings()
        s.stoneList = String(localized: "stone.list.title", defaultValue: "Stone list", bundle: .ravenna,
                             comment: "Set in Stone's book: the heading of its last pages, the stones to buy")
        s.number = String(localized: "stone.list.number", defaultValue: "No.", bundle: .ravenna,
                          comment: "Set in Stone's stone list: the column of the paint's number")
        s.smalti = String(localized: "stone.list.smalti", defaultValue: "Smalti", bundle: .ravenna,
                          comment: "Set in Stone's stone list: the column naming the glass to order (smalti: mosaic glass)")
        s.tiles = String(localized: "stone.list.tiles", defaultValue: "Tiles", bundle: .ravenna,
                         comment: "Set in Stone's stone list: the column of how many tiles of the stone the mosaic has")
        s.buy = String(localized: "stone.list.buy", defaultValue: "Buy", bundle: .ravenna,
                       comment: "Set in Stone's stone list: the column of how many to buy, with spares")
        s.altogether = String(localized: "stone.list.altogether", defaultValue: "Altogether", bundle: .ravenna,
                              comment: "Set in Stone's stone list: the row of totals")
        s.glass = String(localized: "stone.list.glass", defaultValue: "glass", bundle: .ravenna,
                         comment: "Set in Stone's stone list: what a stone is made of, glass smalti")
        s.stone = String(localized: "stone.list.stone", defaultValue: "glass, or marble to match", bundle: .ravenna,
                         comment: "Set in Stone's stone list: what a stone is made of, for a face's matte tiles")
        s.gold = String(localized: "stone.list.gold", defaultValue: "gold leaf smalti", bundle: .ravenna,
                        comment: "Set in Stone's stone list: what a stone is made of, glass with gold leaf")
        let spare = 0.15.formatted(.percent)
        s.note = String(localized: "stone.list.note",
                        defaultValue: "Codes are Orsoni smalti as Mosaic Workshop sells them, matched to each colour from photos: check them against samples before you order; ≈ marks the nearest where none is close. Counts include \(spare) spare for breakage.",
                        bundle: .ravenna,
                        comment: "Set in Stone's stone list: the note under it; the argument is a percentage, like 15%. Orsoni (a Venetian glassworks) and Mosaic Workshop (a shop) are names")
        s.code = { code, near in
            near
                ? String(localized: "stone.list.codeNear", defaultValue: "≈ Orsoni \(code)", bundle: .ravenna,
                         comment: "Set in Stone's stone list: the nearest smalto to a colour that isn't close; the argument is its code, like S23")
                : String(localized: "stone.list.code", defaultValue: "Orsoni \(code)", bundle: .ravenna,
                         comment: "Set in Stone's stone list: the smalto to order for a colour; the argument is its code, like S23")
        }
        s.decimal = { $0.formatted(.number.precision(.fractionLength($1))) }
        s.count = { $0.formatted() }
        s.centimetres = { SetInStoneSheet.length($0, digits: 1) }
        s.size = { SetInStoneSheet.size($0, $1) }
        s.kilograms = {
            Measurement(value: $0, unit: UnitMass.kilograms)
                .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(1))))
        }
        s.hours = { Measurement(value: Double($0), unit: UnitDuration.hours).formatted(.measurement(width: .abbreviated)) }
        s.minutes = { Measurement(value: Double($0), unit: UnitDuration.minutes).formatted(.measurement(width: .abbreviated)) }
        return s
    }
}
