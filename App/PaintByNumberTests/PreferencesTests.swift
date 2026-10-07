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

        defaults.set(false, forKey: SettingsKey.autoAdvance)
        preferences = Preferences(defaults: defaults)
        #expect(!preferences.autoAdvance)
        // The persisted key strings: renaming one would forget every painter's switch.
        #expect(SettingsKey.haptics == "hapticsEnabled" && SettingsKey.sounds == "soundsEnabled")

        let session = PaintingSession(template: Fixtures.stripes())
        #expect(session.autoAdvance)
        preferences.apply(to: session)
        #expect(!session.autoAdvance)
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

    /// Line Weight defaults to Regular, ignores anything it doesn't know, and steps a book's
    /// line evenly lighter and heavier.
    @Test func lineWeightDefaultsAndPersists() throws {
        let suite = "PBNTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(LineWeight.stored(in: defaults) == .regular && LineWeight.default == .regular)
        for weight in LineWeight.allCases {
            defaults.set(weight.rawValue, forKey: SettingsKey.lineWeight)
            #expect(LineWeight.stored(in: defaults) == weight)
            #expect(!weight.name.isEmpty)
        }
        defaults.set("heavy", forKey: SettingsKey.lineWeight)
        #expect(LineWeight.stored(in: defaults) == .regular)
        #expect(SettingsKey.lineWeight == "lineWeight")
        #expect(Set(LineWeight.allCases.map(\.rawValue)) == ["fine", "regular", "bold"])
        #expect(LineWeight.regular.factor == 1)
        #expect(abs(log2(LineWeight.fine.factor) + log2(LineWeight.bold.factor)) < 0.05)
        // Nearest on a log scale, whatever the factor.
        #expect(LineWeight.nearest(to: 0.5) == .fine && LineWeight.nearest(to: 0.9) == .regular)
        #expect(LineWeight.nearest(to: 1.25) == .bold && LineWeight.nearest(to: 2) == .bold)
        #expect(LineWeight.nearest(to: 0) == .regular && LineWeight.nearest(to: .nan) == .regular)
    }

    /// Settings › Preview defaults to Painting, ignores anything it doesn't know, and is what the
    /// create flow's comparison shows.
    @Test func previewStyleDefaultsAndPersists() throws {
        let suite = "PBNTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(Preferences(defaults: defaults).previewStyle == .painting && PreviewStyle.default == .painting)
        for style in PreviewStyle.allCases {
            defaults.set(style.rawValue, forKey: SettingsKey.previewStyle)
            #expect(Preferences(defaults: defaults).previewStyle == style)
            #expect(!style.name.isEmpty)
        }
        defaults.set("sketch", forKey: SettingsKey.previewStyle)
        #expect(PreviewStyle.stored(in: defaults) == .painting)
        // What `@AppStorage` and launch arguments (`-previewStyle lineArt`) use.
        #expect(SettingsKey.previewStyle == "previewStyle")
        #expect(Set(PreviewStyle.allCases.map(\.rawValue)) == ["painting", "lineArt"])
        #expect(CreateModel(previewStyle: .lineArt).previewStyle == .lineArt)
    }

    /// Settings › Advanced's stored settings are removed at launch, so nothing unseen shapes new
    /// paintings; its Line Weight carries over unless Settings › Line Weight already has one.
    @Test func retiredSettingsAreRemoved() throws {
        let suite = "PBNTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        for key in Preferences.retiredKeys { defaults.set(Data("{}".utf8), forKey: key) }
        defaults.set(false, forKey: "paintingEffect.colorJingle")
        defaults.set("plain", forKey: "colorNameStyle")
        defaults.set("custom", forKey: SettingsKey.paletteOrder)
        defaults.set([2, 0, 1], forKey: Preferences.retiredCustomOrderPrefix + "42")
        defaults.set(PaletteRows.four.rawValue, forKey: SettingsKey.paletteRows)
        defaults.set(Data(#"{"coloringBookWeight": 1.6, "weighted": true}"#.utf8), forKey: "advancedLineAppearance")
        defaults.set(true, forKey: SettingsKey.haptics)
        Preferences.removeRetiredSettings(in: defaults)
        #expect(Preferences.retiredKeys.allSatisfy { defaults.object(forKey: $0) == nil })
        #expect(Preferences.retiredKeys.contains("advancedLineArt") && Preferences.retiredKeys.contains("paintingEffect.finishShine"))
        #expect(LineWeight.stored(in: defaults) == .bold)
        #expect(defaults.object(forKey: SettingsKey.haptics) as? Bool == true, "A current setting went too")
        #expect(Preferences.retiredKeys.contains("printPaperSize") && Preferences.retiredKeys.contains("colorNameStyle"))
        // The Custom palette order goes with every painting's arrangement; the rows stay.
        #expect(defaults.object(forKey: SettingsKey.paletteOrder) == nil)
        #expect(defaults.object(forKey: Preferences.retiredCustomOrderPrefix + "42") == nil)
        #expect(defaults.integer(forKey: SettingsKey.paletteRows) == PaletteRows.four.rawValue)
        defaults.set(PaletteOrder.rainbow.rawValue, forKey: SettingsKey.paletteOrder)
        Preferences.removeRetiredSettings(in: defaults)
        #expect(defaults.string(forKey: SettingsKey.paletteOrder) == "rainbow", "A current palette order went too")

        // A weight already chosen stays; a designed weight, or none, writes nothing.
        defaults.set(Data(#"{"coloringBookWeight": 0.5}"#.utf8), forKey: "advancedLineAppearance")
        Preferences.removeRetiredSettings(in: defaults)
        #expect(LineWeight.stored(in: defaults) == .bold)
        defaults.removeObject(forKey: SettingsKey.lineWeight)
        defaults.set(Data(#"{"coloringBookWeight": 1}"#.utf8), forKey: "advancedLineAppearance")
        Preferences.removeRetiredSettings(in: defaults)
        #expect(defaults.object(forKey: SettingsKey.lineWeight) == nil)
        defaults.set(Data("not json".utf8), forKey: "advancedLineAppearance")
        Preferences.removeRetiredSettings(in: defaults)
        #expect(defaults.object(forKey: SettingsKey.lineWeight) == nil && defaults.object(forKey: "advancedLineAppearance") == nil)
    }
}
