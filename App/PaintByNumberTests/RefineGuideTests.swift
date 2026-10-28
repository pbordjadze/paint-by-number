import Foundation
import PaintCore
import Testing
@testable import PaintByNumber

/// Refine's Tool Guide (`RefineGuideView`): a page for every tool the Toolbox offers, and the
/// practice picture its canvases refine.
@MainActor
struct RefineGuideTests {
    /// The guide lists The Basics, Layers and Coming from Procreate, then every tool the Toolbox
    /// offers, each once, and every page has words; a practice's finger tool is one of the listed
    /// tools, never an action.
    @Test func everyToolTheToolboxOffersHasAPage() {
        let listed = RefineGuideTopic.sections.flatMap(\.topics)
        let start = RefineGuideTopic.sections[0]
        #expect(start.group == nil)
        #expect(start.topics == [.basics, .layers, .procreate])
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

    /// Every tool's page says what it is in Procreate, or what it does that Procreate's pixels
    /// can't, for whoever comes from there or goes on to it.
    @Test func everyToolPageSaysWhatItIsInProcreate() {
        for tool in RefineGroup.allCases.flatMap(\.tools) {
            let line = RefineGuidePage.of(.tool(tool)).inProcreate ?? ""
            #expect(!line.isEmpty, "\(tool)'s page has no In Procreate line")
        }
        // The Procreate page is the comparison itself, practised with the Bucket: touch and hold
        // picks a paint, and a swatch dragged onto a cell pours it.
        let procreate = RefineGuidePage.of(.procreate)
        #expect(procreate.inProcreate == nil && !procreate.notes.isEmpty)
        #expect(procreate.practice == RefinePracticeSetup(scene: .inked, tool: .bucket))
    }

    /// The pages that start the guide: their identifiers (after `refine-guide-topic-`, which UI
    /// tests read), and Layers' practice traces the photo under the paint at half.
    @Test func theStartPagesAreNamed() {
        #expect(RefineGuideTopic.basics.identifier == "basics")
        #expect(RefineGuideTopic.layers.identifier == "layers")
        #expect(RefineGuideTopic.procreate.identifier == "procreate")
        #expect(RefineGuidePage.of(.layers).practice?.layers == .tracing)
    }

    /// A practice canvas's switches are its own: the painter's are their start, and a change on a
    /// page leaves them.
    @Test func thePracticeKeepsItsOwnSwitches() {
        let key = SettingsKey.refinePenColors, painter = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(painter, forKey: key) }
        UserDefaults.standard.set(false, forKey: key)
        RefinePracticeSetup.seedSettings()
        #expect(RefinePracticeSetup.settings.bool(forKey: key) == false)
        RefinePracticeSetup.settings.set(true, forKey: key)
        #expect(UserDefaults.standard.bool(forKey: key) == false)
    }

    /// The guide opens on the tool in hand.
    @Test func theGuideOpensOnTheToolInHand() {
        #expect(RefineGuideTopic.opening(at: .merge) == .tool(.merge))
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
        // Nothing generates and nothing is kept as a draft.
        #expect(model.phase == .ready && model.draft == nil)
        model.cancelRefining()
        try await waitUntil { model.refinements.edits.isEmpty }
        try await waitUntil { model.preview?.template == picture.painted }
        #expect(!model.canUndo && model.phase == .ready)
    }
}
