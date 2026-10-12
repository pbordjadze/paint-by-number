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
    }

    struct Block: Decodable, Identifiable, Sendable {
        enum Kind: String, Sendable {
            case title, subtitle, heading, paragraph, quote, bullet, image, pet, unknown
        }

        let kind: Kind
        let key: String
        let level: Int
        let depth: Int
        let image: String?
        let pet: String?
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

        private enum CodingKeys: String, CodingKey { case kind, key, level, depth, image, pet }

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
                return
            }
            key = try container.decode(String.self, forKey: .key)
            level = min(6, max(1, try container.decodeIfPresent(Int.self, forKey: .level) ?? 1))
            depth = max(0, try container.decodeIfPresent(Int.self, forKey: .depth) ?? 0)
            image = try container.decodeIfPresent(String.self, forKey: .image)
            pet = try container.decodeIfPresent(String.self, forKey: .pet)
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
