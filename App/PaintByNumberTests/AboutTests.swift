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
    /// sources use one of its APIs, so the manifest neither misses a use nor claims one.
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
        let sourcesRoot = repositoryRoot.appending(path: "App/PaintByNumber", directoryHint: .isDirectory)
        let enumerator = try #require(FileManager.default.enumerator(at: sourcesRoot, includingPropertiesForKeys: nil))
        var text = ""
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            text += try String(contentsOf: url, encoding: .utf8)
        }
        #expect(!text.isEmpty, "No sources found at \(sourcesRoot.path)")

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
            #expect(text.hasPrefix("Paint by Numbers ") && text.hasSuffix("."), "\(key): \(text)")
        }
        // Photos are picked out of process and only added to (never read from) the library.
        #expect(info["NSPhotoLibraryUsageDescription"] == nil)
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
    private static let all = Acknowledgements.code + Acknowledgements.methods

    @Test func portedCodeIsCreditedToMapboxUnderISC() {
        #expect(Acknowledgements.code.map(\.name) == ["Earcut", "Polylabel"])
        #expect(Acknowledgements.code.allSatisfy { $0.copyright?.contains("Mapbox") == true })
        #expect(Acknowledgements.methods.allSatisfy { $0.copyright == nil })
        #expect(Acknowledgements.iscLicense.hasPrefix("Permission to use, copy, modify, and/or distribute"))
    }

    @Test func entriesAreCompleteAndUnique() {
        #expect(Set(Self.all.map(\.id)).count == Self.all.count)
        for item in Self.all {
            #expect(!item.credit.isEmpty && !item.usage.isEmpty, "\(item.name) needs a credit and a usage")
        }
    }

    /// The ported sources still name the projects they come from.
    @Test func portedSourcesCiteTheirOrigin() throws {
        let vector = repositoryRoot.appending(path: "Sources/PaintCore/Vector", directoryHint: .isDirectory)
        let earcut = try String(contentsOf: vector.appending(path: "Earcut.swift"), encoding: .utf8)
        let polylabel = try String(contentsOf: vector.appending(path: "PolyLabel.swift"), encoding: .utf8)
        #expect(earcut.contains("mapbox/earcut") && earcut.contains("ISC"))
        #expect(polylabel.contains("mapbox/polylabel") && polylabel.contains("ISC"))
    }

    /// `ACKNOWLEDGEMENTS.md` at the repository root repeats what Settings shows.
    @Test func acknowledgementsFileMatchesTheApp() throws {
        let text = try String(contentsOf: repositoryRoot.appending(path: "ACKNOWLEDGEMENTS.md"), encoding: .utf8)
        for item in Self.all {
            for part in [item.name, item.credit, item.usage] + [item.copyright].compactMap({ $0 }) {
                #expect(text.contains(part), "ACKNOWLEDGEMENTS.md is missing: \(part)")
            }
        }
        #expect(text.contains(Acknowledgements.iscLicense), "ACKNOWLEDGEMENTS.md is missing the ISC license text")
    }
}
