/// Lively paint: kit paint's paints (`KitPaint`) with their hues spread, so a painting has a
/// broader variety of colors than its photo (painting-company row 326). Only the paints move.
///
/// A photo's twenty-four paints are mostly a few hues in many shades: a dog is browns, a sea is
/// blues. A painter mixes such shades apart: the lights warmer, the shadows cooler, each a color
/// of its own. Among the paints of one hue family (`reach`; a paint counts by the square root
/// of the painting it covers, so the family's main paint is its middle and keeps its hue), each
/// paint
///
/// - turns toward `warm` when it is lighter than its family and toward `cool` when darker
///   (`turn`, full at `span` of lightness from the family's mean, the shorter way round and
///   never past the pole), and most toward the pole on its own side of the wheel (`across`): a
///   green's lights go lime and a red's orange, a blue's shadows deepen and a violet's turn
///   blue, while a brown's shadows stay brown and a blue's lights blue (the second round's
///   critic saw a chocolate cake go plum and a blue wall turquoise). A paint alone in its
///   family has no lighter or darker kin and keeps its hue, so a picture's one red stays the
///   red it was;
/// - turns less when it is vivid (`vivid`: a macaw's yellow, a red flower and a blue shirt
///   are what the picture is of; the first round's critic saw them turn peach, magenta and
///   purple), and never at the cost of chroma: a turn that the gamut would answer by paling
///   the paint (a light yellow toward orange) is halved until it doesn't, and after four
///   halvings dropped;
/// - gets a little more chroma (`gain`), fading out over the vivid as kit paint's does.
///
/// Greys are left as kit paint mixed them (tinted with the same temperature, a brown black
/// went purple and a white plate cream). A face's skin is left too, and paints of skin's color
/// elsewhere are held back as in kit paint (`KitPaint.skinHold`). Nothing steps a paint away
/// from its family's mean hue: that turned a navy shirt indigo beside a blue wall gone azure
/// (the third round's critic), for little the turn doesn't give.
///
/// Then each is brought into gamut by chroma alone, and two paints the change brings closer than
/// `minDistance` both step back toward kit paint's until they are apart again. Hues are unit
/// vectors and turns are given by their half-angle's tangent, so everything is `+ − × ÷` and
/// `sqrt` (and the color space's transfer curve): the same paints give the same paints on every
/// device.
public enum LivelyPaint {
    /// The poles, as unit vectors in OKLab's a, b: 85° (a warm yellow) and, opposite it, 265°
    /// (a blue: at 275° a dark blue shirt went violet).
    static let warm = SIMD2<Float>(0.087_156, 0.996_195)
    static let cool = SIMD2<Float>(-0.087_156, -0.996_195)
    /// The cosine of the hue difference where a family ends (60°); a paint's kin weigh by the
    /// square of how far inside it they are.
    static let reach: Float = 0.5
    /// The half-tangent of the most a paint turns toward its pole (about 18°), reached at `span`
    /// of lightness from its family's mean.
    static let turn: Float = 0.16
    static let span: Float = 0.22
    /// The share of the turn a paint opposite its pole keeps; one beside it keeps all.
    static let across: Float = 0.25
    /// The share of the turn a vivid paint loses, fading in over `vividChroma`.
    static let vivid: Float = 0.7
    static let vividChroma: ClosedRange<Float> = 0.1...0.2
    /// The chroma added, over the same ranges as `KitPaint.chromaGain`.
    static let gain: Float = 0.12
    /// Below the lower chroma a paint is a grey and keeps its hue; above the upper it is a color.
    static let colored: ClosedRange<Float> = 0.02...0.06

    /// `kit` (kit paint's paints) made lively, never closer than `minDistance` where kit's
    /// weren't. `shares` is the share of the painting each paint covers (`shares(of:)`), and
    /// `hold` how much of each is skin (0...1, `KitPaint.skinHold`). Shares that aren't the
    /// palette's (another length, a value that is no number, none above zero) count every
    /// paint alike; a `hold` of another length is no skin anywhere.
    public static func mix(
        _ kit: [PaletteColor], shares: [Float] = [], hold: [Float] = [], space: RGBColorSpace, minDistance: Float
    ) -> [PaletteColor] {
        let n = kit.count
        guard n > 0 else { return kit }
        let held = hold.count == n ? hold.map { $0.isFinite ? min(max($0, 0), 1) : 0 } : [Float](repeating: 0, count: n)
        let cover = shares.count == n && shares.allSatisfy({ $0.isFinite && $0 >= 0 }) && shares.contains(where: { $0 > 0 })
            ? shares.map { $0.squareRoot() } : [Float](repeating: 1, count: n)
        let chroma = kit.map { ($0.oklab.y * $0.oklab.y + $0.oklab.z * $0.oklab.z).squareRoot() }
        let hue = kit.indices.map { chroma[$0] > 1e-6 ? SIMD2(kit[$0].oklab.y, kit[$0].oklab.z) / chroma[$0] : SIMD2<Float>(0, 0) }
        let color = chroma.map { KitPaint.smoothstep(colored, $0) }
        // Each paint's family's mean lightness.
        var familyLightness = [Float](repeating: 0, count: n)
        for i in 0..<n where color[i] > 0 {
            var weight: Float = 0, lightness: Float = 0
            for j in 0..<n where color[j] > 0 {
                let inside = min(max(((hue[i] * hue[j]).sum() - reach) / (1 - reach), 0), 1)
                let k = inside * inside * color[j] * cover[j]
                weight += k
                lightness += k * kit[j].oklab.x
            }
            // A paint no painting covers is its own family.
            familyLightness[i] = weight > 0 ? lightness / weight : kit[i].oklab.x
        }
        func encoded(_ lab: SIMD3<Float>) -> PaletteColor {
            let rgb = ColorScience.okLabToEncoded(lab, space: space)
            return PaletteColor(oklab: ColorScience.encodedToOKLab(rgb, space: space), rgb: rgb)
        }
        func paint(_ i: Int, strength: Float) -> PaletteColor {
            guard strength > 0, color[i] > 0 else { return kit[i] }
            let lab = kit[i].oklab
            let own = color[i] * (1 - held[i]) * strength
            let lighter = min(max((lab.x - familyLightness[i]) / span, -1), 1)
            let pole = lighter > 0 ? warm : cool
            // Never past the pole: the half-tangent of the angle to it is |u × p| / (1 + u · p).
            let side = cross(hue[i], pole), along = 1 + (hue[i] * pole).sum()
            let most = turn * abs(lighter) * (across + (1 - across) * along / 2)
            let toPole = along > 1e-3 ? min(most, abs(side) / along) : most
            var s = (side >= 0 ? toPole : -toPole) * own * (1 - vivid * KitPaint.smoothstep(vividChroma, chroma[i]))
            let more = chroma[i] * (1 + gain * (1 - held[i]) * strength * KitPaint.smoothstep(KitPaint.neutralChroma, chroma[i])
                * (1 - KitPaint.smoothstep(KitPaint.vividChroma, chroma[i])))
            // Kit paint's own chroma once in gamut: what a turn may not cost.
            let kept = chroma[i] - 0.002
            for _ in 0..<4 {
                let u = turned(hue[i], by: s) * more
                let mixed = encoded(SIMD3(lab.x, u.x, u.y))
                if (mixed.oklab.y * mixed.oklab.y + mixed.oklab.z * mixed.oklab.z).squareRoot() >= kept { return mixed }
                s /= 2
            }
            let u = hue[i] * more
            return encoded(SIMD3(lab.x, u.x, u.y))
        }
        var strength = [Float](repeating: 1, count: n)
        var mixed = (0..<n).map { paint($0, strength: 1) }
        while true {
            var stepped = false
            for i in 0..<n {
                for j in 0..<n where j > i {
                    let before = ColorScience.distance(kit[i].oklab, kit[j].oklab)
                    let after = ColorScience.distance(mixed[i].oklab, mixed[j].oklab)
                    guard after < minDistance, after < before else { continue }
                    for k in [i, j] where strength[k] > 0 {
                        strength[k] = max(0, strength[k] - KitPaint.backStep)
                        mixed[k] = paint(k, strength: strength[k])
                        stepped = true
                    }
                }
            }
            if !stepped { return mixed }
        }
    }

    /// The share of the painting each of `count` paints covers, by pixels.
    public static func shares(of segmentation: Segmentation) -> [Float] {
        var pixels = [Int](repeating: 0, count: segmentation.palette.count)
        var regions = [Int](repeating: 0, count: segmentation.regionColor.count)
        for region in segmentation.labels.storage where Int(region) < regions.count { regions[Int(region)] += 1 }
        for (region, paint) in segmentation.regionColor.enumerated() where Int(paint) < pixels.count {
            pixels[Int(paint)] += regions[region]
        }
        let total = max(1, pixels.reduce(0, +))
        return pixels.map { Float($0) / Float(total) }
    }

    /// The same of a finished template, by its regions' areas (close to the pixels', not equal:
    /// for a preview of paints a generation will mix from its segmentation).
    public static func shares(of template: Template) -> [Float] {
        var area = [Float](repeating: 0, count: template.palette.count)
        for region in template.regions where Int(region.colorIndex) < area.count && region.area.isFinite {
            area[Int(region.colorIndex)] += max(0, region.area)
        }
        let total = area.reduce(0, +)
        return total > 0 ? area.map { $0 / total } : area
    }

    /// `u × v`: positive when `v` is counter-clockwise of `u`.
    static func cross(_ u: SIMD2<Float>, _ v: SIMD2<Float>) -> Float { u.x * v.y - u.y * v.x }

    /// `u` turned counter-clockwise by the angle whose half's tangent is `s`.
    static func turned(_ u: SIMD2<Float>, by s: Float) -> SIMD2<Float> {
        let d = 1 + s * s, c = (1 - s * s) / d, sn = 2 * s / d
        return SIMD2(u.x * c - u.y * sn, u.x * sn + u.y * c)
    }
}
