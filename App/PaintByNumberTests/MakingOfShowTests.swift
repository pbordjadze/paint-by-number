import CoreGraphics
import Foundation
import MakingOf
import PaintCore
import Testing
@testable import PaintByNumber

/// The making-of show's app half: the setting, the cards, and the show made as Start makes it
/// (`MakingOfShow`), its stills and its player. The show itself is `Sources/MakingOf`'s, tested
/// there against the Python reference.
@MainActor
struct MakingOfShowTests {
    /// Settings › The Making-of is off until switched on, and reads a launch argument's `YES`
    /// (`-playsMakingOf YES`, as `MakingOfUITests` sets it) as on.
    @Test func theMakingOfIsOffUntilSwitchedOn() throws {
        let suite = "PBNTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(!Preferences(defaults: defaults).playsMakingOf)
        defaults.set(true, forKey: SettingsKey.playsMakingOf)
        #expect(Preferences(defaults: defaults).playsMakingOf)
        defaults.set("YES", forKey: SettingsKey.playsMakingOf)
        #expect(Preferences(defaults: defaults).playsMakingOf)
        #expect(SettingsKey.playsMakingOf == "playsMakingOf")
    }

    /// The catalog's captions are the spec's, in English: a caption the Lamp changes in
    /// `making-of.json` changes in the catalog too.
    @Test func captionsAreTheSpecs() throws {
        let spec = try Self.spec()
        #expect(spec.steps.map(\.id) == ShowSpec.StepID.allCases)
        for step in spec.steps {
            #expect(MakingOfCard.caption(for: step.id) == step.caption, "\(step.id)")
        }
    }

    /// Each method a card credits is in Acknowledgements, and its footnote is the credit line
    /// letter for letter after its mark, the paper's title in italics.
    @Test func cardsCreditTheirMethodsLetterForLetter() throws {
        let spec = try Self.spec()
        let marks = ["¹", "²", "³"]
        for (k, step) in spec.steps.enumerated() {
            let card = MakingOfCard(step: step, index: k)
            #expect(card.step == k)
            #expect(card.spoken == step.caption)
            #expect(card.caption == step.caption + marks.prefix(step.methods.count).joined(separator: ","))
            #expect(card.credits.count == step.methods.count)
            for (i, method) in step.methods.enumerated() {
                let credit = try #require(Acknowledgements.methods.first { $0.name == method }?.credit, "\(method)")
                #expect(String(card.credits[i].characters) == marks[i] + " " + credit)
                let italic = card.credits[i].runs.filter { $0.inlinePresentationIntent == .emphasized }
                    .map { String(card.credits[i][$0.range].characters) }
                #expect(italic.count == 1 && credit.contains("\"\(italic[0])\""), "\(method): \(italic)")
            }
        }
    }

    /// A show made from a photo: the spec's length and steps in order, a card per step, every
    /// number of the template, the crew's sprites, the real template to hand over to.
    @Test func aShowIsMadeFromAPhoto() async throws {
        let source = try Self.source()
        let built = try await MakingOfShow.build(source)
        let spec = try Self.spec()
        let show = built.show
        #expect(abs(show.duration - (spec.timing.intro + 6 * spec.timing.step + spec.timing.outro)) < 1e-9)
        #expect(built.cards.map(\.step) == Array(0..<6))
        #expect(built.digits.count == built.numbers.count && !built.digits.isEmpty)
        #expect(built.digits.allSatisfy { (1...8).contains($0) })
        for id in spec.crew.pets { #expect(built.sprites.has(id), "\(id)") }
        #expect(built.handoff != nil)

        // The steps come in order, each with its own card, and the show ends on the real template.
        let timing = show.timeline.timing
        var stages: [Int] = []
        for t in stride(from: 0.0, through: show.duration, by: 0.05) {
            let frame = show.frame(at: t)
            stages.append(frame.picture.stage)
            if let card = frame.card { #expect(card.step == frame.step && frame.step == show.timeline.step(at: t)) }
        }
        #expect(stages == stages.sorted() && stages.first == -1 && stages.last == 6)
        #expect(Set(stages) == Set(-1...6))
        let end = show.frame(at: show.duration)
        #expect(end.picture.handoff > 0.999 && end.numbers.count == built.numbers.count && end.numbers.allSatisfy { $0 > 0.999 })
        #expect(show.frame(at: timing.start(2) + 1).card?.caption == spec.steps[2].caption)

        // A frame's picture is the pictures' size, guardians drawn from cells the sprites hold.
        var pixels = Plane<SIMD4<UInt8>>(width: show.size.width, height: show.size.height, repeating: .zero)
        let image = try #require(built.picture(show.frame(at: timing.start(1) + 1), into: &pixels))
        #expect(image.width == show.size.width && image.height == show.size.height)
        let working = show.frame(at: timing.start(1) + 1).sprites
        #expect(!working.isEmpty && working.allSatisfy { built.sprites.image($0) != nil })
    }

    /// The show draws the painting's own template, edits and all, whatever the base it was
    /// pictured from; and making the base again with an observer makes it as it was.
    @Test func theShowIsOfThePaintingsTemplate() async throws {
        var source = try Self.source()
        let plain = try TemplateGenerator(settings: source.settings).generate(from: source.image, cancel: .none).template
        let (pictures, base) = try MakingOfShow.observe(source, cancel: .none)
        #expect(base == plain)
        #expect(pictures.width <= 1024 && pictures.height <= 1024 && pictures.width > 0)

        var fewer = source.settings
        fewer.colorCount = 4
        let painting = try TemplateGenerator(settings: fewer).generate(from: source.image, cancel: .none).template
        #expect(painting.width == base.width && painting.height == base.height)
        source.template = painting
        let built = try await MakingOfShow.build(source)
        #expect(built.digits == painting.labels.map { Int(painting.regions[Int($0.region)].colorIndex) + 1 })
        #expect(built.numbers.count == painting.labels.count)
    }

    /// Reduce Motion's stills: the picture as each step leaves it, then the real template, with
    /// neither guardians nor rings.
    @Test func stillsFollowTheSteps() async throws {
        let built = try await MakingOfShow.build(Self.source())
        let timing = built.show.timeline.timing
        let times = MakingOfShow.stillTimes(timing)
        #expect(times.map { timing.stage(at: $0) } == Array(0...6))
        let stills = await MakingOfPlayer.stills(of: built)
        #expect(stills.map(\.step) == [0, 1, 2, 3, 4, 5, nil])
        #expect(stills.allSatisfy { $0.frame.sprites.isEmpty && $0.frame.seedRings.isEmpty && $0.picture != nil })
        #expect((stills.last?.frame.picture.handoff ?? 0) > 0.999)
    }

    /// Skip ends a playing show at once, opens the painting once, and the show can then go.
    @Test func skipOpensThePaintingOnce() async throws {
        let source = try Self.source()
        let player = MakingOfPlayer()
        let finished = Count()
        let run = Task { await player.run(source, reduceMotion: false) { finished.value += 1 } }
        try await waitUntil { player.phase == .playing }
        try await waitUntil { player.picture != nil }
        player.skip()
        #expect(finished.value == 1 && player.phase == .finished)
        await run.value
        #expect(finished.value == 1)
        player.release()
        #expect(player.built == nil && player.picture == nil)
    }

    /// The picture fits above the card's band, centered, keeping its shape.
    @Test func theLayoutFitsThePictureAboveTheCard() {
        for (screen, picture) in [
            (CGSize(width: 1032, height: 1376), CGSize(width: 1024, height: 682)),
            (CGSize(width: 1032, height: 1376), CGSize(width: 682, height: 1024)),
            (CGSize(width: 402, height: 800), CGSize(width: 682, height: 1024)),
            (CGSize(width: 1376, height: 1000), CGSize(width: 1024, height: 768)),
        ] {
            let layout = MakingOfLayout(size: screen, picture: picture, band: 150, top: 64)
            let p = layout.picture
            #expect(abs(p.width / p.height - picture.width / picture.height) < 0.01)
            #expect(p.minY >= 64 && p.minX >= MakingOfLayout.margin - 0.5 && p.maxX <= screen.width - MakingOfLayout.margin + 0.5)
            #expect(abs(p.midX - screen.width / 2) < 0.5)
            #expect(layout.band.minY == p.maxY && layout.band.maxY <= screen.height)
        }
    }

    // MARK: Helpers

    @MainActor
    private final class Count {
        var value = 0
    }

    private static func spec() throws -> ShowSpec {
        let url = try #require(Bundle.main.url(forResource: "making-of", withExtension: "json"))
        return try ShowSpec(json: Data(contentsOf: url))
    }

    /// A small library picture, as Start would make its show: classic lines (no edge map), no
    /// refinements.
    nonisolated private static func source() throws -> MakingOfSource {
        guard let url = Bundle.main.url(forResource: "great-wave", withExtension: "jpg") else { throw CocoaError(.fileNoSuchFile) }
        let image = try PhotoLoader.load(url: url, maxPixelSize: 160)
        let photo = try #require(PhotoLoader.cgImage(from: image))
        return MakingOfSource(
            image: image, importance: nil, lineArt: nil, refinements: TemplateRefinements(),
            settings: GenerationSettings(colorCount: 8, detail: 0.5), template: nil, photo: photo, seed: 7)
    }
}
