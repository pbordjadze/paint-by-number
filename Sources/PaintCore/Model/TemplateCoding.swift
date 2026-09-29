import Foundation

/// Compact little-endian binary encoding of `Template`.
///
/// Templates carry hundreds of thousands of vertices, so JSON would be slow and large.
/// Arrays of trivial types are written as raw memory; the region map is run-length
/// encoded (it is piecewise constant, so this typically shrinks it ~50×).
extension Template {
    static let magic: UInt32 = 0x544E_4250  // "PBNT"

    public enum CodingError: Error, Equatable {
        case badMagic
        case unsupportedVersion(UInt32)
        case truncated
        case corrupt(String)
    }

    public func encoded() -> Data {
        var w = BinaryWriter()
        w.write(Template.magic)
        w.write(Template.formatVersion)
        w.write(Int32(width))
        w.write(Int32(height))
        w.write(colorSpace.rawValue)

        w.write(UInt32(palette.count))
        for c in palette {
            w.write(c.oklab.x); w.write(c.oklab.y); w.write(c.oklab.z)
            w.write(c.rgb.x); w.write(c.rgb.y); w.write(c.rgb.z)
        }

        w.write(UInt32(regions.count))
        for r in regions {
            w.write(r.colorIndex); w.write(r.area)
            w.write(r.bounds.minX); w.write(r.bounds.minY); w.write(r.bounds.maxX); w.write(r.bounds.maxY)
            w.write(r.inscribedRadius)
            w.write(r.ringStart); w.write(r.ringCount)
            w.write(r.labelStart); w.write(r.labelCount)
            w.write(r.indexStart); w.write(r.indexCount)
        }

        w.writeArray(points)
        w.write(UInt32(edges.count))
        for e in edges { w.write(e.left); w.write(e.right); w.write(e.pointStart); w.write(e.pointCount) }
        w.writeArray(ringEdges.map { $0.edge | ($0.reversed ? 0x8000_0000 : 0) })
        w.write(UInt32(rings.count))
        for r in rings { w.write(r.edgeStart); w.write(r.edgeCount); w.write(UInt8(r.isHole ? 1 : 0)) }
        w.write(UInt32(labels.count))
        for l in labels { w.write(l.position.x); w.write(l.position.y); w.write(l.radius); w.write(l.region) }

        w.writeArray(mesh.vertices)
        w.writeArray(mesh.vertexRegion)
        w.writeArray(mesh.indices)

        // Region map, RLE: (value, runLength) pairs in raster order.
        var runs: [UInt32] = []
        regionMap.storage.withUnsafeBufferPointer { buf in
            var i = 0
            let n = buf.count
            while i < n {
                let v = buf[i]
                var j = i + 1
                while j < n && buf[j] == v { j += 1 }
                runs.append(v); runs.append(UInt32(j - i))
                i = j
            }
        }
        w.writeArray(runs)
        return w.data
    }

    public init(encoded data: Data) throws {
        var r = BinaryReader(data)
        guard try r.read(UInt32.self) == Template.magic else { throw CodingError.badMagic }
        let version = try r.read(UInt32.self)
        guard version == Template.formatVersion else { throw CodingError.unsupportedVersion(version) }
        let width = Int(try r.read(Int32.self))
        let height = Int(try r.read(Int32.self))
        guard width > 0, height > 0, width * height <= 64_000_000 else { throw CodingError.corrupt("size") }
        guard let space = RGBColorSpace(rawValue: try r.read(UInt8.self)) else { throw CodingError.corrupt("colorspace") }

        let paletteCount = Int(try r.read(UInt32.self))
        var palette: [PaletteColor] = []
        palette.reserveCapacity(paletteCount)
        for _ in 0..<paletteCount {
            let lab = SIMD3(try r.read(Float.self), try r.read(Float.self), try r.read(Float.self))
            let rgb = SIMD3(try r.read(Float.self), try r.read(Float.self), try r.read(Float.self))
            palette.append(PaletteColor(oklab: lab, rgb: rgb))
        }

        let regionCount = Int(try r.read(UInt32.self))
        var regions: [Region] = []
        regions.reserveCapacity(regionCount)
        for _ in 0..<regionCount {
            let colorIndex = try r.read(UInt32.self)
            let area = try r.read(Float.self)
            let bounds = PixelBounds(
                minX: try r.read(Int32.self), minY: try r.read(Int32.self),
                maxX: try r.read(Int32.self), maxY: try r.read(Int32.self))
            let inscribed = try r.read(Float.self)
            regions.append(Region(
                colorIndex: colorIndex, area: area, bounds: bounds, inscribedRadius: inscribed,
                ringStart: try r.read(UInt32.self), ringCount: try r.read(UInt32.self),
                labelStart: try r.read(UInt32.self), labelCount: try r.read(UInt32.self),
                indexStart: try r.read(UInt32.self), indexCount: try r.read(UInt32.self)))
        }

        let points: [SIMD2<Float>] = try r.readArray()
        let edgeCount = Int(try r.read(UInt32.self))
        var edges: [BoundaryEdge] = []
        edges.reserveCapacity(edgeCount)
        for _ in 0..<edgeCount {
            edges.append(BoundaryEdge(
                left: try r.read(UInt32.self), right: try r.read(UInt32.self),
                pointStart: try r.read(UInt32.self), pointCount: try r.read(UInt32.self)))
        }
        let packedRefs: [UInt32] = try r.readArray()
        let ringEdges = packedRefs.map { EdgeRef(edge: $0 & 0x7FFF_FFFF, reversed: $0 & 0x8000_0000 != 0) }
        let ringCount = Int(try r.read(UInt32.self))
        var rings: [Ring] = []
        rings.reserveCapacity(ringCount)
        for _ in 0..<ringCount {
            rings.append(Ring(edgeStart: try r.read(UInt32.self), edgeCount: try r.read(UInt32.self), isHole: try r.read(UInt8.self) != 0))
        }
        let labelCount = Int(try r.read(UInt32.self))
        var labels: [Label] = []
        labels.reserveCapacity(labelCount)
        for _ in 0..<labelCount {
            labels.append(Label(
                position: SIMD2(try r.read(Float.self), try r.read(Float.self)),
                radius: try r.read(Float.self), region: try r.read(UInt32.self)))
        }

        let mesh = FillMesh(vertices: try r.readArray(), vertexRegion: try r.readArray(), indices: try r.readArray())

        let runs: [UInt32] = try r.readArray()
        guard runs.count % 2 == 0 else { throw CodingError.corrupt("region map runs") }
        var map = [UInt32](repeating: 0, count: width * height)
        var pos = 0
        try map.withUnsafeMutableBufferPointer { out in
            var k = 0
            while k < runs.count {
                let v = runs[k], len = Int(runs[k + 1])
                guard pos + len <= out.count else { throw CodingError.corrupt("region map overflow") }
                for i in pos..<(pos + len) { out[i] = v }
                pos += len
                k += 2
            }
        }
        guard pos == width * height else { throw CodingError.corrupt("region map underflow") }

        // Structural validation so a corrupt file can never index out of bounds later.
        let pointCount = UInt32(points.count)
        for e in edges where e.pointStart &+ e.pointCount > pointCount || e.pointCount < 2 {
            throw CodingError.corrupt("edge span")
        }
        for ref in ringEdges where Int(ref.edge) >= edges.count { throw CodingError.corrupt("ring edge") }
        for ring in rings where Int(ring.edgeStart + ring.edgeCount) > ringEdges.count { throw CodingError.corrupt("ring span") }
        for region in regions {
            guard Int(region.colorIndex) < palette.count,
                  Int(region.ringStart + region.ringCount) <= rings.count,
                  Int(region.labelStart + region.labelCount) <= labels.count,
                  Int(region.indexStart + region.indexCount) <= mesh.indices.count
            else { throw CodingError.corrupt("region span") }
        }
        guard mesh.vertexRegion.count == mesh.vertices.count else { throw CodingError.corrupt("mesh") }
        let vertexCount = UInt32(mesh.vertices.count)
        for i in mesh.indices where i >= vertexCount { throw CodingError.corrupt("mesh index") }
        for v in map where Int(v) >= regions.count { throw CodingError.corrupt("region map value") }
        for l in labels where Int(l.region) >= regions.count { throw CodingError.corrupt("label region") }

        self.init(
            width: width, height: height, colorSpace: space, palette: palette, regions: regions,
            points: points, edges: edges, ringEdges: ringEdges, rings: rings, labels: labels,
            mesh: mesh, regionMap: RegionMap(width: width, height: height, storage: map))
    }
}

// MARK: - Binary IO

struct BinaryWriter {
    var data = Data()

    mutating func write<T: BitwiseCopyable>(_ value: T) {
        withUnsafeBytes(of: value) { data.append(contentsOf: $0) }
    }

    mutating func writeArray<T: BitwiseCopyable>(_ values: [T]) {
        write(UInt32(values.count))
        values.withUnsafeBytes { data.append(contentsOf: $0) }
    }
}

struct BinaryReader {
    let data: Data
    var offset: Int

    init(_ data: Data) {
        self.data = data
        self.offset = data.startIndex
    }

    mutating func read<T: BitwiseCopyable>(_: T.Type) throws -> T {
        let size = MemoryLayout<T>.size
        guard offset + size <= data.endIndex else { throw Template.CodingError.truncated }
        let value = data.withUnsafeBytes { raw in
            raw.loadUnaligned(fromByteOffset: offset - data.startIndex, as: T.self)
        }
        offset += size
        return value
    }

    mutating func readArray<T: BitwiseCopyable>() throws -> [T] {
        let count = Int(try read(UInt32.self))
        let stride = MemoryLayout<T>.stride
        let bytes = count * stride
        guard count >= 0, offset + bytes <= data.endIndex else { throw Template.CodingError.truncated }
        let result = [T](unsafeUninitializedCapacity: count) { buf, initialized in
            data.withUnsafeBytes { raw in
                let src = UnsafeRawBufferPointer(rebasing: raw[(offset - data.startIndex)..<(offset - data.startIndex + bytes)])
                UnsafeMutableRawBufferPointer(buf).copyMemory(from: src)
            }
            initialized = count
        }
        offset += bytes
        return result
    }
}
