import CoreGraphics
import Foundation
import PaintCore
import Testing
@testable import PaintByNumber

/// Print's layout (painting-company row 357): `PDFExporter.Layout`'s paper, orientation, size,
/// layers (row 370) and color key, and the preview that draws its pages.
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

    /// The layers start as the template has always printed: lines, numbers and the dotted
    /// guides, on paper (painting-company row 370).
    @Test func theLayersStartAsTheTemplateAlwaysPrinted() {
        let layout = PDFExporter.Layout(paper: .letter)
        #expect(layout.lines && layout.numbers && !layout.colorHints && layout.colorKey)
        let style = layout.templateStyle, printable = TemplateRasterizer.Style.printable
        #expect(style.numbers && style.drawsDrawing && style.lines == .print && style.unpainted == .paper)
        #expect(style.outlineWidth == printable.outlineWidth)
    }

    /// Each layer turned off or on changes the template's page, and with lines, numbers and
    /// color hints all off nothing of the template is left on it.
    @Test func eachLayerChangesThePage() async throws {
        for t in [Fixtures.stripes(), try Fixtures.sample(colors: 12)] {
            let request = PrintPreviewRequest(template: t, title: "Layers", nicknames: [])
            func page(_ change: (inout PDFExporter.Layout) -> Void) async throws -> CGImage {
                var layout = PDFExporter.Layout(paper: .letter, across: 1)
                layout.colorKey = false
                change(&layout)
                return try #require(await PrintPages.images(request, layout: layout, longSide: 1200).first)
            }
            let hintsImage = try await page { $0.colorHints = true }
            let usual = PixelReader(try await page { _ in })
            let noLines = PixelReader(try await page { $0.lines = false })
            let noNumbers = PixelReader(try await page { $0.numbers = false })
            let hints = PixelReader(hintsImage)
            let nothing = PixelReader(try await page { $0.lines = false; $0.numbers = false })
            // Below the header: the template's part of the page.
            func count(_ a: PixelReader, _ test: (SIMD3<Int>) -> Bool) -> Int {
                var n = 0
                for y in stride(from: 140, to: a.height - 80, by: 2) {
                    for x in stride(from: 80, to: a.width - 80, by: 2) where test(a[x, y]) { n += 1 }
                }
                return n
            }
            func differ(_ a: PixelReader, _ b: PixelReader) -> Int {
                var n = 0
                for y in stride(from: 140, to: a.height - 80, by: 2) {
                    for x in stride(from: 80, to: a.width - 80, by: 2) where maxDifference(a[x, y], b[x, y]) > 8 { n += 1 }
                }
                return n
            }
            #expect(differ(usual, noLines) > 10)
            #expect(differ(usual, noNumbers) > 10)
            #expect(differ(usual, hints) > 200)
            // A hint is a color, where the usual page is grey ink on white (its greys lean blue
            // by 13 levels at most).
            let colored = { (c: SIMD3<Int>) in max(c.x, c.y, c.z) - min(c.x, c.y, c.z) > 20 }
            #expect(count(usual, colored) == 0)
            #expect(count(hints, colored) > 200)
            // Nothing but the paper and the picture's frame.
            #expect(count(nothing) { $0.x < 150 } < 40)
            record(hintsImage, "print-layers-hints-\(t.width)x\(t.height)")
        }
    }

    /// Without numbers no legibility floor sizes the print: the smallest size is one page.
    @Test func withoutNumbersTheSmallestSizeIsOnePage() throws {
        let t = try Fixtures.sample(colors: 30, detail: 0.6)
        var layout = PDFExporter.Layout(paper: .letter)
        layout.numbers = false
        let sizes = PDFExporter.sizes(for: t, layout: layout)
        #expect(sizes[0].across == nil && sizes[0].sheets.count == 1)
        #expect(sizes.count >= 2)
        // An asked size is kept.
        layout.across = 2
        #expect(PDFExporter.sheets(for: t, layout: layout).count > 1)
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
}
