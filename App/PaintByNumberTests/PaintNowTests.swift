import CoreGraphics
import Foundation
import PaintCore
import Testing
@testable import PaintByNumber

/// Paint Now (painting-company row 239): the Paint page's Tonight's Picture, the painting's ✎
/// Change saving its new template with the painted areas kept, and its length chip's re-cut.
@MainActor
struct PaintNowTests {
    let root = Fixtures.temporaryDirectory()

    private func makeLibrary() -> Library { Library(store: ArtworkStore(root: root)) }

    private func photo() throws -> CGImage {
        try #require(TemplateRasterizer.image(Fixtures.stripes(), style: .painting, maxPixelSize: 120))
    }

    /// The stripes, painted where asked, with settings the drawing tools' model makes again exactly.
    private func draft(painted: [Int] = [], photo: CGImage? = nil) -> ArtworkDraft {
        var progress = PaintProgress(regionCount: 3)
        for region in painted { _ = progress.paint(region) }
        return ArtworkDraft(
            title: "Stripes", template: Fixtures.stripes(), settings: GenerationSettings(colorCount: 12).normalized,
            settingsOrigin: .suggested, paintingLength: .quick, photo: photo, progress: painted.isEmpty ? nil : progress)
    }

    @Test func tonightsPictureIsOneLibraryPaintingADay() throws {
        let paintings = Sample.all(of: .painting)
        try #require(paintings.count > 1)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let morning = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 7)))
        let night = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 23)))
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: morning))
        let today = try #require(Sample.tonight(on: morning, calendar: calendar))
        #expect(paintings.contains(today))
        #expect(Sample.tonight(on: night, calendar: calendar) == today, "Tonight's Picture changed within the day")
        #expect(Sample.tonight(on: tomorrow, calendar: calendar) != today, "Tonight's Picture stayed the next day")
        // Every painting comes round.
        let days = (0..<paintings.count).compactMap { calendar.date(byAdding: .day, value: $0, to: morning) }
        #expect(Set(days.compactMap { Sample.tonight(on: $0, calendar: calendar)?.id }) == Set(paintings.map(\.id)))
    }

    /// ✎ Change's Done: the new template and refinements replace the painting's, and the painted
    /// areas are carried onto it.
    @Test func adoptingAChangeKeepsThePaintedAreas() async throws {
        let library = makeLibrary()
        let artwork = try await library.create(draft(painted: [0, 2], photo: try photo()))
        var refinements = TemplateRefinements()
        refinements.edits = [.draw(points: [SIMD2(5, 5), SIMD2(30, 30)])]
        var changed = draft()
        changed.refinements = refinements

        let document = try await library.adopt(changed, into: artwork.id)
        #expect(document.progress.painted == [true, false, true])
        #expect(document.notice == nil)
        #expect(try library.store.readRefinements(artwork.id) == refinements)
        #expect(library.artwork(with: artwork.id)?.paintedCount == 2)
        let reopened = try await library.loadForPainting(artwork.id)
        #expect(reopened.progress.painted == [true, false, true])

        // Every edit undone: no refinements left on disk.
        _ = try await library.adopt(draft(), into: artwork.id)
        #expect(!FileManager.default.fileExists(atPath: library.store.url(.refinements, of: artwork.id).path))
    }

    @Test func changeOpensOnThePaintingsPhotoAndRefinements() async throws {
        let library = makeLibrary()
        let artwork = try await library.create(draft(photo: try photo()))
        let inputs = try await library.changeInputs(for: artwork.id)
        #expect(!inputs.photo.isEmpty)
        #expect(inputs.refinements.isEmpty)

        // Refinements from a newer editor may hold edits this one couldn't read: Done would write
        // them away, so ✎ Change doesn't open on them.
        try Data(#"{"editorVersion": 9999, "edits": []}"#.utf8).write(to: library.store.url(.refinements, of: artwork.id))
        await #expect(throws: Library.OpenError.needsNewerApp) {
            _ = try await library.changeInputs(for: artwork.id)
        }

        let bare = try await library.create(draft())
        await #expect(throws: ArtworkFactory.FactoryError.sourceUnavailable) {
            _ = try await library.changeInputs(for: bare.id)
        }
    }

    /// An unedited painting opens in the drawing tools as it stands: its template is the base,
    /// nothing made again.
    @Test func changeOpensOnTheTemplateAsItStands() async throws {
        let library = makeLibrary()
        let created = try await library.create(draft(photo: try photo()))
        // A template the generator made, as a painting's is (the stripes fixture's numbers are
        // smaller than Debug builds' preview check allows).
        let made = try await library.regenerate(artwork: created.id, settings: GenerationSettings(colorCount: 6, detail: 0).normalized)
        let artwork = try #require(library.artwork(with: created.id))
        let inputs = try await library.changeInputs(for: artwork.id)
        let model = CreateModel(previewStyle: .painting)
        model.load(artwork: artwork, photo: inputs.photo, template: made.template, refinements: inputs.refinements)
        await model.settled()
        #expect(model.canRefine)
        #expect(model.preview?.template == made.template)
        #expect(model.settings == artwork.settings)
        let draft = try await model.makeDraft()
        #expect(draft.template == made.template)
    }

    /// The length chip's re-cut records the length it was cut for.
    @Test func recuttingRecordsTheLength() async throws {
        let library = makeLibrary()
        let artwork = try await library.create(draft(photo: try photo()))
        let document = try await library.recut(artwork: artwork.id, length: .detailed)
        #expect(document.notice == nil)
        #expect(document.progress.paintedCount == 0)
        let recut = try #require(library.artwork(with: artwork.id))
        #expect(recut.paintingLength == PaintingLength.detailed.rawValue)
        #expect(recut.regionCount == document.template.regions.count)
        #expect(recut.settings.lineArt == artwork.settings.lineArt)
    }

    /// Back to a length the painting had: that very cut, not one made again (the Mac's QA, 347
    /// areas then 344), the length recorded and nothing painted.
    @Test func aCutPutBackIsTheSameTemplate() async throws {
        let library = makeLibrary()
        let artwork = try await library.create(draft(photo: try photo()))
        let first = try await library.loadForPainting(artwork.id).template
        _ = try await library.recut(artwork: artwork.id, length: .detailed)
        let back = try await library.restoreCut(
            artwork: artwork.id, length: .relaxed, template: first, settings: artwork.settings)
        #expect(back.template == first)
        #expect(try library.store.readTemplate(artwork.id) == first)
        let restored = try #require(library.artwork(with: artwork.id))
        #expect(restored.paintingLength == PaintingLength.relaxed.rawValue)
        #expect(restored.settings == artwork.settings && restored.regionCount == first.regions.count)
        #expect(back.progress.paintedCount == 0)
    }

    /// A painting made over in place (✎ Change's Done, a re-cut) keeps the paint in hand: the same
    /// paint while it has areas left, else the nearest one that has; none when all are done.
    @Test func thePaintInHandStaysInHand() {
        let palette: [SIMD3<Float>] = [SIMD3(0.9, 0, 0), SIMD3(0.5, 0.1, 0), SIMD3(0.52, 0.1, 0.01), SIMD3(0.2, -0.1, 0.1)]
        let open = [true, true, true, true]
        #expect(ArtworkPaintingView.keptColor(palette[2], palette: palette, open: open) == 2)
        #expect(ArtworkPaintingView.keptColor(palette[2], palette: palette, open: [true, true, false, true]) == 1)
        #expect(ArtworkPaintingView.keptColor(SIMD3(0.21, -0.1, 0.1), palette: palette, open: open) == 3)
        #expect(ArtworkPaintingView.keptColor(palette[0], palette: palette, open: [false, false, false, false]) == nil)
    }

    /// The menu's time for the cut on screen and the cuts made while open is the chip's estimate;
    /// a length not cut yet shows the band it aims for.
    @Test func theLengthMenuSaysWhatTheChipSays() {
        let chip = PaintingTimeText.approximate(PaintingTime.estimate(regionCount: 406))
        #expect(LengthChip.rowTime(of: .relaxed, chosen: .relaxed, regionCount: 406, cutAreas: [:]) == chip)
        let quick = PaintingTimeText.approximate(PaintingTime.estimate(regionCount: 150))
        #expect(LengthChip.rowTime(of: .quick, chosen: .relaxed, regionCount: 406, cutAreas: [.quick: 150]) == quick)
        #expect(LengthChip.rowTime(of: .detailed, chosen: .relaxed, regionCount: 406, cutAreas: [.quick: 150])
            == LengthChip.band(of: .detailed))
    }
}
