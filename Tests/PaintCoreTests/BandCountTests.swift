import Foundation
import Testing
@testable import PaintCore

/// The same inputs make the same bytes on any device (`Parallel`'s doc: never a floating-point
/// sum per band), held where a runner can't see it: one runner has one core count, so these force
/// a few (`Parallel.withBandCount`) over the pipeline's paths. They catch what moves the output
/// with the bands (a split that tips a decision, work keyed on a band's index or size); a sum
/// regrouped by band that changes no bit of these templates passes, as it passes every byte
/// comparison (regrouping Lloyd's sums or the color error's chunks by band, tried October 23,
/// changed none). Serialized: the count is the process's while a test runs, and other suites'
/// output must not move with it either.
@Suite("Band counts", .serialized)
struct BandCountTests {
    /// One band (all in order), a few, and more than any device has.
    static let counts = [1, 3, 37]

    /// The forced count reaches every split, a pass inside a worker's band too.
    @Test func theForcedCountSplitsTheWork() {
        let bands = Parallel.withBandCount(37) {
            Parallel.mapBands(370) { _ in Parallel.mapBands(370) { $0.count }.count }
        }
        #expect(bands == Array(repeating: 37, count: 37))
        #expect(Parallel.bandCount == max(1, ProcessInfo.processInfo.activeProcessorCount * 2))
    }

    static func alike<T: Equatable>(_ make: () throws -> T) rethrows -> Bool {
        let made = try counts.map { count in try Parallel.withBandCount(count, make) }
        return made.allSatisfy { $0 == made[0] }
    }

    @Test func aClassicTemplateIsTheSameAtEveryBandCount() throws {
        let image = TestScenes.colorful(width: 300, height: 200)
        let same = try Self.alike {
            try TemplateGenerator(settings: GenerationSettings(colorCount: 16, detail: 0.6))
                .generate(from: image, cancel: .none).template.encoded()
        }
        #expect(same)
    }

    @Test func aColoringBookIsTheSameAtEveryBandCount() throws {
        let same = try Self.alike { try LineArtTests.generate().template.encoded() }
        #expect(same)
    }

    @Test func writingIsTheSameAtEveryBandCount() throws {
        let same = try Self.alike { try WritingTests.book().template.encoded() }
        #expect(same)
    }

    @Test func autosChoiceIsTheSameAtEveryBandCount() throws {
        let image = TestScenes.colorful(width: 300, height: 200)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let same = try Self.alike {
            try encoder.encode(AutoSettings.choose(
                image: image, importance: nil, hints: nil, preference: .relaxed, maxCandidates: 3, cancel: .none,
                firstDraft: nil))
        }
        #expect(same)
    }
}
