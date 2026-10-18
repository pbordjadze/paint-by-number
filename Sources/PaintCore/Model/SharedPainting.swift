import Foundation

/// A painting one painter sends another to paint: its template exactly as it is (the painter's
/// refinements are in it), its title and the settings that made it, and the photo it was made
/// from if the painter includes it. Never its progress or the refinements themselves (edits read
/// from a stranger's file would reach the editor unchecked), so the receiver paints a blank page,
/// and a template made again from the photo is made without the sender's edits. The app's
/// `.moonlight` file.
///
/// **Format.** Little-endian, like `Template`'s:
/// ```
/// UInt32 magic            "PBMS"
/// UInt32 formatVersion    1
/// UInt32 chunkCount
/// repeat chunkCount:
///     UInt32 tag          FourCC stored little-endian, so the bytes read e.g. "META"
///     UInt32 flags        bit 0 = required
///     UInt32 length
///     length bytes of payload
/// ```
/// Nothing may follow the last chunk. Unknown chunks are skipped unless flagged required (the
/// file then needs a newer reader: `Template.CodingError.requiredExtension`); none may appear
/// twice. Chunks defined so far:
/// - `META` (required): UTF-8 JSON, at most `maximumMetaBytes`:
///   `{"title": String, "settings": GenerationSettings, "sampleName": String}`, the last two
///   optional; unknown keys are ignored, settings that don't decode are none, and a `sampleName`
///   (the library picture the painting was made from) that isn't lowercase letters, digits and
///   hyphens is none.
/// - `TMPL`:
///   ```
///   UInt32 compression      `Compression` raw value; one this reader doesn't know needs a newer one
///   UInt32 length           of the encoded template, at most the reader's `maximumTemplateBytes`
///   bytes                   `Template.encoded()`, compressed by that method
///   ```
///   PaintCore compresses nothing itself (it stays portable); the app hands it LZFSE.
/// - `PHOT` (optional): the photo's encoded image (the app's JPEG), at most `maximumPhotoBytes`,
///   never empty. PaintCore doesn't look inside it; the app decodes it as any opened image.
///
/// **Safety.** A shared file comes from anyone. Every count and length is checked against the
/// bytes left, the decompressed length is bounded before decompressing and must come out exact,
/// and the template is read by `Template(encoded:)`, which checks every reference.
public struct SharedPainting: Sendable, Equatable {
    public var title: String
    public var settings: GenerationSettings?
    public var template: Template
    /// The encoded photo, when the painter sent it.
    public var photo: Data?
    /// The library picture the painting was made from (the app's `Sample.id`).
    public var sampleName: String?

    public init(title: String, settings: GenerationSettings?, template: Template, photo: Data? = nil, sampleName: String? = nil) {
        self.title = title
        self.settings = settings
        self.template = template
        self.photo = photo
        self.sampleName = sampleName
    }

    public static let formatVersion: UInt32 = 1
    static let magic: UInt32 = 0x534D_4250  // "PBMS"
    public static let maximumMetaBytes = 64 * 1024
    /// Longer titles are cut to this many characters.
    public static let maximumTitleLength = 200
    /// Far above the app's photos (at most 2048 px, JPEG).
    public static let maximumPhotoBytes = 32 * 1024 * 1024

    public enum Compression: UInt32, Sendable {
        case none = 0
        case lzfse = 1
    }

    enum Chunk {
        static let meta: UInt32 = 0x4154_454D  // "META"
        static let template: UInt32 = 0x4C50_4D54  // "TMPL"
        static let photo: UInt32 = 0x544F_4850  // "PHOT"
    }

    private struct Meta: Codable {
        var title: String
        var settings: GenerationSettings?
        var sampleName: String?

        init(title: String, settings: GenerationSettings?, sampleName: String?) {
            self.title = title
            self.settings = settings
            self.sampleName = sampleName
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            title = try c.decode(String.self, forKey: .title)
            settings = (try? c.decodeIfPresent(GenerationSettings.self, forKey: .settings)) ?? nil
            sampleName = ((try? c.decodeIfPresent(String.self, forKey: .sampleName)) ?? nil).flatMap(SharedPainting.cleanSampleName)
        }
    }

    /// The file's bytes, the template uncompressed.
    public func encoded() -> Data { encoded(compression: .none) { $0 } }

    /// The file's bytes. `compress` turns the encoded template into `compression`'s stream; it
    /// isn't called for `.none`.
    public func encoded(compression: Compression, compress: (Data) throws -> Data) rethrows -> Data {
        let raw = template.encoded()
        let payload = compression == .none ? raw : try compress(raw)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        // A title and settings always encode.
        let meta = (try? encoder.encode(Meta(title: title, settings: settings, sampleName: sampleName))) ?? Data()

        var body = BinaryWriter()
        body.write(compression.rawValue)
        body.write(UInt32(raw.count))
        body.write(bytes: payload)

        var w = BinaryWriter()
        w.write(Self.magic)
        w.write(Self.formatVersion)
        var chunks = [(Chunk.meta, Template.Chunk.requiredFlag, meta), (Chunk.template, Template.Chunk.requiredFlag, body.data)]
        if let photo, !photo.isEmpty { chunks.append((Chunk.photo, 0, photo)) }
        w.write(UInt32(chunks.count))
        for (tag, flags, payload) in chunks {
            w.write(tag)
            w.write(flags)
            w.write(UInt32(payload.count))
            w.write(bytes: payload)
        }
        return w.data
    }

    /// Reads a shared file. `decompress` is given the method, the compressed bytes and the
    /// length they must come to, and should throw when it can't; it isn't called for `.none`.
    /// Errors are `Template.CodingError`s (`requiresNewerReader` for a newer app's file), or
    /// whatever `decompress` throws.
    public init(
        encoded data: Data, maximumTemplateBytes: Int = 256 * 1024 * 1024,
        decompress: (Compression, Data, Int) throws -> Data = { _, _, _ in throw Template.CodingError.corrupt("compression") }
    ) throws {
        typealias CodingError = Template.CodingError
        var r = BinaryReader(data)
        guard try r.read(UInt32.self) == Self.magic else { throw CodingError.badMagic }
        let version = try r.read(UInt32.self)
        guard version != 0 else { throw CodingError.corrupt("version") }
        guard version <= Self.formatVersion else { throw CodingError.newerFormat(version) }

        var meta: Meta?
        var template: Template?
        var photo: Data?
        let count = try r.readCount(elementSize: Template.Chunk.headerSize)
        for _ in 0..<count {
            let tag = try r.read(UInt32.self)
            let flags = try r.read(UInt32.self)
            let payload = try r.readBytes(Int(try r.read(UInt32.self)))
            switch tag {
            case Chunk.meta:
                guard meta == nil else { throw CodingError.corrupt("duplicate chunk") }
                guard payload.count <= Self.maximumMetaBytes,
                      let decoded = try? JSONDecoder().decode(Meta.self, from: payload)
                else { throw CodingError.corrupt(Template.Chunk.name(tag)) }
                meta = decoded
            case Chunk.template:
                guard template == nil else { throw CodingError.corrupt("duplicate chunk") }
                var body = BinaryReader(payload)
                let method = try body.read(UInt32.self)
                let length = Int(try body.read(UInt32.self))
                guard let compression = Compression(rawValue: method) else { throw CodingError.requiredExtension(tag) }
                guard length > 0, length <= maximumTemplateBytes else { throw CodingError.corrupt(Template.Chunk.name(tag)) }
                let stream = try body.readBytes(body.remaining)
                let raw = compression == .none ? stream : try decompress(compression, stream, length)
                guard raw.count == length else { throw CodingError.corrupt(Template.Chunk.name(tag)) }
                template = try Template(encoded: raw)
            case Chunk.photo:
                guard photo == nil else { throw CodingError.corrupt("duplicate chunk") }
                guard !payload.isEmpty, payload.count <= Self.maximumPhotoBytes else { throw CodingError.corrupt(Template.Chunk.name(tag)) }
                photo = Data(payload)
            default:
                if flags & Template.Chunk.requiredFlag != 0 { throw CodingError.requiredExtension(tag) }
            }
        }
        guard r.isAtEnd else { throw CodingError.corrupt("trailing bytes") }
        guard let meta, let template else { throw CodingError.corrupt("missing chunk") }
        self.init(title: Self.cleanTitle(meta.title), settings: meta.settings, template: template, photo: photo, sampleName: meta.sampleName)
    }

    /// Trimmed, without control characters, and at most `maximumTitleLength` characters.
    static func cleanTitle(_ title: String) -> String {
        let visible = String(String.UnicodeScalarView(title.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }))
        return String(visible.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumTitleLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The name itself when it could be a library picture's (lowercase ASCII letters, digits and
    /// hyphens, at most 64), else nil.
    static func cleanSampleName(_ name: String) -> String? {
        let allowed = name.utf8.allSatisfy { (0x61...0x7A).contains($0) || (0x30...0x39).contains($0) || $0 == 0x2D }
        return allowed && (1...64).contains(name.utf8.count) ? name : nil
    }
}
