import Foundation
import SwiftUI

/// Which words of a chapter's story its margin notes are about (`Block.anchorBlocks` and the
/// catalog's `<note>.anchor`), found in each block's text as the reader shows it. Notes about the
/// same words share one highlight. A note whose words aren't all found, as when a translation
/// moved them, isn't lost: it is `unanchored`, and keeps its card after its story.
nonisolated struct MarginariumAnnotations: Sendable {
    /// A phrase of one block's text, as a range of characters, and the notes about it in
    /// chapter order.
    struct Highlight: Equatable, Sendable {
        let range: Range<Int>
        var notes: [String]
    }

    /// Each story block's highlights, by block key, in the order their notes come.
    let highlights: [String: [Highlight]]
    /// Every margin note of the chapter, by key.
    let notes: [String: MarginariumDocument.Block]
    let unanchored: Set<String>

    static let empty = MarginariumAnnotations(highlights: [:], notes: [:], unanchored: [])

    private init(highlights: [String: [Highlight]], notes: [String: MarginariumDocument.Block],
                 unanchored: Set<String>) {
        self.highlights = highlights
        self.notes = notes
        self.unanchored = unanchored
    }

    init(chapter: MarginariumDocument.Chapter) {
        let blocks = Dictionary(chapter.readableBlocks.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        var texts: [String: String] = [:]
        var highlights: [String: [Highlight]] = [:]
        var notes: [String: MarginariumDocument.Block] = [:]
        var unanchored: Set<String> = []
        for note in chapter.readableBlocks where note.kind == .marginNote {
            notes[note.key] = note
            let phrases = note.anchorPhrases
            var found: [(block: String, range: Range<Int>)] = []
            if phrases.count == note.anchorBlocks.count {
                for (phrase, key) in zip(phrases, note.anchorBlocks) {
                    guard !phrase.isEmpty, let block = blocks[key] else { break }
                    let text = texts[key] ?? String(block.attributedText.characters)
                    texts[key] = text
                    guard let match = text.range(of: phrase) else { break }
                    let start = text.distance(from: text.startIndex, to: match.lowerBound)
                    found.append((key, start ..< start + text.distance(from: match.lowerBound, to: match.upperBound)))
                }
            }
            guard !phrases.isEmpty, found.count == phrases.count else {
                unanchored.insert(note.key)
                continue
            }
            for (key, range) in found {
                if let index = highlights[key]?.firstIndex(where: { $0.range == range }) {
                    highlights[key]?[index].notes.append(note.key)
                } else {
                    highlights[key, default: []].append(Highlight(range: range, notes: [note.key]))
                }
            }
        }
        self.init(highlights: highlights, notes: notes, unanchored: unanchored)
    }

    #if DEBUG
    /// The highlight a demo opens: of the note's words, the ones most voices share.
    func busiestHighlight(of note: String) -> (block: String, highlight: Highlight)? {
        highlights.flatMap { block, list in
            list.filter { $0.notes.contains(note) }.map { (block: block, highlight: $0) }
        }
        .max { ($0.highlight.notes.count, $1.highlight.range.lowerBound, $1.block)
            < ($1.highlight.notes.count, $0.highlight.range.lowerBound, $0.block) }
    }
    #endif
}

/// The words a reader tapped: the block holding them and the notes about them, carried by the
/// highlight's link (`marginarium-note:<block>:<note>,<note>`).
nonisolated struct MarginariumSelection: Equatable, Sendable {
    static let scheme = "marginarium-note"

    var block: String?
    var notes: [String] = []

    init(block: String? = nil, notes: [String] = []) {
        self.block = block
        self.notes = notes
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme else { return nil }
        let parts = url.absoluteString.dropFirst(Self.scheme.count + 1).split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        block = String(parts[0])
        notes = parts[1].split(separator: ",").map(String.init)
    }

    var url: URL? {
        guard let block, !notes.isEmpty else { return nil }
        return URL(string: "\(Self.scheme):\(block):\(notes.joined(separator: ","))")
    }
}

/// Draws a block's highlights into its text: a wash of the tint that deepens where several
/// guardians wrote about the same words (two passes of a highlighter), a thin underline, and a
/// link that opens their notes. The words a reader opened wash deeper still. The wash leaves the
/// spaces out: a space where a line wraps would carry it on to the margin.
enum MarginariumHighlighter {
    /// A stretch of text covered by the same highlights; `voices` counts their notes.
    struct Piece: Equatable {
        let range: Range<Int>
        let notes: [String]
        let voices: Int
    }

    nonisolated static func pieces(_ highlights: [MarginariumAnnotations.Highlight]) -> [Piece] {
        let bounds = Set(highlights.flatMap { [$0.range.lowerBound, $0.range.upperBound] }).sorted()
        return zip(bounds, bounds.dropFirst()).compactMap { lower, upper -> Piece? in
            let covering = highlights.filter { $0.range.lowerBound <= lower && upper <= $0.range.upperBound }
            guard !covering.isEmpty else { return nil }
            var seen = Set<String>()
            return Piece(range: lower ..< upper, notes: covering.flatMap(\.notes).filter { seen.insert($0).inserted },
                         voices: covering.reduce(0) { $0 + $1.notes.count })
        }
    }

    static func text(_ base: AttributedString, block: String, highlights: [MarginariumAnnotations.Highlight],
                     selection: Set<String>) -> AttributedString {
        var text = base
        let characters = Array(text.characters)
        func index(_ offset: Int) -> AttributedString.Index {
            text.characters.index(text.characters.startIndex, offsetBy: offset)
        }
        for piece in pieces(highlights) where piece.range.upperBound <= characters.count {
            let opened = !selection.isDisjoint(with: piece.notes)
            var link = AttributeContainer()
            link[AttributeScopes.SwiftUIAttributes.UnderlineStyleAttribute.self] =
                Text.LineStyle(pattern: .solid, color: Theme.accent.opacity(opened ? 1 : 0.6))
            link[AttributeScopes.FoundationAttributes.LinkAttribute.self] =
                MarginariumSelection(block: block, notes: piece.notes).url
            let range = index(piece.range.lowerBound) ..< index(piece.range.upperBound)
            text[range].mergeAttributes(link)
            var washed = AttributeContainer()
            washed[AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute.self] =
                Theme.accent.opacity(wash(voices: piece.voices, opened: opened))
            var start = piece.range.lowerBound
            while start < piece.range.upperBound {
                guard !characters[start].isWhitespace else {
                    start += 1
                    continue
                }
                var end = start
                while end < piece.range.upperBound, !characters[end].isWhitespace { end += 1 }
                let word = index(start) ..< index(end)
                text[word].mergeAttributes(washed)
                start = end
            }
        }
        return text
    }

    /// One voice is a light wash, each more a little deeper, up to three.
    nonisolated static func wash(voices: Int, opened: Bool) -> Double {
        0.04 + 0.1 * Double(min(max(voices, 1), 3)) + (opened ? 0.16 : 0)
    }
}
