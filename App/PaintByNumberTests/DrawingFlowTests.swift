import CoreGraphics
import Foundation
import PaintCore
import Testing
@testable import PaintByNumber

/// Start from a Drawing in the create flow (painting-company row 190): a photo of a drawing
/// is cleaned on the way in, nothing is suggested, the painting is made by the generator's
/// drawing path with the palette set chosen, and the saved painting regenerates the same way.
@MainActor
struct DrawingFlowTests {
    let root = Fixtures.temporaryDirectory()

    private static func photo() throws -> Data { try #require(ShellDemo.drawingPhoto()) }

    @Test func aDrawingIsCleanedAndMadeWithoutASuggestion() async throws {
        let model = CreateModel()
        model.load(drawingData: try Self.photo(), title: "House")
        try await waitUntil { model.isFinal }
        #expect(model.isDrawing)
        #expect(model.decision == nil)
        #expect(model.settingsOrigin == nil)
        #expect(model.settings.drawing == DrawingSettings(palette: .crayons))
        #expect(model.hasLineArtInput)
        let source = try #require(model.source)
        // The sheet, not the table: the cleaned picture is lighter and squarer than the photo.
        #expect(source.image.width < source.image.height)
        #expect(source.image[4, 4].x > 200, "the corner is paper, not table")
        let preview = try #require(model.preview)
        #expect(!preview.isDraft)
        #expect(preview.template.lineArt?.style == .coloringBook)
        #expect(preview.template.regions.count >= 5, "\(preview.template.regions.count) areas")
        #expect(preview.template.palette.last == DrawingPalette.ink, "the solid door is painted ink")
        #expect(preview.template.palette.first == DrawingPalette.colors(of: .crayons)[0])

        // Another palette set makes the painting again, with its paints.
        model.drawingPalette = .sea
        model.settingsChanged()
        try await waitUntil { model.isFinal && model.preview?.settings?.drawing?.palette == .sea }
        let sea = try #require(model.preview)
        #expect(sea.template.palette.first == DrawingPalette.colors(of: .sea)[0])
        #expect(sea.template.regions.count == preview.template.regions.count)

        let draft = try await model.makeDraft()
        #expect(draft.settings.drawing?.palette == .sea)
        #expect(draft.title == "House")
        #expect(model.makingOfSource(for: draft, artworkID: UUID()) == nil, "no show for a drawing")
    }

    @Test func aDrawingsPaintingRegeneratesFromItsCleanedSheet() async throws {
        let model = CreateModel()
        model.load(drawingData: try Self.photo())
        try await waitUntil { model.isFinal }
        let draft = try await model.makeDraft()
        let library = Library(store: ArtworkStore(root: root))
        let artwork = try await library.create(draft)
        #expect(artwork.settings.drawing != nil)
        let document = try await library.regenerate(artwork: artwork.id, settings: artwork.settings)
        #expect(document.template.lineArt?.style == .coloringBook)
        #expect(document.template.palette.last == DrawingPalette.ink)
        // The stored photo is the cleaned sheet, JPEG-encoded: the areas come out the same.
        #expect(abs(document.template.regions.count - draft.template.regions.count) <= 2)
        #expect(library.artwork(with: artwork.id)?.settings.drawing?.palette == .crayons)
    }
}
