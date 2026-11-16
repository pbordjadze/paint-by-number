#if UNRELEASED
import CoreGraphics
import Foundation
import PaintCore
import Testing
@testable import PaintByNumber

/// Fine-Tune (painting-company row 352): the length chip's sheet of Colors, Detail and Lines,
/// which cuts a painting not begun again with the painter's own settings.
@MainActor
struct FineTuneTests {
    let root = Fixtures.temporaryDirectory()

    private func makeLibrary() -> Library { Library(store: ArtworkStore(root: root)) }

    private func draft() throws -> ArtworkDraft {
        let photo = try #require(TemplateRasterizer.image(Fixtures.stripes(), style: .painting, maxPixelSize: 120))
        return ArtworkDraft(
            title: "Stripes", template: Fixtures.stripes(), settings: GenerationSettings(colorCount: 12).normalized,
            settingsOrigin: .suggested, paintingLength: .quick, photo: photo)
    }

    /// The painter's settings are what the painting is made with and records, as custom, at the
    /// length it was cut for.
    @Test func retuningRecordsThePaintersSettings() async throws {
        let library = makeLibrary()
        let artwork = try await library.create(try draft())
        var settings = artwork.settings
        settings.colorCount = 8
        settings.detail = 0.2
        let document = try await library.retune(artwork: artwork.id, settings: settings)
        #expect(document.notice == nil)
        #expect(document.progress.paintedCount == 0)
        let tuned = try #require(library.artwork(with: artwork.id))
        #expect(tuned.settings == settings.normalized)
        #expect(tuned.settingsOrigin == SettingsOrigin.custom.rawValue)
        #expect(tuned.paintingLength == PaintingLength.quick.rawValue)
        #expect(tuned.regionCount == document.template.regions.count)
    }

    /// The Lines slider opens where the create flow's slider left a painting's line art, and
    /// moved there makes that line art again; the middle is the style's own.
    @Test func linesOpenWhereTheCreateFlowLeftThem() {
        let base = LineArtSettings().normalized
        #expect(FineTuneSheet.linesPosition(of: base) == 0.5)
        for lines in [0.0, 0.25, 0.5, 0.8, 1.0] {
            let art = CreateModel.lineArt(base, lines: lines)
            let position = FineTuneSheet.linesPosition(of: art)
            #expect(abs(position - lines) < 1e-4)
            let made = FineTuneSheet.lineArt(base, lines: position)
            #expect(abs(made.minimumStrokeLength - art.minimumStrokeLength) < 1e-3)
            #expect(abs(made.detailThreshold - art.detailThreshold) < 1e-4)
            #expect(abs(made.outlineThreshold - art.outlineThreshold) < 1e-4)
        }
        #expect(FineTuneSheet.linesPosition(of: LineArtSettings(style: .classic)) == 0.5)
    }

    /// Lines moved keeps the rest of the painting's line art.
    @Test func linesKeepTheRestOfTheLineArt() {
        let art = LineArtSettings(keepWriting: false).normalized
        let more = FineTuneSheet.lineArt(art, lines: 1)
        #expect(!more.keepWriting)
        #expect(more.minimumStrokeLength < art.minimumStrokeLength)
    }
}
#endif
