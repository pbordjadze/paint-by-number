import Foundation

/// Compact little-endian binary encoding of `Template`.
///
/// Templates carry hundreds of thousands of vertices, so JSON would be slow and large.
/// Arrays of trivial types are written as raw memory; the region map is run-length
/// encoded (it is piecewise constant, so this typically shrinks it ~50×).
///
/// **Versions.** A file starts with the magic "PBNT" and a `UInt32` format version. Saved
/// paintings must open forever, so every version ever written stays readable:
/// - 1: the original payload (`readPayloadV1`, frozen).
/// - 2: the version-1 payload unchanged, followed by an extension section:
///   ```
///   UInt32 chunkCount
///   repeat chunkCount:
///       UInt32 tag      FourCC stored little-endian, so the bytes read e.g. "GENR"
///       UInt32 flags    bit 0 = required
///       UInt32 length
///       length bytes of payload
///   ```
///   Nothing may follow the last chunk.
///
/// **Extension chunks** carry every later addition, so adding data needs no new version.
/// Readers skip unknown chunks unless they are flagged required (then the file needs a newer
/// reader: `CodingError.requiredExtension`); other flag bits are ignored. A known chunk's
/// fields are read as a prefix of its payload, so a chunk may grow by appending fields; a
/// payload shorter than the fields a reader knows, or a known chunk appearing twice, is
/// corrupt. Chunks defined so far:
/// - `GENR`: `UInt32 pipelineVersion` (see `Template.pipelineVersion`).
/// - `LINE` (optional; layered templates only, see `Template.lineArt`):
///   ```
///   UInt32 edgeCount            equal to the template's edge count
///   edgeCount × UInt8 layer     LineLayer raw value per edge
///   edgeCount × UInt8 weight
///   UInt32 pointCount
///   pointCount × (Float32 x, Float32 y)    interior stroke vertices, inside the canvas
///   UInt32 strokeCount
///   strokeCount × (UInt32 pointStart, UInt32 pointCount, UInt8 layer, UInt8 weight, UInt32 region)
///   ```
///   Readers without it draw every edge alike, which is the classic look of the same cells.
///
/// **Safety.** PaintCore is compiled with `-Ounchecked`, so the decoder checks every count
/// against the bytes left before allocating, and every span, reference and coordinate in
/// `Int` arithmetic (`validateReferences`), before anything can index with them.
extension Template {
    static let magic: UInt32 = 0x544E_4250  // "PBNT"

    public enum CodingError: Error, Equatable {
        case badMagic
        /// Written by a newer encoder: the file's format version is above `Template.formatVersion`.
        case newerFormat(UInt32)
        /// The file needs an extension chunk this reader does not know (its FourCC tag).
        case requiredExtension(UInt32)
        case truncated
        case corrupt(String)

        /// The file is not damaged; a newer app can read it.
        public var requiresNewerReader: Bool {
            switch self {
            case .newerFormat, .requiredExtension: true
            case .badMagic, .truncated, .corrupt: false
            }
        }
    }

    enum Chunk {
        static let generator: UInt32 = 0x524E_4547  // "GENR"
        static let lines: UInt32 = 0x454E_494C  // "LINE"
        static let requiredFlag: UInt32 = 1
        /// Tag, flags and length.
        static let headerSize = 12

        static func name(_ tag: UInt32) -> String {
            let bytes = withUnsafeBytes(of: tag.littleEndian) { Array($0) }
            return bytes.allSatisfy { (0x20..<0x7F).contains($0) }
                ? String(decoding: bytes, as: UTF8.self)
                : "0x" + String(tag, radix: 16)
        }
    }

    public func encoded() -> Data {
        var w = BinaryWriter()
        w.write(Template.magic)
        w.write(Template.formatVersion)
        writePayloadV1(&w)

        var generator = BinaryWriter()
        generator.write(pipelineVersion)
        var chunks: [(tag: UInt32, flags: UInt32, payload: Data)] = [(Chunk.generator, 0, generator.data)]
        if let lineArt { chunks.append((Chunk.lines, 0, lineArt.encoded())) }
        w.write(UInt32(chunks.count))
        for chunk in chunks {
            w.write(chunk.tag)
            w.write(chunk.flags)
            w.write(UInt32(chunk.payload.count))
            w.write(bytes: chunk.payload)
        }
        return w.data
    }

    public init(encoded data: Data) throws {
        var r = BinaryReader(data)
        guard try r.read(UInt32.self) == Template.magic else { throw CodingError.badMagic }
        let version = try r.read(UInt32.self)
        guard version != 0 else { throw CodingError.corrupt("version") }
        guard version <= Template.formatVersion else { throw CodingError.newerFormat(version) }
        var template = try Template.readPayloadV1(&r)
        if version >= 2 {
            try template.readExtensions(&r)
            guard r.isAtEnd else { throw CodingError.corrupt("trailing bytes") }
        }
        try template.validateReferences()
        self = template
    }

    private func writePayloadV1(_ w: inout BinaryWriter) {
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
    }

    /// Frozen: the format-1 layout. Never change what it reads; later formats extend it with
    /// chunks. Checks only what it needs to allocate safely; `validateReferences` does the rest.
    private static func readPayloadV1(_ r: inout BinaryReader) throws -> Template {
        let width = Int(try r.read(Int32.self))
        let height = Int(try r.read(Int32.self))
        guard width > 0, height > 0, width * height <= Template.maxCanvasArea else { throw CodingError.corrupt("size") }
        guard let space = RGBColorSpace(rawValue: try r.read(UInt8.self)) else { throw CodingError.corrupt("colorspace") }

        let paletteCount = try r.readCount(elementSize: 24)
        var palette: [PaletteColor] = []
        palette.reserveCapacity(paletteCount)
        for _ in 0..<paletteCount {
            let lab = SIMD3(try r.read(Float.self), try r.read(Float.self), try r.read(Float.self))
            let rgb = SIMD3(try r.read(Float.self), try r.read(Float.self), try r.read(Float.self))
            palette.append(PaletteColor(oklab: lab, rgb: rgb))
        }

        let regionCount = try r.readCount(elementSize: 52)
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
        let edgeCount = try r.readCount(elementSize: 16)
        var edges: [BoundaryEdge] = []
        edges.reserveCapacity(edgeCount)
        for _ in 0..<edgeCount {
            edges.append(BoundaryEdge(
                left: try r.read(UInt32.self), right: try r.read(UInt32.self),
                pointStart: try r.read(UInt32.self), pointCount: try r.read(UInt32.self)))
        }
        let packedRefs: [UInt32] = try r.readArray()
        let ringEdges = packedRefs.map { EdgeRef(edge: $0 & 0x7FFF_FFFF, reversed: $0 & 0x8000_0000 != 0) }
        let ringCount = try r.readCount(elementSize: 9)
        var rings: [Ring] = []
        rings.reserveCapacity(ringCount)
        for _ in 0..<ringCount {
            rings.append(Ring(edgeStart: try r.read(UInt32.self), edgeCount: try r.read(UInt32.self), isHole: try r.read(UInt8.self) != 0))
        }
        let labelCount = try r.readCount(elementSize: 16)
        var labels: [Label] = []
        labels.reserveCapacity(labelCount)
        for _ in 0..<labelCount {
            labels.append(Label(
                position: SIMD2(try r.read(Float.self), try r.read(Float.self)),
                radius: try r.read(Float.self), region: try r.read(UInt32.self)))
        }

        let mesh = FillMesh(vertices: try r.readArray(), vertexRegion: try r.readArray(), indices: try r.readArray())

        // The runs must tile the canvas exactly before the map is allocated: a damaged size
        // field must not cost `width * height` cells.
        let runs: [UInt32] = try r.readArray()
        guard runs.count % 2 == 0 else { throw CodingError.corrupt("region map runs") }
        let cells = width * height
        var total = 0
        for k in stride(from: 0, to: runs.count, by: 2) {
            guard Int(runs[k]) < regions.count else { throw CodingError.corrupt("region map value") }
            total += Int(runs[k + 1])
            guard total <= cells else { throw CodingError.corrupt("region map overflow") }
        }
        guard total == cells else { throw CodingError.corrupt("region map underflow") }
        let map = [UInt32](unsafeUninitializedCapacity: cells) { out, initialized in
            var pos = 0
            for k in stride(from: 0, to: runs.count, by: 2) {
                let length = Int(runs[k + 1])
                (out.baseAddress! + pos).initialize(repeating: runs[k], count: length)
                pos += length
            }
            initialized = pos
        }

        return Template(
            width: width, height: height, colorSpace: space, palette: palette, regions: regions,
            points: points, edges: edges, ringEdges: ringEdges, rings: rings, labels: labels,
            mesh: mesh, regionMap: RegionMap(width: width, height: height, storage: map))
    }

    private mutating func readExtensions(_ r: inout BinaryReader) throws {
        let count = try r.readCount(elementSize: Chunk.headerSize)
        var seen = Set<UInt32>()
        for _ in 0..<count {
            let tag = try r.read(UInt32.self)
            let flags = try r.read(UInt32.self)
            var payload = BinaryReader(try r.readBytes(Int(try r.read(UInt32.self))))
            switch tag {
            case Chunk.generator:
                guard seen.insert(tag).inserted else { throw CodingError.corrupt("duplicate chunk") }
                guard let version = try? payload.read(UInt32.self) else { throw CodingError.corrupt(Chunk.name(tag)) }
                pipelineVersion = version
            case Chunk.lines:
                guard seen.insert(tag).inserted else { throw CodingError.corrupt("duplicate chunk") }
                do {
                    lineArt = try TemplateLineArt(&payload, edgeCount: edges.count)
                } catch let error as CodingError {
                    if case .corrupt = error { throw error }
                    throw CodingError.corrupt(Chunk.name(tag))
                }
            default:
                if flags & Chunk.requiredFlag != 0 { throw CodingError.requiredExtension(tag) }
            }
        }
    }

    /// Every index, span and coordinate the accessors, `validate()` and the app's renderers
    /// rely on. Arithmetic is in `Int`, so crafted `UInt32` spans cannot wrap.
    func validateReferences() throws {
        func corrupt(_ what: String) -> CodingError { .corrupt(what) }
        let w = Float(width), h = Float(height)
        // Also false for NaN, so this subsumes finiteness.
        func inCanvas(_ p: SIMD2<Float>) -> Bool { p.x >= 0 && p.x <= w && p.y >= 0 && p.y <= h }
        func isFinite(_ v: SIMD3<Float>) -> Bool { v.x.isFinite && v.y.isFinite && v.z.isFinite }

        guard palette.allSatisfy({ isFinite($0.oklab) && isFinite($0.rgb) }) else { throw corrupt("palette") }
        guard points.allSatisfy(inCanvas) else { throw corrupt("point") }
        guard mesh.vertices.allSatisfy(inCanvas) else { throw corrupt("mesh vertex") }

        for e in edges {
            guard e.pointCount >= 2, Int(e.pointStart) + Int(e.pointCount) <= points.count else { throw corrupt("edge span") }
            guard Int(e.left) < regions.count, e.right == BoundaryEdge.outside || Int(e.right) < regions.count
            else { throw corrupt("edge side") }
        }
        guard ringEdges.allSatisfy({ Int($0.edge) < edges.count }) else { throw corrupt("ring edge") }
        guard rings.allSatisfy({ Int($0.edgeStart) + Int($0.edgeCount) <= ringEdges.count }) else { throw corrupt("ring span") }

        for region in regions {
            guard Int(region.colorIndex) < palette.count else { throw corrupt("region color") }
            guard Int(region.ringStart) + Int(region.ringCount) <= rings.count,
                  Int(region.labelStart) + Int(region.labelCount) <= labels.count,
                  Int(region.indexStart) + Int(region.indexCount) <= mesh.indices.count,
                  region.indexCount % 3 == 0
            else { throw corrupt("region span") }
            guard region.area.isFinite, region.inscribedRadius.isFinite else { throw corrupt("region metrics") }
            let b = region.bounds
            // The vectorizer emits `.empty` for a region without an outer ring.
            guard b == .empty
                || (0 <= b.minX && b.minX <= b.maxX && Int(b.maxX) <= width
                    && 0 <= b.minY && b.minY <= b.maxY && Int(b.maxY) <= height)
            else { throw corrupt("region bounds") }
        }

        for l in labels {
            guard Int(l.region) < regions.count, l.radius.isFinite, inCanvas(l.position) else { throw corrupt("label") }
        }

        guard mesh.vertexRegion.count == mesh.vertices.count,
              mesh.vertexRegion.allSatisfy({ Int($0) < regions.count })
        else { throw corrupt("mesh vertex region") }
        let vertexCount = mesh.vertices.count
        guard mesh.indices.count % 3 == 0, mesh.indices.allSatisfy({ Int($0) < vertexCount }) else { throw corrupt("mesh index") }

        if let lineArt {
            let layers = UInt8(LineLayer.allCases.count)
            guard lineArt.edgeLayers.count == edges.count, lineArt.edgeWeights.count == edges.count,
                  lineArt.edgeLayers.allSatisfy({ $0 < layers })
            else { throw corrupt("line edges") }
            guard lineArt.strokePoints.allSatisfy(inCanvas) else { throw corrupt("line point") }
            for stroke in lineArt.strokes {
                guard stroke.pointCount >= 2, Int(stroke.pointStart) + Int(stroke.pointCount) <= lineArt.strokePoints.count,
                      stroke.layer < layers, Int(stroke.region) < regions.count
                else { throw corrupt("line stroke") }
            }
        }
    }
}

extension TemplateLineArt {
    /// The `LINE` chunk's payload.
    func encoded() -> Data {
        var w = BinaryWriter()
        w.write(UInt32(edgeLayers.count))
        w.write(bytes: Data(edgeLayers))
        w.write(bytes: Data(edgeWeights))
        w.writeArray(strokePoints)
        w.write(UInt32(strokes.count))
        for s in strokes {
            w.write(s.pointStart); w.write(s.pointCount); w.write(s.layer); w.write(s.weight); w.write(s.region)
        }
        return w.data
    }

    /// Reads a `LINE` payload (trailing fields of a later writer are ignored). Spans and
    /// values are checked by `Template.validateReferences`.
    init(_ r: inout BinaryReader, edgeCount: Int) throws {
        let count = try r.readCount(elementSize: 2)
        guard count == edgeCount else { throw Template.CodingError.corrupt("LINE edge count") }
        edgeLayers = Array(try r.readBytes(count))
        edgeWeights = Array(try r.readBytes(count))
        strokePoints = try r.readArray()
        let strokeCount = try r.readCount(elementSize: 14)
        var strokes: [InteriorStroke] = []
        strokes.reserveCapacity(strokeCount)
        for _ in 0..<strokeCount {
            strokes.append(InteriorStroke(
                pointStart: try r.read(UInt32.self), pointCount: try r.read(UInt32.self),
                layer: try r.read(UInt8.self), weight: try r.read(UInt8.self), region: try r.read(UInt32.self)))
        }
        self.strokes = strokes
    }
}

// MARK: - Binary IO

struct BinaryWriter {
    var data = Data()

    mutating func write<T: BitwiseCopyable>(_ value: T) {
        withUnsafeBytes(of: value) { data.append(contentsOf: $0) }
    }

    mutating func write(bytes: Data) {
        data.append(bytes)
    }

    mutating func writeArray<T: BitwiseCopyable>(_ values: [T]) {
        write(UInt32(values.count))
        values.withUnsafeBytes { data.append(contentsOf: $0) }
    }
}

/// Reads from any `Data`, including slices (offsets are absolute indices into `data`).
struct BinaryReader {
    let data: Data
    var offset: Int

    init(_ data: Data) {
        self.data = data
        self.offset = data.startIndex
    }

    var remaining: Int { data.endIndex - offset }
    var isAtEnd: Bool { offset == data.endIndex }

    mutating func read<T: BitwiseCopyable>(_: T.Type) throws -> T {
        let size = MemoryLayout<T>.size
        guard size <= remaining else { throw Template.CodingError.truncated }
        let value = data.withUnsafeBytes { raw in
            raw.loadUnaligned(fromByteOffset: offset - data.startIndex, as: T.self)
        }
        offset += size
        return value
    }

    /// An element count that the remaining bytes can hold at `elementSize` bytes each, so a
    /// damaged count throws instead of reserving gigabytes.
    mutating func readCount(elementSize: Int) throws -> Int {
        let count = Int(try read(UInt32.self))
        guard count <= remaining / elementSize else { throw Template.CodingError.truncated }
        return count
    }

    mutating func readBytes(_ count: Int) throws -> Data {
        guard count <= remaining else { throw Template.CodingError.truncated }
        defer { offset += count }
        return data[offset..<(offset + count)]
    }

    mutating func readArray<T: BitwiseCopyable>() throws -> [T] {
        let stride = MemoryLayout<T>.stride
        let count = try readCount(elementSize: stride)
        let bytes = count * stride
        let start = offset - data.startIndex
        let result = [T](unsafeUninitializedCapacity: count) { buf, initialized in
            data.withUnsafeBytes { raw in
                UnsafeMutableRawBufferPointer(buf).copyMemory(from: UnsafeRawBufferPointer(rebasing: raw[start..<(start + bytes)]))
            }
            initialized = count
        }
        offset += bytes
        return result
    }
}
