import Foundation

extension TemplateEditor {
    /// A look laid over a whole painting's paints (Refine's Looks and Edit Paint): each is a fixed function of
    /// a color, so a paint a later edit brings (a drawn line's piece, a fill) takes the look too
    /// (`recolor(_:by:)`). A look's math is frozen once it ships, like a file format: a painting
    /// records the look's name and must lay the same paints in every later build. A retuned look
    /// is a new case. The math is `+ - * /`, `min`, `max` and `sqrt` only, so it gives the same
    /// bits on every platform.
    public enum Look: String, Sendable, CaseIterable, Codable {
        // In the order Refine shows them: the night first, the app's own (the Lamplit Table,
        // October 18), then the day, then the painters'.
        /// Darker, cool and quiet: the painting by moonlight.
        case moonlit
        /// Warm, as the last hour of sun.
        case goldenHour
        /// Light and soft.
        case pastel
        /// Brown ink on old paper.
        case sepia
        /// Each paint, by its lightness, a color of a garden: soil, mushroom, moss, sage, birch.
        case garden
        /// Each paint, by its lightness among the painting's, a color of Van Gogh's
        /// *The Starry Night* (1889).
        case starryNight
        /// The same with Monet's *Water Lilies* (1906).
        case waterLilies
        /// The same with Hokusai's *The Great Wave off Kanagawa* (about 1831).
        case greatWave

        /// The painting's ramp, darkest first (OKLab, from sRGB picks of the painting), for the
        /// looks that map lightness onto a painting's colors.
        var ramp: [SIMD3<Float>]? {
            switch self {
            case .starryNight:
                [SIMD3(0.2553, -0.0050, -0.0736), SIMD3(0.3594, -0.0150, -0.1036), SIMD3(0.4719, -0.0259, -0.1221),
                 SIMD3(0.5773, -0.0369, -0.1054), SIMD3(0.6816, -0.0393, -0.0572), SIMD3(0.7417, -0.0397, 0.0177),
                 SIMD3(0.8071, -0.0234, 0.1049), SIMD3(0.8681, -0.0209, 0.1488), SIMD3(0.9452, -0.0083, 0.0624)]
            case .waterLilies:
                [SIMD3(0.3094, -0.0400, -0.0250), SIMD3(0.4223, -0.0650, -0.0250), SIMD3(0.5072, -0.0700, -0.0350),
                 SIMD3(0.6112, -0.0550, -0.0400), SIMD3(0.6701, -0.0100, -0.0800), SIMD3(0.7278, 0.0400, -0.0750),
                 SIMD3(0.7750, 0.0700, -0.0200), SIMD3(0.8351, 0.0000, 0.0800), SIMD3(0.9211, -0.0100, 0.0550)]
            case .garden:
                [SIMD3(0.2699, 0.0114, 0.0149), SIMD3(0.3783, 0.0154, 0.0349), SIMD3(0.4256, -0.0433, 0.0507),
                 SIMD3(0.5514, -0.0555, 0.0691), SIMD3(0.6684, -0.0473, 0.0640), SIMD3(0.7491, -0.0313, 0.0535),
                 SIMD3(0.7934, -0.0043, 0.0442), SIMD3(0.8923, -0.0036, 0.0269), SIMD3(0.9529, -0.0033, 0.0184)]
            case .greatWave:
                [SIMD3(0.2399, -0.0033, -0.0501), SIMD3(0.3386, -0.0142, -0.0759), SIMD3(0.4424, -0.0258, -0.0834),
                 SIMD3(0.5599, -0.0272, -0.0721), SIMD3(0.6919, -0.0221, -0.0446), SIMD3(0.8072, -0.0138, -0.0115),
                 SIMD3(0.8624, -0.0026, 0.0274), SIMD3(0.9111, 0.0007, 0.0349), SIMD3(0.9550, -0.0006, 0.0205)]
            default: nil
            }
        }

        /// How much of a paint's own chroma a painting's look keeps over the ramp's color: two
        /// paints of one lightness and different hues stay apart rather than become one paint.
        static let keptChroma: Float = 0.25

        /// `c` in this look at full strength. `lightness`: the painting's lightness quantiles
        /// (`quantiles(of:)`), which place `c` on a painting's ramp.
        func apply(_ c: SIMD3<Float>, lightness: [Float]) -> SIMD3<Float> {
            let L = c.x, a = c.y, b = c.z
            switch self {
            case .moonlit: return SIMD3(0.20 + 0.70 * L, 0.4 * a - 0.010, 0.4 * b - 0.050)
            case .pastel: return SIMD3(0.60 + 0.38 * L, 0.55 * a, 0.55 * b)
            case .goldenHour: return SIMD3(0.06 + 0.94 * L, 0.85 * a + 0.020, 0.85 * b + 0.055)
            case .sepia: return SIMD3(0.14 + 0.82 * L, 0.1 * a + 0.007 + 0.01 * L, 0.1 * b + 0.023 + 0.03 * L)
            case .garden, .starryNight, .waterLilies, .greatWave:
                guard let ramp else { return c }
                let r = Self.rank(L, lightness) * Float(ramp.count - 1)
                let k = min(max(Int(r), 0), ramp.count - 2)
                let f = min(max(r - Float(k), 0), 1)
                let on = ramp[k] + (ramp[k + 1] - ramp[k]) * f
                return SIMD3(on.x, on.y + Self.keptChroma * a, on.z + Self.keptChroma * b)
            }
        }

        /// Where `L` lies among `quantiles` (ascending), 0 to 1, linear between them: a paint's
        /// rank among the painting's lightnesses, and the same for a color between them.
        static func rank(_ L: Float, _ quantiles: [Float]) -> Float {
            guard quantiles.count >= 2 else { return min(max(L, 0), 1) }
            if L <= quantiles[0] { return 0 }
            let last = quantiles.count - 1
            if L >= quantiles[last] { return 1 }
            var k = 0
            while k + 1 < last, L > quantiles[k + 1] { k += 1 }
            let span = quantiles[k + 1] - quantiles[k]
            let f = span > 0 ? (L - quantiles[k]) / span : 0
            return (Float(k) + min(max(f, 0), 1)) / Float(last)
        }

        /// How many lightness quantiles a painting's look records.
        static let quantileCount = 9

        /// The palette's lightnesses at `quantileCount` evenly spaced ranks, ascending; empty for
        /// a look that needs none.
        func quantiles(of palette: [PaletteColor]) -> [Float] {
            guard ramp != nil, !palette.isEmpty else { return [] }
            let sorted = palette.map(\.oklab.x).sorted()
            return (0..<Self.quantileCount).map { i in
                sorted[(i * (sorted.count - 1) + (Self.quantileCount - 1) / 2) / (Self.quantileCount - 1)]
            }
        }
    }

    /// The edit that lays `look` at `strength` (0 to 1) over `template`'s paints, with the
    /// lightnesses it reads from them.
    public static func look(_ look: Look, strength: Float, on template: Template) -> Edit {
        self.look(look, strength: strength, paints: template.palette)
    }

    /// The edit that lays `look` at `strength` over `paints`, with the lightnesses it reads from them.
    public static func look(_ look: Look, strength: Float, paints: [PaletteColor]) -> Edit {
        .look(look, strength: strength, lightness: look.quantiles(of: paints))
    }

    /// The least chroma of a paint whose family is its hue (`repaint`'s `family`); a grayer
    /// paint's family is the colors near it.
    static let familyChroma: Float = 0.04

    /// `color` as a recoloring edit makes it, and as every color laid after that edit is made
    /// (a drawn line's photo colors, a fill's), so later edits bring paints in the same colors.
    /// Any other edit leaves it as it is.
    public static func recolor(_ color: SIMD3<Float>, by edit: Edit) -> SIMD3<Float> {
        switch edit {
        case .look(let look, let strength, let lightness):
            let s = strength.isFinite ? min(max(strength, 0), 1) : 0
            return clampedLab(color + (look.apply(color, lightness: lightness) - color) * s)
        case .repaint(let from, let to, let family):
            guard color != from else { return clampedLab(to) }
            guard family else { return color }
            let w = familyWeight(color, of: from)
            guard w > 0 else { return color }
            let fromChroma = (from.y * from.y + from.z * from.z).squareRoot()
            let moved: SIMD3<Float>
            if fromChroma >= familyChroma {
                // The family turns and grows with the swatch: (a, b) times to/from as complex
                // numbers, and lightness shifts by as much.
                let d = fromChroma * fromChroma
                let re = (to.y * from.y + to.z * from.z) / d, im = (to.z * from.y - to.y * from.z) / d
                moved = SIMD3(color.x + to.x - from.x, color.y * re - color.z * im, color.y * im + color.z * re)
            } else {
                moved = color + (to - from)
            }
            return clampedLab(color + (moved - color) * w)
        default:
            return color
        }
    }

    /// How much `c` belongs to `from`'s family, 0 to 1: for a colorful swatch, colors of about
    /// its hue (full within 30°, none past 60°) that have color at all; for a gray one, colors
    /// near it (full within 0.05, none past 0.1).
    static func familyWeight(_ c: SIMD3<Float>, of from: SIMD3<Float>) -> Float {
        func ramp(_ x: Float, _ lo: Float, _ hi: Float) -> Float { min(max((x - lo) / (hi - lo), 0), 1) }
        let fromChroma = (from.y * from.y + from.z * from.z).squareRoot()
        guard fromChroma >= familyChroma else {
            return 1 - ramp(ColorScience.distance(c, from), 0.05, 0.10)
        }
        let chroma = (c.y * c.y + c.z * c.z).squareRoot()
        guard chroma > 0 else { return 0 }
        let cosine = (c.y * from.y + c.z * from.z) / (chroma * fromChroma)
        return ramp(cosine, 0.5, 0.8660254) * ramp(chroma, 0.02, 0.05)
    }

    /// A color OKLab can hold: lightness 0 to 1, chroma axes within the gamuts' reach.
    static func clampedLab(_ c: SIMD3<Float>) -> SIMD3<Float> {
        pointwiseMin(pointwiseMax(c, SIMD3(0, -0.5, -0.5)), SIMD3(1, 0.5, 0.5))
    }

    /// Whether `edit` changes paints alone (a look, a repaint).
    public static func isRecolor(_ edit: Edit) -> Bool {
        switch edit {
        case .look, .repaint: true
        default: false
        }
    }

    /// `edit` with the colors it brings (a drawn line's or a split's paints, a fill's color) as
    /// the recoloring edits laid before it make them, in order. A painted area's color
    /// (`paintArea`) is one of the template on screen, the looks already in it, and stays as sent,
    /// as a brush stroke's (`brush`) does.
    public static func recolored(_ edit: Edit, by recolors: [Edit]) -> Edit {
        guard !recolors.isEmpty else { return edit }
        func map(_ c: SIMD3<Float>) -> SIMD3<Float> { recolors.reduce(c) { recolor($0, by: $1) } }
        func map(_ paints: [Paint]) -> [Paint] { paints.map { Paint(at: $0.at, color: map($0.color)) } }
        switch edit {
        case .draw(let points, let closed, let paints): return .draw(points: points, closed: closed, paints: paints.map(map))
        case .split(let points, let closed, let paints): return .split(points: points, closed: closed, paints: map(paints))
        case .fill(let point, let color): return .fill(at: point, color: map(color))
        default: return edit
        }
    }
}

extension EditWork {
    /// Makes each paint the color `edit` gives it (`TemplateEditor.recolor(_:by:)`). Where a
    /// changed paint comes within a just-noticeable difference of another, the two become one
    /// paint, the lower number, and the higher leaves the palette so the numbers after it close
    /// up (a number only loses digits, so every label keeps its room). Areas that now share a
    /// paint across an undrawn boundary (the Color Splitter's) become one area, the larger
    /// keeping its index, as the eraser joins them. Shapes, lines and numbers are otherwise
    /// untouched.
    mutating func recolor(_ edit: TemplateEditor.Edit) throws {
        let old = t.palette.map(\.oklab)
        let new = old.map { TemplateEditor.recolor($0, by: edit) }
        // Each paint, the paint it becomes: itself, or an earlier one it now matches.
        var target = Array(old.indices)
        for k in new.indices {
            for j in 0..<k where target[j] == j && (new[j] != old[j] || new[k] != old[k]) {
                if ColorScience.distance(new[j], new[k]) < SegmentationParameters.jnd {
                    target[k] = j
                    break
                }
            }
        }
        let merged = old.indices.filter { target[$0] != $0 }.count
        let changed = old.indices.filter { target[$0] == $0 && new[$0] != old[$0] }.count
        guard merged > 0 || changed > 0 else { return }
        let before = t.regions.map(\.colorIndex)
        try renumberPaints(into: target, colors: new)
        try joinAreas(paintedBefore: before)
        for e in t.edges.indices where !edgeDead[e] && !isInked(e) {
            guard let r = right(e) else { continue }
            weights[e] = colorWeight(t.regions[left(e)].colorIndex, t.regions[r].colorIndex)
        }
        summary.paintsChanged += changed
        summary.paintsMerged += merged
    }

    /// Lays the palette out again: each paint `k` becomes paint `target[k]` (itself, or a paint
    /// that is its own target) of color `colors[k]`. A paint made another leaves the palette and
    /// the numbers after it close up (a number only loses digits, so every label keeps its room);
    /// every region takes the number its paint has now.
    mutating func renumberPaints(into target: [Int], colors new: [SIMD3<Float>]) throws {
        let old = t.palette.map(\.oklab)
        var index = [Int](repeating: -1, count: old.count)
        var palette: [PaletteColor] = []
        for k in old.indices where target[k] == k {
            index[k] = palette.count
            palette.append(new[k] == old[k] ? t.palette[k] : PaletteColor(oklab: new[k], space: t.colorSpace))
        }
        t.palette = palette
        for r in t.regions.indices {
            let k = Int(t.regions[r].colorIndex)
            guard k < target.count else { throw EditFailure.invalid("a region's paint is not in the palette") }
            let to = UInt32(index[target[k]])
            if to != t.regions[r].colorIndex || target[k] != k || new[k] != old[k] {
                t.regions[r].colorIndex = to
                regionTouched[r] = true
                summary.touched.insert(r)
            }
        }
    }

    /// Areas that share a paint across an undrawn boundary now and did not `before` (each region's
    /// paint then) become one area, the larger keeping its index, as the eraser joins them. Areas
    /// that shared a paint before keep their boundary.
    mutating func joinAreas(paintedBefore before: [UInt32]) throws {
        var groups = Groups()
        for e in t.edges.indices where !edgeDead[e] && !isInked(e) {
            guard let r = right(e) else { continue }
            let l = left(e)
            if regionAlive[l], regionAlive[r], before[l] != before[r], t.regions[l].colorIndex == t.regions[r].colorIndex {
                groups.join(l, r)
            }
        }
        try mergeGroups(groups.groups(), surviving: [:])
    }
}
