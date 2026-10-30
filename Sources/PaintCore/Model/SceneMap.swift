import Foundation

/// What a photo is of, beyond its pixels: the subjects' mask, where the eye goes, the faces and
/// animals and their features, at a low resolution. On the device Vision finds it
/// (`SubjectVision` in the app); off the device a stand-in does (`tools/scene_standin.py`,
/// `pbn --scene`). The scene method of generation reads it
/// (`GenerationSettings.Method.scene`), and a template made with one keeps it (the `SCEN`
/// chunk, `Template.scene`), so regeneration anywhere reads the same scene and makes the same
/// bytes. The color method ignores it.
///
/// Coordinates: the maps are `width × height` in raster order; rects and features are
/// normalized to the photo (0...1, origin top-left), like `SubjectHints` and `LineArtInput`.
public struct SceneMap: Sendable, Hashable {
    /// The maps' long side is at most this; the app samples Vision's at `resolution`.
    public static let maxSide = 1024
    public static let resolution = 256

    public var width: Int
    public var height: Int
    /// Per pixel, 0...255: how surely the pixel lies on a subject (the foreground mask; the
    /// people, animals and objects the photo is of). All zero when nothing was found.
    public var subject: [UInt8]
    /// Per pixel, 0...255: attention saliency, where the eye goes first. All zero when unknown.
    public var saliency: [UInt8]
    /// Faces and animals as detected, normalized rects.
    public var faces: [NormalizedRect]
    public var animals: [NormalizedRect]
    /// The subjects' features: an eye, a nose or a mouth, with the radius (as a share of the
    /// photo's long side) within which the picture is that feature.
    public var features: [Feature]

    public struct Feature: Sendable, Hashable, Codable {
        public enum Kind: UInt8, Sendable, Codable, CaseIterable {
            case eye = 0, nose = 1, mouth = 2
        }
        public var kind: Kind
        public var x: Float
        public var y: Float
        public var radius: Float

        public init(kind: Kind, x: Float, y: Float, radius: Float) {
            self.kind = kind
            self.x = x
            self.y = y
            self.radius = radius
        }
    }

    public init(
        width: Int, height: Int, subject: [UInt8], saliency: [UInt8],
        faces: [NormalizedRect] = [], animals: [NormalizedRect] = [], features: [Feature] = []
    ) {
        precondition(width > 0 && height > 0 && subject.count == width * height && saliency.count == width * height)
        self.width = width
        self.height = height
        self.subject = subject
        self.saliency = saliency
        self.faces = faces
        self.animals = animals
        self.features = features
    }

    /// A scene with nothing found: no subject, no saliency, no faces. The scene method then
    /// treats the whole photo as its subject.
    public static func empty(width: Int, height: Int) -> SceneMap {
        SceneMap(width: width, height: height, subject: [UInt8](repeating: 0, count: width * height),
                 saliency: [UInt8](repeating: 0, count: width * height))
    }

    /// The least share of the frame the mask must cover (at half or more) to count as a subject
    /// found: a few stray pixels are the mask's noise, not a subject, and the scene method
    /// would otherwise take the whole photo for background.
    public static let minimumSubjectShare: Float = 0.01

    /// Whether a subject was found: the mask covers `minimumSubjectShare` of the frame, or a
    /// face or an animal was detected.
    public var hasSubject: Bool {
        if !faces.isEmpty || !animals.isEmpty { return true }
        let covered = subject.count { $0 >= 128 }
        return Float(covered) >= Self.minimumSubjectShare * Float(max(1, subject.count))
    }

    /// The subject mask (0...1) resampled bilinearly to `width × height`, as `ImportanceMap.resample`
    /// resamples the importance map.
    public func subjectResampled(width w: Int, height h: Int) -> [Float] {
        ImportanceMap.resample(grid(subject), width: w, height: h)
    }

    /// The saliency (0...1) resampled bilinearly to `width × height`.
    public func saliencyResampled(width w: Int, height h: Int) -> [Float] {
        ImportanceMap.resample(grid(saliency), width: w, height: h)
    }

    private func grid(_ bytes: [UInt8]) -> Grid<Float> {
        Grid(width: width, height: height, storage: bytes.map { Float($0) / 255 })
    }

    // MARK: - Coding

    /// The `SCEN` chunk's payload. Fields may be appended; readers read a prefix.
    /// ```
    /// UInt8 version               1
    /// UInt32 width, UInt32 height  1...maxSide each
    /// width × height × UInt8 subject
    /// width × height × UInt8 saliency
    /// UInt32 faceCount; faceCount × (Float32 x, y, width, height)
    /// UInt32 animalCount; the same
    /// UInt32 featureCount; featureCount × (UInt8 kind, Float32 x, y, radius)
    /// ```
    static let codingVersion: UInt8 = 1

    func encoded() -> Data {
        var w = BinaryWriter()
        w.write(Self.codingVersion)
        w.write(UInt32(width))
        w.write(UInt32(height))
        w.write(bytes: Data(subject))
        w.write(bytes: Data(saliency))
        for rects in [faces, animals] {
            w.write(UInt32(rects.count))
            for r in rects { w.write(r.x); w.write(r.y); w.write(r.width); w.write(r.height) }
        }
        w.write(UInt32(features.count))
        for f in features { w.write(f.kind.rawValue); w.write(f.x); w.write(f.y); w.write(f.radius) }
        return w.data
    }

    /// Reads a chunk payload as hostile input: sizes and counts are checked against the bytes
    /// left before anything is allocated, every number is finite and every coordinate lies
    /// near the unit square.
    init(_ r: inout BinaryReader) throws {
        let version = try r.read(UInt8.self)
        guard version == Self.codingVersion else { throw Template.CodingError.corrupt("scene version") }
        let w = Int(try r.read(UInt32.self)), h = Int(try r.read(UInt32.self))
        guard w >= 1, h >= 1, w <= Self.maxSide, h <= Self.maxSide else { throw Template.CodingError.corrupt("scene size") }
        width = w
        height = h
        subject = Array(try r.readBytes(w * h))
        saliency = Array(try r.readBytes(w * h))
        func inRange(_ v: Float) -> Bool { v.isFinite && v >= -1 && v <= 2 }
        func rects() throws -> [NormalizedRect] {
            let count = try r.readCount(elementSize: 16)
            var out: [NormalizedRect] = []
            out.reserveCapacity(count)
            for _ in 0..<count {
                let rect = NormalizedRect(
                    x: try r.read(Float.self), y: try r.read(Float.self),
                    width: try r.read(Float.self), height: try r.read(Float.self))
                guard inRange(rect.x), inRange(rect.y), inRange(rect.width), inRange(rect.height), rect.width >= 0, rect.height >= 0
                else { throw Template.CodingError.corrupt("scene rect") }
                out.append(rect)
            }
            return out
        }
        faces = try rects()
        animals = try rects()
        let featureCount = try r.readCount(elementSize: 13)
        var features: [Feature] = []
        features.reserveCapacity(featureCount)
        for _ in 0..<featureCount {
            guard let kind = Feature.Kind(rawValue: try r.read(UInt8.self)) else { throw Template.CodingError.corrupt("scene feature") }
            let f = Feature(kind: kind, x: try r.read(Float.self), y: try r.read(Float.self), radius: try r.read(Float.self))
            guard inRange(f.x), inRange(f.y), f.radius.isFinite, f.radius >= 0, f.radius <= 1 else {
                throw Template.CodingError.corrupt("scene feature")
            }
            features.append(f)
        }
        self.features = features
    }

    /// The scene as `Data` on its own (the app keeps a draft's beside its template; `pbn` writes
    /// one): the chunk payload behind the magic "PBNS".
    public static let magic: UInt32 = 0x534E_4250  // "PBNS"

    public func encodedFile() -> Data {
        var w = BinaryWriter()
        w.write(Self.magic)
        w.write(bytes: encoded())
        return w.data
    }

    public init(encodedFile data: Data) throws {
        var r = BinaryReader(data)
        guard try r.read(UInt32.self) == Self.magic else { throw Template.CodingError.badMagic }
        try self.init(&r)
        guard r.isAtEnd else { throw Template.CodingError.corrupt("trailing bytes") }
    }
}
