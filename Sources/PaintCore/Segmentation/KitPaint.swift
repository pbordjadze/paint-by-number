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
///   make most of a kit's paints;
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
    /// together). Its slope stays above 1 − 2 · spread, so lightness keeps its order.
    static let lightnessSpread: Float = 0.2
    /// Skin's hue in OKLab, as a unit vector (50°: pale to very dark skin measure 48°–64°, a
    /// flushed cheek 28°), and the cosines of the hue difference where skin fades out (40°) and
    /// is full (25°).
    static let skinHue = SIMD2<Float>(0.642_788, 0.766_044)
    static let skinCosine: ClosedRange<Float> = 0.766...0.906
    /// Skin's chroma: above this range a paint is too vivid to be skin (a fox, a pumpkin).
    static let skinChroma: ClosedRange<Float> = 0.10...0.14
    /// The share of the gain and spread skin keeps: 1.12× chroma, which brings a face's mean
    /// chroma back to about the photo's (averaging left it at 89 % over the evaluation set's
    /// faces), and a gentle spread.
    static let skinShare: Float = 0.4
    /// The strength two paints too close step back by, a round at a time.
    static let backStep: Float = 0.25

    /// The palette mixed as a kit would mix it, never closer than `minDistance` where the
    /// regions' colors weren't. Each paint's `oklab` is its in-gamut color's.
    public static func mix(_ palette: [PaletteColor], space: RGBColorSpace, minDistance: Float) -> [PaletteColor] {
        var strength = [Float](repeating: 1, count: palette.count)
        var mixed = palette.map { mix($0, strength: 1, space: space) }
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
                        mixed[k] = mix(palette[k], strength: strength[k], space: space)
                        stepped = true
                    }
                }
            }
            if !stepped { return mixed }
        }
    }

    /// One paint at a strength (0: the regions' color, 1: the kit's).
    static func mix(_ paint: PaletteColor, strength: Float, space: RGBColorSpace) -> PaletteColor {
        guard strength > 0 else { return paint }
        let lab = paint.oklab
        let chroma = (lab.y * lab.y + lab.z * lab.z).squareRoot()
        var skin: Float = 0
        if chroma > 0 {
            let cosine = (lab.y * skinHue.x + lab.z * skinHue.y) / chroma
            skin = smoothstep(skinCosine, cosine) * (1 - smoothstep(skinChroma, chroma))
        }
        let share = strength * (1 - (1 - skinShare) * skin)
        let gain = 1 + chromaGain * share * smoothstep(neutralChroma, chroma) * (1 - smoothstep(vividChroma, chroma))
        let L = min(max(lab.x, 0), 1)
        let lightness = L + lightnessSpread * share * (L - 0.5) * 4 * L * (1 - L)
        let rgb = ColorScience.okLabToEncoded(SIMD3(lightness, lab.y * gain, lab.z * gain), space: space)
        return PaletteColor(oklab: ColorScience.encodedToOKLab(rgb, space: space), rgb: rgb)
    }

    static func smoothstep(_ edges: ClosedRange<Float>, _ x: Float) -> Float {
        let t = min(max((x - edges.lowerBound) / (edges.upperBound - edges.lowerBound), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
