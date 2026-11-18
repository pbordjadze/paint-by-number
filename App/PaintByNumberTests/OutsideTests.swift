import CoreGraphics
import Foundation
import PaintCore
import Testing
@testable import PaintByNumber

/// The shelf the widgets and the stickers read (painting-company rows 348 and 349).
struct OutsideShelfTests {
    let shelf = OutsideShelf(root: Fixtures.temporaryDirectory().appending(path: "Outside"))

    private func now(steps: Int, token: String = "a") -> OutsideShelf.Now {
        OutsideShelf.Now(
            token: token, artwork: UUID(), title: "Stripes", total: 10,
            steps: (0..<steps).map { OutsideShelf.Now.Step(picture: "now-\($0).jpg", painted: $0, region: $0 > 0 ? $0 : nil, next: nil) })
    }

    @Test func listsRoundTripAndAnotherVersionReadsAsNothing() throws {
        #expect(shelf.now() == nil && shelf.finished() == nil && shelf.stickers() == nil)
        var laid = now(steps: 3)
        try shelf.write(laid, to: .now)
        #expect(shelf.now() == laid)
        laid.version = OutsideShelf.version + 1
        try shelf.write(laid, to: .now)
        #expect(shelf.now() == nil)

        let finished = OutsideShelf.Finished(paintings: [.init(id: UUID(), title: "One", picture: "finished-1.jpg")])
        try shelf.write(finished, to: .finished)
        #expect(shelf.finished() == finished)
        let stickers = OutsideShelf.Stickers(stickers: [.init(painting: UUID(), title: "One", picture: "sticker-1.png")])
        try shelf.write(stickers, to: .stickers)
        #expect(shelf.stickers() == stickers)
    }

    /// A tap is counted only while the layout has a picture for it, and against its layout alone.
    @Test func tapsStopAtTheLastPictureAndGoStaleWithTheLayout() throws {
        #expect(shelf.addTap() == 0)
        let laid = now(steps: 3)
        try shelf.write(laid, to: .now)
        #expect(shelf.taps(for: laid) == 0 && laid.offersTap(after: 0))
        #expect(shelf.addTap() == 1)
        #expect(shelf.addTap() == 2)
        #expect(shelf.addTap() == 2)
        #expect(shelf.taps(for: laid) == 2 && !laid.offersTap(after: 2))
        #expect(laid.step(after: 2)?.picture == "now-2.jpg" && laid.step(after: 9)?.picture == "now-2.jpg")

        let next = now(steps: 3, token: "b")
        try shelf.write(next, to: .now)
        #expect(shelf.taps(for: next) == 0)
        #expect(shelf.addTap() == 1)
        shelf.clearTaps()
        #expect(shelf.taps(for: next) == 0)
    }

    /// The widget's percentage is the gallery card's: 135 of 314 areas is 42%, not 43%.
    @Test func theWidgetsPercentIsTheGallerysRule() {
        #expect(OutsideShelf.percent(painted: 135, total: 314) == 42)
        for total in [0, 1, 2, 3, 7, 99, 100, 101, 314, 1000, 2047] {
            for painted in Set([0, 1, 2, total / 3, total / 2, total - 2, total - 1, total, total + 1]) where painted >= 0 {
                #expect(OutsideShelf.percent(painted: painted, total: total) == PaintSpeech.percent(painted: painted, total: total))
            }
        }
        var laid = now(steps: 3)
        laid.total = 314
        laid.steps = laid.steps.enumerated().map { index, step in
            var step = step
            step.painted = 134 + index
            return step
        }
        #expect(laid.percent(after: 0) == 42 && laid.percent(after: 1) == 42 && laid.percent(after: 9) == 43)
    }

    @Test func theFrameTurnsThroughThePaintingsADayEach() {
        let paintings = (0..<3).map { OutsideShelf.Finished.Painting(id: UUID(), title: "\($0)", picture: "\($0).jpg") }
        let finished = OutsideShelf.Finished(paintings: paintings)
        #expect((0..<4).map { finished.painting(onDay: $0)?.title } == ["0", "1", "2", "0"])
        #expect(finished.painting(onDay: -1)?.title == "2")
        #expect(OutsideShelf.Finished(paintings: []).painting(onDay: 5) == nil)
    }

    @Test func sweepingKeepsWhatIsNamed() throws {
        try shelf.write(Data([1]), named: "now-a-0.jpg")
        try shelf.write(Data([1]), named: "now-b-0.jpg")
        try shelf.write(Data([1]), named: "finished-a.jpg")
        shelf.sweep(prefix: "now-", keeping: ["now-b-0.jpg"])
        let left = try FileManager.default.contentsOfDirectory(atPath: shelf.root.path).sorted()
        #expect(left == ["finished-a.jpg", "now-b-0.jpg"])
    }

    @Test func aPaintingsLinkReadsBackAndNoOtherDoes() throws {
        let id = UUID()
        #expect(OutsideShelf.painting(of: OutsideShelf.link(toPainting: id)) == id)
        #expect(OutsideShelf.painting(of: try #require(URL(string: "paintbymoonlight://settings/\(id.uuidString)"))) == nil)
        #expect(OutsideShelf.painting(of: URL(filePath: "/tmp/\(id.uuidString)")) == nil)
    }

    /// Signed again by SideStore the group has that team's name, which its Info.plist carries.
    @Test func theGroupFallsBackToItsOwnName() {
        #expect(OutsideShelf.groups(of: .main).last == OutsideShelf.group)
    }
}

#if UNRELEASED
@MainActor
struct OutsideDeskTests {
    let root = Fixtures.temporaryDirectory()
    let shelf = OutsideShelf(root: Fixtures.temporaryDirectory().appending(path: "Outside"))

    private func makeLibrary() -> Library { Library(store: ArtworkStore(root: root)) }

    private func mosaic(in library: Library) async throws -> Artwork {
        try await library.create(ArtworkDraft(
            title: "Mosaic", template: Fixtures.mosaic, settings: GenerationSettings(colorCount: 12), photo: nil, sampleName: nil, progress: nil))
    }

    /// The plan paints the largest areas left, of any paint, so a widget's tap shows; it takes
    /// no area twice and never the last.
    @Test func thePlanPaintsTheLargestAreasAndLeavesTheLast() {
        let template = Fixtures.mosaic
        let count = template.regions.count
        var progress = PaintProgress(regionCount: count)
        let plan = OutsideFills.plan(template: template, progress: progress)
        #expect(plan.count == OutsideFills.most && Set(plan).count == plan.count)
        let areas = plan.map { template.regions[$0].area }
        #expect(areas == areas.sorted(by: >))
        let rest = template.regions.indices.filter { !plan.contains($0) }.map { template.regions[$0].area }
        #expect(rest.allSatisfy { $0 <= areas.last! })

        // Painted areas are left out.
        progress.paint(plan[0])
        #expect(!OutsideFills.plan(template: template, progress: progress).contains(plan[0]))

        progress = PaintProgress(regionCount: count)
        for region in 0..<(count - 3) { progress.paint(region) }
        #expect(OutsideFills.plan(template: template, progress: progress).count == 2)
        progress.paint(count - 3)
        progress.paint(count - 2)
        #expect(OutsideFills.plan(template: template, progress: progress).isEmpty)
        #expect(OutsideFills.plan(template: template, progress: PaintProgress(regionCount: count + 1)).isEmpty)
    }

    /// The widget's taps are painted into the saved painting when the app comes back, in the
    /// plan's order; the taps are spent, and taps on a painting that changed since are dropped.
    @Test func tapsArePaintedIntoThePaintingAsSaved() async throws {
        let library = makeLibrary()
        let artwork = try await mosaic(in: library)
        let template = Fixtures.mosaic
        let fresh = PaintProgress(regionCount: template.regions.count)
        let now = try #require(OutsideDesk.now(of: artwork, template: template, progress: fresh, shelf: shelf, limit: 3))
        #expect(now.steps.count == 4 && now.steps.map(\.painted) == [0, 1, 2, 3] && now.total == template.regions.count)
        #expect(now.steps[0].region == nil && now.steps[0].next?.number == Int(template.regions[now.steps[1].region ?? 0].colorIndex) + 1)
        #expect(now.steps[3].next == nil)
        for step in now.steps { #expect(FileManager.default.fileExists(atPath: shelf.url(step.picture).path)) }
        try shelf.write(now, to: .now)

        #expect(OutsideDesk.painted(fresh, by: now, taps: 0) == nil)
        let two = try #require(OutsideDesk.painted(fresh, by: now, taps: 2))
        #expect(two.log.map { Int($0.region) } == now.steps[1...2].compactMap(\.region))
        // Another count of painted areas than the layout's, or an area painted already: no fit.
        #expect(OutsideDesk.painted(two, by: now, taps: 1) == nil)

        shelf.addTap()
        shelf.addTap()
        await OutsideDesk.absorb(now, into: library, shelf: shelf)
        await library.flush()
        let saved = try library.store.readProgress(artwork.id, regionCount: template.regions.count)
        #expect(saved.problem == nil && saved.progress == two)
        #expect(shelf.taps(for: now) == 0)

        // The same layout's taps again: the painting has moved on, so they are dropped, and spent.
        shelf.addTap()
        await OutsideDesk.absorb(now, into: library, shelf: shelf)
        await library.flush()
        #expect(try library.store.readProgress(artwork.id, regionCount: template.regions.count).progress == two)
        #expect(shelf.taps(for: now) == 0)
    }

    /// Laying out leaves waiting taps and their pictures alone while they fit the painting as
    /// saved; once it has moved on (the widget tapped while the app was still on its way out,
    /// against the layout before), they go and the painting is laid out as it stands.
    @Test func layingOutKeepsOnlyTapsThatStillFit() async throws {
        let library = makeLibrary()
        let artwork = try await mosaic(in: library)
        let template = Fixtures.mosaic
        var progress = PaintProgress(regionCount: template.regions.count)
        OutsideDesk.layOutNow(artwork, store: library.store, shelf: shelf)
        let first = try #require(shelf.now())
        #expect(first.steps.first?.painted == 0 && first.steps.count == OutsideFills.most + 1)
        shelf.addTap()
        OutsideDesk.layOutNow(artwork, store: library.store, shelf: shelf)
        #expect(shelf.now() == first && shelf.taps(for: first) == 1)

        let unplanned = try #require((0..<template.regions.count).first { region in !first.steps.contains { $0.region == region } })
        progress.paint(unplanned)
        library.saveProgress(progress, for: artwork.id)
        await library.flush()
        OutsideDesk.layOutNow(artwork, store: library.store, shelf: shelf)
        let second = try #require(shelf.now())
        #expect(second.token != first.token && second.steps.first?.painted == 1)
        #expect(shelf.taps(for: second) == 0)
        for step in first.steps { #expect(!FileManager.default.fileExists(atPath: shelf.url(step.picture).path)) }

        OutsideDesk.layOutNow(nil, store: library.store, shelf: shelf)
        #expect(shelf.now() == nil)
    }

    /// What this launch laid out stands while the painting is saved as it was: nothing is
    /// drawn again. A change of the paint in hand alone, or a shelf another layout wrote,
    /// is drawn anew.
    @Test func aLayoutStandsWhileThePaintingIsAsSaved() async throws {
        let library = makeLibrary()
        let artwork = try await mosaic(in: library)
        let laid = try #require(OutsideDesk.layOutNow(artwork, store: library.store, shelf: shelf))
        let first = try #require(shelf.now())
        #expect(laid.token == first.token)
        #expect(OutsideDesk.layOutNow(artwork, store: library.store, shelf: shelf, standing: laid) == laid)
        #expect(shelf.now() == first)

        var progress = PaintProgress(regionCount: Fixtures.mosaic.regions.count)
        progress.inHand = 1
        library.saveProgress(progress, for: artwork.id, recording: false)
        await library.flush()
        let again = try #require(OutsideDesk.layOutNow(artwork, store: library.store, shelf: shelf, standing: laid))
        #expect(again.token != laid.token && shelf.now()?.token == again.token)

        OutsideDesk.layOutNow(artwork, store: library.store, shelf: shelf)
        #expect(OutsideDesk.layOutNow(artwork, store: library.store, shelf: shelf, standing: again)?.token != again.token)
    }
}

struct StickerMakerTests {
    @Test func aMaskGrowsByItsReachAndNoFurther() {
        var inside = [Bool](repeating: false, count: 21 * 21)
        inside[10 * 21 + 10] = true
        let grown = StickerMaker.grown(inside, width: 21, height: 21, by: 3)
        #expect(grown[10 * 21 + 13] && grown[7 * 21 + 10] && grown[10 * 21 + 10])
        #expect(!grown[10 * 21 + 14] && !grown[7 * 21 + 7] && !grown[0])
    }

    /// The print is the picture on white with clear corners, centered on a square of a
    /// sticker's side, its white edge casting a soft shadow that shows on white.
    @Test func thePrintHasAWhiteEdgeAShadowAndClearCorners() throws {
        let painting = try #require(TemplateRasterizer.image(Fixtures.stripes(), style: .finished, maxPixelSize: 300))
        let print = try #require(StickerMaker.framed(painting))
        #expect(print.width == StickerMaker.pixels && print.height == StickerMaker.pixels)
        let pixels = PixelReader(print)
        #expect(pixels.alpha(x: 0, y: 0) == 0)
        #expect(pixels.alpha(x: print.width / 2, y: print.height / 2) == 255)
        expectShadowBeforeTheWhiteEdge(pixels)
    }

    /// Along the middle row from the left: clear, then the shadow's partly covered pixels, then
    /// the white edge.
    private func expectShadowBeforeTheWhiteEdge(_ pixels: PixelReader) {
        let y = pixels.height / 2
        guard let opaque = (0..<pixels.width).first(where: { pixels.alpha(x: $0, y: y) == 255 }) else {
            Issue.record("No opaque pixel in the middle row")
            return
        }
        #expect((0..<opaque).contains { pixels.alpha(x: $0, y: y) > 0 })
        let white = pixels[opaque + 2, y]
        #expect(white.x >= 250 && white.y >= 250 && white.z >= 250)
    }

    /// The cut-out is cropped to its subject and clear outside its white edge; a speck, the
    /// whole picture or a mask of another shape gives none.
    @Test func theCutOutKeepsTheSubjectAlone() throws {
        let painting = try #require(TemplateRasterizer.image(Fixtures.stripes(), style: .finished, maxPixelSize: 300))
        let width = 60, height = 40
        var inside = [Bool](repeating: false, count: width * height)
        for y in 10..<30 { for x in 20..<40 { inside[y * width + x] = true } }
        let cut = try #require(StickerMaker.cutOut(painting, inside: inside, width: width, height: height))
        #expect(cut.width == StickerMaker.pixels && cut.height == StickerMaker.pixels)
        let pixels = PixelReader(cut)
        #expect(pixels.alpha(x: 0, y: 0) == 0)
        #expect(pixels.alpha(x: cut.width / 2, y: cut.height / 2) == 255)
        // Inside the white edge; its outermost pixels are soft, as the mask is scaled up.
        #expect(pixels.alpha(x: cut.width / 2, y: cut.height / 10) == 255)
        // The scaled-up mask is soft on every side; the shadow, drawn a little down, makes the
        // band below the subject's white edge the heavier one.
        let x = cut.width / 2
        let column = (0..<cut.height).filter { pixels.alpha(x: x, y: $0) == 255 }
        if let top = column.first, let bottom = column.last {
            let above = (max(0, top - 10)..<top).reduce(0) { $0 + pixels.alpha(x: x, y: $1) }
            let below = ((bottom + 1)..<min(cut.height, bottom + 11)).reduce(0) { $0 + pixels.alpha(x: x, y: $1) }
            #expect(below > above)
        } else {
            Issue.record("No opaque pixel in the middle column")
        }

        var speck = [Bool](repeating: false, count: width * height)
        speck[0] = true
        #expect(StickerMaker.cutOut(painting, inside: speck, width: width, height: height) == nil)
        #expect(StickerMaker.cutOut(painting, inside: [Bool](repeating: true, count: width * height), width: width, height: height) == nil)
        #expect(StickerMaker.cutOut(painting, inside: [Bool](repeating: true, count: 40 * 60), width: 40, height: 60) == nil)
    }

    /// A finished painting gets its print on the shelf, small enough for Messages; with no
    /// photo there is no cut-out, which is noted so it isn't tried again; a painting gone
    /// takes its sticker with it.
    @Test @MainActor func finishedPaintingsGetTheirStickers() async throws {
        let library = Library(store: ArtworkStore(root: Fixtures.temporaryDirectory()))
        let shelf = OutsideShelf(root: Fixtures.temporaryDirectory().appending(path: "Outside"))
        let artwork = try await library.create(ArtworkDraft(
            title: "Stripes", template: Fixtures.stripes(), settings: GenerationSettings(colorCount: 12), photo: nil, sampleName: nil, progress: nil))
        await StickerMaker.layOut([artwork], store: library.store, shelf: shelf)
        let stickers = try #require(shelf.stickers()).stickers
        #expect(stickers.map(\.painting) == [artwork.id] && stickers.first?.title == "Stripes")
        let picture = try #require(stickers.first?.picture)
        let data = try Data(contentsOf: shelf.url(picture))
        #expect(!data.isEmpty && data.count <= StickerMaker.mostBytes)
        let names = try FileManager.default.contentsOfDirectory(atPath: shelf.root.path)
        #expect(names.contains { $0.hasSuffix("-nocut") })

        await StickerMaker.layOut([], store: library.store, shelf: shelf)
        #expect(shelf.stickers()?.stickers.isEmpty == true)
        #expect(try FileManager.default.contentsOfDirectory(atPath: shelf.root.path) == ["stickers.json"])
    }
}
#endif
