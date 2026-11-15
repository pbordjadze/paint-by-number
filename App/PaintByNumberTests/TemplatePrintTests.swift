import CoreGraphics
import Foundation
import PaintCore
import PDFKit
import Testing
import UIKit
@testable import PaintByNumber

/// Print… (a painting's More menu, a gallery card's menu; painting-company row 240): what it
/// hands the print dialog is Print Template…'s PDF, from the gallery's saved painting and from an
/// open painting's session alike, and for a painting someone sent.
@MainActor
struct TemplatePrintTests {
    let root = Fixtures.temporaryDirectory()

    private func makeLibrary() -> Library { Library(store: ArtworkStore(root: root)) }

    private func draft() -> ArtworkDraft {
        ArtworkDraft(title: "Stripes", template: Fixtures.stripes(), settings: Artwork.settingsBeforeLineArt)
    }

    /// A PDF as its pages' sizes and words: two documents made a moment apart differ in their
    /// creation dates, never in these.
    private func pages(_ data: Data) throws -> [String] {
        let document = try #require(PDFDocument(data: data))
        return (0..<document.pageCount).map { index in
            let page = document.page(at: index)
            let box = page?.bounds(for: .mediaBox) ?? .zero
            return "\(Int(box.width)) x \(Int(box.height)): \(page?.string ?? "")"
        }
    }

    /// What an open painting's More › Print… makes, as `PaintView.printTemplate` does: from the
    /// session's template and paint names.
    private func openJob(_ artwork: Artwork, in library: Library, paper: PDFExporter.Paper) async throws -> TemplatePrintJob {
        let template = try library.store.readTemplate(artwork.id)
        let session = PaintingSession(
            template: template, nicknameSeed: artwork.nicknameSeed, nicknameVersion: artwork.nicknameVersion)
        return try await TemplatePrintJob.open(
            template: session.template, title: artwork.title, nicknames: session.colorNicknames, paper: paper)
    }

    @Test func aCardPrintsWhatPrintTemplateShares() async throws {
        let library = makeLibrary()
        let artwork = try await library.create(draft())
        let job = try await TemplatePrintJob.saved(store: library.store, artwork: artwork, paper: .a4)
        let shared = try ArtworkExporter.templatePDF(store: library.store, artwork: artwork, paper: .a4)
        #expect(job.name == "Stripes Template")
        #expect(job.pdf.starts(with: Data("%PDF".utf8)))
        // The template, then the color key.
        #expect(try pages(job.pdf).count == 2)
        #expect(try pages(job.pdf) == pages(shared))
        #expect(UIPrintInteractionController.canPrint(job.pdf))
    }

    @Test func anOpenPaintingPrintsTheSame() async throws {
        let library = makeLibrary()
        let artwork = try await library.create(draft())
        for paper in PDFExporter.Paper.allCases {
            let job = try await openJob(artwork, in: library, paper: paper)
            let shared = try ArtworkExporter.templatePDF(store: library.store, artwork: artwork, paper: paper)
            #expect(job.name == "Stripes Template")
            #expect(try pages(job.pdf) == pages(shared))
        }
    }

    /// A painting someone sent prints as any other, its key under the sender's paint names.
    @Test func aReceivedPaintingPrints() async throws {
        let library = makeLibrary()
        let sent = try await library.create(draft())
        let file = try ArtworkExporter.sharedPainting(store: library.store, artwork: sent, includesPhoto: false)
        let received = try await library.receive(file, fallbackTitle: "File Name")
        let shared = try ArtworkExporter.templatePDF(store: library.store, artwork: received, paper: .letter)
        let card = try await TemplatePrintJob.saved(store: library.store, artwork: received, paper: .letter)
        let open = try await openJob(received, in: library, paper: .letter)
        #expect(try pages(card.pdf) == pages(shared))
        #expect(try pages(open.pdf) == pages(shared))
        #expect(card.name == ArtworkExporter.templateName(title: received.title))
    }
}
