/// A rectangle in normalized image coordinates (0…1, top-left origin), as Vision reports
/// faces and animals once flipped.
public struct NormalizedRect: Sendable, Codable, Hashable {
    public var x: Float
    public var y: Float
    public var width: Float
    public var height: Float

    public init(x: Float, y: Float, width: Float, height: Float) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// Area of the part inside the unit square.
    var clippedArea: Float {
        let w = min(x + width, 1) - max(x, 0), h = min(y + height, 1) - max(y, 0)
        return w > 0 && h > 0 ? w * h : 0
    }
}

/// What the device knows about a photo's subject beyond pixels (Vision on Apple platforms;
/// empty, or hand-written for tooling, elsewhere).
public struct SubjectHints: Sendable, Codable, Hashable {
    /// Normalized rects (0…1, top-left origin) of detected human faces and animals.
    public var faces: [NormalizedRect]
    public var animals: [NormalizedRect]

    public init(faces: [NormalizedRect] = [], animals: [NormalizedRect] = []) {
        self.faces = faces
        self.animals = animals
    }

    /// Missing lists decode as empty: hand-written hints for tooling name only what a photo has.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        faces = try c.decodeIfPresent([NormalizedRect].self, forKey: .faces) ?? []
        animals = try c.decodeIfPresent([NormalizedRect].self, forKey: .animals) ?? []
    }
}
