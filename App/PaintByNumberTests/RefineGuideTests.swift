import Foundation
import PaintCore
import Testing
@testable import PaintByNumber

/// Refine's Tool Guide (`RefineGuideView`): a page for every tool the Toolbox offers, and the
/// practice picture its canvases refine.
@MainActor
struct RefineGuideTests {
    /// The guide lists The Basics and Views, then every tool the Toolbox offers, each once, and
    /// every page has words; a practice's finger tool is one of the listed tools, never an action.
    @Test func everyToolTheToolboxOffersHasAPage() {
        let listed = RefineGuideTopic.sections.flatMap(\.topics)
        #expect(Array(listed.prefix(2)) == [.basics, .views])
        #expect(Set(listed).count == listed.count, "a page listed twice")
        for tool in RefineGroup.allCases.flatMap(\.tools) {
            #expect(listed.contains(.tool(tool)), "\(tool) has no page")
        }
        for topic in listed {
            let page = RefineGuidePage.of(topic)
            #expect(!page.summary.isEmpty && !page.about.isEmpty && !page.steps.isEmpty, "\(topic)")
            #expect(!page.related.contains { RefineGuideTopic.tool($0) == topic }, "\(topic) goes well with itself")
            if let practice = page.practice {
                #expect(listed.contains(.tool(practice.tool)) && practice.tool != .tryPainting, "\(topic)")
            }
        }
        // Writing works on the text found in the painter's photo: the practice picture has none.
        #expect(RefineGuidePage.of(.tool(.text)).practice == nil)
        #expect(RefineGuidePage.of(.tool(.tryPainting)).practice?.teaches == .tryPainting)
    }

    /// The guide opens on the tool in hand, or on The Basics for one it doesn't list.
    @Test func theGuideOpensOnTheToolInHand() {
        #expect(RefineGuideTopic.opening(at: .merge) == .tool(.merge))
        #expect(RefineGuideTopic.opening(at: .splitter) == (RefineView.offersSplitter ? .tool(.splitter) : .basics))
    }

    /// A practice is final at once, with nothing generated: an edit lays on it, and Cancel's way
    /// back (Reset) leaves the picture as it was.
    @Test func thePracticePictureIsReadyToRefine() async throws {
        let picture = try await RefinePracticePicture.make()
        let model = CreateModel(previewStyle: .lineArt)
        model.practice(picture, scene: .painted)
        try await waitUntil { model.canRefine }
        #expect(model.isPractice && model.hasLineArtInput && model.refinements.isEmpty)
        #expect(model.preview?.template == picture.painted)
        model.beginRefining()
        // From the sky into the moon: the moon joins the sky.
        let height = Float(RefinePractice.height)
        model.edit(.merge(points: [SIMD2(0.6, 0.2) * height, SIMD2(1.04, 0.2) * height]))
        try await waitUntil { model.settledEdits == 1 }
        #expect(model.refinements.edits.count == 1 && model.preview?.template.regions.count == 12)
        model.cancelRefining()
        try await waitUntil { model.refinements.edits.isEmpty }
        try await waitUntil { model.preview?.template == picture.painted }
        #expect(!model.canUndo)
    }
}
