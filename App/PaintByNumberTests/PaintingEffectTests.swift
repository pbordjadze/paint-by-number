import Foundation
import Testing
@testable import PaintByNumber

/// Settings › Advanced › Sounds & Effects: every effect starts on and follows its own switch.
@MainActor
struct PaintingEffectTests {
    @Test func everyEffectStartsOnAndFollowsItsOwnSwitch() throws {
        let suite = "PaintingEffectTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(Set(PaintingEffect.allCases.map(\.key)).count == PaintingEffect.allCases.count)
        for effect in PaintingEffect.allCases {
            #expect(effect.isEnabled(in: defaults), "\(effect) isn't on by default")
            defaults.set(false, forKey: effect.key)
            #expect(!effect.isEnabled(in: defaults), "\(effect) ignores its switch")
            #expect(PaintingEffect.allCases.filter { !$0.isEnabled(in: defaults) } == [effect], "\(effect)'s switch turns off others")
            defaults.removeObject(forKey: effect.key)
        }
    }

    @Test func everyEffectHasANameAndADescription() {
        for effect in PaintingEffect.allCases {
            #expect(!effect.title.isEmpty && !effect.summary.isEmpty)
        }
        #expect(Set(PaintingEffect.allCases.map(\.title)).count == PaintingEffect.allCases.count)
    }
}
