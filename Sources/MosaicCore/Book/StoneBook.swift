import Foundation
import MosaicKit

/// Set in Stone (painting-company row 367): the book for setting a mosaic of the app's in real
/// stone, by the mesh method, and the stones to buy. Paint by Mosaic's counterpart to Paint by
/// Moonlight's print layout.
///
/// The mosaic is set at true size: its median tile has the face `Options.tileFace` asks (a
/// hand-cut smalto is about 17 × 10 mm, 1.5 cm²). It is set on sheets that each fit an A4 page at
/// 1:1, its sections: per section a cartoon at true size, laid under film and mesh, and the tiles
/// glued face up onto the mesh in steps, in the order the engine laid them (features and eyes,
/// strands along the outlines, the rows that echo them, then the field patch by patch). The sheets
/// are set into thinset on a board by the map, cured, then grouted.
///
/// What a mosaicist can't set is changed here, never in the mosaic: each tile becomes pieces a
/// pair of nippers can cut (`BookPieces.cuttable`), the joints the engine left wider than a real
/// mosaic's get pieces cut to fill them (`BookPieces.fillers`), and a paint used by a handful of
/// tiles is set in its nearest paint's stone. Deterministic: the same mosaic and options make the
/// same book. `pages` lays out every page (`BookPage`); the app draws them, and `svg` for a look on
/// Linux (`mosaic book`).
public struct StoneBook: Sendable {
    public typealias Point = SIMD2<Double>

    public struct Options: Sendable, Equatable {
        /// The median tile's face, cm²: what sets the mosaic's size and the stone to buy.
        public var tileFace: Double
        public init(tileFace: Double = 1.5) { self.tileFace = tileFace }
    }

    public enum Stage: Sendable, Equatable {
        case feature, eye, strand, row, field
        /// A piece cut to fill a wide joint, laid with the field.
        case filler

        init(_ s: Mosaic.Stage?) {
            switch s {
            case .feature: self = .feature
            case .eye: self = .eye
            case .strand: self = .strand
            case .row: self = .row
            case .field, nil: self = .field
            }
        }
    }

    /// One piece to cut and set: convex, in canvas units.
    public struct Piece: Sendable, Equatable {
        public var corners: [Point]
        /// Index into the palette, folded (`paintFolded`): the stone it is cut from.
        public var paint: Int
        public var stone: Bool
        public var stage: Stage
        /// The mosaic's tile it was cut from; nil for a filler.
        public var tile: Int?
        public var centre: Point
        public var area: Double
        public var section = 0
        public var step = 0
    }

    public struct Step: Sendable, Equatable {
        public var section: Int
        /// Indices into `pieces`, in the order they are set.
        public var pieces: [Int]
    }

    /// One stone to buy.
    public struct Stone: Sendable, Equatable {
        public enum Kind: Sendable { case glass, stone, gold }
        public var paint: Int
        public var count: Int
        /// The count with spares for breakage at the nippers.
        public var buy: Int
        public var areaCM2: Double
        public var kilograms: Double
        public var kind: Kind
        /// The nearest smalto in `Smalti.orsoni`, and how far it is (ΔE, OKLab).
        public var smalto: Smalti.Entry?
        public var distance: Double
        /// A gold's shade among the book's golds, lightest 0: gold leaf smalti have no codes, so the
        /// list names them by shade (`BookStrings.goldShades`) beside a swatch of each.
        public var goldShade: Int? = nil
    }

    // The book's measures.
    static let kilogramsPerM2 = 15.0     // Orsoni smalti: about 1 kg per 25 × 25 cm (Mosaic Workshop)
    static let spare = 0.15              // tiles bought over the count: breakage at the nippers
    static let minimumPaintTiles = 8     // a paint with fewer tiles is set in its nearest paint's stone
    static let minimumPieceMM = 5.0      // narrower than this, a piece is left to the grout: smalti are 8 mm thick
    static let jointMM = 1.0             // the joint a cut leaves, and the joint fillers keep
    static let reachMM = 4.0             // how far a piece may grow to close a joint
    static let groutDepthCM = 0.6, groutGramsPerCM3 = 1.9
    static let stepMaximum = 12          // pieces in one step at most

    public let title: String
    public let options: Options
    public let width: Double, height: Double
    public let palette: [SIMD3<Double>]
    public let grout: SIMD3<Double>
    /// Each paint's name in the app, for the stone list; nil where it has none.
    public let names: [String?]
    /// Millimetres per canvas unit.
    public let mm: Double
    /// The median tile's side, in canvas units: the book's measure of nearness.
    public let spacing: Double
    public let columns: Int, rows: Int
    public let pieces: [Piece]
    public let steps: [Step]
    /// Each section's pieces, in `pieces`' order.
    public let sections: [[Int]]
    /// Tiles cut into more than one piece, and the pieces cut to fill joints.
    public let cutTiles: Int, fillerCount: Int
    let pageKinds: [PageKind]
    /// The page (1-based) each step is on.
    let stepPage: [Int]
    /// The corner map, one per section: the sections before it set.
    let minimaps: [BookImage]

    public var widthMM: Double { width * mm }
    public var heightMM: Double { height * mm }
    var sectionWidth: Double { width / Double(columns) }
    var sectionHeight: Double { height / Double(rows) }

    public init(mosaic: Mosaic, title: String, names: [String?], options: Options = Options()) {
        self.title = title
        self.options = options
        self.names = names
        width = Double(mosaic.width); height = Double(mosaic.height)
        palette = mosaic.palette.map { SIMD3<Double>($0) }
        grout = SIMD3<Double>(mosaic.grout)
        let raw = mosaic.tiles.map { $0.corners.map { Point(Double($0.x), Double($0.y)) } }
        let areas = raw.map(BookGeometry.area).sorted()
        let median = areas.isEmpty ? 1 : max(areas[areas.count / 2], 1e-9)
        mm = (options.tileFace * 100 / median).squareRoot()
        spacing = median.squareRoot()

        // a paint used by a handful of tiles isn't worth a stone of its own
        var counts = [Int](repeating: 0, count: palette.count)
        for t in mosaic.tiles where counts.indices.contains(t.paint) { counts[t.paint] += 1 }
        let labs = palette.map { StoneBook.oklab($0) }
        let kept = counts.indices.filter { counts[$0] >= StoneBook.minimumPaintTiles }
        let fold: [Int] = counts.indices.map { p in
            guard !kept.isEmpty, counts[p] < StoneBook.minimumPaintTiles else { return p }
            return kept.min { StoneBook.distance(labs[p], labs[$0]) < StoneBook.distance(labs[p], labs[$1]) }!
        }

        // every tile as pieces a nipper can cut, the cuts leaving a joint
        var pieces: [Piece] = []
        var cut = 0
        for (i, t) in mosaic.tiles.enumerated() where counts.indices.contains(t.paint) {
            let parts = BookPieces.cuttable(raw[i], medianArea: median, joint: StoneBook.jointMM / mm,
                                            minimumWidth: StoneBook.minimumPieceMM / mm)
            if parts.count > 1 { cut += 1 }
            for part in parts {
                pieces.append(Piece(corners: part, paint: fold[t.paint], stone: t.stone, stage: Stage(t.stage), tile: i,
                                    centre: BookGeometry.centre(part), area: BookGeometry.area(part)))
            }
        }
        cutTiles = cut
        // a needle no one can nip goes to its neighbours, which grow into its room (an eye's
        // round piece stays, however small)
        let narrowest = StoneBook.minimumPieceMM / mm
        pieces.removeAll { $0.stage != .eye && BookGeometry.minimumWidth($0.corners) < narrowest }
        // each cut to fit its neighbours, a joint apart
        // twice: a piece held back the first time (its room's hull crossed a neighbour's) may grow
        // once its neighbours have
        // a raster of about 20 pixels to a tile's side, never more than 8 million pixels
        let pixel = max(spacing / 20, (width * height / 8e6).squareRoot())
        var fitted = pieces.map(\.corners)
        for _ in 0..<2 {
            fitted = BookPieces.fitted(fitted, width: width, height: height, pixel: pixel,
                                       joint: StoneBook.jointMM / mm, reach: StoneBook.reachMM / mm)
        }
        for i in pieces.indices where fitted[i] != pieces[i].corners {
            pieces[i].corners = fitted[i]
            pieces[i].centre = BookGeometry.centre(fitted[i])
            pieces[i].area = BookGeometry.area(fitted[i])
        }
        // and the joints left wider than a mosaicist's, filled with pieces cut to fit
        let fillers = BookPieces.fillers(pieces.map(\.corners), width: width, height: height, pixel: pixel,
                                         joint: StoneBook.jointMM / mm, minimumWidth: StoneBook.minimumPieceMM / mm,
                                         targetArea: median)
        for f in fillers {
            let beside = pieces[f.neighbour]
            pieces.append(Piece(corners: f.corners, paint: beside.paint, stone: beside.stone, stage: .filler, tile: nil,
                                centre: BookGeometry.centre(f.corners), area: BookGeometry.area(f.corners)))
        }
        fillerCount = fillers.count

        columns = max(1, Int((width * mm / BookLayout.sectionMaxWidth).rounded(.up)))
        rows = max(1, Int((height * mm / BookLayout.sectionMaxHeight).rounded(.up)))
        let sw = width / Double(columns), sh = height / Double(rows)
        var sections = [[Int]](repeating: [], count: columns * rows)
        for i in pieces.indices {
            let c = pieces[i].centre
            let col = min(max(Int(c.x / sw), 0), columns - 1), row = min(max(Int(c.y / sh), 0), rows - 1)
            pieces[i].section = row * columns + col
            sections[row * columns + col].append(i)
        }
        self.sections = sections
        var steps: [Step] = []
        for (s, members) in sections.enumerated() {
            let origin = Point(Double(s % columns) * sw, Double(s / columns) * sh)
            for chunk in StoneBook.planSteps(origin: origin, members: members, pieces: pieces, mm: mm, spacing: spacing,
                                             frameHeight: StoneBook.frameHeight(section: s, width: width, height: height,
                                                                                columns: columns, rows: rows, spacing: spacing,
                                                                                mm: mm)) {
                steps.append(Step(section: s, pieces: chunk))
            }
        }
        var laid = pieces
        for (n, step) in steps.enumerated() { for i in step.pieces { laid[i].step = n } }
        self.pieces = laid
        self.steps = steps
        var paints = Set<Int>()
        for p in laid { paints.insert(p.paint) }
        (pageKinds, stepPage) = StoneBook.assemble(sections: sections.count, steps: steps, stones: paints.count)
        let raster = StoneBook.rasterize(laid, width: width, height: height)
        let colours = palette
        minimaps = (0...max(sections.count, 1)).map { StoneBook.minimapImage(raster, laid, colours, doneBefore: $0) }
    }

    // MARK: Sections and steps

    func sectionRect(_ s: Int) -> (x: Double, y: Double, w: Double, h: Double) {
        (Double(s % columns) * sectionWidth, Double(s / columns) * sectionHeight, sectionWidth, sectionHeight)
    }

    /// The window every step of a section is drawn through: the sheet's full width with a margin,
    /// as tall as the step view's shape allows, panning down the sheet.
    func frame(_ s: Int) -> (loX: Double, hiX: Double, loY: Double, hiY: Double, spanW: Double, spanH: Double) {
        StoneBook.frame(section: s, width: width, height: height, columns: columns, rows: rows, spacing: spacing)
    }

    static func frame(section s: Int, width: Double, height: Double, columns: Int, rows: Int, spacing: Double)
        -> (loX: Double, hiX: Double, loY: Double, hiY: Double, spanW: Double, spanH: Double) {
        let sw = width / Double(columns), sh = height / Double(rows)
        let sx = Double(s % columns) * sw, sy = Double(s / columns) * sh
        let m = 1.5 * spacing
        let loX = max(0, sx - m), hiX = min(width, sx + sw + m)
        let loY = max(0, sy - m), hiY = min(height, sy + sh + m)
        let spanW = hiX - loX
        return (loX, hiX, loY, hiY, spanW, min(spanW * BookLayout.viewHeight / BookLayout.viewWidth, hiY - loY))
    }

    static func frameHeight(section: Int, width: Double, height: Double, columns: Int, rows: Int, spacing: Double, mm: Double) -> Double {
        frame(section: section, width: width, height: height, columns: columns, rows: rows, spacing: spacing).spanH - 2 * spacing
    }

    /// The engine's own order: features and eyes, then strands along the outlines, then the rows
    /// that echo them (each a chain, cut into steps where it jumps), then the field between,
    /// gathered patch by patch in a boustrophedon over the section, its fillers with it. No step is
    /// taller than the frame, and none overflows its parts box (it is halved until it fits).
    static func planSteps(origin: Point, members: [Int], pieces: [Piece], mm: Double, spacing: Double, frameHeight: Double) -> [[Int]] {
        func ySpan(_ list: [Int]) -> Double {
            var lo = Double.infinity, hi = -Double.infinity
            for i in list { for c in pieces[i].corners { lo = min(lo, c.y); hi = max(hi, c.y) } }
            return hi - lo
        }
        func dist(_ a: Int, _ b: Int) -> Double {
            let d = pieces[a].centre - pieces[b].centre
            return ((d * d).sum()).squareRoot()
        }
        func facial(_ i: Int) -> Bool { pieces[i].stage == .feature || pieces[i].stage == .eye }
        var chains: [[Int]] = [], current: [Int] = []
        for i in members where pieces[i].stage != .field && pieces[i].stage != .filler {
            if let last = current.last,
               current.count >= stepMaximum || ySpan(current + [i]) > frameHeight || facial(i) != facial(last)
                || (pieces[i].stage == .strand) != (pieces[last].stage == .strand) || dist(i, last) > 2.6 * spacing {
                chains.append(current); current = []
            }
            current.append(i)
        }
        if !current.isEmpty { chains.append(current) }
        // short runs join a neighbouring step of the same kind when they lie close
        var merged: [[Int]] = []
        for chain in chains {
            if let last = merged.last, chain.count < 5, last.count + chain.count <= stepMaximum + 4,
               ySpan(last + chain) <= frameHeight,
               last.contains(where: { a in chain.contains { b in dist(a, b) < 6 * spacing } }) {
                merged[merged.count - 1] += chain
            } else {
                merged.append(chain)
            }
        }
        let field = members.filter { pieces[$0].stage == .field || pieces[$0].stage == .filler }
        let cell = 4.5 * spacing
        func key(_ i: Int) -> (Int, Int, Double, Double) {
            let c = pieces[i].centre - origin
            let gx = Int((c.x / cell).rounded(.down)), gy = Int((c.y / cell).rounded(.down))
            return (gy, gy % 2 == 0 ? gx : -gx, c.y, c.x)
        }
        let ordered = field.sorted { key($0) < key($1) }
        var patches: [[Int]] = []
        current = []
        var currentKey: (Int, Int)?
        for i in ordered {
            let k = key(i)
            if !current.isEmpty, current.count >= stepMaximum || (currentKey.map { $0 != (k.0, k.1) } ?? false && current.count >= 8) {
                patches.append(current); current = []
            }
            current.append(i)
            currentKey = (k.0, k.1)
        }
        if !current.isEmpty { patches.append(current) }
        var out: [[Int]] = []
        for step in merged + patches {
            if let last = out.last, step.count < 6, last.count + step.count <= stepMaximum + 3, ySpan(last + step) <= frameHeight {
                out[out.count - 1] += step
            } else {
                out.append(step)
            }
        }
        // a step whose pieces overflow its parts box is halved until each half fits
        var fitted: [[Int]] = []
        func fit(_ step: [Int]) {
            if step.count <= 1 || BookLayout.partsFit(step.map { pieces[$0] }, mm: mm) { fitted.append(step); return }
            fit(Array(step[..<(step.count / 2)]))
            fit(Array(step[(step.count / 2)...]))
        }
        out.forEach(fit)
        return fitted
    }

    // MARK: Stones and grout

    /// The grout to buy, kg: the joints' area, 0.6 cm deep.
    public var groutKilograms: Double {
        let joints = (width * height - pieces.reduce(0) { $0 + $1.area }) * mm * mm / 100
        return joints * StoneBook.groutDepthCM * StoneBook.groutGramsPerCM3 / 1000
    }

    /// Every stone, most used first. Each paint gets a smalto of its own, so the picture keeps
    /// every contrast it has: the most used paints choose first, each the nearest not yet chosen.
    public var stones: [Stone] {
        var count = [Int](repeating: 0, count: palette.count), stone = count
        var area = [Double](repeating: 0, count: palette.count)
        for p in pieces {
            count[p.paint] += 1
            area[p.paint] += p.area
            if p.stone { stone[p.paint] += 1 }
        }
        let used = palette.indices.filter { count[$0] > 0 }.sorted { count[$0] != count[$1] ? count[$0] > count[$1] : $0 < $1 }
        var taken = Set<String>()
        var out: [Stone] = []
        for p in used {
            let cm2 = area[p] * mm * mm / 100
            let isGold = TileColor.isGold(SIMD3<Float>(palette[p]))
            let kind: Stone.Kind = isGold ? .gold : stone[p] * 2 > count[p] ? .stone : .glass
            let match = kind == .gold ? nil : Smalti.nearest(to: palette[p], excluding: taken)
            if let match { taken.insert(match.entry.code) }
            out.append(Stone(paint: p, count: count[p], buy: Int((Double(count[p]) * (1 + StoneBook.spare)).rounded(.up)),
                             areaCM2: cm2, kilograms: cm2 / 1e4 * StoneBook.kilogramsPerM2 * (1 + StoneBook.spare),
                             kind: kind, smalto: match?.entry, distance: match?.distance ?? 0))
        }
        // golds named lightest to darkest, so no two on a list share a name
        let golds = out.indices.filter { out[$0].kind == .gold }
            .sorted { StoneBook.oklab(palette[out[$0].paint]).x > StoneBook.oklab(palette[out[$1].paint]).x }
        let shades = golds.count <= 1 ? [1] : golds.count == 2 ? [1, 2] : golds.count == 3 ? [0, 1, 2] : [0, 1, 2, 3]
        for (rank, i) in golds.enumerated() { out[i].goldShade = shades[min(rank, shades.count - 1)] }
        return out
    }

    // MARK: Colour

    static func oklab(_ c: SIMD3<Double>) -> SIMD3<Double> {
        func lin(_ x: Double) -> Double { x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        let r = lin(c.x), g = lin(c.y), b = lin(c.z)
        func cbrt(_ v: Double) -> Double { v < 0 ? -pow(-v, 1.0 / 3) : pow(v, 1.0 / 3) }
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return SIMD3(0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                     1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                     0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    static func distance(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        let d = a - b
        return ((d * d).sum()).squareRoot()
    }
}
