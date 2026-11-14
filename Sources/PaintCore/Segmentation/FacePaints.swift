/// A face's own paints, for rich paint (`PaintMix.rich`; painting-company row 344).
///
/// The segmentation fits one paint to every area of a colour, so a face in shadow shares its
/// paints with whatever else in the photo is that brown: on Girl with a Pearl Earring three of
/// the cheek's paints were the ochre jacket's too. Each was the mean of both, a khaki neither
/// is, and a mix can't treat it as either: kept, the cheek is muddy; mixed as skin, the jacket
/// turns pink. So a paint that a face shares with something of another colour is split: the
/// regions on the face (most of their pixels within `KitPaint.faceReach` of an eye, where the
/// importance map marks a face) take a new paint, and each of the two becomes its own
/// regions' colour (the paint moved by how far its regions' mean in the photo is from all of
/// the old paint's regions').
///
/// Only skin splits (`KitPaint.skinCosine`: a headscarf's blue across a brow stays one blue),
/// only where the two differ (`apart`: a face and its neck in the same light stay one paint,
/// so the neck is mixed as the face is), and only when both keep a fair part of the paint
/// (`share`, `least`). The new paints come after the others, so every other paint keeps its
/// number, and at most `most` are added (a painting of 24 paints may have 30). Regions are only
/// recolored whole, and only where the new number fits: a region whose paint's number was
/// shorter than the new one (paints 1 to 9 of 24) moves only if it holds the disc the longer
/// number needs (`roomy`, as `RegionSimplifier.enforceLabelRoom` measures it); a thinner one
/// keeps the old paint. Sums are taken a pixel at a time in raster order, so the same photo gives
/// the same paints on every device.
enum FacePaints {
    /// The least of a paint's pixels each side keeps for it to split, and the fewest pixels on
    /// the face, as a share of the canvas.
    static let share: Float = 0.05
    static let least: Float = 1 / 4000
    /// How far apart in OKLab the face's colour and the rest's are for a split: six tenths
    /// of a just-noticeable difference (the jacket's ochre was 0.014 to 0.03 from the cheek).
    static let apart: Float = 0.012
    /// The most paints added.
    static let most = 6

    /// Splits the paints `segmentation`'s faces share (above); `importance` is the
    /// segmentation's weights, one per pixel, `eyes` as `KitPaint.faces` takes them and `photo`
    /// the working image; `minRadius` is the inscribed radius a region needs for a number of
    /// so many digits (`SegmentationParameters.minRadius(digits:)`). Returns how many paints it
    /// added (none without eyes, or when the maps aren't the segmentation's size).
    @discardableResult
    static func split(
        _ segmentation: inout Segmentation, importance: [Float], eyes: [[SIMD2<Float>]], photo: RGBAImage,
        minRadius: (Int) -> Float
    ) -> Int {
        let w = segmentation.width, h = segmentation.height, n = w * h
        let regionCount = segmentation.regionColor.count, paintCount = segmentation.palette.count
        guard importance.count == n, !eyes.isEmpty, photo.width == w, photo.height == h, paintCount > 0,
            paintCount < GenerationSettings.colorCountRange.upperBound
        else { return 0 }
        let near = KitPaint.nearEyes(width: w, height: h, eyes: eyes)
        var size = [Int](repeating: 0, count: regionCount), face = size
        for i in 0..<n {
            let region = Int(segmentation.labels.storage[i])
            guard region < regionCount else { continue }
            size[region] += 1
            if near[i] > 0, importance[i] >= KitPaint.faceImportance { face[region] += 1 }
        }
        var onFace = (0..<regionCount).map { face[$0] > 0 && 2 * face[$0] >= size[$0] }
        // A region has room for its own paint's number (`enforceLabelRoom`); the new paints'
        // may be longer, and a face's region without room for one stays as it is.
        let room = min(most, GenerationSettings.colorCountRange.upperBound - paintCount)
        let longest = LabelSizing.digitCount(of: paintCount + room)
        let tight = (0..<regionCount).map { region in
            onFace[region] && Int(segmentation.regionColor[region]) < paintCount
                && LabelSizing.digitCount(colorIndex: segmentation.regionColor[region]) < longest
        }
        if tight.contains(true) {
            let wide = roomy(segmentation.labels, among: tight, radius: minRadius(longest))
            for region in 0..<regionCount where tight[region] && !wide[region] { onFace[region] = false }
        }
        var pixels = [SIMD2<Int>](repeating: SIMD2(0, 0), count: paintCount)
        for region in 0..<regionCount {
            let paint = Int(segmentation.regionColor[region])
            guard paint < paintCount else { continue }
            if onFace[region] { pixels[paint].x += size[region] } else { pixels[paint].y += size[region] }
        }
        let fewest = max(64, Int(Float(n) * least))
        var candidate = pixels.map { p in
            let all = Float(p.x + p.y)
            return p.x >= fewest && Float(p.x) >= share * all && Float(p.y) >= share * all
        }
        guard candidate.contains(true) else { return 0 }
        // The photo's mean colour under each candidate's regions on the face and off it.
        var sums = [[SIMD3<Double>]](repeating: [SIMD3(0, 0, 0), SIMD3(0, 0, 0)], count: paintCount)
        for i in 0..<n {
            let region = Int(segmentation.labels.storage[i])
            guard region < regionCount else { continue }
            let paint = Int(segmentation.regionColor[region])
            guard paint < paintCount, candidate[paint] else { continue }
            let rgb = SIMD3(Float(photo.pixels[4 * i]), Float(photo.pixels[4 * i + 1]), Float(photo.pixels[4 * i + 2])) / 255
            sums[paint][onFace[region] ? 0 : 1] += SIMD3<Double>(ColorScience.encodedToOKLab(rgb, space: photo.colorSpace))
        }
        func mean(_ paint: Int, _ side: Int) -> SIMD3<Float> {
            SIMD3<Float>(sums[paint][side] / Double(side == 0 ? pixels[paint].x : pixels[paint].y))
        }
        for paint in 0..<paintCount where candidate[paint] {
            let skin = mean(paint, 0)
            let chroma = (skin.y * skin.y + skin.z * skin.z).squareRoot()
            candidate[paint] = chroma > KitPaint.neutralChroma.lowerBound
                && (skin.y * KitPaint.skinHue.x + skin.z * KitPaint.skinHue.y) / chroma > KitPaint.skinCosine.lowerBound
                && ColorScience.distance(skin, mean(paint, 1)) >= apart
        }
        // The paints with the most of a face first, at most `most`, then in the palette's order.
        let chosen = (0..<paintCount).filter { candidate[$0] }
            .sorted { (pixels[$0].x, $1) > (pixels[$1].x, $0) }.prefix(room).sorted()
        guard !chosen.isEmpty else { return 0 }
        var facePaint = [Int: UInt32]()
        let space = segmentation.colorSpace
        func moved(_ paint: PaletteColor, by offset: SIMD3<Float>) -> PaletteColor {
            let rgb = ColorScience.okLabToEncoded(paint.oklab + offset, space: space)
            return PaletteColor(oklab: ColorScience.encodedToOKLab(rgb, space: space), rgb: rgb)
        }
        for paint in chosen {
            let all = SIMD3<Float>((sums[paint][0] + sums[paint][1]) / Double(pixels[paint].x + pixels[paint].y))
            let old = segmentation.palette[paint]
            facePaint[paint] = UInt32(segmentation.palette.count)
            segmentation.palette.append(moved(old, by: mean(paint, 0) - all))
            segmentation.palette[paint] = moved(old, by: mean(paint, 1) - all)
        }
        for region in 0..<regionCount where onFace[region] {
            if let new = facePaint[Int(segmentation.regionColor[region])] { segmentation.regionColor[region] = new }
        }
        return chosen.count
    }

    /// Which of the regions `among` marks hold a disc of `radius`, in the sense of
    /// `RegionSimplifier.hasInscribedDisc`: a pixel with no boundary pixel (one with a
    /// 4-neighbour of another region, or on the canvas's edge) nearer than `radius` − ½.
    static func roomy(_ labels: RegionMap, among: [Bool], radius: Float) -> [Bool] {
        let w = labels.width, h = labels.height
        var wide = [Bool](repeating: false, count: among.count)
        let reach = max(radius - 0.5, 0), limit = reach * reach
        let r = Int(reach.rounded(.up))
        guard w > 2 * r, h > 2 * r, w >= 3, h >= 3 else { return limit <= 0 ? among : wide }
        var boundary = [Bool](repeating: true, count: w * h)
        labels.storage.withUnsafeBufferPointer { l in
            for y in 1..<(h - 1) {
                for x in 1..<(w - 1) {
                    let i = y * w + x, v = l[i]
                    boundary[i] = l[i - 1] != v || l[i + 1] != v || l[i - w] != v || l[i + w] != v
                }
            }
        }
        // Row dy of the disc spans dx in -span...span (-1: an empty row).
        let span: [Int] = (-r...r).map { (dy: Int) -> Int in
            var reached = -1
            for dx in 0...r where Float(dx * dx + dy * dy) < limit { reached = dx }
            return reached
        }
        for y in r..<(h - r) {
            for x in r..<(w - r) {
                let region = Int(labels.storage[y * w + x])
                guard region < among.count, among[region], !wide[region], !boundary[y * w + x] else { continue }
                var clear = true
                rows: for dy in -r...r where span[dy + r] >= 0 {
                    let row = (y + dy) * w + x
                    for dx in -span[dy + r]...span[dy + r] where boundary[row + dx] {
                        clear = false
                        break rows
                    }
                }
                if clear { wide[region] = true }
            }
        }
        return wide
    }
}
