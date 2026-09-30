import Foundation
import PaintCore
import Testing
@testable import PaintByNumber

@MainActor
struct CreateModelTests {
    @Test func generatesDraftThenFinalAndFollowsSettings() async throws {
        let model = CreateModel(initial: GenerationSettings(colorCount: 12, detail: 0.3))
        model.load(sample: try #require(Sample.named("espresso")))
        try await waitUntil { model.isFinal }
        let first = try #require(model.preview)
        #expect(!first.isDraft)
        #expect(model.phase == .ready)
        #expect((model.stats?.areas ?? 0) > 0)
        #expect(model.defaultTitle == "Espresso")
        #expect(model.resolvedTitle == "Espresso")

        // Dragging a slider: quick drafts at reduced size…
        model.setAdjusting(true)
        model.colorCount = 8
        model.settingsChanged()
        try await waitUntil { model.preview?.isDraft == true && model.preview?.settings.colorCount == 8 }
        #expect(model.preview.map { max($0.template.width, $0.template.height) } ?? 0 <= Int(CreateModel.draftLongSide) + 1)

        // …and the full resolution once it is released.
        model.setAdjusting(false)
        try await waitUntil { model.isFinal }
        #expect(model.preview?.settings.colorCount == 8)

        model.title = "  Morning Coffee "
        let draft = try await model.makeDraft()
        #expect(draft.title == "Morning Coffee")
        #expect(draft.template.palette.count <= 8)
        #expect(draft.sampleName == "espresso")
        #expect(draft.photo != nil)
    }

    @Test func startingPaintingGeneratesTheFinalTemplateIfNeeded() async throws {
        let model = CreateModel(initial: GenerationSettings(colorCount: 10, detail: 0.2))
        model.load(sample: try #require(Sample.named("regatta")))
        try await waitUntil { model.preview != nil }
        // Change the settings and immediately start: the draft must match the new settings.
        model.colorCount = 7
        let draft = try await model.makeDraft()
        #expect(draft.settings.colorCount == 7)
        #expect(model.isFinal)
    }

    @Test func cameraFailureSurfacesAnError() async throws {
        let model = CreateModel(initial: GenerationSettings(colorCount: 10, detail: 0.2))
        model.load(sample: try #require(Sample.named("espresso")))
        try await waitUntil { model.source != nil }
        // The camera's shot couldn't be read: the earlier photo and its work are dropped.
        model.fail(.cameraCapture)
        #expect(model.phase == .failed(CreateModel.CreateError.cameraCapture.localizedDescription))
        #expect(model.source == nil && model.preview == nil && model.stats == nil)
        #expect(!model.isWorking)
        try await Task.sleep(for: .milliseconds(300))
        #expect(model.preview == nil)
    }

    /// The typed name is trimmed; an empty one falls back to the sample's name or, for a
    /// photo, the date. A new photo starts over with its own default.
    @Test func titleFallsBackToTheDefault() throws {
        let model = CreateModel()
        model.load(sample: try #require(Sample.named("espresso")))
        #expect(model.title == "")
        #expect(model.defaultTitle == "Espresso")
        model.title = "  Jungle \n"
        #expect(model.resolvedTitle == "Jungle")
        model.title = "   "
        #expect(model.resolvedTitle == "Espresso")

        model.title = "Jungle"
        model.load(imageData: Data())
        #expect(model.title == "")
        #expect(model.defaultTitle == Date.now.formatted(.dateTime.month(.wide).day()))
        #expect(model.resolvedTitle == model.defaultTitle)
        model.cancelAll()
    }

    private func waitUntil(timeout: Duration = .seconds(120), _ condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !condition() {
            guard clock.now < deadline else {
                Issue.record("Timed out waiting for the create model")
                throw CancellationError()
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }
}
