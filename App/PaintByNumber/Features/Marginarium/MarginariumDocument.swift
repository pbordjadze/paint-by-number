import Foundation

/// The bundled reader manifest, made by `tools/marginarium.py` from `docs/marginarium/*.md`.
/// Blocks carry stable catalog keys, never their position; the catalog holds their inline
/// Markdown (an image or pet's key holds its VoiceOver description). See the tool's docstring for
/// the authoring format. Unknown kinds are discarded before rendering, without decoding
/// their payload, so adding a kind doesn't make the rest of a chapter unreadable.
nonisolated struct MarginariumDocument: Decodable, Sendable {
    let version: Int
    let chapters: [Chapter]

    struct Chapter: Decodable, Sendable {
        let id: String
        let blocks: [Block]

        var readableBlocks: [Block] { blocks.filter { $0.kind != .unknown } }

        /// Group adjacent cells/notes without changing their row-major reading order or keys.
        /// A new header's first cell starts a table even when two tables touch in the source.
        var sections: [Section] {
            var result: [Section] = []
            for block in readableBlocks {
                if block.kind == .tableCell {
                    if result.last?.kind == .table, !(block.row == 0 && block.column == 0) {
                        result[result.count - 1].blocks.append(block)
                    } else {
                        result.append(Section(kind: .table, blocks: [block]))
                    }
                } else if block.kind == .marginNote, result.last?.kind == .margin {
                    result[result.count - 1].blocks.append(block)
                } else {
                    result.append(Section(kind: block.kind == .marginHeading ? .margin : .prose, blocks: [block]))
                }
            }
            return result
        }
    }

    struct Section: Identifiable, Sendable {
        enum Kind: Sendable { case prose, table, margin }
        let kind: Kind
        var blocks: [Block]
        var id: String { blocks.first?.key ?? "" }

        var tableRows: [TableRow] {
            var rows: [TableRow] = []
            for block in blocks {
                if block.column == 0 || rows.isEmpty {
                    rows.append(TableRow(cells: [block]))
                } else {
                    rows[rows.count - 1].cells.append(block)
                }
            }
            return rows
        }
    }

    struct TableRow: Identifiable, Sendable {
        var cells: [Block]
        var id: String { cells.first?.key ?? "" }
    }

    struct Block: Decodable, Identifiable, Sendable {
        enum Kind: String, Sendable {
            case title, subtitle, heading, paragraph, quote, bullet, ordered, image, pet
            case tableCell, marginHeading, marginNote, unknown
        }

        let kind: Kind
        let key: String
        let level: Int
        let depth: Int
        let image: String?
        let pet: String?
        let number: Int
        /// Editorial identity for future guardian pets; never substituted for the signed text.
        let speaker: String?
        let row: Int
        let column: Int
        let header: Bool
        var id: String { key }

        /// Runtime catalog lookup, like Sample.title; strings_check validates every key and
        /// exact English value against the source Markdown. No printf formatting is applied.
        var text: String { Bundle.main.localizedString(forKey: key, value: nil, table: nil) }

        var attributedText: AttributedString { Self.inline(text) }

        /// Keep paragraph breaks inside a quote while interpreting emphasis and links.
        static func inline(_ text: String) -> AttributedString {
            (try? AttributedString(markdown: text,
                                   options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                ?? AttributedString(text)
        }

        private enum CodingKeys: String, CodingKey {
            case kind, key, level, depth, image, pet, number, speaker, row, column, header
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let name = try container.decode(String.self, forKey: .kind)
            kind = Kind(rawValue: name) ?? .unknown
            guard kind != .unknown else {
                key = ""
                level = 1
                depth = 0
                image = nil
                pet = nil
                number = 1
                speaker = nil
                row = 0
                column = 0
                header = false
                return
            }
            key = try container.decode(String.self, forKey: .key)
            level = min(6, max(1, try container.decodeIfPresent(Int.self, forKey: .level) ?? 1))
            depth = max(0, try container.decodeIfPresent(Int.self, forKey: .depth) ?? 0)
            image = try container.decodeIfPresent(String.self, forKey: .image)
            pet = try container.decodeIfPresent(String.self, forKey: .pet)
            number = max(0, try container.decodeIfPresent(Int.self, forKey: .number) ?? 1)
            speaker = try container.decodeIfPresent(String.self, forKey: .speaker)
            row = try container.decodeIfPresent(Int.self, forKey: .row) ?? 0
            column = try container.decodeIfPresent(Int.self, forKey: .column) ?? 0
            header = try container.decodeIfPresent(Bool.self, forKey: .header) ?? false
        }
    }

    /// Called through Background.run by the reader, keeping file IO and decoding off MainActor.
    static func bundled() -> MarginariumDocument? {
        guard let url = Bundle.main.url(forResource: "marginarium", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let document = try? JSONDecoder().decode(MarginariumDocument.self, from: data),
              document.version == 1 else { return nil }
        return document
    }
}
