import Foundation
import PaintCore
import Testing
@testable import PaintByNumber

/// Refine's Tool Guide (`RefineGuideView`): a page for every tool the Toolbox offers, and the
/// practice picture its canvases refine.
@MainActor
struct RefineGuideTests {
    /// The guide lists The Basics and Layers, then every tool the Toolbox offers, each once, and
    /// every page has words and a practice picture; a practice's finger tool is one of the listed
    /// tools, never an action.
    @Test func everyToolTheToolboxOffersHasAPage() {
        let listed = RefineGuideTopic.sections.flatMap(\.topics)
        let start = RefineGuideTopic.sections[0]
        #expect(start.group == nil)
        #expect(start.topics == [.basics, .layers])
        #expect(Set(listed).count == listed.count, "a page listed twice")
        for tool in RefineGroup.allCases.flatMap(\.tools) {
            #expect(listed.contains(.tool(tool)), "\(tool) has no page")
        }
        for topic in listed {
            let page = RefineGuidePage.of(topic)
            #expect(!page.summary.isEmpty && !RefineGuideText.blocks(page.text).isEmpty, "\(topic)")
            #expect(listed.contains(.tool(page.practice.tool)) && page.practice.tool != .tryPainting, "\(topic)")
        }
        // Writing practises on the note, whose text it corrects; every other page on the evening.
        #expect(RefineGuidePage.of(.tool(.text)).practice == RefinePracticeSetup(scene: .note, tool: .text))
        #expect(RefineGuidePage.of(.tool(.tryPainting)).practice.teaches == .tryPainting)
    }

    /// Every page ends with On the practice picture, which SideStore and Debug builds lay over
    /// the practice canvas as the page's invitation, the rest under How It Works
    /// (painting-company row 316).
    @Test func everyPageInvitesToItsPractice() {
        for topic in RefineGuideTopic.sections.flatMap(\.topics) {
            let blocks = RefineGuideText.blocks(RefineGuidePage.of(topic).text)
            let lastHeading = blocks.last { if case .heading = $0 { true } else { false } }
            #expect(lastHeading == .heading("On the practice picture"), "\(topic)")
            let split = RefineGuideText.invitation(blocks)
            #expect(!split.invitation.isEmpty && !split.rest.isEmpty, "\(topic)")
            #expect(!split.invitation.contains { if case .heading = $0 { true } else { false } }, "\(topic)")
        }
        let split = RefineGuideText.invitation(RefineGuideText.blocks("Lead.\n\n## More\nMiddle.\n\n## Try\nDo it."))
        #expect(split.invitation == [.paragraph("Do it.")])
        #expect(split.rest == [.paragraph("Lead."), .heading("More"), .paragraph("Middle.")])
        #expect(RefineGuideText.invitation([.paragraph("Alone.")]).invitation.isEmpty)
    }

    /// A page's links name pages the guide lists, and none links to itself.
    @Test func everyLinkOpensAListedPage() throws {
        for topic in RefineGuideTopic.sections.flatMap(\.topics) {
            let text = RefineGuidePage.of(topic).text
            let targets = text.matches(of: /\]\((guide:[A-Za-z]+)\)/).map { String($0.output.1) }
            for target in targets {
                let url = try #require(URL(string: target))
                let linked = RefineGuideTopic(link: url)
                #expect(linked != nil, "\(topic) links \(target), which isn't a page")
                #expect(linked != topic, "\(topic) links to itself")
            }
        }
        // Merge's page sends the painter on to Cell Edge (the UI test follows it).
        #expect(RefineGuidePage.of(.tool(.merge)).text.contains("(guide:cellEdge)"))
    }

    /// The words' layout: a heading takes its paragraph on the next line, a run of `- ` lines is
    /// a list, and a paragraph's links parse.
    @Test func theWordsLayOut() throws {
        let blocks = RefineGuideText.blocks("Lead.\n\n## A heading\nIts paragraph.\n\n- one\n- two\n\n## Alone")
        #expect(blocks == [.paragraph("Lead."), .heading("A heading"), .paragraph("Its paragraph."), .list(["one", "two"]), .heading("Alone")])
        // A paragraph and a list in one chunk, as the Pen's page has under a heading.
        #expect(RefineGuideText.blocks("## Notes\nWhat went wrong:\n- one\n- two\nAfter.") == [
            .heading("Notes"), .paragraph("What went wrong:"), .list(["one", "two"]), .paragraph("After."),
        ])
        let link = RefineGuideText.inline("Use [Merge](guide:merge).").runs.compactMap { $0.link }.first
        #expect(link.flatMap(RefineGuideTopic.init(link:)) == .tool(.merge))
    }

    /// The pages that start the guide: their identifiers (after `refine-guide-topic-`, which UI
    /// tests read), and Layers' practice traces the photo under the paint at half.
    @Test func theStartPagesAreNamed() {
        #expect(RefineGuideTopic.basics.identifier == "basics")
        #expect(RefineGuideTopic.layers.identifier == "layers")
        #expect(RefineGuidePage.of(.layers).practice.layers == .tracing)
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

    /// Writing's practice: the note is generated from its own line-art input, its found lines are
    /// Writing's boxes, and marking the pencil line makes it again with the mark (no draft kept).
    @Test func theNoteIsWritingsPractice() async throws {
        let picture = try await RefinePracticePicture.make()
        let model = CreateModel(previewStyle: .lineArt)
        model.practice(picture, scene: .note)
        try await waitUntil(timeout: .seconds(120)) { model.preview != nil && model.phase == .ready }
        #expect(model.isPractice && model.foundText == RefinePracticeNote.foundText)
        let before = try #require(model.preview?.template.lineArt?.writingStrokes.count)
        #expect(before > 0, "the found lines drew no writing")
        model.beginRefining()
        let missed = RefinePracticeNote.missedText
        model.change(.markText(TemplateRefinements.textLine(from: missed[0], to: missed[2])))
        try await waitUntil(timeout: .seconds(120)) { model.preview?.refinements.addedText.count == 1 && model.phase == .ready }
        let after = try #require(model.preview?.template.lineArt?.writingStrokes.count)
        #expect(after > before, "the pencil line, marked, drew no writing")
        #expect(model.draft == nil)
    }
}
