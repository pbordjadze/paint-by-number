/// How a template's paints are mixed from its regions' colors (`GenerationSettings.paintMix`).
public enum PaintMix: String, Sendable, Hashable, Codable, CaseIterable {
    /// Each paint is the mean color of its regions, as the segmentation fits it: faithful to
    /// the photo, and greyer than it, since averaging pulls toward grey.
    case photo
    /// The same regions in the paints a kit would sell (`KitPaint`): bolder and cleaner than
    /// the regions' means, skin kept close to the photo.
    case kit
}

/// Kit paint: the finished template's paints mixed as a paint-by-numbers kit mixes them, bolder
/// than the photo's averages. Only the paints move; regions, numbers and lines are untouched.
///
/// Averaging a region's pixels makes its paint greyer and flatter than the photo: over the
/// over-constraint spike's twelve photos (painting-company row 191, `docs/over-constraint-spike.md`)
/// the painting kept 95 % of the photo's top-decile chroma and 96 % of its lightness spread,
/// while a kit's paints are mixed brighter than the photo. Each paint gets
///
/// - up to `chromaGain` more chroma, fading in over near-greys (`neutralChroma`: an off-white
///   would turn pink) and out over paints already vivid (`vividChroma`: they would clip or turn
///   neon);
/// - a wider lightness spread (`lightnessSpread`), as a cubic that leaves black and white where
///   they are, so the lightest paints never pile up at the paper's white;
/// - less of both on skin (`skinHue`…, `skinShare`): a sunburnt face is the complaint painters
///   make most of a kit's paints; instead light skin is lifted (`skinLift`, never dark skin)
///   and turned a little from yellow toward pink (`skinTurn`), since a coloring book's larger
///   cells average a face's shadows into its paint, which read khaki beside the photo's peach
///   (the round-1 critic, on kodim04 and street-couple). Skin's colour is a fox's, a lion's and
///   a loaf's too, so all of this is for paints on a face (`faceShare`: the share of a paint's
///   pixels where the importance map marks a face), and paints of skin's colour elsewhere are
///   only held back a little (`elsewhereSkin`: a fox treated as skin turned beige);
/// - less gain on pale paints (`paleCut`): a wall or a sky boosted outshone the faces;
///
/// then is brought into gamut by chroma alone (`ColorScience.okLabToEncoded`). Two paints the
/// change brings closer than the template's `minPaletteDistance` both step back toward their
/// regions' colors until they are apart again, so paints stay as distinct as the pipeline made
/// them. Pure arithmetic (`sqrt`, the color space's transfer curve), so the same paints give the
/// same paints on every device.
public enum KitPaint {
    /// The most chroma is multiplied by (1.3 in the spike, where it read best at a glance).
    static let chromaGain: Float = 0.3
    /// Below the lower chroma a paint is grey and keeps its chroma; above the upper it gets all.
    static let neutralChroma: ClosedRange<Float> = 0.015...0.04
    /// Over this chroma range the gain fades out: a paint at the upper end is vivid already.
    static let vividChroma: ClosedRange<Float> = 0.12...0.2
    /// The lightness push, `spread · (L − ½) · 4L(1 − L)`: 0 at black, middle grey and white,
    /// about +0.04 at L 0.8 (the spike's linear 1.15× gave +0.045 but clamped the whites
    /// together). Its slope stays above 1 − 2 · spread, so paints mixed alike (the greys, say)
    /// keep their order of lightness.
    static let lightnessSpread: Float = 0.2
    /// Skin's hue in OKLab, as a unit vector (50°: pale to very dark skin measure 48°–64°, a
    /// flushed cheek 28°), and the cosines of the hue difference where skin fades out (40°) and
    /// is full (25°).
    static let skinHue = SIMD2<Float>(0.642_788, 0.766_044)
    static let skinCosine: ClosedRange<Float> = 0.766...0.906
    /// Skin's chroma: above this range a paint is too vivid to be skin (a fox's coat, a
    /// pumpkin; at 0.10–0.14 a fox's lighter fur was lifted and turned peach). Tan skin measures
    /// about 0.09.
    static let skinChroma: ClosedRange<Float> = 0.09...0.12
    /// The share of the gain and spread skin keeps: 1.06× chroma and a gentle spread (at 1.12×
    /// warm faces drifted orange).
    static let skinShare: Float = 0.2
    /// Light skin's lift: up to +0.05 lightness, full from L 0.62 to 0.74, none below 0.5 (dark
    /// skin keeps its depth) nor above 0.84 (pale skin lifted more read bleached).
    static let skinLift: Float = 0.05
    static let lightSkin: ClosedRange<Float> = 0.5...0.62
    static let skinHighlight: ClosedRange<Float> = 0.74...0.84
    /// Skin's hue turned toward pink by up to this angle, in radians (5.7°).
    static let skinTurn: Float = 0.1
    /// The share of the gain pale, soft paints lose, fading in over `pale` lightness and out
    /// over `paleChroma` (a pale orange fur keeps its gain).
    static let paleCut: Float = 0.4
    static let pale: ClosedRange<Float> = 0.72...0.9
    static let paleChroma: ClosedRange<Float> = 0.05...0.09
    /// The share of skin's restraint a paint of skin's colour gets off any face.
    static let elsewhereSkin: Float = 0.35
    /// Importance from which a pixel is on a face (the app's map raises Vision's faces toward
    /// 1 in an ellipse; the subject sits at 0.75), and the share of a paint's pixels there
    /// over which it becomes a face's paint.
    static let faceImportance: Float = 0.9
    static let faceShareRange: ClosedRange<Float> = 0.1...0.3
    /// The strength two paints too close step back by, a round at a time.
    static let backStep: Float = 0.25

    /// The palette mixed as a kit would mix it, never closer than `minDistance` where the
    /// regions' colors weren't. Each paint's `oklab` is its in-gamut color's. `faces` is each
    /// paint's share of pixels on a face (`faceShare`); nil, or a count that isn't the
    /// palette's, is no face anywhere.
    public static func mix(
        _ palette: [PaletteColor], space: RGBColorSpace, minDistance: Float, faces: [Float]? = nil
    ) -> [PaletteColor] {
        let onFace = palette.indices.map { k in
            faces.map { $0.count == palette.count ? smoothstep(faceShareRange, $0[k]) : 0 } ?? 0
        }
        var strength = [Float](repeating: 1, count: palette.count)
        var mixed = palette.indices.map { mix(palette[$0], strength: 1, face: onFace[$0], space: space) }
        // Few paints (at most 150), and rarely more than one round.
        while true {
            var stepped = false
            for i in mixed.indices {
                for j in mixed.indices where j > i {
                    let before = ColorScience.distance(palette[i].oklab, palette[j].oklab)
                    let after = ColorScience.distance(mixed[i].oklab, mixed[j].oklab)
                    guard after < minDistance, after < before else { continue }
                    for k in [i, j] where strength[k] > 0 {
                        strength[k] = max(0, strength[k] - backStep)
                        mixed[k] = mix(palette[k], strength: strength[k], face: onFace[k], space: space)
                        stepped = true
                    }
                }
            }
            if !stepped { return mixed }
        }
    }

    /// Each paint's share of its pixels on a face: importance at least `faceImportance` in
    /// `importance` (the segmentation's weights, one per pixel), counted exactly.
    public static func faceShare(_ segmentation: Segmentation, importance: [Float]) -> [Float] {
        let n = segmentation.width * segmentation.height
        guard importance.count == n else { return [Float](repeating: 0, count: segmentation.palette.count) }
        var total = [Int](repeating: 0, count: segmentation.palette.count)
        var face = total
        for i in 0..<n {
            let region = Int(segmentation.labels.storage[i])
            guard region < segmentation.regionColor.count else { continue }
            let paint = Int(segmentation.regionColor[region])
            guard paint < total.count else { continue }
            total[paint] += 1
            if importance[i] >= faceImportance { face[paint] += 1 }
        }
        return zip(face, total).map { $1 > 0 ? Float($0) / Float($1) : 0 }
    }

    /// One paint at a strength (0: the regions' color, 1: the kit's), `face` how much it is a
    /// face's paint (0...1).
    static func mix(_ paint: PaletteColor, strength: Float, face: Float = 0, space: RGBColorSpace) -> PaletteColor {
        guard strength > 0 else { return paint }
        let lab = paint.oklab
        let chroma = (lab.y * lab.y + lab.z * lab.z).squareRoot()
        var skin: Float = 0
        if chroma > 0 {
            let cosine = (lab.y * skinHue.x + lab.z * skinHue.y) / chroma
            // Faded with the gain over near-greys too, so greys are all mixed alike and keep
            // their order of lightness, a warm one beside a cool one.
            skin = smoothstep(skinCosine, cosine) * (1 - smoothstep(skinChroma, chroma)) * smoothstep(neutralChroma, chroma)
        }
        let share = strength * (1 - (1 - skinShare) * skin * (elsewhereSkin + (1 - elsewhereSkin) * face))
        let L = min(max(lab.x, 0), 1)
        let gain = 1 + chromaGain * share * smoothstep(neutralChroma, chroma) * (1 - smoothstep(vividChroma, chroma))
            * (1 - paleCut * smoothstep(pale, L) * (1 - smoothstep(paleChroma, chroma)))
        var lightness = L + lightnessSpread * share * (L - 0.5) * 4 * L * (1 - L)
        let onSkin = strength * skin * face
        lightness += skinLift * onSkin * smoothstep(lightSkin, L) * (1 - smoothstep(skinHighlight, L))
        // A small turn toward pink, kept to its chroma: (a, b) rotated by −θ to first order.
        let theta = skinTurn * onSkin
        let norm = 1 / (1 + theta * theta).squareRoot()
        let a = (lab.y + theta * lab.z) * norm, b = (lab.z - theta * lab.y) * norm
        let rgb = ColorScience.okLabToEncoded(SIMD3(lightness, a * gain, b * gain), space: space)
        return PaletteColor(oklab: ColorScience.encodedToOKLab(rgb, space: space), rgb: rgb)
    }

    static func smoothstep(_ edges: ClosedRange<Float>, _ x: Float) -> Float {
        let t = min(max((x - edges.lowerBound) / (edges.upperBound - edges.lowerBound), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
