#if UNRELEASED
import CoreGraphics
import Foundation
import PaintCore
import Testing
@testable import PaintByNumber

/// The length chip's other Painting Lengths cut ahead (painting-company row 361): nearest
/// first, each the very cut `Library.recut` makes, nothing saved until one is picked, and
/// nothing more once stopped.
@MainActor
struct LengthPrecutsTests {
    /// The cuts handed over, in order.
    @MainActor private final class Made {
        var cuts: [LengthPrecuts.Cut] = []
    }

    let root = Fixtures.temporaryDirectory()

    private func makeLibrary() -> Library { Library(store: ArtworkStore(root: root)) }

    /// The stripes cut Quick, as `PaintNowTests` makes them, with a photo to cut again.
    private func painting(in library: Library) async throws -> Artwork {
        let photo = try #require(TemplateRasterizer.image(Fixtures.stripes(), style: .painting, maxPixelSize: 120))
        return try await library.create(ArtworkDraft(
            title: "Stripes", template: Fixtures.stripes(), settings: GenerationSettings(colorCount: 12).normalized,
            settingsOrigin: .suggested, paintingLength: .quick, photo: photo))
    }

    @Test func theNearestLengthsAreCutFirst() {
        #expect(LengthPrecuts.order(from: .relaxed, includingCurrent: false) == [.quick, .detailed])
        #expect(LengthPrecuts.order(from: .quick, includingCurrent: false) == [.relaxed, .detailed])
        #expect(LengthPrecuts.order(from: .detailed, includingCurrent: false) == [.relaxed, .quick])
        // A painting of the painter's own settings: its own length is cut afresh too, first.
        #expect(LengthPrecuts.order(from: .relaxed, includingCurrent: true) == [.relaxed, .quick, .detailed])
        #expect(LengthPrecuts.order(from: .quick, includingCurrent: false, skipping: [.relaxed]) == [.detailed])
        #expect(LengthPrecuts.order(from: nil, includingCurrent: false) == PaintingLength.allCases)
    }

    /// A cut made ahead of the photo's analysis is the cut the length chip's re-cut makes, byte
    /// for byte, and its settings too.
    @Test func aCutMadeAheadIsTheRecut() async throws {
        let library = makeLibrary()
        let artwork = try await painting(in: library)
        let inputs = try await library.cutInputs(for: artwork.id)
        let analysis = try await ArtworkFactory.analysis(of: inputs.photo, lineArt: artwork.settings.lineArt)
        let ahead = try await ArtworkFactory.cut(
            of: analysis, keeping: artwork.settings, length: .detailed, refinements: inputs.refinements,
            maxCandidates: CreateModel.maxCandidates, progress: nil)
        let recut = try await library.recut(artwork: artwork.id, length: .detailed)
        #expect(ahead.template == recut.template)
        #expect(ahead.settings == library.artwork(with: artwork.id)?.settings)
    }

    /// The lengths are cut in turn, nearest first, and nothing reaches the painting's folder
    /// until one is picked; picked, it is put in as it was made and the length recorded.
    @Test func cutsMadeAheadAreKeptUntilOneIsPicked() async throws {
        let library = makeLibrary()
        let artwork = try await painting(in: library)
        let saved = try library.store.readTemplate(artwork.id)
        let precuts = LengthPrecuts()
        let made = Made()
        precuts.resume(artwork: artwork, current: .quick, includingCurrent: false, skipping: [], library: library) {
            made.cuts.append($0)
        }
        let deadline = ContinuousClock.now + .seconds(60)
        while made.cuts.count < 2, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
        #expect(made.cuts.map(\.length) == [.relaxed, .detailed])
        #expect(try library.store.readTemplate(artwork.id) == saved)
        #expect(library.artwork(with: artwork.id)?.paintingLength == PaintingLength.quick.rawValue)

        let detailed = try #require(made.cuts.last)
        let document = try await library.restoreCut(
            artwork: artwork.id, length: .detailed, template: detailed.template, settings: detailed.settings)
        #expect(document.template == detailed.template)
        #expect(try library.store.readTemplate(artwork.id) == detailed.template)
        #expect(library.artwork(with: artwork.id)?.paintingLength == PaintingLength.detailed.rawValue)
    }

    /// A length picked before its cut is made gets a cut at once (`claim`), the progress the chip
    /// shows meanwhile ending with it.
    @Test func aLengthPickedIsCutForThePainter() async throws {
        let library = makeLibrary()
        let artwork = try await painting(in: library)
        let precuts = LengthPrecuts()
        let cut = try await precuts.claim(.relaxed, of: artwork, library: library).value
        #expect(cut.length == .relaxed)
        #expect(precuts.awaitedProgress != nil)
        precuts.finished()
        #expect(precuts.awaitedProgress == nil)
        let recut = try await library.recut(artwork: artwork.id, length: .relaxed)
        #expect(cut.template == recut.template)
    }

    /// Stopped (the painter began) or forgotten (the painting closed) before the cuts start,
    /// nothing is cut.
    @Test func nothingIsCutOnceStopped() async throws {
        let library = makeLibrary()
        let artwork = try await painting(in: library)
        for forgets in [false, true] {
            let precuts = LengthPrecuts()
            let made = Made()
            precuts.resume(artwork: artwork, current: .quick, includingCurrent: false, skipping: [], library: library) {
                made.cuts.append($0)
            }
            if forgets { precuts.forget() } else { precuts.stop() }
            try await Task.sleep(for: LengthPrecuts.settle + .seconds(2))
            #expect(made.cuts.isEmpty)
        }
    }
}
#endif
