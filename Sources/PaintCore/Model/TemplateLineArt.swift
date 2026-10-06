/// The strength class of a line of the drawing (`LayeredLines`). A coloring book draws
/// `outline`, `detail` and `texture` alike and `color` not at all.
public enum LineLayer: UInt8, Sendable, CaseIterable {
    /// Strong edges and eyes; only these split same-paint cells by default.
    case outline = 0
    /// Weaker edges.
    case detail = 1
    /// The weakest drawn edges, which only the retired layered style made.
    case texture = 2
    /// A boundary where only the paint changes and nothing is drawn (banded skies, shading).
    case color = 3
}

/// Line data of a template made from an edge map: which edges are lines of the drawing, in
/// which layer, and the lines drawn inside cells. `style` says how renderers draw it.
public struct TemplateLineArt: Sendable, Equatable {
    /// How a template's line art is drawn, in every renderer (canvas, pictures, print, SVG).
    /// Stored with the template, so a painting looks the same whatever the settings are later.
    public enum Style: UInt8, Sendable, CaseIterable {
        /// Made by the retired layered style, which faded each layer in as the painter zoomed.
        /// Saved paintings keep it; every renderer draws it as a coloring book.
        case layered = 0
        /// A coloring book: every drawn layer (`outline`, `detail`, `texture`) alike, in full ink
        /// and heavy at every zoom, over the paint for good; `color` edges are never drawn, so the
        /// areas inside an outline are told apart only by their numbers and by the highlight of
        /// the selected color, which is never outlined. On paper, where there is no highlight,
        /// color edges print as faint dotted guides.
        case coloringBook = 1
    }

    /// `LineLayer` raw value per `Template.edges` entry.
    public var edgeLayers: [UInt8]
    /// Strength per edge (0...255): its line's, or for a color edge the paint difference.
    public var edgeWeights: [UInt8]
    /// Shared vertices of `strokes`, inside the canvas and on `Template.coordinateQuantum`.
    public var strokePoints: [SIMD2<Float>]
    /// Lines drawn inside a cell: between two cells of the same paint that were joined (see
    /// `LineArtSettings.SamePaint`), or in a coloring book any stretch of the drawing that bounds
    /// no cell (a crease, a strand of fur).
    public var strokes: [InteriorStroke]
    public var style: Style

    public init(
        edgeLayers: [UInt8], edgeWeights: [UInt8], strokePoints: [SIMD2<Float>] = [], strokes: [InteriorStroke] = [],
        style: Style = .layered
    ) {
        self.edgeLayers = edgeLayers
        self.edgeWeights = edgeWeights
        self.strokePoints = strokePoints
        self.strokes = strokes
        self.style = style
    }
}

/// A polyline drawn inside one region (one that closes on itself, such as an eye's contour
/// inside a single cell, repeats its first point at the end).
public struct InteriorStroke: Sendable, Hashable {
    /// Span into `TemplateLineArt.strokePoints` (at least 2 points).
    public var pointStart: UInt32
    public var pointCount: UInt32
    /// `LineLayer` raw value.
    public var layer: UInt8
    /// Strength, 0...255.
    public var weight: UInt8
    /// The region the stroke lies in.
    public var region: UInt32

    public init(pointStart: UInt32, pointCount: UInt32, layer: UInt8, weight: UInt8, region: UInt32) {
        self.pointStart = pointStart; self.pointCount = pointCount
        self.layer = layer; self.weight = weight; self.region = region
    }
}
