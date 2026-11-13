import Foundation
import Testing
@testable import PaintByNumber

/// The rating prompt's moment (painting-company row 341): from the second painting finished, once
/// per app version.
@MainActor
struct RatingPromptTests {
    private func freshDefaults() throws -> UserDefaults {
        let suite = "RatingPromptTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func theFirstFinishedPaintingDoesNotAsk() throws {
        let prompt = RatingPrompt(defaults: try freshDefaults(), version: "1.2")
        #expect(!prompt.paintingFinished())
    }

    @Test func theSecondAsksAndTheVersionAsksOnce() throws {
        let defaults = try freshDefaults()
        let prompt = RatingPrompt(defaults: defaults, version: "1.2")
        _ = prompt.paintingFinished()
        #expect(prompt.paintingFinished())
        prompt.asked()
        #expect(!prompt.paintingFinished(), "one ask per version")
        #expect(RatingPrompt(defaults: defaults, version: "1.3").paintingFinished(), "a new version may ask again")
    }

    @Test func aMomentMissedIsOfferedAgain() throws {
        let prompt = RatingPrompt(defaults: try freshDefaults(), version: "1.2")
        _ = prompt.paintingFinished()
        #expect(prompt.paintingFinished())
        // The painter left before the ask: nothing was recorded, so the next finish asks.
        #expect(prompt.paintingFinished())
    }

    @Test func demoAndTestLaunchesNeverAsk() {
        #expect(RatingPrompt.forLaunch == nil)
    }
}
