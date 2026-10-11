import Foundation
import Testing
import UIKit
@testable import PaintByNumber

/// The imported chapter blocks, runtime localization and forward-compatible reader decoding.
@MainActor
struct MarginariumReaderTests {
    @Test func everyManifestKeyExistsInTheCatalogAndBundle() throws {
        let document = try #require(MarginariumDocument.bundled(), "marginarium.json must ship and decode")
        let url = Fixtures.repositoryRoot.appending(path: "App/PaintByNumber/Resources/Localizable.xcstrings")
        let catalog = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let strings = try #require(catalog["strings"] as? [String: [String: Any]])
        let entries = MarginariumEntry.chapters + MarginariumEntry.appendices
        #expect(document.chapters.map(\.id) == entries.map(\.id))
        var keys = Set<String>()
        for chapter in document.chapters {
            #expect(chapter.readableBlocks.count == chapter.blocks.count)
            for block in chapter.blocks {
                #expect(keys.insert(block.key).inserted, "Repeated block key: \(block.key)")
                let entry = try #require(strings[block.key], "Missing catalog key: \(block.key)")
                #expect(entry["extractionState"] as? String == "manual")
                let localizations = try #require(entry["localizations"] as? [String: [String: Any]])
                let unit = try #require(localizations["en"]?["stringUnit"] as? [String: String])
                let english = try #require(unit["value"])
                #expect(block.text == english, "\(block.key) doesn't resolve through the bundled catalog")
                if let image = block.image {
                    #expect(UIImage(named: image) != nil, "\(image) must be bundled")
                    #expect(!block.text.isEmpty, "An illustration needs a VoiceOver description")
                }
            }
        }
        #expect(!keys.isEmpty)
    }

    /// Until the chapters are approved, the import must introduce no new prose, including
    /// the two-paragraph passage. This expectation changes only with approved content.
    @Test func initialPagesContainOnlyTheShippedTitleSubtitleAndPassage() throws {
        let document = try #require(MarginariumDocument.bundled())
        for entry in MarginariumEntry.chapters + MarginariumEntry.appendices {
            let chapter = try #require(document.chapters.first { $0.id == entry.id })
            #expect(chapter.blocks.map(\.kind) == [.title, .subtitle, .quote])
            #expect(chapter.blocks.map(\.text) == [entry.title, entry.subtitle, entry.passage])
        }
    }

    @Test func unknownKindIsSkippedWithoutDecodingItsPayload() throws {
        let data = Data(#"""
            {"version":1,"chapters":[{"id":"fixture","blocks":[
              {"kind":"paragraph","key":"before"},
              {"kind":"futureInteractiveBlock","key":["not a string"],"level":{},"payload":[1,2,3]},
              {"kind":"quote","key":"after"}
            ]}]}
            """#.utf8)
        let document = try JSONDecoder().decode(MarginariumDocument.self, from: data)
        let chapter = try #require(document.chapters.first)
        #expect(chapter.blocks.count == 3)
        #expect(chapter.readableBlocks.map(\.key) == ["before", "after"])
        #expect(chapter.readableBlocks.map(\.kind) == [.paragraph, .quote])
    }

    @Test func allBlockKindsDecodeTheirRenderingMetadata() throws {
        let data = Data(#"""
            {"version":1,"chapters":[{"id":"fixture","blocks":[
              {"kind":"title","key":"t"}, {"kind":"subtitle","key":"s"},
              {"kind":"heading","key":"h","level":3}, {"kind":"paragraph","key":"p"},
              {"kind":"quote","key":"q"}, {"kind":"bullet","key":"b","depth":2},
              {"kind":"image","key":"i","image":"fixture-illustration"}
            ]}]}
            """#.utf8)
        let document = try JSONDecoder().decode(MarginariumDocument.self, from: data)
        let blocks = try #require(document.chapters.first).readableBlocks
        #expect(blocks.map(\.kind) == [.title, .subtitle, .heading, .paragraph, .quote, .bullet, .image])
        #expect(blocks.first { $0.kind == .heading }?.level == 3)
        #expect(blocks.first { $0.kind == .bullet }?.depth == 2)
        #expect(blocks.first { $0.kind == .image }?.image == "fixture-illustration")
    }

    @Test func inlineMarkdownRetainsEmphasisLinksAndParagraphBreaks() {
        let attributed = MarginariumDocument.Block.inline("*Quiet* and **bold**.\n\n[Read](https://example.org).")
        #expect(String(attributed.characters) == "Quiet and bold.\n\nRead.")
        #expect(attributed.runs.contains { $0.inlinePresentationIntent?.contains(.emphasized) == true })
        #expect(attributed.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
        #expect(attributed.runs.contains { $0.link == URL(string: "https://example.org") })
    }
}
