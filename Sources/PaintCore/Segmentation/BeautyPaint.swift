/// Beauty paint (`PaintMix.beauty`; painting-company row 360): rich paint mixed for a pretty
/// painting rather than a faithful one. Only the paints move, as with every mix.
///
/// The beauty spike (painting-company `factory/pieces/beauty-paint/`) tried eleven ways on 22
/// pictures; the one chosen is three steps on rich paint's colors:
///
/// 1. **No mud** (`clean`): a black with no hue of its own (below `neutralChroma`, darker than
///    `darkLightness`) is mixed from a touch of indigo, as a painter mixes black, never from
///    black itself; other greys stay grey. A clearly coloured paint still greyed (from about
///    0.035 up to `greyChroma`) keeps its own hue and gets a little more of it (`greyGain`). A khaki or olive
///    (`mudArc`, `mudChroma`, `mudLightness`) turns part of the way to sienna or sap green,
///    whichever is nearer, with more chroma (`mudGain`); every other paint gets a little more
///    (`gain`). Skin keeps its colors (`hold`, `KitPaint.skinHold`). Two critic rounds took the
///    rest of the spike's version out: pulling every grey toward indigo, violet or a warm pearl
///    gave navy chocolate, blue-violet shadows on dark skin, peach snow and khaki or lavender
///    storm skies, and the greys' own hue pushed harder turned grey clouds olive.
/// 2. **Vibrance**: more chroma where a paint has some but little (`vibrance`, fading in over
///    `huedChroma` and out by `vibranceLimit`; a pale greyish paint, `pastel`, none), skin held
///    to `skinVibrance` of it, and the lightness spread around the painting's median by
///    `contrast`, unless that would cost a paint at the gamut's edge chroma.
/// 3. **Focus**, when the importance of each paint is known and uneven (`evenImportance`): a third (`focus`) of the way to a
///    painting whose subject (above the `subjectCut` share of the importance) is bolder
///    (`subjectGain`) and whose background recedes into a soft blue haze (`haze`), a dark
///    background by losing color rather than into grey, a vivid one (`vividChroma`) not at all.
/// 4. **A face held near the photo** (`faceGain`): a paint whose pixels lie mostly on a face
///    (`faceHeldShare`) is mixed at most `faceGain` times as colorful as the photo's (`photo`,
///    the regions' means), and a greyish one `faceLift` more (`faceLiftFade`), so a pale face's
///    lit side and a dark face's warm shadows keep what kit and rich paint gave them. Kit, rich
///    and beauty paint each add chroma, and skin's hold ends at a lip's red, so a man's pink lips
///    in a dim selfie came out crimson and his cheeks apricot (painting-company row 363).
///
/// Rich paint's colors go in, so a face keeps its own paints (`FacePaints`). Two paints the
/// steps bring closer than `minDistance` step back toward rich paint's until they are apart.
/// Hues move by vectors, never angles: no trigonometry, so the same paints mix to the same
/// paints on every device.
public enum BeautyPaint {
    /// Below this chroma a paint has no hue of its own; a dark one is mixed from color, fully at 0.
    static let neutralChroma: Float = 0.025
    /// Up to this chroma a paint is a greyed color: its own hue, `greyGain` more of it at most.
    static let greyChroma: Float = 0.06
    static let greyGain: Float = 0.2
    /// Below this lightness a neutral is a dark: a touch of indigo (OKLab hue 280°).
    static let darkLightness: Float = 0.25
    static let indigo = SIMD2<Float>(0.173_648, -0.984_808)
    static let indigoChroma: Float = 0.02
    /// Mud: hues from 45° to 115°, from `greyChroma` (a greyer paint keeps its hue) to this
    /// chroma, in this lightness.
    static let mudFrom = SIMD2<Float>(0.707_107, 0.707_107)
    static let mudTo = SIMD2<Float>(-0.422_618, 0.906_308)
    static let mudSplit = SIMD2<Float>(0.087_156, 0.996_195)
    static let mudChroma: Float = 0.1
    static let mudLightness: ClosedRange<Float> = 0.25...0.55
    /// Mud turns this share of the way to sienna (50°) below 85°, sap green (125°) above.
    static let sienna = SIMD2<Float>(0.642_788, 0.766_044)
    static let sapGreen = SIMD2<Float>(-0.573_576, 0.819_152)
    static let mudTurn: Float = 0.4
    static let mudGain: Float = 0.2
    static let gain: Float = 0.08
    /// Vibrance: chroma × (1 + vibrance · (1 − C / limit)^1.5).
    static let vibrance: Float = 0.45
    static let vibranceLimit: Float = 0.22
    /// Vibrance is for paints with a hue: none below this chroma, all above (a warm grey wall
    /// given it went mustard, a grey cloud olive: the third round's critic).
    static let huedChroma: ClosedRange<Float> = 0.03...0.07
    static let skinVibrance: Float = 0.3
    static let contrast: Float = 1.08
    static let lightnessRange: ClosedRange<Float> = 0.06...0.97
    /// Focus: its share of the mix, the importance share that is subject, and the subject's gain.
    static let focus: Float = 0.33
    static let subjectCut: Float = 0.55
    static let subjectGain: Float = 0.35
    /// Paints whose mean importance spans less than this get no focus.
    static let evenImportance: Float = 0.1
    static let haze = SIMD3<Float>(0.86, -0.0125, -0.021_651)
    static let hazeMost: Float = 0.2
    static let vividChroma: ClosedRange<Float> = 0.08...0.14
    /// A face's paint: at most `faceGain` times the photo's chroma, and `faceLift` more for a
    /// greyish one (fading out over `faceLiftFade`), held fully once `faceHeldShare` of its
    /// pixels lie on a face.
    static let faceGain: Float = 1.1
    static let faceLift: Float = 0.03
    static let faceLiftFade: ClosedRange<Float> = 0.03...0.08
    static let faceHeldShare: ClosedRange<Float> = 0.2...0.5

    /// `rich` (rich paint's colors) mixed as beauty paint. `shares`: the share of the painting
    /// each paint covers; `hold`: how much each is skin (`KitPaint.skinHold`); `faceShare`: the
    /// share of its pixels on a face; `importance`: its pixels' mean importance (`importance(of:…)`);
    /// `photo`: the regions' colors rich paint was mixed from (a face isn't held without).
    /// A list that isn't the palette's is left out (no focus without importance).
    public static func mix(
        _ rich: [PaletteColor], shares: [Float] = [], hold: [Float] = [], faceShare: [Float] = [], importance: [Float] = [],
        photo: [PaletteColor] = [], space: RGBColorSpace, minDistance: Float
    ) -> [PaletteColor] {
        let n = rich.count
        guard n > 0 else { return rich }
        func valid(_ list: [Float]) -> [Float]? {
            list.count == n && list.allSatisfy(\.isFinite) ? list.map { min(max($0, 0), 1) } : nil
        }
        let weight = valid(shares).flatMap { s in s.contains(where: { $0 > 0 }) ? s : nil } ?? [Float](repeating: 1, count: n)
        let skin = valid(hold) ?? [Float](repeating: 0, count: n)
        let face = valid(faceShare) ?? [Float](repeating: 0, count: n)

        // 1. No mud.
        let clean: [SIMD3<Float>] = rich.indices.map { i in
            let lab = rich[i].oklab, L = lab.x
            let ab = SIMD2(lab.y, lab.z), C = length(ab)
            let own = 1 - skin[i]
            if C < neutralChroma {
                let t = (1 - C / neutralChroma) * own
                let target = L < darkLightness ? indigo * indigoChroma : ab
                let mixed = ab * (1 - t) + target * t
                return SIMD3(L, mixed.x, mixed.y)
            }
            if C < greyChroma {
                // Fades in from no-hue and out toward a full color, so neighbors stay in order.
                let more = 1 + greyGain * own * pastel(L, C) * KitPaint.smoothstep(0.035...0.045, C)
                    * (1 - KitPaint.smoothstep(0.045...greyChroma, C))
                return SIMD3(L, lab.y * more, lab.z * more)
            }
            let u = ab / C
            if C < mudChroma, mudLightness.contains(L), cross(mudFrom, u) >= 0, cross(u, mudTo) >= 0 {
                let target = cross(mudSplit, u) < 0 ? sienna : sapGreen
                let s = mudTurn * own
                let turned = u * (1 - s) + target * s
                let v = turned / max(length(turned), 1e-6) * C * (1 + mudGain * own)
                return SIMD3(L, v.x, v.y)
            }
            return SIMD3(L, lab.y * (1 + gain * own), lab.z * (1 + gain * own))
        }

        // 2. Vibrance.
        let middle2 = percentile(clean.map(\.x), weights: weight, 0.5)
        let vivid: [SIMD3<Float>] = clean.indices.map { i in
            let lab = clean[i]
            let C = length(SIMD2(lab.y, lab.z))
            let k = vibrance * (1 - (1 - skinVibrance) * skin[i]) * KitPaint.smoothstep(huedChroma, C) * pastel(lab.x, C)
            let fade = max(0, 1 - C / vibranceLimit)
            let more = 1 + k * fade * fade.squareRoot()
            let L = min(max(middle2 + (lab.x - middle2) * contrast, lightnessRange.lowerBound), lightnessRange.upperBound)
            let wanted = SIMD3(L, lab.y * more, lab.z * more)
            // A vivid paint at the gamut's edge keeps its lightness where the spread would cost it
            // chroma (a macaw's yellow chest, lifted, washed out to butter).
            let fits = ColorScience.encodedToOKLab(ColorScience.okLabToEncoded(wanted, space: space), space: space)
            return length(SIMD2(fits.y, fits.z)) < C - 0.005 ? SIMD3(lab.x, wanted.y, wanted.z) : wanted
        }

        // 3. Focus.
        var target = vivid
        // An even map names no subject: every paint would come forward and none recede.
        if let importance = valid(importance), (importance.max() ?? 0) - (importance.min() ?? 0) >= evenImportance {
            let cut = percentile(importance, weights: weight, subjectCut)
            target = vivid.indices.map { i in
                let lab = vivid[i]
                let w = KitPaint.smoothstep((cut - 0.15)...(cut + 0.05), importance[i])
                let focused: SIMD3<Float>
                if w > 0.55 || face[i] > 0.3 {
                    let more = 1 + subjectGain * (1 - skin[i])
                    focused = SIMD3(min(lab.x, 0.95), lab.y * more, lab.z * more)
                } else {
                    // A vivid paint keeps its color however little it matters (a crimson sweater went brick).
                    let C = length(SIMD2(lab.y, lab.z))
                    var t = hazeMost * (1 - KitPaint.smoothstep(0.1...0.55, w)) * (1 - KitPaint.smoothstep(vividChroma, C))
                    let less = 1 - 0.5 * t / hazeMost
                    let base = SIMD3(lab.x, lab.y * less, lab.z * less)
                    t *= KitPaint.smoothstep(0.3...0.6, lab.x)
                    focused = base * (1 - t) + haze * t
                }
                return lab * (1 - focus) + focused * focus
            }
        }

        // 4. A face held near the photo.
        let limit: [(chroma: Float, weight: Float)?] = rich.indices.map { i in
            guard photo.count == n, face[i] > faceHeldShare.lowerBound else { return nil }
            let lab = photo[i].oklab
            let C = length(SIMD2(lab.y, lab.z))
            guard C.isFinite else { return nil }
            return (C * faceGain + faceLift * (1 - KitPaint.smoothstep(faceLiftFade, C)), KitPaint.smoothstep(faceHeldShare, face[i]))
        }
        // Scaled with the strength, so a paint stepped all the way back is rich paint's again.
        func limited(_ i: Int, _ lab: SIMD3<Float>, strength: Float) -> SIMD3<Float> {
            guard let (cap, full) = limit[i] else { return lab }
            let w = full * strength
            let C = length(SIMD2(lab.y, lab.z))
            guard C > cap else { return lab }
            let scale = 1 - w + w * cap / C
            return SIMD3(lab.x, lab.y * scale, lab.z * scale)
        }

        func encoded(_ lab: SIMD3<Float>) -> PaletteColor {
            let rgb = ColorScience.okLabToEncoded(lab, space: space)
            return PaletteColor(oklab: ColorScience.encodedToOKLab(rgb, space: space), rgb: rgb)
        }
        func paint(_ i: Int, strength: Float) -> PaletteColor {
            strength > 0 ? encoded(limited(i, rich[i].oklab + (target[i] - rich[i].oklab) * strength, strength: strength)) : rich[i]
        }
        var strength = [Float](repeating: 1, count: n)
        var mixed = (0..<n).map { paint($0, strength: 1) }
        while true {
            var stepped = false
            for i in 0..<n {
                for j in 0..<n where j > i {
                    let before = ColorScience.distance(rich[i].oklab, rich[j].oklab)
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

    /// Each paint's pixels' mean importance (0 for a paint with none), or empty when the map
    /// isn't the segmentation's size.
    public static func importance(of segmentation: Segmentation, importance: [Float]) -> [Float] {
        let n = segmentation.width * segmentation.height
        guard importance.count == n else { return [] }
        var sum = [Double](repeating: 0, count: segmentation.palette.count)
        var count = [Int](repeating: 0, count: segmentation.palette.count)
        for i in 0..<n {
            let region = Int(segmentation.labels.storage[i])
            guard region < segmentation.regionColor.count else { continue }
            let paint = Int(segmentation.regionColor[region])
            guard paint < sum.count, importance[i].isFinite else { continue }
            sum[paint] += Double(importance[i])
            count[paint] += 1
        }
        return sum.indices.map { count[$0] > 0 ? Float(sum[$0] / Double(count[$0])) : 0 }
    }

    /// The value below which `fraction` of the weight lies (the values sorted, ties by index).
    static func percentile(_ values: [Float], weights: [Float], _ fraction: Float) -> Float {
        let order = values.indices.sorted { values[$0] < values[$1] || (values[$0] == values[$1] && $0 < $1) }
        let total = weights.reduce(0, +)
        guard total > 0 else { return values[order[order.count / 2]] }
        var running: Float = 0
        for k in order {
            running += weights[k]
            if running >= fraction * total { return values[k] }
        }
        return values[order[order.count - 1]]
    }

    /// How much of a greyed paint's extra chroma it may take: none for a pale, greyish one (a
    /// wall, a cloud, a stone in the light: given it, they went mustard and olive), all below
    /// `paleLightness` or above `paleChroma`.
    static func pastel(_ L: Float, _ C: Float) -> Float {
        1 - KitPaint.smoothstep(paleLightness, L) * (1 - KitPaint.smoothstep(paleChroma, C))
    }
    static let paleLightness: ClosedRange<Float> = 0.55...0.7
    static let paleChroma: ClosedRange<Float> = 0.06...0.09

    static func length(_ v: SIMD2<Float>) -> Float { (v.x * v.x + v.y * v.y).squareRoot() }
    static func cross(_ u: SIMD2<Float>, _ v: SIMD2<Float>) -> Float { u.x * v.y - u.y * v.x }
}
