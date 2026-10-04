import Foundation
import Testing
@testable import PaintByNumber

/// The repository checkout the tests were built from (tests run on the build machine's
/// simulator, which sees the host's files).
private let repositoryRoot = URL(filePath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

struct PrivacyManifestTests {
    private static func manifest() throws -> [String: Any] {
        let url = try #require(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        return try #require(plist as? [String: Any])
    }

    /// Category → reason codes as declared in the manifest.
    private static func declaredAPIs() throws -> [String: [String]] {
        let entries = try #require(manifest()["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        return Dictionary(uniqueKeysWithValues: entries.compactMap { entry -> (String, [String])? in
            guard let category = entry["NSPrivacyAccessedAPIType"] as? String else { return nil }
            return (category, entry["NSPrivacyAccessedAPITypeReasons"] as? [String] ?? [])
        })
    }

    @Test func manifestShipsInTheBundleAndDeclaresNoTrackingOrCollection() throws {
        let manifest = try Self.manifest()
        #expect(manifest["NSPrivacyTracking"] as? Bool == false)
        #expect((manifest["NSPrivacyTrackingDomains"] as? [String])?.isEmpty == true)
        #expect((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty == true)
    }

    @Test func userDefaultsIsDeclaredForTheAppsOwnPreferences() throws {
        #expect(try Self.declaredAPIs()["NSPrivacyAccessedAPICategoryUserDefaults"] == ["CA92.1"])
    }

    /// Apple's required-reason APIs: a category must be declared exactly when the app's
    /// sources (the app's and PaintCore's) use one of its APIs, so the manifest neither misses a use nor claims one.
    @Test func manifestDeclaresExactlyTheRequiredReasonAPIsTheSourcesUse() throws {
        struct RequiredReasonAPI {
            let category: String
            let symbols: [String]
        }
        let apis = [
            RequiredReasonAPI(category: "NSPrivacyAccessedAPICategoryUserDefaults", symbols: ["UserDefaults", "AppStorage"]),
            RequiredReasonAPI(category: "NSPrivacyAccessedAPICategoryFileTimestamp", symbols: [
                "contentModificationDateKey", "creationDateKey", "contentAccessDateKey", "fileModificationDate",
                "fileCreationDate", ".modificationDate", ".creationDate", "st_mtime", "st_ctime", "st_birthtime", "fstat(", " stat(",
            ]),
            RequiredReasonAPI(category: "NSPrivacyAccessedAPICategoryDiskSpace", symbols: [
                "volumeAvailableCapacity", "volumeTotalCapacity", "systemFreeSize", "systemSize", "NSFileSystemFreeSize",
                "NSFileSystemSize", "statfs", "statvfs", "getattrlist",
            ]),
            RequiredReasonAPI(category: "NSPrivacyAccessedAPICategorySystemBootTime", symbols: ["systemUptime", "mach_absolute_time"]),
            RequiredReasonAPI(category: "NSPrivacyAccessedAPICategoryActiveKeyboards", symbols: ["activeInputModes"]),
        ]
        // PaintCore is linked into the app, so its sources answer to the same manifest
        // (Sources/pbn is a separate command-line tool and is not part of the app).
        var text = ""
        for directory in ["App/PaintByNumber", "Sources/PaintCore"] {
            let root = repositoryRoot.appending(path: directory, directoryHint: .isDirectory)
            let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
            var found = false
            for case let url as URL in enumerator where url.pathExtension == "swift" {
                text += try String(contentsOf: url, encoding: .utf8)
                found = true
            }
            #expect(found, "No sources found at \(root.path)")
        }

        let used = Set(apis.filter { api in api.symbols.contains(where: { text.contains($0) }) }.map { $0.category })
        let declaredAPIs = try Self.declaredAPIs()
        let declared = Set(declaredAPIs.keys)
        #expect(declared == used, "PrivacyInfo.xcprivacy declares \(declared.sorted()) but the sources use \(used.sorted())")
        #expect(declaredAPIs.values.allSatisfy({ !$0.isEmpty }), "Every declared API needs an approved reason code")
    }
}

struct BundleMetadataTests {
    private let info = Bundle.main.infoDictionary ?? [:]

    @Test func exportComplianceAndCategoryAreDeclared() {
        #expect(info["ITSAppUsesNonExemptEncryption"] as? Bool == false)
        #expect(info["LSApplicationCategoryType"] as? String == "public.app-category.entertainment")
    }

    @Test func usageDescriptionsExplainWhyAndCoverOnlyWhatTheAppAsksFor() {
        for key in ["NSCameraUsageDescription", "NSPhotoLibraryAddUsageDescription"] {
            let text = info[key] as? String ?? ""
            #expect(text.hasPrefix("Paint by Moonlight ") && text.hasSuffix("."), "\(key): \(text)")
        }
        // Photos are picked out of process and only added to (never read from) the library.
        #expect(info["NSPhotoLibraryUsageDescription"] == nil)
    }
}

/// "Open in Paint by Moonlight": the app declares itself an alternate viewer of images; files are
/// copied into its inbox (`IncomingFile`), not opened in place.
struct DocumentTypeTests {
    private let info = Bundle.main.infoDictionary ?? [:]

    @Test func appOpensImagesAsAnAlternateViewerOnACopy() throws {
        let types = try #require(info["CFBundleDocumentTypes"] as? [[String: Any]])
        let image = try #require(types.first)
        #expect(types.count == 1)
        #expect(image["CFBundleTypeName"] as? String == "Image")
        #expect(image["CFBundleTypeRole"] as? String == "Viewer")
        #expect(image["LSHandlerRank"] as? String == "Alternate")
        #expect(image["LSItemContentTypes"] as? [String] == ["public.image"])
        #expect(info["LSSupportsOpeningDocumentsInPlace"] as? Bool == false)
        #expect(info["UISupportsDocumentBrowser"] == nil)
    }
}

struct AppInfoTests {
    @Test func readsVersionAndBuildFromTheInfoDictionary() {
        let info = AppInfo(infoDictionary: ["CFBundleShortVersionString": "1.0.42", "CFBundleVersion": "42"])
        #expect(info.version == "1.0.42")
        #expect(info.build == "42")
        #expect(info.summary == "1.0.42 (42)")
    }

    @Test func missingKeysReadAsQuestionMarks() {
        #expect(AppInfo(infoDictionary: [:]).summary == "? (?)")
    }

    @Test func theAppBundleHasANumericVersionAndBuild() {
        let info = AppInfo()
        #expect(info.version.range(of: #"^\d+(\.\d+)*$"#, options: .regularExpression) != nil, "version \(info.version)")
        #expect(info.build.range(of: #"^\d+$"#, options: .regularExpression) != nil, "build \(info.build)")
    }
}

struct AcknowledgementsTests {
    private static let all = Acknowledgements.code + Acknowledgements.models + Acknowledgements.methods

    @Test func portedCodeIsCreditedWithItsLicense() throws {
        #expect(Acknowledgements.code.map(\.name) == ["Earcut", "Polylabel"])
        #expect(Acknowledgements.code.allSatisfy { $0.license == .isc && $0.copyright?.contains("Mapbox") == true })
        // The curve fitter implements Selinger's paper and contains no potrace code: a method.
        let potrace = try #require(Acknowledgements.methods.first { $0.name == "Potrace" })
        #expect(potrace.credit.contains("Peter Selinger") && potrace.credit.contains("2003"))
        #expect(Acknowledgements.code.allSatisfy { $0.license != nil && $0.copyright != nil })
        #expect(Acknowledgements.methods.allSatisfy { $0.copyright == nil && $0.license == nil })
    }

    @Test func licenseTextsAreTheCompleteLicenses() {
        #expect(License.isc.text.hasPrefix("Permission to use, copy, modify, and/or distribute"))
        #expect(License.isc.text.contains("THE SOFTWARE IS PROVIDED \"AS IS\""))
        #expect(License.apache2.text.hasPrefix("TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION"))
        for section in 1...9 { #expect(License.apache2.text.contains("\n\n\(section). "), "Apache 2.0 section \(section)") }
        #expect(License.apache2.text.hasSuffix("END OF TERMS AND CONDITIONS"))
        #expect(License.mit.text.hasPrefix("Permission is hereby granted, free of charge"))
        #expect(License.mit.text.contains("THE SOFTWARE IS PROVIDED \"AS IS\""))
    }

    /// The bundled HED model: ControlNet's Apache-2.0 weights, credited with their license, and
    /// the method (Xie & Tu) among the methods. The conversion script records the weights'
    /// origin and checksum, and the model itself is in the bundle.
    @Test func bundledModelsAreCreditedWithTheirLicense() throws {
        #expect(Acknowledgements.models.map(\.name) == ["ControlNet HED", "Informative Drawings"])
        let hed = try #require(Acknowledgements.models.first)
        #expect(hed.license == .apache2 && hed.credit.contains("lllyasviel") && hed.credit.contains("ControlNetHED.pth"))
        let method = try #require(Acknowledgements.methods.first { $0.name == "Holistically-nested edge detection" })
        #expect(method.credit.contains("Saining Xie and Zhuowen Tu") && method.credit.contains("2015"))
        let script = try String(contentsOf: repositoryRoot.appending(path: "tools/models/convert_hed.py"), encoding: .utf8)
        #expect(script.contains("lllyasviel/Annotators") && script.contains("Apache") && script.contains("SOURCE_SHA256 = \""))
        #expect(Bundle.main.url(forResource: "HED", withExtension: "mlmodelc") != nil, "HED.mlmodelc isn't in the app bundle")
        // The line-drawing model: Informative Drawings' MIT-licensed weights, its method among the methods.
        let drawing = try #require(Acknowledgements.models.last)
        #expect(drawing.license == .mit && drawing.credit.contains("Caroline Chan") && drawing.credit.contains("sk_model.pth"))
        let drawingMethod = try #require(Acknowledgements.methods.first { $0.name == "Informative drawings" })
        #expect(drawingMethod.credit.contains("Chan") && drawingMethod.credit.contains("2022"))
        let lineScript = try String(contentsOf: repositoryRoot.appending(path: "tools/models/convert_lineart.py"), encoding: .utf8)
        #expect(lineScript.contains("lllyasviel/Annotators") && lineScript.contains("MIT") && lineScript.contains("SOURCE_SHA256 = \""))
        #expect(Bundle.main.url(forResource: "LineArt", withExtension: "mlmodelc") != nil, "LineArt.mlmodelc isn't in the app bundle")
    }

    @Test func entriesAreCompleteAndUnique() {
        #expect(Set(Self.all.map(\.id)).count == Self.all.count)
        for item in Self.all {
            #expect(!item.credit.isEmpty && !item.usage.isEmpty, "\(item.name) needs a credit and a usage")
        }
    }

    /// The ported sources still name the projects they come from and the licenses they are under.
    @Test func portedSourcesCiteTheirOrigin() throws {
        let vector = repositoryRoot.appending(path: "Sources/PaintCore/Vector", directoryHint: .isDirectory)
        let earcut = try String(contentsOf: vector.appending(path: "Earcut.swift"), encoding: .utf8)
        let polylabel = try String(contentsOf: vector.appending(path: "PolyLabel.swift"), encoding: .utf8)
        let curveFitter = try String(contentsOf: vector.appending(path: "CurveFitter.swift"), encoding: .utf8)
        #expect(earcut.contains("mapbox/earcut") && earcut.contains("ISC"))
        #expect(polylabel.contains("mapbox/polylabel") && polylabel.contains("ISC"))
        #expect(curveFitter.contains("Selinger") && curveFitter.contains("polygon-based tracing algorithm") && !curveFitter.contains("GPL"))
    }

    /// Every picture the Samples pane offers is credited, in Settings (`Sample.all` with its
    /// `library.json` record) and in `ACKNOWLEDGEMENTS.md`'s Pictures section: the same pictures
    /// in the same order, each with its creator, year, credit and license. The retired samples,
    /// whose provenance was never recorded, are in neither.
    @Test func picturesAreCreditedInTheAppAndTheFile() throws {
        #expect(!Sample.all.isEmpty)
        let text = try String(contentsOf: repositoryRoot.appending(path: "ACKNOWLEDGEMENTS.md"), encoding: .utf8)
        let section = try #require(
            text.components(separatedBy: "\n## Pictures\n").dropFirst().first?.components(separatedBy: "\n## ").first,
            "ACKNOWLEDGEMENTS.md has no Pictures section")
        // The section's pictures: a "### <title>" heading each, with its lines up to the next.
        let entries = Array(section.components(separatedBy: "\n### ").dropFirst())
        let titles = entries.map { entry in String(entry.prefix { $0 != "\n" }) }
        #expect(titles == Sample.all.map(\.title), "ACKNOWLEDGEMENTS.md credits \(titles)")
        for (sample, entry) in zip(Sample.all, entries) {
            let provenance = try #require(sample.provenance, "\(sample.id) has no credit")
            for field in [provenance.creator, provenance.year, provenance.credit, provenance.license] {
                #expect(!field.trimmingCharacters(in: .whitespaces).isEmpty, "\(sample.id) has an empty credit field")
            }
            for line in [Acknowledgements.byline(provenance), provenance.credit, provenance.license] {
                #expect(entry.contains("\n\(line)\n"), "ACKNOWLEDGEMENTS.md's \(sample.title) is missing: \(line)")
            }
        }
        #expect(Sample.retired.allSatisfy { $0.provenance == nil && !Sample.all.contains($0) })
    }

    /// `ACKNOWLEDGEMENTS.md` at the repository root repeats what Settings shows.
    @Test func acknowledgementsFileMatchesTheApp() throws {
        let text = try String(contentsOf: repositoryRoot.appending(path: "ACKNOWLEDGEMENTS.md"), encoding: .utf8)
        for item in Self.all {
            for part in [item.name, item.credit, item.usage] + [item.copyright].compactMap({ $0 }) {
                #expect(text.contains(part), "ACKNOWLEDGEMENTS.md is missing: \(part)")
            }
        }
        for license in License.allCases {
            #expect(text.contains(license.name), "ACKNOWLEDGEMENTS.md is missing the \(license.name) heading")
            #expect(text.contains(license.text), "ACKNOWLEDGEMENTS.md is missing the \(license.name) text")
        }
    }
}
