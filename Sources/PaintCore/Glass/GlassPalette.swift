import Foundation

/// Stained Glass's glasses (painting-company row 366): the colors the photo suggests for the
/// pieces of a window the painter leaded (`GlassWindow`), and the few every glazier keeps.
///
/// A piece's color is its photo's, read so it stays alive: each pixel weighs by its chroma, so an
/// orange wing crossed by black veins and white dots reads orange, never the mud of all three.
/// Pieces with little detail under them and a fair share of the window (an out-of-focus
/// background) are set apart and take two or three deep, quiet glasses of their own; the subject
/// gets the rest, brighter and more saturated than the photo, the way light comes through glass.
/// Gathering the pieces into glasses is k-means from a farthest-point start, so nothing here is
/// random, and every sum runs in raster order on one thread: the same template and photo give
/// the same glasses on every device. `version` names this recipe; a change to what it suggests
/// bumps it.
///
/// Free glazing (Paul, November 20, 2026) means the suggestion is only a hint: the painter may
/// put any glass in any piece (`Glazing`). The glasses offered are the window's own, then
/// `classics` not already among them (`offered`).
public enum GlassPalette {
    public static let version = 1

    /// The glasses the window suggests: `glasses` in OKLab, background ones first; for each
    /// region its glass (`ofRegion`) and whether it was read as background (`isBackground`).
    public struct Suggestion: Sendable, Equatable {
        public var glasses: [SIMD3<Float>]
        public var ofRegion: [Int]
        public var isBackground: [Bool]
    }

    /// Glass a glazier always has, offered after the window's own: cobalt, ruby, gold, emerald
    /// and milk, as sRGB. Append only: a glazed piece records its glass by place in `offered`.
    public static let classics: [SIMD3<UInt8>] = [
        SIMD3(28, 64, 196), SIMD3(196, 24, 56), SIMD3(244, 182, 36), SIMD3(22, 150, 96), SIMD3(238, 232, 218),
    ]

    /// The long side of the grid the photo is read on: enough for a piece's color and its
    /// detail, small enough that reading a window costs little.
    static let gridSide = 360
    /// Below this mean gradient (the sum over R, G, B of the central differences across and
    /// down, in 8-bit steps) a piece is out of focus. Measured on the monarch of the mockup
    /// (`factory/pieces/stained-glass/`): its background pieces read 6–45, the subject's 55–320.
    static let backgroundDetail: Float = 40
    /// How far in from its lead, in grid pixels, a piece's detail is read.
    static let borderMargin = 4
    /// A piece is background only with at least this share of the window: a smooth petal is not.
    static let backgroundShare: Float = 0.01

    /// The window's suggestion: `template`'s regions read over `photo` (any size; it is laid over
    /// the whole canvas).
    public static func suggest(for template: Template, photo: RGBAImage) -> Suggestion {
        let n = template.regions.count
        guard n > 0 else { return Suggestion(glasses: [], ofRegion: [], isBackground: []) }
        let scale = Float(gridSide) / Float(max(template.width, template.height))
        let gw = max(1, Int((Float(template.width) * min(scale, 1)).rounded()))
        let gh = max(1, Int((Float(template.height) * min(scale, 1)).rounded()))
        let small = photo.width > 0 && photo.height > 0
            ? Resample.area(photo, width: gw, height: gh)
            : RGBAImage(width: gw, height: gh, fill: SIMD4(255, 255, 255, 255))
        var label = [Int](repeating: 0, count: gw * gh)
        for y in 0..<gh {
            let my = min(template.height - 1, Int((Float(y) + 0.5) * Float(template.height) / Float(gh)))
            for x in 0..<gw {
                let mx = min(template.width - 1, Int((Float(x) + 0.5) * Float(template.width) / Float(gw)))
                label[y * gw + x] = min(n - 1, Int(template.regionMap[mx, my]))
            }
        }

        // Each piece's color, weighed by chroma, and its detail.
        var sum = [SIMD4<Float>](repeating: .zero, count: n)
        var area = [Float](repeating: 0, count: n)
        var detail = [Float](repeating: 0, count: n), detailCount = [Float](repeating: 0, count: n)
        let lut = ColorScience.decodeLUT
        for y in 0..<gh {
            for x in 0..<gw {
                let i = y * gw + x, k = label[i], px = small[x, y]
                let lab = ColorScience.linearToOKLab(
                    SIMD3(lut[Int(px.x)], lut[Int(px.y)], lut[Int(px.z)]), space: small.colorSpace)
                let c = (lab.y * lab.y + lab.z * lab.z).squareRoot()
                let w = (c * 3 + 0.06) * (c * 3 + 0.06)
                sum[k] += SIMD4(lab.x * w, lab.y * w, lab.z * w, w)
                area[k] += 1
                // Detail is read away from the piece's lead: a line traced along an edge in the
                // photo has that edge just beside it, which says nothing of the piece's focus.
                let r = borderMargin
                guard x >= r, y >= r, x < gw - r, y < gh - r,
                      label[i - r] == k, label[i + r] == k, label[i - r * gw] == k, label[i + r * gw] == k else { continue }
                var g: Float = 0
                for (a, b) in [(small[x + 1, y], small[x - 1, y]), (small[x, y + 1], small[x, y - 1])] {
                    g += abs(Float(a.x) - Float(b.x)) + abs(Float(a.y) - Float(b.y)) + abs(Float(a.z) - Float(b.z))
                }
                detail[k] += g
                detailCount[k] += 1
            }
        }
        let total = Float(gw * gh)
        var labs = (0..<n).map { k -> SIMD3<Float> in
            let s = sum[k]
            return s.w > 0 ? SIMD3(s.x, s.y, s.z) / s.w : SIMD3(1, 0, 0)
        }
        let back = (0..<n).map { k in
            area[k] / total > backgroundShare && detail[k] / max(1, detailCount[k]) < backgroundDetail
        }
        // Background is set deeper and quieter before glasses are chosen, so it gets its own.
        for k in 0..<n where back[k] { labs[k] = SIMD3(labs[k].x * 0.8, labs[k].y * 0.7, labs[k].z * 0.7) }

        let weight = area.map { $0.squareRoot() }
        var centers: [SIMD3<Float>] = []
        var assigned = [Int](repeating: 0, count: n)
        let backIndices = (0..<n).filter { back[$0] }, subjectIndices = (0..<n).filter { !back[$0] }
        let wanted = min(12, max(4, Int((Float(n).squareRoot() * 1.6).rounded())))
        let backCount = backIndices.isEmpty ? 0 : min(3, max(2, Int((Float(wanted) / 4).rounded())))
        cluster(backIndices, count: backCount, labs: labs, weight: weight, area: area, centers: &centers, assigned: &assigned)
        let backCenters = centers.count
        cluster(subjectIndices, count: max(3, wanted - backCount), labs: labs, weight: weight, area: area,
                centers: &centers, assigned: &assigned)

        // Glass: the subject brighter and richer than the photo, the background deeper.
        var glasses = centers.enumerated().map { j, c -> SIMD3<Float> in
            glass(c, background: j < backCenters)
        }
        // Glasses a just-noticeable difference apart become one.
        var merged = Array(0..<glasses.count)
        for j in 0..<glasses.count {
            for i in 0..<j where merged[i] == i && ColorScience.distance(glasses[i], glasses[j]) < SegmentationParameters.jnd {
                merged[j] = i
                break
            }
        }
        var renumber = [Int](repeating: -1, count: glasses.count), kept: [SIMD3<Float>] = []
        for j in 0..<glasses.count where merged[j] == j && assigned.contains(where: { merged[$0] == j }) {
            renumber[j] = kept.count
            kept.append(glasses[j])
        }
        glasses = kept
        let ofRegion = assigned.map { renumber[merged[$0]] }
        return Suggestion(glasses: glasses, ofRegion: ofRegion, isBackground: back)
    }

    /// The window with its suggestion as its paints: the palette the glasses (in `template`'s
    /// color space) and each region's paint its suggested glass. Geometry, labels and lines are
    /// untouched.
    public static func glazed(_ template: Template, with suggestion: Suggestion) -> Template {
        precondition(suggestion.ofRegion.count == template.regions.count, "a suggestion for another window")
        var t = template
        t.palette = suggestion.glasses.map { PaletteColor(oklab: $0, space: template.colorSpace) }
        for r in t.regions.indices { t.regions[r].colorIndex = UInt32(suggestion.ofRegion[r]) }
        return t
    }

    /// The glasses offered for `template` (already `glazed`): its own palette, then each of
    /// `classics` not within `apart` of one already offered. A glazed piece names its glass by
    /// its place here.
    public static func offered(for template: Template, apart: Float = 0.09) -> [PaletteColor] {
        var out = template.palette
        for c in classics {
            let lab = ColorScience.encodedToOKLab(SIMD3(Float(c.x), Float(c.y), Float(c.z)) / 255, space: .sRGB)
            guard !out.contains(where: { ColorScience.distance($0.oklab, lab) < apart }) else { continue }
            out.append(PaletteColor(oklab: lab, space: template.colorSpace))
        }
        return out
    }

    /// A piece's photo color as glass.
    static func glass(_ c: SIMD3<Float>, background: Bool) -> SIMD3<Float> {
        let chroma = (c.y * c.y + c.z * c.z).squareRoot()
        let boost: Float, lightness: Float
        if background {
            boost = chroma < 0.03 ? 1.15 : 0.8
            lightness = min(max(c.x * 0.62, 0.30), 0.46)
        } else if chroma < 0.03 {
            boost = 1.15
            lightness = min(max(c.x * 1.05, 0.20), 0.92)
        } else {
            boost = min(max(0.17 / chroma, 1.6), 2.8)
            lightness = min(max(0.16 + c.x * 0.92, 0.5), 0.9)
        }
        return SIMD3(lightness, c.y * boost, c.z * boost)
    }

    /// k-means of the pieces `indices` into `count` glasses appended to `centers`, from a
    /// farthest-point start (the largest piece first), each piece weighed by the square root of
    /// its area; `assigned` gets each piece's center.
    static func cluster(
        _ indices: [Int], count: Int, labs: [SIMD3<Float>], weight: [Float], area: [Float],
        centers: inout [SIMD3<Float>], assigned: inout [Int]
    ) {
        guard !indices.isEmpty, count > 0 else { return }
        let base = centers.count, k = min(count, indices.count)
        func d2(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float { let d = a - b; return (d * d).sum() }
        var first = indices[0]
        for i in indices where area[i] > area[first] { first = i }
        centers.append(labs[first])
        while centers.count - base < k {
            var best = indices[0], bestDistance: Float = -1
            for i in indices {
                var m = Float.greatestFiniteMagnitude
                for j in base..<centers.count { m = min(m, d2(labs[i], centers[j])) }
                if m * weight[i] > bestDistance { bestDistance = m * weight[i]; best = i }
            }
            centers.append(labs[best])
        }
        for _ in 0..<12 {
            for i in indices {
                var best = base, bestDistance = Float.greatestFiniteMagnitude
                for j in base..<centers.count {
                    let d = d2(labs[i], centers[j])
                    if d < bestDistance { bestDistance = d; best = j }
                }
                assigned[i] = best
            }
            var acc = [SIMD4<Float>](repeating: .zero, count: centers.count - base)
            for i in indices {
                let w = weight[i]
                acc[assigned[i] - base] += SIMD4(labs[i].x * w, labs[i].y * w, labs[i].z * w, w)
            }
            for j in acc.indices where acc[j].w > 0 {
                centers[base + j] = SIMD3(acc[j].x, acc[j].y, acc[j].z) / acc[j].w
            }
        }
    }
}
