/// A finished paint-by-numbers template: palette, regions, vector boundaries, a GPU-ready
/// fill mesh, label placements and a raster region map for hit testing.
///
/// Coordinates are in *canvas units*: one unit is one pixel of the working-resolution
/// image the template was segmented from, origin top-left, +y down. Everything is stored
/// as flat arrays with index spans so it can be uploaded to Metal buffers directly and
/// serialized quickly.
public struct Template: Sendable, Equatable {
    public static let formatVersion: UInt32 = 1

    /// Canvas size in units.
    public var width: Int
    public var height: Int
    /// Primaries of `PaletteColor.rgb`.
    public var colorSpace: RGBColorSpace

    /// Paint colors. The number shown to the user for color `i` is `i + 1`.
    public var palette: [PaletteColor]
    /// Paintable regions. A region is one connected area of a single palette color.
    public var regions: [Region]

    /// Shared polyline vertices for all boundary edges.
    public var points: [SIMD2<Float>]
    /// Boundary edges: maximal polylines separating exactly two regions (or a region and
    /// the canvas border). Shared by both neighbours, so fills never crack or overlap.
    public var edges: [BoundaryEdge]
    /// Edge references forming region rings, grouped per ring.
    public var ringEdges: [EdgeRef]
    /// Rings (outer boundaries and holes) of regions, grouped per region.
    public var rings: [Ring]

    /// Number placements, grouped per region.
    public var labels: [Label]

    /// Triangulated region fills.
    public var mesh: FillMesh

    /// Region index per canvas unit (`width * height`), for hit testing.
    public var regionMap: RegionMap

    public init(
        width: Int, height: Int, colorSpace: RGBColorSpace,
        palette: [PaletteColor], regions: [Region],
        points: [SIMD2<Float>], edges: [BoundaryEdge], ringEdges: [EdgeRef], rings: [Ring],
        labels: [Label], mesh: FillMesh, regionMap: RegionMap
    ) {
        self.width = width; self.height = height; self.colorSpace = colorSpace
        self.palette = palette; self.regions = regions
        self.points = points; self.edges = edges; self.ringEdges = ringEdges; self.rings = rings
        self.labels = labels; self.mesh = mesh; self.regionMap = regionMap
    }
}

public struct PaletteColor: Sendable, Hashable, Codable {
    /// Perceptual coordinates (L, a, b).
    public var oklab: SIMD3<Float>
    /// Gamma-encoded RGB (0...1) in the template's color space, in gamut.
    public var rgb: SIMD3<Float>

    public init(oklab: SIMD3<Float>, rgb: SIMD3<Float>) {
        self.oklab = oklab
        self.rgb = rgb
    }

    public init(oklab: SIMD3<Float>, space: RGBColorSpace) {
        self.oklab = oklab
        self.rgb = ColorScience.okLabToEncoded(oklab, space: space)
    }
}

public struct Region: Sendable, Hashable {
    /// Palette index.
    public var colorIndex: UInt32
    /// Area in square canvas units.
    public var area: Float
    /// Bounding box in canvas units.
    public var bounds: PixelBounds
    /// Radius of the largest inscribed disc (≈ how big a number fits).
    public var inscribedRadius: Float
    /// Span into `Template.rings` (first ring is the outer boundary; others are holes).
    public var ringStart: UInt32
    public var ringCount: UInt32
    /// Span into `Template.labels` (first label is the primary one).
    public var labelStart: UInt32
    public var labelCount: UInt32
    /// Span into `Template.mesh.indices` (a multiple of 3).
    public var indexStart: UInt32
    public var indexCount: UInt32

    public init(
        colorIndex: UInt32, area: Float, bounds: PixelBounds, inscribedRadius: Float,
        ringStart: UInt32 = 0, ringCount: UInt32 = 0, labelStart: UInt32 = 0, labelCount: UInt32 = 0,
        indexStart: UInt32 = 0, indexCount: UInt32 = 0
    ) {
        self.colorIndex = colorIndex; self.area = area; self.bounds = bounds
        self.inscribedRadius = inscribedRadius
        self.ringStart = ringStart; self.ringCount = ringCount
        self.labelStart = labelStart; self.labelCount = labelCount
        self.indexStart = indexStart; self.indexCount = indexCount
    }
}

/// A polyline separating two regions.
public struct BoundaryEdge: Sendable, Hashable {
    /// Sentinel neighbour meaning "outside the canvas".
    public static let outside: UInt32 = .max

    /// Region on the left when walking the points in order (y down), i.e. the region
    /// whose outer ring traverses this edge forwards when rings are counter-clockwise
    /// in a y-up frame.
    public var left: UInt32
    /// Region on the right, or `outside`.
    public var right: UInt32
    /// Span into `Template.points`. Closed loops repeat their first point at the end.
    public var pointStart: UInt32
    public var pointCount: UInt32

    public init(left: UInt32, right: UInt32, pointStart: UInt32, pointCount: UInt32) {
        self.left = left; self.right = right
        self.pointStart = pointStart; self.pointCount = pointCount
    }
}

/// A directed reference to an edge within a ring.
public struct EdgeRef: Sendable, Hashable {
    public var edge: UInt32
    public var reversed: Bool

    public init(edge: UInt32, reversed: Bool) {
        self.edge = edge; self.reversed = reversed
    }
}

public struct Ring: Sendable, Hashable {
    /// Span into `Template.ringEdges`.
    public var edgeStart: UInt32
    public var edgeCount: UInt32
    public var isHole: Bool

    public init(edgeStart: UInt32, edgeCount: UInt32, isHole: Bool) {
        self.edgeStart = edgeStart; self.edgeCount = edgeCount; self.isHole = isHole
    }
}

/// Where to draw a region's number.
public struct Label: Sendable, Hashable {
    public var position: SIMD2<Float>
    /// Radius of free space around `position`; the glyph run is sized to fit inside.
    public var radius: Float
    public var region: UInt32

    public init(position: SIMD2<Float>, radius: Float, region: UInt32) {
        self.position = position; self.radius = radius; self.region = region
    }
}

/// Triangulated fills for all regions, ready for a single indexed draw call.
public struct FillMesh: Sendable, Equatable {
    public var vertices: [SIMD2<Float>]
    /// Owning region of each vertex (vertices are never shared between regions).
    public var vertexRegion: [UInt32]
    /// Triangle list indices into `vertices`.
    public var indices: [UInt32]

    public init(vertices: [SIMD2<Float>] = [], vertexRegion: [UInt32] = [], indices: [UInt32] = []) {
        self.vertices = vertices; self.vertexRegion = vertexRegion; self.indices = indices
    }
}

// MARK: - Convenience accessors

extension Template {
    public var regionCount: Int { regions.count }

    /// Number of regions per palette color.
    public var regionCountsByColor: [Int] {
        var counts = [Int](repeating: 0, count: palette.count)
        for r in regions { counts[Int(r.colorIndex)] += 1 }
        return counts
    }

    /// Points of an edge in storage order.
    public func points(of edge: BoundaryEdge) -> ArraySlice<SIMD2<Float>> {
        points[Int(edge.pointStart)..<Int(edge.pointStart + edge.pointCount)]
    }

    /// The closed polygon of a ring as a point list (first point not repeated).
    public func polygon(of ring: Ring) -> [SIMD2<Float>] {
        var out: [SIMD2<Float>] = []
        for k in 0..<Int(ring.edgeCount) {
            let ref = ringEdges[Int(ring.edgeStart) + k]
            let pts = points(of: edges[Int(ref.edge)])
            if ref.reversed {
                for p in pts.reversed().dropLast() { out.append(p) }
            } else {
                for p in pts.dropLast() { out.append(p) }
            }
        }
        return out
    }

    /// All rings of a region as polygons; the first is the outer boundary.
    public func polygons(ofRegion index: Int) -> [[SIMD2<Float>]] {
        let r = regions[index]
        return (0..<Int(r.ringCount)).map { polygon(of: rings[Int(r.ringStart) + $0]) }
    }

    /// Labels belonging to a region.
    public func labels(ofRegion index: Int) -> ArraySlice<Label> {
        let r = regions[index]
        return labels[Int(r.labelStart)..<Int(r.labelStart + r.labelCount)]
    }

    /// Region under a canvas-space point, if inside the canvas.
    public func region(at point: SIMD2<Float>) -> Int? {
        let x = Int(point.x.rounded(.down)), y = Int(point.y.rounded(.down))
        guard regionMap.contains(x: x, y: y) else { return nil }
        return Int(regionMap[x, y])
    }
}
