import CoreGraphics
import Foundation
import PDFKit
import PaintCore
import Testing
@testable import PaintByNumber

struct RasterizerTests {
    @Test(arguments: [true, false])
    func paintsRegionsInPaletteColors(vector: Bool) throws {
        let t = Fixtures.stripes(vector: vector)
        let image = try #require(TemplateRasterizer.image(t, painted: [true, false, true], style: .thumbnail, maxPixelSize: 120))
        #expect(image.width == 120 && image.height == 80)
        let pixels = PixelReader(image)
        #expect(pixels[20, 40] == SIMD3(255, 0, 0))
        #expect(pixels[100, 40] == SIMD3(0, 0, 255))
        // The unpainted green stripe is sketched as a light neutral grey.
        let sketch = pixels[60, 40]
        #expect(sketch.x == sketch.y && sketch.y == sketch.z)
        #expect(sketch.x > 200 && sketch.x < 255)
    }

    @Test(arguments: [true, false])
    func templateHasPaperOutlinesAndNumbers(vector: Bool) throws {
        let t = Fixtures.stripes(count: 3, stripeWidth: 40, height: 40, vector: vector)
        var style = TemplateRasterizer.Style.template
        style.maximumNumberFraction = 1
        let image = try #require(TemplateRasterizer.image(t, style: style, maxPixelSize: 480))
        let pixels = PixelReader(image)
        #expect(pixels[8, 8] == SIMD3(255, 255, 255))
        // Stripe boundary at canvas x = 40 → 160 px.
        let boundary = (156...163).map { pixels[$0, 20].x }.min() ?? 255
        #expect(boundary < 230)
        // A number is drawn at each label (canvas (20, 20) → (80, 80)).
        var ink = 0
        for y in 50..<110 {
            for x in 50..<110 where pixels[x, y].x < 170 { ink += 1 }
        }
        #expect(ink > 40)
        if let png = ImageCodec.pngData(image) {
            Attachment.record(png, named: "stripes-template-\(vector ? "vector" : "raster").png")
        }
    }

    @Test func numbersAreNeverDropped() throws {
        // Labels with almost no room: the numbers are drawn at the legible floor, not left out.
        var t = Fixtures.stripes(count: 3, stripeWidth: 40, height: 40)
        for k in t.labels.indices { t.labels[k].radius = 0.2 }
        let image = try #require(TemplateRasterizer.image(t, style: .template, maxPixelSize: 480))
        let pixels = PixelReader(image)
        for label in t.labels {
            let cx = Int(label.position.x * 4), cy = Int(label.position.y * 4)
            var ink = 0
            for y in (cy - 12)..<(cy + 12) {
                for x in (cx - 12)..<(cx + 12) where pixels[x, y].x < 170 { ink += 1 }
            }
            #expect(ink > 5, "number of region \(label.region)")
        }
    }

    @Test(arguments: [false, true])
    func threeDigitNumbersFit(printable: Bool) throws {
        // The middle stripe shows 121: sized for three digits, its run stays inside the stripe,
        // on screen and in print alike (one sizing rule, no per-style floor).
        var t = Fixtures.stripes(count: 3, stripeWidth: 40, height: 40)
        let grey = PaletteColor(oklab: SIMD3(0.6, 0, 0), space: .sRGB)
        t.palette += Array(repeating: grey, count: 121 - t.palette.count)
        t.regions[1].colorIndex = 120
        var style = printable ? TemplateRasterizer.Style.printable : TemplateRasterizer.Style.template
        style.maximumNumberFraction = 1
        let image = try #require(TemplateRasterizer.image(t, style: style, maxPixelSize: 480))
        let pixels = PixelReader(image)
        // Separators at canvas x = 40 and 80 → 160 and 320 px; the bands just outside them are
        // clear of the other stripes' single digits.
        var outside = 0, inside = 0
        for y in 0..<pixels.height {
            for x in 130..<157 where pixels[x, y].x < 170 { outside += 1 }
            for x in 324..<350 where pixels[x, y].x < 170 { outside += 1 }
            for x in 164..<317 where pixels[x, y].x < 170 { inside += 1 }
        }
        #expect(outside == 0)
        #expect(inside > 100)
        if let png = ImageCodec.pngData(image) {
            Attachment.record(png, named: "three-digit-number-\(printable ? "printable" : "template").png")
        }
    }

    /// A number in a region with the minimum room stays inside that room at print scale, both
    /// where the template is fitted to one page and where `PDFExporter` tiles it, so print
    /// agrees with SVG and the canvas. (Drawn 4× supersampled to measure it.)
    @Test(arguments: [false, true])
    func minimalRoomNumbersStayInsideTheirRoomAtPDFScale(tiled: Bool) throws {
        var t = Fixtures.stripes(count: 3, stripeWidth: 700, height: 1400)
        for k in t.labels.indices { t.labels[k].radius = LabelSizing.minimumRadius }
        let sheets = PDFExporter.sheets(for: t, paper: .letter)
        let scale = tiled ? sheets.scale : min(sheets.body.width / CGFloat(t.width), sheets.body.height / CGFloat(t.height))
        let supersampling: CGFloat = 4
        let image = try #require(TemplateRasterizer.image(
            t, style: .printable, maxPixelSize: Int((CGFloat(t.width) * scale * supersampling).rounded())))
        let pixels = PixelReader(image)
        let pixelsPerUnit = CGFloat(image.width) / CGFloat(t.width)
        for label in t.labels {
            let cx = CGFloat(label.position.x) * pixelsPerUnit, cy = CGFloat(label.position.y) * pixelsPerUnit
            let room = CGFloat(label.radius) * pixelsPerUnit
            var inside = 0, outside = 0
            // Far from every outline, so only the number is drawn here.
            for y in Int(cy) - 40...Int(cy) + 40 {
                for x in Int(cx) - 40...Int(cx) + 40 where pixels[x, y].x < 235 {
                    // Anti-aliasing spreads a glyph edge by about a pixel.
                    if hypot(CGFloat(x) + 0.5 - cx, CGFloat(y) + 0.5 - cy) <= room + 2 { inside += 1 } else { outside += 1 }
                }
            }
            #expect(inside > 0, "number of region \(label.region) drawn (tiled \(tiled))")
            #expect(outside == 0, "number of region \(label.region) within its room (tiled \(tiled))")
        }
    }

    @Test func finishedPaintingHasNoSketch() throws {
        let t = Fixtures.stripes()
        let image = try #require(TemplateRasterizer.image(t, style: .painting, maxPixelSize: 60))
        let pixels = PixelReader(image)
        #expect(pixels[30, 20] == SIMD3(0, 255, 0))
        #expect(pixels[50, 5] == SIMD3(0, 0, 255))
    }

    @Test func rendersGeneratedSample() throws {
        let t = try Fixtures.sample()
        let progress = ArtworkFactory.progress(painting: 0.4, of: t)
        #expect(abs(Double(progress.paintedCount) / Double(t.regions.count) - 0.4) < 0.01)
        let thumbnail = try #require(TemplateRasterizer.pngData(t, painted: progress.painted, style: .thumbnail, maxPixelSize: 1024))
        let finished = try #require(TemplateRasterizer.pngData(t, style: .finished, maxPixelSize: 1600))
        let numbers = try #require(TemplateRasterizer.pngData(t, style: .template, maxPixelSize: 2000))
        #expect(thumbnail.count > 10_000)
        Attachment.record(thumbnail, named: "parrots-thumbnail-40.png")
        Attachment.record(finished, named: "parrots-finished.png")
        Attachment.record(numbers, named: "parrots-numbers.png")
    }

    @Test(arguments: zip([12, 150], [Float(0.2), 1]))
    func generatedTemplatesKeepEveryNumberLegible(colors: Int, detail: Float) throws {
        // The bundled photo decoded on device, through the whole pipeline: every label has
        // room for its number at the legible size (what CreateModel asserts in Debug builds).
        let t = try Fixtures.sample(colors: colors, detail: detail)
        let report = t.validate(minLabelRadius: LabelSizing.minimumRadius)
        #expect(report.isValid, "\(report)")
        for label in t.labels {
            let digits = LabelSizing.digitCount(colorIndex: t.regions[Int(label.region)].colorIndex)
            #expect(LabelSizing.fittedFontSize(radius: label.radius, digits: digits) >= LabelSizing.minimumFontSize - 1e-4)
        }
    }
}

struct PDFExporterTests {
    @Test func documentHasTemplateAndColorKeyPages() throws {
        let data = PDFExporter.document(for: Fixtures.stripes(), title: "Stripes", paper: .letter)
        #expect(data.starts(with: Data("%PDF".utf8)))
        let document = try #require(CGDataProvider(data: data as CFData).flatMap { CGPDFDocument($0) })
        #expect(document.numberOfPages == 2)
        let box = try #require(document.page(at: 1)?.getBoxRect(.mediaBox))
        // Wide templates print in landscape.
        #expect(box.width == 792 && box.height == 612)
        Attachment.record(data, named: "stripes.pdf")
    }

    @Test func samplePDFRendersPages() throws {
        let t = try Fixtures.sample(colors: 18)
        let data = PDFExporter.document(for: t, title: "Parrots", paper: .a4)
        let document = try #require(CGDataProvider(data: data as CFData).flatMap { CGPDFDocument($0) })
        let sheets = PDFExporter.sheets(for: t, paper: .a4)
        // The template (an overview and its sheets when tiled), then the color key.
        #expect(document.numberOfPages == (sheets.isTiled ? sheets.count + 2 : 2))
        Attachment.record(data, named: "parrots.pdf")
        for index in 1...document.numberOfPages {
            let page = try #require(document.page(at: index))
            let image = try #require(render(page, scale: 2))
            let pixels = PixelReader(image)
            // Something besides white paper was drawn.
            var ink = 0
            for y in stride(from: 0, to: pixels.height, by: 4) {
                for x in stride(from: 0, to: pixels.width, by: 4) where pixels[x, y].x < 200 { ink += 1 }
            }
            #expect(ink > 50)
            if let png = ImageCodec.pngData(image) { Attachment.record(png, named: "parrots-pdf-page\(index).png") }
        }
    }

    /// The color key names every color, so the printed key helps people who can't tell paints apart.
    @Test func colorKeyNamesEveryColor() throws {
        let t = Fixtures.stripes()
        let data = PDFExporter.document(for: t, title: "Stripes", paper: .letter)
        let key = try #require(PDFDocument(data: data)?.page(at: 1)?.string)
        for color in t.palette {
            let name = ColorNameText.title(color.colorName)
            #expect(key.contains(name), "\(name) missing from the key: \(key)")
        }
        #expect(key.contains("Vivid red"))
    }

    /// With nicknames the key names each color by its nickname, then its plain name, then the hex
    /// code; colors without one keep the plain name as their heading.
    @Test func colorKeyShowsNicknameShadeAndHex() throws {
        let t = Fixtures.stripes()
        let nicknames: [String?] = ["Poppy Field", nil, "Harbor Fog"]
        let data = PDFExporter.document(for: t, title: "Stripes", paper: .letter, nicknames: nicknames)
        let key = try #require(PDFDocument(data: data)?.page(at: 1)?.string)
        for (color, nickname) in zip(t.palette, nicknames) {
            let shade = ColorNameText.title(color.colorName)
            #expect(key.contains(shade), "\(shade) missing from the key: \(key)")
            #expect(key.contains(PDFExporter.hex(color.rgb)), "hex missing from the key: \(key)")
            if let nickname { #expect(key.contains(nickname), "\(nickname) missing from the key: \(key)") }
        }
        // Heading, then the plain name below it.
        let order = [key.range(of: "Poppy Field")?.lowerBound, key.range(of: ColorNameText.title(t.palette[0].colorName))?.lowerBound]
        #expect(order[0] != nil && order[1] != nil && order[0]! < order[1]!)
        Attachment.record(data, named: "stripes-nicknames.pdf")
    }

    /// Entries with a nickname are three lines tall: the key still fits every page up to 150 colors.
    @Test func threeLineKeyFitsUpTo150Colors() {
        for paper in PDFExporter.Paper.allCases {
            for landscape in [false, true] {
                let size = landscape ? CGSize(width: paper.size.height, height: paper.size.width) : paper.size
                let content = CGRect(origin: .zero, size: size).insetBy(dx: 36, dy: 36)
                let body = CGRect(x: content.minX, y: content.minY + 36, width: content.width, height: content.height - 36)
                for count in [1, 24, 100, 150] {
                    let layout = PDFExporter.keyLayout(count: count, widestEntry: 150, lines: 3, in: body)
                    #expect(layout.height <= body.height, "\(paper) landscape \(landscape), \(count) colors")
                    #expect(layout.rowHeight == 32 * layout.scale)
                }
            }
        }
    }

    /// The key fits its page for every palette size the app makes (up to 150 colors).
    @Test func keyLayoutFitsUpTo150Colors() {
        for paper in PDFExporter.Paper.allCases {
            for landscape in [false, true] {
                let size = landscape ? CGSize(width: paper.size.height, height: paper.size.width) : paper.size
                // Page margins and the header, as `document` lays them out.
                let content = CGRect(origin: .zero, size: size).insetBy(dx: 36, dy: 36)
                let body = CGRect(x: content.minX, y: content.minY + 36, width: content.width, height: content.height - 36)
                for count in [0, 1, 12, 24, 48, 100, 150] {
                    for widest: CGFloat in [110, 160] {
                        let layout = PDFExporter.keyLayout(count: count, widestEntry: widest, in: body)
                        let context = "\(paper) landscape \(landscape), \(count) colors, entry \(widest)"
                        #expect(layout.height <= body.height, "\(context)")
                        #expect(CGFloat(layout.columns) * layout.columnWidth + 12 * CGFloat(layout.columns - 1)
                                <= body.width + 0.5, "\(context)")
                        #expect(layout.scale >= 0.6, "\(context)")
                        #expect(layout.rows >= 1, "\(context)")
                        #expect(layout.rows * layout.columns >= count, "\(context)")
                    }
                }
            }
        }
        let a4 = CGRect(x: 36, y: 72, width: PDFExporter.Paper.a4.size.width - 72, height: PDFExporter.Paper.a4.size.height - 108)
        #expect(PDFExporter.keyLayout(count: 24, widestEntry: 120, in: a4).scale == 1)
    }

    @Test func largeTemplatesPrintOnSheetsWithLegibleNumbers() throws {
        // 2100 × 1400 canvas units whose labels have the minimum room: fitted to one page its
        // numbers would print at about 1.3 pt, so it goes on overlapping sheets at a scale
        // that prints the smallest number at the legible floor, after an overview page.
        var t = Fixtures.stripes(count: 3, stripeWidth: 700, height: 1400)
        for k in t.labels.indices { t.labels[k].radius = LabelSizing.minimumRadius }
        let sheets = PDFExporter.sheets(for: t, paper: .letter)
        #expect(sheets.columns == 2 && sheets.rows == 2)
        #expect(CGFloat(LabelSizing.minimumFontSize) * sheets.scale >= PDFExporter.minimumNumberSize)
        // The grid covers the template exactly, neighbours overlapping.
        let last = sheets.window(column: sheets.columns - 1, row: sheets.rows - 1)
        #expect(abs(last.maxX - sheets.printed.width) < 1e-6 && abs(last.maxY - sheets.printed.height) < 1e-6)
        let first = sheets.window(column: 0, row: 0)
        #expect(sheets.window(column: 1, row: 0).minX == first.maxX - PDFExporter.sheetOverlap)

        let data = PDFExporter.document(for: t, title: "Stripes", paper: .letter)
        let document = try #require(CGDataProvider(data: data as CFData).flatMap { CGPDFDocument($0) })
        #expect(document.numberOfPages == sheets.count + 2)
        Attachment.record(data, named: "stripes-sheets.pdf")
        // Each sheet shows its part of the outlines: the separators at canvas x = 700 and 1400.
        for index in 2...(sheets.count + 1) {
            let page = try #require(document.page(at: index))
            let image = try #require(render(page, scale: 2))
            let pixels = PixelReader(image)
            var ink = 0
            // Inside the body (72...576 pt down, 36...756 pt across at 2 px/pt), clear of the
            // header and of every sheet's border.
            for y in stride(from: 160, to: 900, by: 2) {
                for x in 80..<1490 where pixels[x, y].x < 230 { ink += 1 }
            }
            #expect(ink > 100, "sheet \(index - 1)")
        }

        // A template whose numbers are large enough stays on one page.
        #expect(!PDFExporter.sheets(for: Fixtures.stripes(), paper: .letter).isTiled)
    }

    @Test func paperFollowsRegion() {
        #expect(PDFExporter.Paper.default(for: Locale.Region("US")) == .letter)
        #expect(PDFExporter.Paper.default(for: Locale.Region("DE")) == .a4)
        #expect(PDFExporter.Paper.default(for: nil) == .a4)
    }

    private func render(_ page: CGPDFPage, scale: CGFloat) -> CGImage? {
        let box = page.getBoxRect(.mediaBox)
        let width = Int(box.width * scale), height = Int(box.height * scale)
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.scaleBy(x: scale, y: scale)
        ctx.drawPDFPage(page)
        return ctx.makeImage()
    }
}

@MainActor
struct PreferencesTests {
    @Test func defaultsAndSessionMapping() throws {
        let suite = "PBNTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        var preferences = Preferences(defaults: defaults)
        #expect(preferences.autoAdvance && preferences.haptics && preferences.sounds)
        #expect(preferences.colorNames == .playful)

        defaults.set(false, forKey: SettingsKey.autoAdvance)
        defaults.set("a4", forKey: SettingsKey.paperSize)
        defaults.set(false, forKey: "hapticsEnabled")
        defaults.set("plain", forKey: SettingsKey.colorNames)
        preferences = Preferences(defaults: defaults)
        #expect(preferences.colorNames == .plain)
        #expect(!preferences.autoAdvance)
        #expect(!preferences.haptics)
        #expect(preferences.paper == .a4)

        let session = PaintingSession(template: Fixtures.stripes())
        #expect(session.autoAdvance && session.colorNameStyle == .playful)
        preferences.apply(to: session)
        #expect(!session.autoAdvance && session.colorNameStyle == .plain)
    }

    /// An unknown stored value is the default, not a crash or a third style.
    @Test func colorNameStyleFallsBackToPlayful() throws {
        let suite = "PBNTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for stored in ["", "shouty", "Playful"] {
            defaults.set(stored, forKey: SettingsKey.colorNames)
            #expect(Preferences(defaults: defaults).colorNames == .playful, "\(stored)")
        }
        defaults.set("playful", forKey: SettingsKey.colorNames)
        #expect(Preferences(defaults: defaults).colorNames == .playful)
        #expect(ColorNameStyle.allCases == [.playful, .plain])
    }

    /// The Paper preference defaults to light, round-trips its raw values, and ignores
    /// anything it doesn't know.
    @Test func paperAppearanceDefaultsAndParses() throws {
        let suite = "PBNTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(Preferences(defaults: defaults).paperAppearance == .light)
        for appearance in PaperAppearance.allCases {
            defaults.set(appearance.rawValue, forKey: SettingsKey.paperAppearance)
            #expect(Preferences(defaults: defaults).paperAppearance == appearance)
        }
        defaults.set("sepia", forKey: SettingsKey.paperAppearance)
        #expect(Preferences(defaults: defaults).paperAppearance == .light)
        #expect(SettingsKey.paperAppearance == "paperAppearance")
        #expect(Set(PaperAppearance.allCases.map(\.rawValue)) == ["light", "dark", "automatic"])
    }

    /// Painting Length defaults to Relaxed, round-trips its raw values, ignores anything it
    /// doesn't know, and is what the create flow aims for.
    @Test func paintingLengthDefaultsAndPersists() throws {
        let suite = "PBNTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(Preferences(defaults: defaults).paintingLength == .relaxed)
        #expect(PaintingLength.default == .relaxed)
        for length in PaintingLength.allCases {
            defaults.set(length.rawValue, forKey: SettingsKey.paintingLength)
            #expect(Preferences(defaults: defaults).paintingLength == length)
            #expect(!length.name.isEmpty && !length.footer.isEmpty)
        }
        defaults.set("marathon", forKey: SettingsKey.paintingLength)
        #expect(Preferences(defaults: defaults).paintingLength == .relaxed)
        #expect(SettingsKey.paintingLength == "paintingLength")
        #expect(Set(PaintingLength.allCases.map(\.rawValue)) == ["quick", "relaxed", "detailed"])
        #expect(PaintingLength.relaxed.footer == "Suggested settings aim for about an hour of painting.")

        #expect(CreateModel(paintingLength: .quick).paintingLength == .quick)
    }

    @Test func createModelMapsSliders() {
        let model = CreateModel()
        // The sliders wait at the generator's defaults until a photo's suggestion moves them.
        #expect(model.settings == GenerationSettings())
        #expect(model.settingsOrigin == nil && model.decision == nil && !model.isChoosingSettings)
        model.colorCount = 30
        model.detail = 0.25
        model.smoothness = 0.75
        #expect(model.settings == GenerationSettings(colorCount: 30, detail: 0.25, smoothness: 0.75))
        model.colorCount = 11.6
        #expect(model.settings.colorCount == 12)
        model.colorCount = 999
        #expect(model.settings.colorCount == GenerationSettings.colorCountRange.upperBound)
        #expect(model.preview == nil && !model.isFinal)
    }

    @Test func formatsDurations() {
        #expect(PaintByNumber.PaintingTime.approximate(10 * 60) == "~10 min")
        #expect(PaintByNumber.PaintingTime.approximate(2 * 3600) == "~2 h")
        #expect(PaintByNumber.PaintingTime.approximate(1.4 * 3600) == "~1.5 h")
        #expect(PaintByNumber.PaintingTime.approximate(30 * 3600) == "~30 h")
        #expect(PaintByNumber.PaintingTime.spent(125 * 60) == "2 h 5 min")
        #expect(PaintByNumber.PaintingTime.spent(20) == "< 1 min")
    }
}
