import Foundation
import PaintCore
import Testing
@testable import PaintByNumber

@MainActor
struct PreferencesTests {
    @Test func defaultsAndSessionMapping() throws {
        let suite = "PBNTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        var preferences = Preferences(defaults: defaults)
        #expect(preferences.autoAdvance)
        #expect(preferences.colorNames == .playful)

        defaults.set(false, forKey: SettingsKey.autoAdvance)
        defaults.set("plain", forKey: SettingsKey.colorNames)
        preferences = Preferences(defaults: defaults)
        #expect(preferences.colorNames == .plain)
        #expect(!preferences.autoAdvance)
        // The persisted key strings: renaming one would forget every painter's switch.
        #expect(SettingsKey.haptics == "hapticsEnabled" && SettingsKey.sounds == "soundsEnabled")

        let session = PaintingSession(template: Fixtures.stripes())
        #expect(session.autoAdvance && session.colorNameStyle == .playful)
        preferences.apply(to: session)
        #expect(!session.autoAdvance && session.colorNameStyle == .plain)
    }

    /// An unknown stored value is the default, not a crash or a third style.
    @Test func colorNameStyleFallsBackToPlayful() throws {
        let suite = "PBNTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for stored in ["", "shouty", "Playful"] {
            defaults.set(stored, forKey: SettingsKey.colorNames)
            #expect(Preferences(defaults: defaults).colorNames == .playful, "\(stored)")
        }
        defaults.set("playful", forKey: SettingsKey.colorNames)
        #expect(Preferences(defaults: defaults).colorNames == .playful)
        #expect(ColorNameStyle.allCases == [.playful, .plain])
    }

    /// The Paper preference's key and raw values are what `@AppStorage` and launch arguments
    /// (`-paperAppearance dark`) use, and anything else isn't a paper.
    @Test func paperAppearanceKeyAndRawValues() {
        #expect(SettingsKey.paperAppearance == "paperAppearance")
        #expect(Set(PaperAppearance.allCases.map(\.rawValue)) == ["light", "dark", "automatic"])
        #expect(PaperAppearance(rawValue: "sepia") == nil)
    }

    /// Painting Length defaults to Relaxed, round-trips its raw values, ignores anything it
    /// doesn't know, and is what the create flow aims for.
    @Test func paintingLengthDefaultsAndPersists() throws {
        let suite = "PBNTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(Preferences(defaults: defaults).paintingLength == .relaxed)
        #expect(PaintingLength.default == .relaxed)
        for length in PaintingLength.allCases {
            defaults.set(length.rawValue, forKey: SettingsKey.paintingLength)
            #expect(Preferences(defaults: defaults).paintingLength == length)
            #expect(!length.name.isEmpty && !length.footer.isEmpty)
        }
        defaults.set("marathon", forKey: SettingsKey.paintingLength)
        #expect(Preferences(defaults: defaults).paintingLength == .relaxed)
        #expect(SettingsKey.paintingLength == "paintingLength")
        #expect(Set(PaintingLength.allCases.map(\.rawValue)) == ["quick", "relaxed", "detailed"])
        #expect(PaintingLength.relaxed.footer == "Suggested settings aim for about half an hour of painting. Small or simple photos make shorter paintings.")

        #expect(CreateModel(paintingLength: .quick).paintingLength == .quick)
    }
}
