/// A finished paint-by-numbers template: palette, regions, vector boundaries, a GPU-ready
/// fill mesh, label placements and a raster region map for hit testing.
///
/// Coordinates are in *canvas units*: one unit is one pixel of the working-resolution
/// image the template was segmented from, origin top-left, +y down. Everything is stored
/// as flat arrays with index spans so it can be uploaded to Metal buffers directly and
/// serialized quickly.
public struct Template: Sendable, Equatable {
    /// Binary layout written by `encoded()`. Every version ever written stays readable:
    /// 1 = the original layout; 2 = the version-1 payload followed by extension chunks (see
    /// `TemplateCoding.swift`), so later additions need no new version.
    public static let formatVersion: UInt32 = 2
    /// Largest canvas (`width * height`) the decoder accepts. The generator caps the long side
    /// at 2100 units (≈ 3 M cells); the headroom is for `pbn trace` of large flat images, and
    /// the cap keeps a damaged size field from allocating gigabytes.
    public static let maxCanvasArea = 64_000_000
    /// Grid all boundary coordinates are snapped to, canvas units.
    public static let coordinateQuantum: Float = 1.0 / 256

    /// Canvas size in units.
    public var width: Int
    public var height: Int
    /// Primaries of `PaletteColor.rgb`.
    public var colorSpace: RGBColorSpace

    /// Paint colors. The number shown to the user for color `i` is `i + 1`.
    public var palette: [PaletteColor]
    /// Paintable regions. A region is one connected area of a single palette color.
    public var regions: [Region]

    /// Shared polyline vertices for all boundary edges. Coordinates are exact multiples of
    /// `coordinateQuantum`, so geometric predicates on them can be evaluated exactly.
    /// Like every coordinate in a template (mesh vertices, label positions) they lie inside
    /// the canvas, `0...width` × `0...height`: the decoder enforces it, and
    /// `GeometryValidator` relies on it to size its fixed-point grid.
    public var points: [SIMD2<Float>]
    /// Boundary edges: maximal polylines separating exactly two regions (or a region and
    /// the canvas border). Shared by both neighbours, so fills never crack or overlap.
    /// Together they form a planar subdivision of the canvas: edges meet only at their
    /// end points (junctions) and never cross or touch elsewhere.
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

    /// `TemplateGenerator.pipelineVersion` that produced the template; 0 = unknown
    /// (format-1 files, templates built outside the generator such as `pbn trace`).
    public var pipelineVersion: UInt32

    public init(
        width: Int, height: Int, colorSpace: RGBColorSpace,
        palette: [PaletteColor], regions: [Region],
        points: [SIMD2<Float>], edges: [BoundaryEdge], ringEdges: [EdgeRef], rings: [Ring],
        labels: [Label], mesh: FillMesh, regionMap: RegionMap, pipelineVersion: UInt32 = 0
    ) {
        self.width = width; self.height = height; self.colorSpace = colorSpace
        self.palette = palette; self.regions = regions
        self.points = points; self.edges = edges; self.ringEdges = ringEdges; self.rings = rings
        self.labels = labels; self.mesh = mesh; self.regionMap = regionMap
        self.pipelineVersion = pipelineVersion
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
    /// Area of the (smoothed) polygon in square canvas units.
    public var area: Float
    /// Integer bounding box of the (smoothed) polygon in canvas units.
    public var bounds: PixelBounds
    /// Radius of the largest inscribed disc of the polygon (≈ how big a number fits); the
    /// primary label sits at its centre.
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
///
/// **Orientation.** For a step from point `p` to the next point `q`, `left` is the region
/// on the side where `cross(q − p, x − p) > 0`, with `cross(a, b) = a.x·b.y − a.y·b.x`
/// evaluated on raw canvas coordinates (x right, y down). Equivalently: `left` is the
/// region whose rings traverse the edge forwards, and every ring has positive signed
/// (shoelace) area `½ Σ (xᵢ·yᵢ₊₁ − xᵢ₊₁·yᵢ)` when it is an outer ring and negative when it is
/// a hole. On screen (y down) outer rings therefore run **clockwise** and `left` is on the
/// walker's *right-hand* side; in a y-up frame they run counter-clockwise with `left` on
/// the left. Example: an edge along the top canvas border running from (0, 0) to (w, 0)
/// has the region below it (+y) as `left` and `right == outside`.
///
/// Edges are stored with `left < right` (so canvas-border edges always have
/// `right == outside`). Junctions — lattice corners where three or more regions (counting
/// the outside) meet, or where two regions touch diagonally — are the end points of edges
/// and stay exactly on their integer lattice positions. An edge without any junction (the
/// boundary between a region and the single region enclosing it, or the canvas border of
/// a region touching no other region there) is *closed*: its last point repeats its first.
/// An edge may also start and end at the same junction; then too the first point repeats.
public struct BoundaryEdge: Sendable, Hashable {
    /// Sentinel neighbour meaning "outside the canvas".
    public static let outside: UInt32 = .max

    /// Region whose rings traverse this edge forwards (see the orientation note above).
    public var left: UInt32
    /// Region whose rings traverse this edge backwards, or `outside`.
    public var right: UInt32
    /// Span into `Template.points` (at least 2 points).
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

/// A closed boundary of a region, as a cycle of directed edges. The region is on the
/// `left` of every traversed edge, so outer rings have positive and holes negative signed
/// area (see `BoundaryEdge`). Consecutive edge references share their end points; a ring
/// is a simple polygon except that it may touch itself (or another ring of the region) at
/// a junction where the region meets itself diagonally.
public struct Ring: Sendable, Hashable {
    /// Span into `Template.ringEdges`.
    public var edgeStart: UInt32
    public var edgeCount: UInt32
    public var isHole: Bool

    public init(edgeStart: UInt32, edgeCount: UInt32, isHole: Bool) {
        self.edgeStart = edgeStart; self.edgeCount = edgeCount; self.isHole = isHole
    }
}

/// Where to draw a region's number. A region's first label sits at the pole of
/// inaccessibility of its polygon (the most spacious point); large regions get further
/// labels spread across them so a number stays in view when zoomed in.
public struct Label: Sendable, Hashable {
    /// Inside the canvas, like every template coordinate.
    public var position: SIMD2<Float>
    /// Radius of free space around `position`; the glyph run is sized to fit inside.
    public var radius: Float
    public var region: UInt32

    public init(position: SIMD2<Float>, radius: Float, region: UInt32) {
        self.position = position; self.radius = radius; self.region = region
    }
}

/// How big a region's number is drawn: the one sizing rule shared by SVG, the CoreGraphics
/// rasterizer (thumbnails, previews, PDF) and the Metal canvas, so they cannot drift apart.
///
/// A number's run of digits is fitted by its bounding-box diagonal (nominal digit metrics)
/// into the label's free disc, so a 3-digit number needs about twice the room of a 1-digit
/// one. The pipeline gives every label at least `minimumRadius(digits:)` of room, hence no
/// number is smaller than `minimumFontSize` whatever its digit count; renderers never drop a
/// number, they draw it at the floor instead (a region without a number cannot be painted).
public enum LabelSizing {
    /// Nominal digit advance and cap height, em. Real fonts (SF Rounded, Helvetica) are a
    /// little narrower; `fill` leaves the slack.
    public static let digitAdvance: Float = 0.6
    public static let digitHeight: Float = 0.72
    /// Share of the free disc's diameter the run's diagonal may take.
    public static let fill: Float = 0.85

    /// Free radius (canvas units) every 1-digit label is guaranteed; longer numbers get
    /// proportionally more (`minimumRadius(digits:)`). It is the smoothed-polygon tolerance
    /// (`SegmentationParameters.vectorRadiusTolerance`) times the smallest raster minimum,
    /// bounded by what a pixel-exact outline around a raster disc of that minimum clears
    /// (1.5·√2 ≈ 2.121 for 2.7): `LabelSizingTests.minimumRadiusIsAchievable` ties them together.
    public static let minimumRadius: Float = 2.12

    /// Decimal digits of a positive number (at least 1).
    public static func digitCount(of number: Int) -> Int {
        var digits = 1
        var rest = number / 10
        while rest != 0 { digits += 1; rest /= 10 }
        return digits
    }

    /// Digits of the number shown for palette index `colorIndex` (numbers start at 1).
    public static func digitCount(colorIndex: UInt32) -> Int { digitCount(of: Int(colorIndex) + 1) }

    /// Diagonal of a run of `digits` digits at 1 em.
    static func runDiagonal(digits: Int) -> Float {
        let w = digitAdvance * Float(max(digits, 1)), h = digitHeight
        return (w * w + h * h).squareRoot()
    }

    /// How much more room than a single digit a run of `digits` digits needs at the same size.
    public static func roomFactor(digits: Int) -> Float { runDiagonal(digits: digits) / runDiagonal(digits: 1) }

    /// Free radius a label with `digits` digits is guaranteed.
    public static func minimumRadius(digits: Int) -> Float { minimumRadius * roomFactor(digits: digits) }

    /// Font size (canvas units) whose run of `digits` digits fits a free disc of `radius`.
    public static func fittedFontSize(radius: Float, digits: Int) -> Float {
        2 * radius * fill / runDiagonal(digits: digits)
    }

    /// The smallest size a number is drawn at: what a minimal label fits, for any digit count.
    public static var minimumFontSize: Float { fittedFontSize(radius: minimumRadius, digits: 1) }

    /// Size to draw a label's number at: fitted to its room, at most `maximum` (a renderer's
    /// cap for huge regions) and never below `minimumFontSize`, which wins over the cap.
    public static func fontSize(radius: Float, digits: Int, maximum: Float = .infinity) -> Float {
        max(min(fittedFontSize(radius: radius, digits: digits), maximum), minimumFontSize)
    }
}

/// Triangulated fills for all regions, ready for a single indexed draw call.
public struct FillMesh: Sendable, Equatable {
    /// Inside the canvas, like every template coordinate.
    public var vertices: [SIMD2<Float>]
    /// Owning region of each vertex (vertices are never shared between regions).
    public var vertexRegion: [UInt32]
    /// Triangle list indices into `vertices`. Triangles have positive signed area, like
    /// outer rings (clockwise on screen, y down). Each region's triangles exactly cover its
    /// polygon, using the same boundary coordinates as its neighbours'.
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
        points[Int(edge.pointStart)..<Int(edge.pointStart) + Int(edge.pointCount)]
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
        return labels[Int(r.labelStart)..<Int(r.labelStart) + Int(r.labelCount)]
    }

    /// Region under a canvas-space point, if inside the canvas.
    public func region(at point: SIMD2<Float>) -> Int? {
        let x = Int(point.x.rounded(.down)), y = Int(point.y.rounded(.down))
        guard regionMap.contains(x: x, y: y) else { return nil }
        return Int(regionMap[x, y])
    }
}
