import Foundation
import PaintCore
import Testing
@testable import PaintByNumber

/// `Localizable.xcstrings` holds every user-facing string. `tools/strings_check.py` keeps it in
/// step with the sources on CI's Linux job; these tests check what the app bundle ships and that
/// the code reads it. They run in English, the catalog's source language.
struct LocalizationTests {
    private typealias Entry = [String: Any]

    private static func catalog(_ name: String) throws -> [String: Entry] {
        let url = Fixtures.repositoryRoot.appending(path: "App/PaintByNumber/Resources/\(name).xcstrings")
        let root = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        #expect(root["sourceLanguage"] as? String == "en")
        return try #require(root["strings"] as? [String: Entry])
    }

    private static func english(_ entry: Entry) -> Entry? {
        (entry["localizations"] as? [String: Any])?["en"] as? Entry
    }

    private static func value(of unit: Entry?) -> String? {
        (unit?["stringUnit"] as? Entry)?["value"] as? String
    }

    private static let missing = "\u{1}not in the bundle\u{1}"

    /// Every explicit key (dotted, with an English value) is in the shipped bundle with exactly
    /// the catalog's English text: the catalog is compiled into the app and the table is found.
    @Test func explicitKeysResolveToTheCatalogsEnglish() throws {
        var checked = 0
        for (key, entry) in try Self.catalog("Localizable") {
            guard let text = Self.value(of: Self.english(entry)) else { continue }
            let resolved = Bundle.main.localizedString(forKey: key, value: Self.missing, table: nil)
            #expect(resolved == text, "\(key) resolved to \(resolved)")
            checked += 1
        }
        #expect(checked > 100, "Only \(checked) explicit keys found")
    }

    @Test func keysTheCodeUsesResolve() {
        #expect(PaintSpeech.canvasLabel == "Painting")
        #expect(PaintSpeech.areaLabel(number: 12) == "Area 12")
        #expect(PaintSpeech.percentPainted(30) == "30 percent painted")
        #expect(PaintSpeech.paintingProgress(title: "Irises", percent: 30) == "Irises, 30 percent painted")
        #expect(ArtworkExporter.templateName(title: "Irises") == "Irises Template")
        #expect(ArtworkExporter.timelapseName(title: "Irises") == "Irises Time-lapse")
        // A library picture's title is its `sample.<id>` (each against its record: `SampleLibraryTests`).
        #expect(Sample.named("great-wave")?.title == "The Great Wave")
        let hokusai = Sample.Provenance(kind: .painting, creator: "Katsushika Hokusai", year: "c. 1830–32", credit: "", license: "")
        #expect(Acknowledgements.byline(hokusai) == "Katsushika Hokusai, c. 1830–32")
        #expect(PaintSpeech.colorLabel(
            number: 12, name: ColorName(family: .blue, lightness: .dark, chroma: .grayish), nickname: "Harbor Fog")
                == "12, Harbor Fog, dark grayish blue")
    }

    /// The nickname label resolves through the catalog, and a locale that isn't English shows the
    /// structured name: no nickname reaches the label.
    @Test func nonEnglishLocalesShowTheStructuredName() throws {
        let palette = [PaletteColor(oklab: SIMD3(0.5, -0.03, -0.03), space: .sRGB)]
        let name = palette[0].colorName
        let german = try #require(ColorNameText.nicknames(for: palette, seed: 1, languageCode: "de").first)
        #expect(german == nil)
        #expect(PaintSpeech.colorLabel(number: 3, name: name, nickname: german) == "3, \(name.english)")
        #expect(ColorNameText.numbered(number: 3, name: name, nickname: german) == "3 · \(name.englishTitle)")
        let english = try #require(ColorNameText.nicknames(for: palette, seed: 1, languageCode: "en").first)
        #expect(english != nil)
        #expect(ColorNameText.numbered(number: 3, name: name, nickname: english) == "3 · \(english!)")
    }

    /// Catalog plurals, not hand-built suffixes: one and other differ, and each reads right.
    @Test func countsUsePluralForms() {
        #expect(TemplateCounts.colors(1) == "1 color")
        #expect(TemplateCounts.colors(2) == "2 colors")
        #expect(TemplateCounts.areas(1) == "1 area")
        #expect(TemplateCounts.areas(2) == "2 areas")
        #expect(TemplateCounts.areas(24) == "24 areas")
    }

    @Test func pluralKeysYieldDifferentStringsForOneAndTwo() {
        func sheets(_ count: Int) -> String {
            String(localized: "pdf.sheets", defaultValue: "\(count) sheets", comment: "")
        }
        func inProgress(_ count: Int) -> String {
            String(localized: "gallery.subtitle.inProgress", defaultValue: "\(count) paintings in progress", comment: "")
        }
        func finished(_ count: Int) -> String {
            String(localized: "gallery.subtitle.finished", defaultValue: "\(count) finished paintings", comment: "")
        }
        func notStarted(_ count: Int) -> String {
            String(localized: "gallery.card.spoken.notStarted", defaultValue: "Not started, \(count) colors", comment: "")
        }
        #expect(sheets(1) == "1 sheet" && sheets(2) == "2 sheets")
        #expect(inProgress(1) == "1 painting in progress" && inProgress(2) == "2 paintings in progress")
        #expect(finished(1) == "1 finished painting" && finished(2) == "2 finished paintings")
        #expect(notStarted(1) == "Not started, 1 color" && notStarted(2) == "Not started, 2 colors")
    }

    /// Every plural entry of the catalog is a real plural: `%lld` in the forms English needs.
    @Test func pluralEntriesCarryTheirCount() throws {
        var plurals = 0
        for (key, entry) in try Self.catalog("Localizable") {
            guard let forms = ((Self.english(entry)?["variations"] as? Entry)?["plural"] as? [String: Entry]) else { continue }
            plurals += 1
            #expect(forms["one"] != nil && forms["other"] != nil, "\(key) needs one and other")
            for (category, form) in forms {
                #expect(Self.value(of: form)?.contains("%lld") == true, "\(key) \(category) has no %lld")
            }
        }
        #expect(plurals >= 10, "Only \(plurals) plural entries found")
    }

    @Test func durationsAreAssembledFromCatalogUnits() {
        #expect(PaintingTimeText.spent(14 * 60) == "14 min")
        #expect(PaintingTimeText.spent(2 * 3600) == "2 h")
        #expect(PaintingTimeText.spent(134 * 60) == "2 h 14 min")
        #expect(PaintingTimeText.approximate(90 * 60) == "~1.5 h")
    }

    @Test func formatsDurations() {
        #expect(PaintingTimeText.approximate(10 * 60) == "~10 min")
        #expect(PaintingTimeText.approximate(2 * 3600) == "~2 h")
        #expect(PaintingTimeText.approximate(1.4 * 3600) == "~1.5 h")
        #expect(PaintingTimeText.approximate(30 * 3600) == "~30 h")
        #expect(PaintingTimeText.spent(125 * 60) == "2 h 5 min")
        #expect(PaintingTimeText.spent(20) == "< 1 min")
    }

    @Test func errorsDescribeThemselvesInWords() throws {
        let errors: [any LocalizedError] = [
            CreateModel.CreateError.unreadable, CreateModel.CreateError.renderFailed,
            CreateModel.CreateError.cameraCapture, ArtworkExporter.ExportError.renderFailed,
            ArtworkExporter.ExportError.timelapseFailed,
        ]
        for error in errors {
            let text = try #require(error.errorDescription)
            // Prose, not a catalog key that failed to resolve.
            #expect(text.contains(" ") && !text.hasPrefix("create.") && !text.hasPrefix("export."), "\(text)")
            #expect(error.localizedDescription == text)
        }
    }

    /// The names the system shows (Home Screen, permission alerts, the share sheet's document
    /// type) come from `InfoPlist.xcstrings`, which must agree with the build settings and the
    /// document types that fill Info.plist. A document type is localized under its own English name.
    @Test func infoPlistCatalogMatchesTheBundle() throws {
        let strings = try Self.catalog("InfoPlist")
        #expect(Set(strings.keys) == ["CFBundleDisplayName", "Image", "NSCameraUsageDescription", "NSPhotoLibraryAddUsageDescription"])
        let documentTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String: Any]] ?? []
        let typeNames = Set(documentTypes.compactMap { $0["CFBundleTypeName"] as? String })
        #expect(typeNames == ["Image"])
        for (key, entry) in strings {
            let bundled = typeNames.contains(key) ? key : Bundle.main.object(forInfoDictionaryKey: key) as? String
            #expect(bundled == Self.value(of: Self.english(entry)), "\(key): \(bundled ?? "nil")")
        }
    }
}
