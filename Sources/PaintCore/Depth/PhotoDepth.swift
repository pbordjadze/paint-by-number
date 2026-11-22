/// What a Portrait photo knows of its own scene (painting-company research
/// `2026-11-22-obscure-apple-apis`): how near each point is, and where the sky, hair and skin are.
/// The camera made these when it took the photo and keeps them in the file beside it (the app's
/// `PhotoDepthReader` reads them through ImageIO); nothing here is a model of ours, so a mode
/// that cuts the picture by depth (Woodblock's blocks, Paper-cut's layers) follows the painter's
/// own photo.
///
/// The maps keep the camera's size (a few hundred pixels across, already turned upright); a mode
/// lays them on its template's canvas with `laid(width:height:)`. Everything is integer and
/// deterministic: the same depth gives the same planes on every device, and `encoded()` is what
/// a painting keeps of it, so its blocks or layers come out the same when it opens again.
public struct PhotoDepth: Sendable, Equatable {
    /// How near each point is: 0 the farthest the photo sees, 255 the nearest.
    public let nearness: Grid<UInt8>
    /// The camera's mattes, 0…255 (255: surely sky, hair, skin), at `nearness`' size; nil where
    /// the photo has none.
    public let sky: Grid<UInt8>?
    public let hair: Grid<UInt8>?
    public let skin: Grid<UInt8>?

    /// The largest map a painting keeps (cameras record well under it).
    public static let mostPixels = 4096 * 4096

    public init?(nearness: Grid<UInt8>, sky: Grid<UInt8>? = nil, hair: Grid<UInt8>? = nil, skin: Grid<UInt8>? = nil) {
        let w = nearness.width, h = nearness.height
        guard w > 0, h > 0, w * h <= Self.mostPixels,
              [sky, hair, skin].allSatisfy({ $0 == nil || ($0!.width == w && $0!.height == h) })
        else { return nil }
        self.nearness = nearness
        self.sky = sky
        self.hair = hair
        self.skin = skin
    }

    /// Nearness from the camera's disparity (larger is nearer), read at its own size: spread
    /// between its 2nd and 98th percentiles so a stray point doesn't flatten the rest; a point
    /// with no reading (not finite) is the farthest.
    public static func nearness(disparity: Grid<Float>) -> Grid<UInt8>? {
        let finite = disparity.storage.filter { $0.isFinite }
        guard disparity.width > 0, disparity.height > 0, finite.count >= 2 else { return nil }
        let sorted = finite.sorted()
        let low = sorted[sorted.count * 2 / 100], high = sorted[(sorted.count - 1) * 98 / 100]
        let span = high - low
        let values = disparity.storage.map { v -> UInt8 in
            guard v.isFinite, span > 0 else { return 0 }
            let t = min(max((v - low) / span, 0), 1)
            return UInt8((t * 255).rounded())
        }
        return Grid(width: disparity.width, height: disparity.height, storage: values)
    }

    /// The maps laid on a canvas of `width` × `height` (the template's), sampled bilinearly in
    /// integer arithmetic.
    public func laid(width: Int, height: Int) -> PhotoDepth {
        guard width > 0, height > 0, width != nearness.width || height != nearness.height else { return self }
        func lay(_ g: Grid<UInt8>) -> Grid<UInt8> { Self.resample(g, width: width, height: height) }
        return PhotoDepth(nearness: lay(nearness), sky: sky.map(lay), hair: hair.map(lay), skin: skin.map(lay))!
    }

    /// Each pixel's plane, 0 (farthest) to `count - 1` (nearest): the photo cut where its nearness
    /// divides the pixels into equal shares, the sky (its matte at least half sure) always the
    /// farthest.
    public func planes(count: Int) -> Grid<UInt8> {
        let n = max(1, min(count, 255))
        let w = nearness.width, h = nearness.height
        var histogram = [Int](repeating: 0, count: 256)
        var counted = 0
        for i in 0..<(w * h) where !isSky(i) {
            histogram[Int(nearness.storage[i])] += 1
            counted += 1
        }
        // The nearness at which each plane after the first begins.
        var starts = [Int](repeating: 256, count: n)
        starts[0] = 0
        var running = 0, plane = 1
        for v in 0..<256 where plane < n {
            running += histogram[v]
            while plane < n, running * n >= counted * plane {
                starts[plane] = v + 1
                plane += 1
            }
        }
        var out = Grid<UInt8>(width: w, height: h, repeating: 0)
        for i in 0..<(w * h) where !isSky(i) {
            let v = Int(nearness.storage[i])
            var p = 0
            while p + 1 < n, v >= starts[p + 1] { p += 1 }
            out.storage[i] = UInt8(p)
        }
        return out
    }

    /// Each of `template`'s regions' plane: the one most of its pixels lie in, the nearer on a
    /// tie. The depth is laid on the template's canvas first.
    public func regionPlanes(of template: Template, count: Int) -> [Int] {
        regionPlanes(of: template.regionMap, regions: template.regions.count, count: count)
    }

    /// Whether each of `template`'s regions is sky: more than half its pixels in the sky's matte
    /// (none without one).
    public func skyRegions(of template: Template) -> [Bool] {
        skyRegions(of: template.regionMap, regions: template.regions.count)
    }

    func regionPlanes(of map: RegionMap, regions: Int, count: Int) -> [Int] {
        let planes = laid(width: map.width, height: map.height).planes(count: count)
        let n = max(1, min(count, 255))
        var votes = [Int](repeating: 0, count: regions * n)
        for i in 0..<map.count {
            let r = Int(map.storage[i])
            guard r < regions else { continue }
            votes[r * n + Int(planes.storage[i])] += 1
        }
        return (0..<regions).map { r in
            var best = 0
            for p in 0..<n where votes[r * n + p] >= votes[r * n + best] { best = p }
            return best
        }
    }

    func skyRegions(of map: RegionMap, regions: Int) -> [Bool] {
        guard sky != nil else { return [Bool](repeating: false, count: regions) }
        let laid = laid(width: map.width, height: map.height)
        var inSky = [Int](repeating: 0, count: regions), all = inSky
        for i in 0..<map.count {
            let r = Int(map.storage[i])
            guard r < regions else { continue }
            all[r] += 1
            if laid.isSky(i) { inSky[r] += 1 }
        }
        return (0..<regions).map { all[$0] > 0 && inSky[$0] * 2 > all[$0] }
    }

    private func isSky(_ i: Int) -> Bool { (sky?.storage[i] ?? 0) >= 128 }

    static func resample(_ g: Grid<UInt8>, width: Int, height: Int) -> Grid<UInt8> {
        var out = Grid<UInt8>(width: width, height: height, repeating: 0)
        // Pixel centres in 1/256ths of a source pixel.
        for y in 0..<height {
            let sy = max(0, ((2 * y + 1) * g.height * 128) / height - 128)
            let y0 = min(sy >> 8, g.height - 1), y1 = min(y0 + 1, g.height - 1), fy = sy & 255
            for x in 0..<width {
                let sx = max(0, ((2 * x + 1) * g.width * 128) / width - 128)
                let x0 = min(sx >> 8, g.width - 1), x1 = min(x0 + 1, g.width - 1), fx = sx & 255
                let top = Int(g[x0, y0]) * (256 - fx) + Int(g[x1, y0]) * fx
                let bottom = Int(g[x0, y1]) * (256 - fx) + Int(g[x1, y1]) * fx
                out[x, y] = UInt8((top * (256 - fy) + bottom * fy + 32768) >> 16)
            }
        }
        return out
    }
}

// MARK: - Keeping it with a painting

extension PhotoDepth {
    public enum CodingError: Error, Equatable { case notDepth, newerVersion, damaged }

    static let magic: [UInt8] = Array("PDEP".utf8)
    static let version: UInt8 = 1

    /// The bytes a painting keeps (`depth.bin`): "PDEP", a version, the width and height (32-bit
    /// little endian), which mattes follow (bits 1 sky, 2 hair, 4 skin), then the maps a row at a
    /// time, nearness first.
    public func encoded() -> [UInt8] {
        var out = Self.magic
        out.append(Self.version)
        for v in [UInt32(nearness.width), UInt32(nearness.height)] {
            out += [UInt8(v & 0xff), UInt8(v >> 8 & 0xff), UInt8(v >> 16 & 0xff), UInt8(v >> 24)]
        }
        out.append((sky != nil ? 1 : 0) | (hair != nil ? 2 : 0) | (skin != nil ? 4 : 0))
        out += nearness.storage
        for g in [sky, hair, skin] { if let g { out += g.storage } }
        return out
    }

    /// Reads `encoded()`'s bytes, as hostile input: every size is checked against the bytes
    /// there before anything is made.
    public init(decoding bytes: [UInt8]) throws {
        guard bytes.count >= 14, Array(bytes[0..<4]) == Self.magic else { throw CodingError.notDepth }
        guard bytes[4] <= Self.version else { throw CodingError.newerVersion }
        func u32(_ at: Int) -> Int {
            Int(bytes[at]) | Int(bytes[at + 1]) << 8 | Int(bytes[at + 2]) << 16 | Int(bytes[at + 3]) << 24
        }
        let w = u32(5), h = u32(9), flags = bytes[13]
        guard w > 0, h > 0, w <= Self.mostPixels, h <= Self.mostPixels, w * h <= Self.mostPixels, flags & ~7 == 0
        else { throw CodingError.damaged }
        let mattes = (0..<3).filter { flags & (1 << $0) != 0 }.count
        let size = w * h
        guard bytes.count == 14 + size * (1 + mattes) else { throw CodingError.damaged }
        var at = 14
        func next() -> Grid<UInt8> {
            defer { at += size }
            return Grid(width: w, height: h, storage: Array(bytes[at..<(at + size)]))
        }
        let near = next()
        let sky = flags & 1 != 0 ? next() : nil
        let hair = flags & 2 != 0 ? next() : nil
        let skin = flags & 4 != 0 ? next() : nil
        guard let depth = PhotoDepth(nearness: near, sky: sky, hair: hair, skin: skin) else { throw CodingError.damaged }
        self = depth
    }
}
