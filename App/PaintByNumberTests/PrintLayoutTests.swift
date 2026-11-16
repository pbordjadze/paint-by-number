import CoreGraphics
import Foundation
import PaintCore
import Testing
@testable import PaintByNumber

/// Print's layout (painting-company row 357): `PDFExporter.Layout`'s paper, orientation, size
/// and color key, and the preview that draws its pages.
@MainActor
struct PrintLayoutTests {
    private func pageCount(_ data: Data) throws -> Int {
        try #require(CGDataProvider(data: data as CFData).flatMap { CGPDFDocument($0) }).numberOfPages
    }

    private func firstPage(_ data: Data) throws -> CGRect {
        try #require(CGDataProvider(data: data as CFData).flatMap { CGPDFDocument($0) }?.page(at: 1)).getBoxRect(.mediaBox)
    }

    /// A layout of nothing but the paper is the document Print Template… has always made.
    @Test func theDefaultLayoutIsTheTemplateAsBefore() throws {
        let t = try Fixtures.sample(colors: 18)
        for paper in PDFExporter.Paper.allCases {
            #expect(PDFExporter.sheets(for: t, layout: PDFExporter.Layout(paper: paper)) == PDFExporter.sheets(for: t, paper: paper))
            let before = PDFExporter.document(for: t, title: "Wave", paper: paper)
            let layout = PDFExporter.document(for: t, title: "Wave", layout: PDFExporter.Layout(paper: paper))
            #expect(try pageCount(before) == pageCount(layout))
            #expect(try firstPage(before) == firstPage(layout))
        }
    }

    /// The orientation chosen turns the page, whatever the picture's shape.
    @Test func orientationTurnsThePage() throws {
        let wide = Fixtures.stripes()
        let auto = PDFExporter.document(for: wide, title: "Stripes", layout: PDFExporter.Layout(paper: .letter))
        #expect(try firstPage(auto).size == CGSize(width: 792, height: 612))
        let upright = PDFExporter.document(
            for: wide, title: "Stripes", layout: PDFExporter.Layout(paper: .letter, orientation: .portrait))
        #expect(try firstPage(upright).size == CGSize(width: 612, height: 792))
    }

    /// Without the color key the template's pages are all there is.
    @Test func theColorKeyCanBeLeftOut() throws {
        let t = Fixtures.stripes()
        let with = PDFExporter.document(for: t, title: "Stripes", layout: PDFExporter.Layout(paper: .a4))
        let without = PDFExporter.document(for: t, title: "Stripes", layout: PDFExporter.Layout(paper: .a4, colorKey: false))
        #expect(try pageCount(with) == 2)
        #expect(try pageCount(without) == 1)
    }

    /// The sizes offered grow: the smallest is the fewest legible sheets, and each after it more
    /// sheets and a bigger picture, never a smallest number below the floor.
    @Test func sizesGrowAndStayLegible() throws {
        for t in [Fixtures.stripes(), try Fixtures.sample(colors: 18)] {
            for paper in PDFExporter.Paper.allCases {
                let layout = PDFExporter.Layout(paper: paper)
                let sizes = PDFExporter.sizes(for: t, layout: layout)
                #expect(sizes.count >= 2 && sizes.count <= 3)
                #expect(sizes[0].across == nil)
                #expect(sizes[0].sheets == PDFExporter.sheets(for: t, layout: layout))
                for (smaller, bigger) in zip(sizes, sizes.dropFirst()) {
                    #expect(bigger.sheets.count > smaller.sheets.count)
                    #expect(bigger.sheets.printed.width > smaller.sheets.printed.width)
                }
                if let needed = PDFExporter.legibleScale(t) {
                    for size in sizes { #expect(size.sheets.scale >= needed * (1 - 1e-6)) }
                }
                // Each size is what its `across` asks for, and the document has its sheets.
                for size in sizes.dropFirst() {
                    var asked = layout
                    asked.across = size.across
                    #expect(PDFExporter.sheets(for: t, layout: asked) == size.sheets)
                    let data = PDFExporter.document(for: t, title: "T", layout: asked)
                    // The overview, the sheets, the key.
                    #expect(try pageCount(data) == size.sheets.count + 2)
                }
            }
        }
    }

    /// A small template asked across two sheets prints on more than one, bigger than one page.
    @Test func twoAcrossIsBiggerThanOnePage() {
        let t = Fixtures.stripes()
        let one = PDFExporter.sheets(for: t, layout: PDFExporter.Layout(paper: .letter))
        #expect(!one.isTiled)
        let two = PDFExporter.sheets(for: t, layout: PDFExporter.Layout(paper: .letter, across: 2))
        #expect(two.columns == 2)
        #expect(two.scale > one.scale)
    }

    #if UNRELEASED
    /// The preview draws every page of the layout, painted or not, and Painted changes the
    /// template's pages alone.
    @Test func thePreviewDrawsEveryPage() async throws {
        let t = Fixtures.stripes()
        let request = PrintPreviewRequest(template: t, title: "Stripes", nicknames: [])
        let blank = await PrintPages.images(request, layout: PDFExporter.Layout(paper: .letter), longSide: 600)
        let painted = await PrintPages.images(request, layout: PDFExporter.Layout(paper: .letter, painted: true), longSide: 600)
        #expect(blank.count == 2 && painted.count == 2)
        #expect(blank.allSatisfy { max($0.width, $0.height) == 600 })
        let blankPage = PixelReader(blank[0]), paintedPage = PixelReader(painted[0])
        var differ = 0
        for y in stride(from: 0, to: blankPage.height, by: 6) {
            for x in stride(from: 0, to: blankPage.width, by: 6) where blankPage[x, y] != paintedPage[x, y] { differ += 1 }
        }
        #expect(differ > 100)
        record(painted[0], "print-preview-painted")
    }

    /// What Print hands the dialog is the layout's blank document.
    @Test func printingSendsTheLayoutsDocument() async throws {
        let t = Fixtures.stripes()
        let layout = PDFExporter.Layout(paper: .a4, orientation: .portrait, colorKey: false)
        let job = try await TemplatePrintJob.open(template: t, title: "Stripes", nicknames: [], layout: layout)
        #expect(job.name == "Stripes Template")
        #expect(try pageCount(job.pdf) == 1)
        #expect(try firstPage(job.pdf).size == PDFExporter.Paper.a4.size)
    }
    #endif
}
