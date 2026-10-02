/// Edge strength per pixel (0 = none … 255 = certain), the input of layered line art. The app
/// computes it with its HED model; `pbn` reads it from a PGM. Any resolution: the generator
/// resamples it to the working size, so a map from the photo's own aspect ratio lines up.
/// Quantized to 8 bits so that small floating-point differences between devices and compute
/// units cannot change the template.
public struct EdgeMap: Sendable, Equatable {
    public let width: Int
    public let height: Int
    /// Row-major, `width * height` values.
    public var values: [UInt8]

    public init(width: Int, height: Int, values: [UInt8]) {
        precondition(width > 0 && height > 0 && values.count == width * height, "EdgeMap size mismatch")
        self.width = width
        self.height = height
        self.values = values
    }
}

/// Everything layered line art needs beyond the photo.
public struct LineArtInput: Sendable, Equatable {
    public var edges: EdgeMap
    /// Detected eyes as closed polygons (contours, then irises), in coordinates normalized to
    /// the source photo (0...1, origin top-left). Drawn as outlines when
    /// `LineArtSettings.outlineEyes` is on.
    public var eyes: [[SIMD2<Float>]]

    public init(edges: EdgeMap, eyes: [[SIMD2<Float>]] = []) {
        self.edges = edges
        self.eyes = eyes
    }
}
