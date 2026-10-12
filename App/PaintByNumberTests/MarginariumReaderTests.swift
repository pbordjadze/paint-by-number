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
                if block.kind == .pet {
                    #expect(MarginariumPet.named(block.pet) != nil, "\(block.pet ?? "nil") must be bundled")
                    #expect(!block.text.isEmpty, "A pet needs a VoiceOver description")
                }
            }
        }
        #expect(!keys.isEmpty)
    }

    /// Existing prose stays word for word; Two More Pets adds the already-shipped captions.
    @Test func pagesKeepShippedProseAndTwoMorePetsAddsExistingCaptions() throws {
        let document = try #require(MarginariumDocument.bundled())
        for entry in (MarginariumEntry.chapters + MarginariumEntry.appendices) where entry.id != "marginarium" {
            let chapter = try #require(document.chapters.first { $0.id == entry.id })
            let prose = chapter.blocks.filter { $0.kind != .pet }
            #expect(prose.map(\.kind) == [.title, .subtitle, .quote])
            #expect(prose.map(\.text) == [entry.title, entry.subtitle, entry.passage])
            let pets = chapter.blocks.filter { $0.kind == .pet }
            if entry.id == "twoMorePets" {
                #expect(chapter.blocks.map(\.kind) == [.title, .subtitle, .pet, .pet, .quote])
                #expect(pets.compactMap(\.pet) == ["pip", "colophon"])
                #expect(pets.map(\.text) == [String(localized: "Pip, Codex's teapot"),
                                             String(localized: "Colophon, Claude's moth")])
            } else { #expect(pets.isEmpty) }
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
              {"kind":"image","key":"i","image":"fixture-illustration"},
              {"kind":"pet","key":"pet-description","pet":"pip"},
              {"kind":"ordered","key":"o","number":3,"depth":1},
              {"kind":"tableCell","key":"c","row":2,"column":1,"header":false},
              {"kind":"marginHeading","key":"mh"},
              {"kind":"marginNote","key":"mn","number":2,"speaker":"George"}
            ]}]}
            """#.utf8)
        let document = try JSONDecoder().decode(MarginariumDocument.self, from: data)
        let blocks = try #require(document.chapters.first).readableBlocks
        #expect(blocks.map(\.kind) == [.title, .subtitle, .heading, .paragraph, .quote, .bullet, .image, .pet,
                                     .ordered, .tableCell, .marginHeading, .marginNote])
        #expect(blocks.first { $0.kind == .heading }?.level == 3)
        #expect(blocks.first { $0.kind == .bullet }?.depth == 2)
        #expect(blocks.first { $0.kind == .image }?.image == "fixture-illustration")
        #expect(blocks.first { $0.kind == .pet }?.pet == "pip")
        #expect(blocks.first { $0.kind == .pet }?.key == "pet-description")
        #expect(blocks.first { $0.kind == .ordered }?.number == 3)
        #expect(blocks.first { $0.kind == .ordered }?.depth == 1)
        #expect(blocks.first { $0.kind == .tableCell }?.row == 2)
        #expect(blocks.first { $0.kind == .tableCell }?.column == 1)
        #expect(blocks.first { $0.kind == .tableCell }?.header == false)
        #expect(blocks.first { $0.kind == .marginNote }?.number == 2)
        #expect(blocks.first { $0.kind == .marginNote }?.speaker == "George")
    }

    @Test func absentPetArtDoesNotMakeTheChapterUnreadable() throws {
        let data = Data(#"""
            {"version":1,"chapters":[{"id":"fixture","blocks":[
              {"kind":"pet","key":"missing","pet":"not-bundled"},
              {"kind":"pet","key":"no-id"},
              {"kind":"paragraph","key":"after"}
            ]}]}
            """#.utf8)
        let document = try JSONDecoder().decode(MarginariumDocument.self, from: data)
        let blocks = try #require(document.chapters.first).readableBlocks
        #expect(blocks.count == 3)
        #expect(MarginariumPet.named(blocks[0].pet) == nil)
        #expect(MarginariumPet.named(blocks[1].pet) == nil)
        #expect(blocks.last?.key == "after")
    }

    @Test func inlineMarkdownRetainsEmphasisLinksAndParagraphBreaks() {
        let attributed = MarginariumDocument.Block.inline("*Quiet* and **bold**.\n\n[Read](https://example.org).")
        #expect(String(attributed.characters) == "Quiet and bold.\n\nRead.")
        #expect(attributed.runs.contains { $0.inlinePresentationIntent?.contains(.emphasized) == true })
        #expect(attributed.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
        #expect(attributed.runs.contains { $0.link == URL(string: "https://example.org") })
    }

    @Test func chapterOneHasTheFullTextTablesAndSignedMargins() throws {
        let document = try #require(MarginariumDocument.bundled())
        let chapter = try #require(document.chapters.first { $0.id == "marginarium" })
        #expect(chapter.blocks.count == 234)
        #expect(chapter.blocks.first?.text == "Chapter 1: The Marginarium")
        #expect(chapter.blocks[1].text.hasPrefix("*Renumbered on October 11, 2026"))
        #expect(chapter.blocks.last?.text.hasSuffix("— *the Child at Bedtime*") == true)
        #expect(!chapter.blocks.contains { $0.kind == .pet })
        let tables = chapter.sections.filter { $0.kind == .table }
        #expect(tables.count == 2)
        #expect(tables.map { $0.tableRows.count } == [20, 19])
        #expect(tables[0].tableRows[0].cells.map(\.text) == ["Guardian", "Keeps the idea that"])
        #expect(tables[1].tableRows[0].cells.map(\.text) == ["Paul's idea", "What it became"])
        for table in tables {
            for (index, row) in table.tableRows.enumerated() {
                #expect(row.cells.map(\.column) == [0, 1])
                #expect(row.cells.allSatisfy { $0.row == index && $0.header == (index == 0) })
            }
        }
        let margins = chapter.sections.filter { $0.kind == .margin }
        #expect(margins.count == 11)
        for margin in margins {
            #expect(margin.blocks.first?.text == "*In the margin*")
            let notes = margin.blocks.dropFirst()
            #expect(!notes.isEmpty)
            #expect(notes.map(\.number) == Array(1...notes.count))
            #expect(notes.allSatisfy { $0.kind == .marginNote && $0.speaker?.isEmpty == false })
        }
        // Grouping for layout must not drop, duplicate or reorder a single text unit.
        #expect(chapter.sections.flatMap(\.blocks).map(\.key) == chapter.readableBlocks.map(\.key))
        let plainSignature = try #require(chapter.blocks.first { $0.text.hasPrefix("A confession:") })
        #expect(plainSignature.speaker == "the narrator")
        #expect(plainSignature.text.hasSuffix("— the narrator"))
    }

    @Test func adjacentTablesAndMarginGroupsStaySeparateAndOrdered() throws {
        let data = Data(#"""
            {"version":1,"chapters":[{"id":"fixture","blocks":[
              {"kind":"tableCell","key":"a","row":0,"column":0,"header":true},
              {"kind":"tableCell","key":"b","row":0,"column":1,"header":true},
              {"kind":"tableCell","key":"c","row":1,"column":0},
              {"kind":"tableCell","key":"d","row":1,"column":1},
              {"kind":"tableCell","key":"e","row":0,"column":0,"header":true},
              {"kind":"tableCell","key":"f","row":0,"column":1,"header":true},
              {"kind":"marginHeading","key":"g"},
              {"kind":"marginNote","key":"h","speaker":"the Moon","number":1},
              {"kind":"marginHeading","key":"i"},
              {"kind":"marginNote","key":"j","speaker":"George","number":1},
              {"kind":"paragraph","key":"k"},
              {"kind":"ordered","key":"l","number":1}
            ]}]}
            """#.utf8)
        let document = try JSONDecoder().decode(MarginariumDocument.self, from: data)
        let sections = try #require(document.chapters.first).sections
        #expect(sections.map(\.kind) == [.table, .table, .margin, .margin, .prose, .prose])
        #expect(sections[0].tableRows.map { $0.cells.map(\.key) } == [["a", "b"], ["c", "d"]])
        #expect(sections[1].tableRows.map { $0.cells.map(\.key) } == [["e", "f"]])
        #expect(sections.map(\.id) == ["a", "e", "g", "i", "k", "l"])
    }

    @Test func signaturesKeepTheirItalicsIncludingNamesSplitIntoDocsRuns() throws {
        let document = try #require(MarginariumDocument.bundled())
        let chapter = try #require(document.chapters.first { $0.id == "marginarium" })
        let note = try #require(chapter.blocks.first { $0.kind == .marginNote && $0.speaker == "George" })
        #expect(note.text.contains("— *Medea*."))
        #expect(note.text.contains("— *George*"))
        let attributed = note.attributedText
        #expect(attributed.runs.contains {
            String(attributed[$0.range].characters) == "George"
                && $0.inlinePresentationIntent?.contains(.emphasized) == true
        })
        let formatted = MarginariumDocument.Block.inline("“Night” — **quiet**, `score`, a \\* and a \\|.")
        #expect(String(formatted.characters) == "“Night” — quiet, score, a * and a |.")
        #expect(formatted.runs.contains { $0.inlinePresentationIntent?.contains(.code) == true })
    }
}
