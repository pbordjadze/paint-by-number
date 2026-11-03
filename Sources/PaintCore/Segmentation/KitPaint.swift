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
///   and turned to the photo's own skin hue (`skinAnchor`): a face's paints averaged over a
///   coloring book's larger cells came out up to 8° yellower than the face (kodim04: 65° for
///   the photo's 57°), which read khaki beside it (the critics of rounds 1 and 3). Skin's
///   colour is a fox's, a lion's and a loaf's too, so all of this is for paints on a face
///   (`Faces`: the share of a paint's pixels on a person's face, where the importance map
///   marks a face near an eye Vision found; its animal boxes raise the map alike, and a
///   ginger cat is no face), and paints of skin's colour elsewhere are only held back a
///   little (`elsewhereSkin`: a fox treated as skin turned beige);
/// - on a pale face in dim light (`Faces.pallor`: little chroma for its lightness, kodim04's
///   fair face at L 0.52, C 0.042), the lit side painted as a kit paints fair skin, lighter
///   (`paleLift`) and a cleaner, pinker peach (`paleFloor`, `palePink`), its shadows left: matched to the photo,
///   such a face read muddy grey-brown beside a red hat (the round 4 critic). Tanned, flushed
///   and dark skin has the chroma for its lightness and is left as above;
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
    /// How far a face's paint turns to the photo's skin hue (`Faces.skinHue`), at most: most of
    /// the way, keeping a little of each paint's own (a flushed cheek, a shadow's coolness).
    static let skinAnchor: Float = 0.8
    /// The anchor corrects a drift, never a colour: it turns paints within 10° of the face's
    /// hue fully and none past 20° (a hat's red shadow by the face, 30° off, turned brown).
    static let anchorCosine: ClosedRange<Float> = 0.94...0.985
    /// The share of the gain pale, soft paints lose, fading in over `pale` lightness and out
    /// over `paleChroma` (a pale orange fur keeps its gain).
    static let paleCut: Float = 0.4
    static let pale: ClosedRange<Float> = 0.72...0.9
    static let paleChroma: ClosedRange<Float> = 0.05...0.09
    /// A face's pallor (`Faces.pallor`) is full below the lower ratio of its skin's chroma to its
    /// lightness and none above the upper: fair skin in dim light measures 0.07–0.08 (kodim04,
    /// the astronaut, the street couple), sunburnt children 0.13, tanned and dark skin 0.15–0.16.
    static let pallidRatio: ClosedRange<Float> = 0.09...0.11
    /// A pale face's lit paints, from `litBelow` under its skin's mean lightness to the mean,
    /// get up to this much more lightness (fading out over `skinHighlight`) and at least
    /// `paleFloor` × L chroma: 0.05 at L 0.7, the clean peach of a kit's fair skin.
    static let paleLift: Float = 0.06
    static let litBelow: Float = 0.06
    static let paleFloor: Float = 0.07
    /// …and are turned up to this share of the way to `peach` (45°, a kit's fair-skin mix).
    static let palePink: Float = 0.5
    static let peach = SIMD2<Float>(0.707_107, 0.707_107)
    /// The share of skin's restraint a paint of skin's colour gets off any face.
    static let elsewhereSkin: Float = 0.35
    /// Importance from which a pixel is on a face (the app's map raises Vision's faces, and
    /// its animals, toward 1 in an ellipse; the subject sits at 0.75), within `faceReach` eye
    /// widths of an eye's centre (eyes come from a person's face landmarks only; the chin is
    /// about three eye widths below them), and the share of a paint's pixels there over which
    /// it becomes a face's paint.
    static let faceImportance: Float = 0.9
    static let faceReach: Float = 4
    /// The face's skin is measured within this many eye widths of an eye (cheeks, nose,
    /// brow): further out, blond hair at skin's hue made kodim04's pale face read tanned.
    static let skinReach: Float = 2
    /// From 3 % (a face's skin paint is also the neck's, the chest's and the arms').
    static let faceShareRange: ClosedRange<Float> = 0.03...0.12

    /// Where the faces are, for the skin of `mix`: each paint's share of its pixels on a
    /// person's face, and the photo's own skin hue there (a unit vector in OKLab's a, b; nil
    /// when no face shows skin).
    public struct Faces: Sendable, Equatable {
        public var share: [Float]
        public var skinHue: SIMD2<Float>?
        /// The photo's mean skin lightness on the faces (0 when none shows skin).
        public var skinLightness: Float
        /// How pale the faces' skin is for its lightness, 0...1 (`pallidRatio`).
        public var pallor: Float

        public init(share: [Float], skinHue: SIMD2<Float>? = nil, skinLightness: Float = 0, pallor: Float = 0) {
            self.share = share
            self.skinHue = skinHue
            self.skinLightness = skinLightness
            self.pallor = pallor
        }
    }
    /// The strength two paints too close step back by, a round at a time.
    static let backStep: Float = 0.25

    /// The palette mixed as a kit would mix it, never closer than `minDistance` where the
    /// regions' colors weren't. Each paint's `oklab` is its in-gamut color's. `faces` says
    /// which paints are on a face (`faces(of:importance:eyes:photo:)`); nil, or shares that
    /// aren't the palette's, is no face anywhere.
    public static func mix(
        _ palette: [PaletteColor], space: RGBColorSpace, minDistance: Float, faces: Faces? = nil
    ) -> [PaletteColor] {
        let onFace = palette.indices.map { k in
            faces.map { $0.share.count == palette.count ? smoothstep(faceShareRange, $0.share[k]) : 0 } ?? 0
        }
        let anchor = faces?.skinHue
        let pallid = faces.map { Pallid(lightness: $0.skinLightness, pallor: min(max($0.pallor, 0), 1)) }
        var strength = [Float](repeating: 1, count: palette.count)
        var mixed = palette.indices.map { mix(palette[$0], strength: 1, face: onFace[$0], skinHue: anchor, pallid: pallid, space: space) }
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
                        mixed[k] = mix(palette[k], strength: strength[k], face: onFace[k], skinHue: anchor, pallid: pallid, space: space)
                        stepped = true
                    }
                }
            }
            if !stepped { return mixed }
        }
    }

    /// Where the faces are: a pixel is on a face where `importance` (the segmentation's
    /// weights, one per pixel) is at least `faceImportance` near one of `eyes` (closed polygons
    /// normalized to the photo, `LineArtInput.eyes`); each paint's share of its pixels there is
    /// counted exactly, and the skin hue is the mean direction of `photo`'s skin-hued pixels
    /// within `skinReach` (the working image, the segmentation's size), its lightness and
    /// pallor their mean's. No eyes, no face.
    public static func faces(
        of segmentation: Segmentation, importance: [Float], eyes: [[SIMD2<Float>]], photo: RGBAImage
    ) -> Faces {
        let w = segmentation.width, h = segmentation.height, n = w * h
        var total = [Int](repeating: 0, count: segmentation.palette.count)
        guard importance.count == n, !eyes.isEmpty else { return Faces(share: total.map { _ in 0 }) }
        // 1 within `faceReach` of an eye, 2 within `skinReach`.
        var near = [UInt8](repeating: 0, count: n)
        let size = SIMD2(Float(w), Float(h))
        for eye in eyes where !eye.isEmpty && eye.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) {
            let points = eye.map { $0 * size }
            var lo = points[0], hi = points[0], sum = SIMD2<Float>(0, 0)
            for p in points {
                lo = pointwiseMin(lo, p)
                hi = pointwiseMax(hi, p)
                sum += p
            }
            let centre = sum / Float(points.count)
            let reach = faceReach * max(hi.x - lo.x, hi.y - lo.y)
            // Bounded before any Int conversion: a coordinate far off the canvas would trap.
            guard reach > 0, reach < Float(w + h), abs(centre.x) < Float(2 * (w + h)), abs(centre.y) < Float(2 * (w + h))
            else { continue }
            let x0 = max(0, Int((centre.x - reach).rounded(.down))), x1 = min(w - 1, Int((centre.x + reach).rounded(.up)))
            let y0 = max(0, Int((centre.y - reach).rounded(.down))), y1 = min(h - 1, Int((centre.y + reach).rounded(.up)))
            guard x0 <= x1, y0 <= y1 else { continue }
            for y in y0...y1 {
                for x in x0...x1 {
                    let d = SIMD2(Float(x) + 0.5, Float(y) + 0.5) - centre
                    let d2 = (d * d).sum(), core = reach * skinReach / faceReach
                    if d2 <= core * core {
                        near[y * w + x] = 2
                    } else if d2 <= reach * reach, near[y * w + x] == 0 {
                        near[y * w + x] = 1
                    }
                }
            }
        }
        var face = total
        let readsPhoto = photo.width == w && photo.height == h
        var hueSum = SIMD2<Double>(0, 0), skinSum = SIMD2<Double>(0, 0), skinCount = 0
        for i in 0..<n {
            let region = Int(segmentation.labels.storage[i])
            guard region < segmentation.regionColor.count else { continue }
            let paint = Int(segmentation.regionColor[region])
            guard paint < total.count else { continue }
            total[paint] += 1
            guard near[i] > 0, importance[i] >= faceImportance else { continue }
            face[paint] += 1
            guard readsPhoto, near[i] == 2 else { continue }
            let rgb = SIMD3(Float(photo.pixels[4 * i]), Float(photo.pixels[4 * i + 1]), Float(photo.pixels[4 * i + 2])) / 255
            let lab = ColorScience.encodedToOKLab(rgb, space: photo.colorSpace)
            let chroma = (lab.y * lab.y + lab.z * lab.z).squareRoot()
            // Skin-hued and coloured: not the eyes, lips' red nor the hair's grey.
            guard chroma > neutralChroma.lowerBound, (lab.y * skinHue.x + lab.z * skinHue.y) / chroma > skinCosine.lowerBound
            else { continue }
            hueSum += SIMD2(Double(lab.y / chroma), Double(lab.z / chroma))
            skinSum += SIMD2(Double(lab.x), Double(chroma))
            skinCount += 1
        }
        let length = (hueSum * hueSum).sum().squareRoot()
        let skin = skinCount > 0 ? skinSum / Double(skinCount) : SIMD2(0, 0)
        return Faces(
            share: zip(face, total).map { $1 > 0 ? Float($0) / Float($1) : 0 },
            skinHue: length > 0 ? SIMD2(Float(hueSum.x / length), Float(hueSum.y / length)) : nil,
            skinLightness: Float(skin.x),
            pallor: skin.x > 0 ? 1 - smoothstep(pallidRatio, Float(skin.y / skin.x)) : 0)
    }

    /// A pale face's skin: its mean lightness and its pallor.
    struct Pallid {
        var lightness: Float
        var pallor: Float
    }

    /// One paint at a strength (0: the regions' color, 1: the kit's), `face` how much it is a
    /// face's paint (0...1), `skinHue` the photo's skin there, `pallid` its pallor.
    static func mix(
        _ paint: PaletteColor, strength: Float, face: Float = 0, skinHue anchor: SIMD2<Float>? = nil, pallid: Pallid? = nil,
        space: RGBColorSpace
    ) -> PaletteColor {
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
        // A face's paint turned to the face's own hue, kept to its chroma.
        var a = lab.y, b = lab.z
        var near: Float = 0
        if let anchor, chroma > 0, onSkin > 0 {
            let own = SIMD2(a, b) / chroma
            near = smoothstep(anchorCosine, (own * anchor).sum())
            let turned = own + skinAnchor * onSkin * near * (anchor - own)
            let length = (turned * turned).sum().squareRoot()
            if length > 1e-4 {
                a = turned.x / length * chroma
                b = turned.y / length * chroma
            }
        }
        var scale = gain
        if let pallid, pallid.pallor > 0, pallid.lightness.isFinite, onSkin > 0, chroma > 0 {
            // Hair at skin's hue beside the face is lifted with it, so the two keep apart.
            let lit = onSkin * pallid.pallor * smoothstep((pallid.lightness - litBelow)...pallid.lightness, L)
                * (1 - smoothstep(skinHighlight, L))
            lightness += paleLift * lit
            scale = max(gain, 1 + lit * (paleFloor * lightness / chroma - 1))
            // Turned toward peach, never past it: a yellow cast kept, matched, read khaki.
            // Only paints of the face's own hue: blond hair stays blond.
            let own = SIMD2(a, b) / chroma
            if near > 0, own.y > own.x * peach.y / peach.x {
                let turned = own + palePink * near * lit * (peach - own)
                let length = (turned * turned).sum().squareRoot()
                a = turned.x / length * chroma
                b = turned.y / length * chroma
            }
        }
        let rgb = ColorScience.okLabToEncoded(SIMD3(lightness, a * scale, b * scale), space: space)
        return PaletteColor(oklab: ColorScience.encodedToOKLab(rgb, space: space), rgb: rgb)
    }

    static func smoothstep(_ edges: ClosedRange<Float>, _ x: Float) -> Float {
        let t = min(max((x - edges.lowerBound) / (edges.upperBound - edges.lowerBound), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
