import CoreGraphics
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

/// Marks a block's highlights: a wash of the tint that deepens where several guardians wrote
/// about the same words (two passes of a highlighter), a thin underline, and a link that opens
/// their notes. The words a reader opened wash deeper still. `MarginariumWashRenderer` draws
/// the wash, which a background color can't: one on a space where a line wraps runs on to the
/// margin.
enum MarginariumHighlighter {
    /// A stretch of text covered by the same highlights; `voices` counts their notes.
    struct Piece: Equatable {
        let range: Range<Int>
        let notes: [String]
        let voices: Int
    }

    /// A stretch of a block's text: plain, or a highlight's words or the spaces between them.
    struct Segment {
        let text: AttributedString
        let wash: MarginariumWash?
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

    /// The block's text with its highlights, for a view drawn by `MarginariumWashRenderer`. It
    /// joins the segments by interpolation, which keeps each one's wash (`+` is deprecated).
    static func text(_ base: AttributedString, block: String, highlights: [MarginariumAnnotations.Highlight],
                     selection: Set<String>) -> Text {
        let parts = segments(base, block: block, highlights: highlights, selection: selection)
        var joined = LocalizedStringKey.StringInterpolation(literalCapacity: 0, interpolationCount: parts.count)
        for part in parts {
            let words = Text(part.text)
            joined.appendInterpolation(part.wash.map { words.customAttribute($0) } ?? words)
        }
        return Text(LocalizedStringKey(stringInterpolation: joined))
    }

    static func segments(_ base: AttributedString, block: String, highlights: [MarginariumAnnotations.Highlight],
                         selection: Set<String>) -> [Segment] {
        let characters = Array(base.characters)
        func index(_ offset: Int) -> AttributedString.Index {
            base.characters.index(base.characters.startIndex, offsetBy: offset)
        }
        var segments: [Segment] = []
        var cursor = 0
        for piece in pieces(highlights) where piece.range.upperBound <= characters.count {
            if cursor < piece.range.lowerBound {
                segments.append(Segment(text: AttributedString(base[index(cursor) ..< index(piece.range.lowerBound)]), wash: nil))
            }
            let opened = !selection.isDisjoint(with: piece.notes)
            var link = AttributeContainer()
            link[AttributeScopes.SwiftUIAttributes.UnderlineStyleAttribute.self] =
                Text.LineStyle(pattern: .solid, color: Theme.accent.opacity(opened ? 1 : 0.6))
            link[AttributeScopes.FoundationAttributes.LinkAttribute.self] =
                MarginariumSelection(block: block, notes: piece.notes).url
            let opacity = wash(voices: piece.voices, opened: opened)
            var start = piece.range.lowerBound
            while start < piece.range.upperBound {
                let isSpace = characters[start].isWhitespace
                var end = start + 1
                while end < piece.range.upperBound, characters[end].isWhitespace == isSpace { end += 1 }
                var words = AttributedString(base[index(start) ..< index(end)])
                words.mergeAttributes(link)
                segments.append(Segment(text: words, wash: MarginariumWash(opacity: opacity, isSpace: isSpace)))
                start = end
            }
            cursor = piece.range.upperBound
        }
        if cursor < characters.count {
            segments.append(Segment(text: AttributedString(base[index(cursor)...]), wash: nil))
        }
        return segments
    }

    /// One voice is a light wash, each more a little deeper, up to three.
    nonisolated static func wash(voices: Int, opened: Bool) -> Double {
        0.04 + 0.1 * Double(min(max(voices, 1), 3)) + (opened ? 0.16 : 0)
    }
}

/// How deep to wash a highlight's words, or the spaces between them.
nonisolated struct MarginariumWash: TextAttribute {
    let opacity: Double
    let isSpace: Bool
}

/// Washes the highlighted words of each line (`MarginariumWash`), then draws the line over
/// them. Neighbouring words join into one band with rounded ends, the spaces between them
/// filled; a space with no washed word after it on its line, where a highlight wraps, is left
/// out, so the band ends with the line's last word.
nonisolated struct MarginariumWashRenderer: TextRenderer {
    /// One line's band of washed words and the depths along it.
    struct Band: Equatable {
        var rect: CGRect
        var parts: [Part]
    }

    struct Part: Equatable {
        var minX: CGFloat
        var maxX: CGFloat
        let opacity: Double
    }

    let color: Color

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for band in Self.bands(line.map { (rect: $0.typographicBounds.rect, wash: $0[MarginariumWash.self]) }) {
                var washed = context
                washed.clip(to: Path(roundedRect: band.rect, cornerRadius: 3))
                for part in band.parts {
                    let rect = CGRect(x: part.minX, y: band.rect.minY, width: part.maxX - part.minX, height: band.rect.height)
                    washed.fill(Path(rect), with: .color(color.opacity(part.opacity)))
                }
            }
            context.draw(line)
        }
    }

    /// A line's bands, from its runs in order: each stretch of washed runs, less the spaces at
    /// its ends, with runs of the same depth joined.
    static func bands(_ runs: [(rect: CGRect, wash: MarginariumWash?)]) -> [Band] {
        var bands: [Band] = []
        var stretch: [(rect: CGRect, wash: MarginariumWash)] = []
        func close() {
            while stretch.last?.wash.isSpace == true { stretch.removeLast() }
            while stretch.first?.wash.isSpace == true { stretch.removeFirst() }
            guard let first = stretch.first else { return }
            var band = Band(rect: first.rect, parts: [])
            for run in stretch {
                band.rect = band.rect.union(run.rect)
                if let last = band.parts.last, last.opacity == run.wash.opacity {
                    band.parts[band.parts.count - 1].maxX = max(last.maxX, run.rect.maxX)
                } else {
                    band.parts.append(Part(minX: run.rect.minX, maxX: run.rect.maxX, opacity: run.wash.opacity))
                }
            }
            bands.append(band)
            stretch = []
        }
        for run in runs {
            if let wash = run.wash {
                stretch.append((rect: run.rect, wash: wash))
            } else {
                close()
            }
        }
        close()
        return bands
    }
}
