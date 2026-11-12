import Foundation
import PaintCore
import Testing
import UIKit
@testable import PaintByNumber

/// From Scratch in the New Painting screen (painting-company row 231): a blank page with no
/// photo behind it, Blank from the start, a name of its own, and Refine asked for at once; the
/// painting drawn on it saves and regenerates as a Blank start does.
@MainActor
struct ScratchFlowTests {
    let root = Fixtures.temporaryDirectory()

    @Test func aPageFromScratchIsBlankNamedAndOpensRefine() async throws {
        let model = CreateModel()
        model.loadScratch()
        try await waitUntil { model.isFinal }
        #expect(model.isScratch)
        #expect(!model.isDrawing)
        #expect(model.refinements.start == .blank)
        #expect(model.refinements.edits.isEmpty)
        #expect(model.decision == nil && model.settingsOrigin == nil, "nothing is suggested for paper")
        #expect(model.hasLineArtInput, "Refine's tools draw on it")
        #expect(model.opensRefine, "Refine opens by itself once the page is made")
        let source = try #require(model.source)
        #expect(source.sampleName == nil, "no sample photo behind it")
        #expect(source.image.width == CreateModel.blankPageSide && source.image.height == CreateModel.blankPageSide)
        #expect(source.image[source.image.width / 2, source.image.height / 2] == SIMD4(255, 255, 255, 255))
        let template = try #require(model.preview?.template)
        #expect(template.regions.count == 1, "one area: the page")
        // Its own name, not a sample's: "Drawing, " and the date.
        #expect(model.resolvedTitle == CreateModel.scratchTitle())
        #expect(model.resolvedTitle.hasPrefix("Drawing, "))
        #expect(model.draft == nil, "a page with nothing drawn is no draft")
        model.cancelAll()
    }

    @Test func aDrawingFromScratchIsKeptSavedAndRegenerated() async throws {
        let model = CreateModel()
        model.loadScratch()
        try await waitUntil { model.isFinal }
        model.withdrawRefine()
        let page = try #require(model.preview?.template)
        let w = Float(page.width), h = Float(page.height)
        let box = TemplateEditor.Edit.draw(
            points: [SIMD2(0.3 * w, 0.3 * h), SIMD2(0.7 * w, 0.3 * h), SIMD2(0.7 * w, 0.7 * h), SIMD2(0.3 * w, 0.7 * h)], closed: true)
        let serial = model.edit(box)
        try await waitUntil(polling: .milliseconds(2)) { model.settledEdits >= serial && model.isFinal }
        #expect(model.preview?.template.regions.count == 2, "the box closed an area of its own")
        let kept = try #require(model.draft, "a drawing is kept as a draft once something is drawn")
        #expect(kept.refinements.start == .blank && kept.sampleName == nil)
        #expect(kept.defaultTitle == CreateModel.scratchTitle())
        #expect(kept.scratch == true)
        let coded = try JSONDecoder().decode(CreateDraft.self, from: JSONEncoder().encode(kept))
        #expect(coded.scratch == true, "draft.json keeps that it is a page from scratch")

        // Resumed, it is a page from scratch again: no analysis, no Start From, its line laid.
        let paper = try #require(model.source?.preview)
        let photo = try #require(UIImage(cgImage: paper).pngData())
        let resumed = CreateModel()
        resumed.load(draft: kept, photo: photo)
        try await waitUntil { resumed.isFinal && resumed.preview?.refinements.edits.count == 1 }
        #expect(resumed.isScratch)
        #expect(resumed.refinements.start == .blank)
        #expect(resumed.decision == nil)
        #expect(resumed.preview?.template.regions.count == 2)
        resumed.cancelAll()

        let draft = try await model.makeDraft()
        #expect(draft.title == CreateModel.scratchTitle())
        #expect(draft.sampleName == nil)
        #expect(model.makingOfSource(for: draft, artworkID: UUID()) == nil, "no show for a blank start")
        let library = Library(store: ArtworkStore(root: root))
        let artwork = try await library.create(draft)
        #expect(artwork.title == CreateModel.scratchTitle())
        // The stored page is the photo a regeneration reads: blank again, the box laid on it.
        let document = try await library.regenerate(artwork: artwork.id, settings: artwork.settings)
        #expect(document.template.regions.count == draft.template.regions.count)
    }

    /// Another photo after From Scratch is a photo again: Start From and the sliders come back.
    /// Back from the preview of a page drawn on, From Scratch again opens that page in Refine
    /// (`reopenScratch`): a fresh one would replace its draft at the first line (QA, November 5).
    /// A page with nothing drawn is no drawing to reopen.
    @Test func aDrawnPageIsOpenedAgainNotReplaced() async throws {
        let model = CreateModel()
        model.loadScratch()
        try await waitUntil { model.isFinal }
        #expect(!model.hasScratchDrawing, "nothing drawn yet")
        model.withdrawRefine()
        let page = try #require(model.preview?.template)
        let w = Float(page.width), h = Float(page.height)
        let serial = model.edit(.draw(points: [SIMD2(0.2 * w, 0.5 * h), SIMD2(0.8 * w, 0.5 * h)], closed: false))
        try await waitUntil(polling: .milliseconds(2)) { model.settledEdits >= serial && model.isFinal }
        #expect(model.hasScratchDrawing)
        #expect(!model.opensRefine)
        model.reopenScratch()
        #expect(model.opensRefine, "Refine opens again on the drawing")
        #expect(model.refinements.changeCount == 1, "the drawing is still there")
        model.cancelAll()
    }

    @Test func aPhotoAfterScratchIsNoLongerScratch() async throws {
        let model = CreateModel()
        model.loadScratch()
        try await waitUntil { model.isFinal }
        model.load(sample: try #require(Sample.named("red-fox")))
        #expect(!model.isScratch)
        #expect(model.refinements.start == .generated)
        model.cancelAll()
    }
}
