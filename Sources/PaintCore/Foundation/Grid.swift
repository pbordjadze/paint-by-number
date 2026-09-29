/// A dense, row-major 2D buffer. The workhorse container of the pipeline.
public struct Grid<Element> {
    public let width: Int
    public let height: Int
    public var storage: [Element]

    @inlinable
    public init(width: Int, height: Int, repeating value: Element) {
        precondition(width >= 0 && height >= 0)
        self.width = width
        self.height = height
        self.storage = [Element](repeating: value, count: width * height)
    }

    @inlinable
    public init(width: Int, height: Int, storage: [Element]) {
        precondition(storage.count == width * height, "Grid storage size mismatch")
        self.width = width
        self.height = height
        self.storage = storage
    }

    @inlinable public var count: Int { storage.count }

    @inlinable
    public subscript(x: Int, y: Int) -> Element {
        get { storage[y * width + x] }
        set { storage[y * width + x] = newValue }
    }

    @inlinable
    public func contains(x: Int, y: Int) -> Bool {
        x >= 0 && y >= 0 && x < width && y < height
    }

    /// Returns a new grid produced by applying `transform` to every element, in parallel.
    @inlinable
    public func map<T>(_ transform: (Element) -> T) -> Grid<T> {
        let n = count
        var out = [T]()
        out.reserveCapacity(n)
        storage.withUnsafeBufferPointer { src in
            out = [T](unsafeUninitializedCapacity: n) { dst, initialized in
                let d = UncheckedSendable(dst.baseAddress!)
                let s = UncheckedSendable(src.baseAddress!)
                Parallel.forEachBand(n, minimumBandSize: 16_384) { range in
                    for i in range { (d.value + i).initialize(to: transform(s.value[i])) }
                }
                initialized = n
            }
        }
        return Grid<T>(width: width, height: height, storage: out)
    }
}

extension Grid: Sendable where Element: Sendable {}
extension Grid: Equatable where Element: Equatable {}

public typealias RegionMap = Grid<UInt32>

/// 8-bit RGBA pixels, row-major, non-premultiplied. The pipeline's input format.
public struct RGBAImage: Sendable, Equatable {
    public let width: Int
    public let height: Int
    /// `width * height * 4` bytes: R, G, B, A.
    public var pixels: [UInt8]
    /// Primaries the RGB values are encoded in. Both supported spaces use the sRGB
    /// transfer curve.
    public var colorSpace: RGBColorSpace

    public init(width: Int, height: Int, pixels: [UInt8], colorSpace: RGBColorSpace = .sRGB) {
        precondition(pixels.count == width * height * 4, "RGBAImage buffer size mismatch")
        self.width = width
        self.height = height
        self.pixels = pixels
        self.colorSpace = colorSpace
    }

    public init(width: Int, height: Int, fill: SIMD4<UInt8>, colorSpace: RGBColorSpace = .sRGB) {
        var p = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            p[i * 4] = fill.x; p[i * 4 + 1] = fill.y; p[i * 4 + 2] = fill.z; p[i * 4 + 3] = fill.w
        }
        self.init(width: width, height: height, pixels: p, colorSpace: colorSpace)
    }

    @inlinable
    public subscript(x: Int, y: Int) -> SIMD4<UInt8> {
        get {
            let i = (y * width + x) * 4
            return SIMD4(pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3])
        }
        set {
            let i = (y * width + x) * 4
            pixels[i] = newValue.x; pixels[i + 1] = newValue.y
            pixels[i + 2] = newValue.z; pixels[i + 3] = newValue.w
        }
    }
}
