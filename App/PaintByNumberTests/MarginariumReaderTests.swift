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

    /// The contents page quotes each chapter as written: its passage is in the chapter, word for word.
    @Test func everyPassageIsQuotedAsWritten() throws {
        let document = try #require(MarginariumDocument.bundled())
        for entry in MarginariumEntry.chapters + MarginariumEntry.appendices {
            let chapter = try #require(document.chapters.first { $0.id == entry.id })
            #expect(chapter.blocks.contains { $0.text.contains(entry.passage) }, "\(entry.id)'s passage isn't in it")
        }
    }

    /// Existing prose stays word for word; Two More Pets adds the already-shipped captions.
    @Test func pagesKeepShippedProseAndTwoMorePetsAddsExistingCaptions() throws {
        let document = try #require(MarginariumDocument.bundled())
        for entry in (MarginariumEntry.chapters + MarginariumEntry.appendices)
        where !["marginarium", "petsWeMade"].contains(entry.id) {
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

    /// Codex's chapter follows Two More Pets: its full text, a pet for every guardian but the Moon
    /// where the chapter shows it, and Claude's note kept as the quotation it is.
    @Test func chapterSixIsCodexsChapterWithItsPets() throws {
        let document = try #require(MarginariumDocument.bundled())
        #expect(document.chapters.map(\.id).firstIndex(of: "petsWeMade") == 5)
        let chapter = try #require(document.chapters.first { $0.id == "petsWeMade" })
        #expect(chapter.blocks.first?.kind == .title)
        #expect(chapter.blocks.first?.text == "Chapter 6: The Pets We Actually Made")
        #expect(chapter.blocks[1].kind == .subtitle)
        #expect(chapter.blocks[1].text == "Narrated by Codex.")
        #expect(chapter.blocks[2].text.hasPrefix("There are two pets called Dab."))
        let entry = try #require(MarginariumEntry.chapters.first { $0.id == "petsWeMade" })
        #expect(entry.title == "The Pets We Actually Made")
        #expect(entry.subtitle == "Narrated by Codex.")
        #expect(chapter.blocks[2].text.hasPrefix(entry.passage))

        let pets = chapter.blocks.filter { $0.kind == .pet }
        #expect(pets.compactMap(\.pet) == [
            "medea", "bulat-okudzhava", "originality", "snow-queen", "enchanted-workshop", "painter", "scholar",
            "robber-girl", "pirosmani", "emily-dickinson", "open-source-enthusiast", "storybook",
            "child-at-bedtime", "nutcracker", "balanchine", "bible-school-teacher", "baba-yaga", "glassblower",
            "hedge-witch",
        ])
        for pet in pets {
            #expect(MarginariumPet.named(pet.pet) != nil, "\(pet.pet ?? "nil") must be bundled")
            #expect(!pet.text.isEmpty, "A pet needs a VoiceOver description")
        }
        #expect(pets.first { $0.pet == "snow-queen" }?.text == "Hush, the Snow Queen's ermine")
        #expect(pets.first { $0.pet == "pirosmani" }?.text == "Gentle Giraffe, Niko's giraffe")
        #expect(!chapter.blocks.contains { $0.pet == "moon" })
        // Every pet stands in a section of its own, so the reader lays out one player per block.
        #expect(chapter.sections.filter { $0.blocks.first?.kind == .pet }.count == 19)

        let note = try #require(chapter.blocks.first { $0.text.hasPrefix("**A note from Claude, who keeps the record") })
        #expect(note.kind == .quote)
        #expect(note.text.hasSuffix("Codex is away until October 19 and will tell this part in its own words then."))
        let tables = chapter.sections.filter { $0.kind == .table }
        #expect(tables.count == 1)
        #expect(tables.first?.tableRows.first?.cells.map(\.text) == ["Question", "Matching choices"])
        #expect(tables.first?.tableRows.count == 6)
        #expect(chapter.sections.flatMap(\.blocks).map(\.key) == chapter.readableBlocks.map(\.key))
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
        #expect(chapter.blocks.count == 235)
        #expect(chapter.blocks.first?.text == "Chapter 1: The Marginarium")
        // A newcomer meets the contents page's line first; the renumbering note closes the chapter.
        #expect(chapter.blocks[1].kind == .subtitle)
        #expect(chapter.blocks[1].text == MarginariumEntry.chapters[0].subtitle)
        #expect(chapter.blocks.last?.kind == .paragraph)
        #expect(chapter.blocks.last?.text.hasPrefix("*Renumbered on October 11, 2026") == true)
        #expect(chapter.blocks.dropLast().last?.text.hasSuffix("— *the Child at Bedtime*") == true)
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

    /// A margin column sits beside the story it annotates: each margin group joins the sections
    /// since the previous one, and the story after the last group stands alone.
    @Test func spreadsJoinEachMarginGroupToTheStoryBeforeIt() throws {
        let data = Data(#"""
            {"version":1,"chapters":[{"id":"fixture","blocks":[
              {"kind":"heading","key":"a"},
              {"kind":"paragraph","key":"b"},
              {"kind":"marginHeading","key":"c"},
              {"kind":"marginNote","key":"d","speaker":"the Moon","number":1},
              {"kind":"marginHeading","key":"e"},
              {"kind":"marginNote","key":"f","speaker":"George","number":1},
              {"kind":"paragraph","key":"g"},
              {"kind":"tableCell","key":"h","row":0,"column":0,"header":true},
              {"kind":"paragraph","key":"i"}
            ]}]}
            """#.utf8)
        let chapter = try #require(try JSONDecoder().decode(MarginariumDocument.self, from: data).chapters.first)
        let spreads = chapter.spreads
        #expect(spreads.map { $0.story.map(\.id) } == [["a", "b"], [], ["g", "h", "i"]])
        #expect(spreads.map { $0.margin?.id } == ["c", "e", nil])
        #expect(Set(spreads.map(\.id)).count == spreads.count)
        // Nothing is dropped, duplicated or reordered on the way into spreads.
        let keys = spreads.flatMap { ($0.story + [$0.margin].compactMap { $0 }).flatMap(\.blocks) }.map(\.key)
        #expect(keys == chapter.readableBlocks.map(\.key))
    }

    @Test func chapterOneSetsEveryMarginGroupBesideItsStory() throws {
        let document = try #require(MarginariumDocument.bundled())
        let chapter = try #require(document.chapters.first { $0.id == "marginarium" })
        let withMargins = chapter.spreads.filter { $0.margin != nil }
        #expect(withMargins.count == chapter.sections.filter { $0.kind == .margin }.count)
        #expect(withMargins.allSatisfy { !$0.story.isEmpty })
        // Chapter 6's pets stay one lazy row each: it has no margin groups to join them.
        let six = try #require(document.chapters.first { $0.id == "petsWeMade" })
        #expect(six.spreads.allSatisfy { $0.margin == nil })
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
