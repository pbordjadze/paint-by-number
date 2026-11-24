import Foundation
import PaintCore
import Testing
@testable import PaintByNumber

/// Tonight's Picture made before it is picked (painting-company row 361): kept by what a flow's
/// own making reads, taken once and only by the same picture, length and line art, and the
/// painting it gives the very one a pick makes without it.
@MainActor
struct TonightAheadTests {
    private let lineArt = LineArtSettings().normalized

    @Test func keysTellPicturesLengthsAndLineArtApart() throws {
        let fox = try #require(Sample.named("red-fox"))
        let wave = try #require(Sample.named("great-wave"))
        let key = try #require(TonightAhead.key(for: fox, paintingLength: .quick, lineArt: lineArt))
        #expect(TonightAhead.key(for: fox, paintingLength: .quick, lineArt: lineArt) == key)
        #expect(TonightAhead.key(for: fox, paintingLength: .relaxed, lineArt: lineArt) != key)
        #expect(TonightAhead.key(for: wave, paintingLength: .quick, lineArt: lineArt) != key)
        #expect(TonightAhead.key(for: fox, paintingLength: .quick, lineArt: LineArtSettings(style: .classic)) != key)
        #expect(key.pipelineVersion == TemplateGenerator.pipelineVersion)
        #expect(key.paintMix == CreateModel.newPaintMix && key.tuning == CreateModel.newTuning)
        #expect(key.candidates == CreateModel.maxCandidates)
        #if UNRELEASED
        // A night's picture whose full picture hasn't come can't be made yet.
        let folder = Fixtures.temporaryDirectory()
        let thumbnail = folder.appending(path: "thumb.jpg")
        try Data([0xFF]).write(to: thumbnail)
        let night = Sample(
            night: Nights.Picture(
                id: "aic-1", title: "A Night", creator: "A Painter", year: "1890", credit: "A Museum", license: "Public domain",
                source: "https://example.org", medium: nil, place: nil, image: "pictures/aic-1.jpg", thumb: "thumbs/aic-1.jpg",
                sha256: String(repeating: "0", count: 64)),
            file: folder.appending(path: "missing.jpg"), thumbnail: thumbnail)
        #expect(TonightAhead.key(for: night, paintingLength: .quick, lineArt: lineArt) == nil)
        #endif
    }

    /// Made ahead, then picked: the flow shows the final painting with no draft before it, and it
    /// is byte for byte what the same pick makes with nothing made ahead.
    @Test func aPictureMadeAheadIsWhatItsPickMakes() async throws {
        let fox = try #require(Sample.named("red-fox"))
        let key = try #require(TonightAhead.key(for: fox, paintingLength: .quick, lineArt: lineArt))
        let ahead = TonightAhead()
        await ahead.prepare(key)?.value
        #expect(ahead.keptKey == key)
        #expect(ahead.prepare(key) == nil, "A picture kept was made again")
        // Another picture's pick takes nothing, and leaves it kept.
        let greatWave = try #require(Sample.named("great-wave"))
        let wave = try #require(TonightAhead.key(for: greatWave, paintingLength: .quick, lineArt: lineArt))
        #expect(ahead.take(wave) == nil)
        #expect(ahead.keptKey == key)

        let picked = CreateModel(paintingLength: .quick)
        picked.ahead = ahead
        picked.paintsNow = true
        picked.load(sample: fox)
        #expect(ahead.keptKey == nil, "What was made ahead wasn't taken")
        var sawDraft = false
        try await waitUntil(polling: .milliseconds(5)) {
            if picked.preview?.isDraft == true { sawDraft = true }
            return picked.isFinal
        }
        #expect(!sawDraft, "The painting made ahead waited for a draft")

        let plain = CreateModel(paintingLength: .quick)
        plain.ahead = TonightAhead()
        plain.load(sample: fox)
        try await waitUntil { plain.isFinal }
        let decision = try #require(plain.decision)
        #expect(CreateModel.aheadSettings(of: decision, lineArt: plain.baseLineArt) == plain.settings)
        #expect(picked.decision?.settings == decision.settings)
        #expect(picked.settings == plain.settings)
        #expect(picked.settingsOrigin == .suggested)
        let template = try #require(picked.preview?.template)
        #expect(template == plain.preview?.template, "The painting made ahead isn't the one its pick makes")

        let draft = try await picked.makeDraft()
        #expect(draft.template == template)
        #expect(draft.sampleName == fox.id)
        #expect(draft.paintingLength == .quick)
    }

    /// Picked while it is still being made, or at another length: the flow makes its own, and
    /// the making ahead stops so the two don't run side by side.
    @Test func aPickThatMissesMakesItsOwnAndStopsTheMakingAhead() async throws {
        let fox = try #require(Sample.named("red-fox"))
        let key = try #require(TonightAhead.key(for: fox, paintingLength: .quick, lineArt: lineArt))
        let ahead = TonightAhead()
        let making = try #require(ahead.prepare(key))

        let model = CreateModel(paintingLength: .relaxed)
        model.ahead = ahead
        model.load(sample: fox)
        await making.value
        #expect(ahead.keptKey == nil, "A making ahead that missed went on")
        try await waitUntil { model.isFinal }
        #expect(model.decision?.preference == .relaxed)
    }
}
