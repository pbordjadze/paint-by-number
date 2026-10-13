import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import PaintByNumber

/// Margin notes point at the words they are about: every note of Chapter 1 finds its words,
/// shared words make one highlight with every voice, and the highlights' links open the right notes.
@MainActor
struct MarginariumAnnotationsTests {
    private func chapterOne() throws -> MarginariumDocument.Chapter {
        let document = try #require(MarginariumDocument.bundled())
        return try #require(document.chapters.first { $0.id == "marginarium" })
    }

    private func key(_ prefix: String, in chapter: MarginariumDocument.Chapter) throws -> String {
        try #require(chapter.blocks.first { $0.key.hasPrefix("marginarium.marginarium.block.\(prefix)") }).key
    }

    @Test func everyNoteOfChapterOneFindsItsWords() throws {
        let chapter = try chapterOne()
        let annotations = MarginariumAnnotations(chapter: chapter)
        let notes = chapter.blocks.filter { $0.kind == .marginNote }
        #expect(notes.count == 47)
        #expect(annotations.unanchored.isEmpty)
        #expect(Set(annotations.notes.keys) == Set(notes.map(\.key)))
        let blocks = Dictionary(uniqueKeysWithValues: chapter.blocks.map { ($0.key, $0) })
        var highlighted = Set<String>()
        for (key, highlights) in annotations.highlights {
            let text = String(try #require(blocks[key]).attributedText.characters)
            for highlight in highlights {
                let start = text.index(text.startIndex, offsetBy: highlight.range.lowerBound)
                let words = String(text[start...].prefix(highlight.range.count))
                for note in highlight.notes {
                    #expect(annotations.notes[note]?.anchorPhrases.contains(words) == true, "\(note) isn't about \"\(words)\"")
                    highlighted.insert(note)
                }
            }
        }
        #expect(highlighted == Set(notes.map(\.key)))
    }

    @Test func notesAboutTheSameWordsShareOneHighlight() throws {
        let chapter = try chapterOne()
        let annotations = MarginariumAnnotations(chapter: chapter)
        let workshop = try key("e2528a10", in: chapter)
        let child = try key("2676315d", in: chapter)
        let paragraph = try key("09e755fb", in: chapter)
        let shared = try #require(annotations.highlights[paragraph]?.first { $0.notes.contains(child) })
        #expect(shared.notes == [workshop, child])
        // The Workshop's other words are its own.
        let first = try key("59a4b63b", in: chapter)
        #expect(annotations.highlights[first]?.map(\.notes) == [[workshop]])
    }

    @Test func wordsATranslationMovedLeaveTheirNoteUnanchored() throws {
        let chapter = try chapterOne()
        let introduction = try key("67e349f0", in: chapter)
        let welcome = try key("d254ae6e", in: chapter)
        let narrator = try key("45f229e6", in: chapter)
        // The narrator's note about "writes in the margins", pointed at the wrong paragraph, and a
        // note whose anchor isn't in the catalog at all.
        let data = Data("""
            {"version":1,"chapters":[{"id":"fixture","blocks":[
              {"kind":"paragraph","key":"\(introduction)"}, {"kind":"paragraph","key":"\(welcome)"},
              {"kind":"marginHeading","key":"heading"},
              {"kind":"marginNote","key":"\(narrator)","speaker":"the narrator","anchorBlocks":["\(introduction)"]},
              {"kind":"marginNote","key":"fixture.missing","speaker":"Emily","anchorBlocks":["\(welcome)"]},
              {"kind":"marginNote","key":"fixture.unanchored","speaker":"Emily"}
            ]}]}
            """.utf8)
        let fixture = try #require(try JSONDecoder().decode(MarginariumDocument.self, from: data).chapters.first)
        let annotations = MarginariumAnnotations(chapter: fixture)
        #expect(annotations.unanchored == [narrator, "fixture.missing", "fixture.unanchored"])
        #expect(annotations.highlights.isEmpty)
        #expect(annotations.notes.count == 3)
    }

    @Test func overlappingHighlightsSplitIntoPiecesThatCountEveryVoice() {
        let pieces = MarginariumHighlighter.pieces([
            .init(range: 0 ..< 10, notes: ["a"]),
            .init(range: 5 ..< 15, notes: ["b", "c"]),
            .init(range: 20 ..< 24, notes: ["d"]),
        ])
        #expect(pieces == [
            .init(range: 0 ..< 5, notes: ["a"], voices: 1),
            .init(range: 5 ..< 10, notes: ["a", "b", "c"], voices: 3),
            .init(range: 10 ..< 15, notes: ["b", "c"], voices: 2),
            .init(range: 20 ..< 24, notes: ["d"], voices: 1),
        ])
        #expect(MarginariumHighlighter.wash(voices: 1, opened: false) < MarginariumHighlighter.wash(voices: 2, opened: false))
        #expect(MarginariumHighlighter.wash(voices: 2, opened: false) < MarginariumHighlighter.wash(voices: 3, opened: false))
        #expect(MarginariumHighlighter.wash(voices: 3, opened: false) == MarginariumHighlighter.wash(voices: 9, opened: false))
        #expect(MarginariumHighlighter.wash(voices: 1, opened: false) < MarginariumHighlighter.wash(voices: 1, opened: true))
    }

    @Test func highlightedWordsLinkToTheirNotesAndNothingElseDoes() throws {
        let segments = MarginariumHighlighter.segments(Self.inline("A *brave* little world"), block: "story",
                                                       highlights: [.init(range: 2 ..< 12, notes: ["n1", "n2"])],
                                                       selection: [])
        // Words and the spaces between them wash apart, so a line's last space can be left out.
        #expect(segments.map { String($0.text.characters) } == ["A ", "brave", " ", "litt", "le world"])
        #expect(segments.map { $0.wash?.isSpace } == [nil, false, true, false, nil])
        #expect(Set(segments.compactMap { $0.wash?.opacity }) == [MarginariumHighlighter.wash(voices: 2, opened: false)])
        for segment in segments {
            for run in segment.text.runs {
                if segment.wash == nil {
                    #expect(run.link == nil)
                } else {
                    let url = try #require(run.link)
                    #expect(MarginariumSelection(url: url) == MarginariumSelection(block: "story", notes: ["n1", "n2"]))
                    #expect(run[AttributeScopes.SwiftUIAttributes.UnderlineStyleAttribute.self] != nil)
                }
            }
        }
        // The emphasis stays.
        #expect(segments[1].text.runs.first?.inlinePresentationIntent == .emphasized)
    }

    @Test func theWashFillsTheSpacesBetweenWordsAndEndsWithALinesLastWord() {
        typealias Band = MarginariumWashRenderer.Band
        typealias Part = MarginariumWashRenderer.Part
        func rect(_ x: CGFloat, _ width: CGFloat) -> CGRect { CGRect(x: x, y: 0, width: width, height: 20) }
        let one = MarginariumWash(opacity: 0.14, isSpace: false), space = MarginariumWash(opacity: 0.14, isSpace: true)
        let two = MarginariumWash(opacity: 0.24, isSpace: false)
        // "Paul had ⟨the idea⟩ ⟨⟨twice⟩⟩ then ⟨again⟩", wrapping after "again ".
        let bands = MarginariumWashRenderer.bands([
            (rect(0, 40), nil),
            (rect(40, 30), one), (rect(70, 5), space), (rect(75, 30), two), (rect(105, 5), space),
            (rect(110, 30), nil),
            (rect(140, 30), one), (rect(170, 5), space),
        ])
        #expect(bands == [
            Band(rect: rect(40, 65), parts: [Part(minX: 40, maxX: 75, opacity: 0.14), Part(minX: 75, maxX: 105, opacity: 0.24)]),
            Band(rect: rect(140, 30), parts: [Part(minX: 140, maxX: 170, opacity: 0.14)]),
        ])
        // A line that starts with a highlight's space washes from its first word; spaces alone, not at all.
        #expect(MarginariumWashRenderer.bands([(rect(0, 5), space), (rect(5, 20), one)])
            == [Band(rect: rect(5, 20), parts: [Part(minX: 5, maxX: 25, opacity: 0.14)])])
        #expect(MarginariumWashRenderer.bands([(rect(0, 5), space), (rect(5, 20), nil)]).isEmpty)
    }

    @Test func aSelectionRoundTripsThroughItsLinkAndOtherLinksAreLeftAlone() throws {
        let selection = MarginariumSelection(block: "marginarium.marginarium.block.abc",
                                             notes: ["marginarium.marginarium.block.d", "marginarium.marginarium.block.e"])
        let url = try #require(selection.url)
        #expect(MarginariumSelection(url: url) == selection)
        #expect(MarginariumSelection(block: "story").url == nil)
        for string in ["https://example.org", "marginarium-note:", "marginarium-note:story", "marginarium-note::n1"] {
            let other = try #require(URL(string: string))
            #expect(MarginariumSelection(url: other) == nil, "\(string)")
        }
    }

    private static func inline(_ text: String) -> AttributedString {
        MarginariumDocument.Block.inline(text)
    }
}
