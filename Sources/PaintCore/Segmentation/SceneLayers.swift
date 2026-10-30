import Foundation

/// The scene method's view of the photo at working size (`GenerationSettings.Method.scene`):
/// which side of the subject's silhouette each pixel is on, and from that and the rest of the
/// `SceneMap` the per-pixel knobs the segmentation reads.
///
/// A paint-by-number designer draws the subject's outline first, then simplifies the
/// background into a few calm shapes and spends the detail on the face and its features. The
/// layers make the pipeline do the same:
/// - `isSubject`, the mask's side per pixel: the low-resolution mask resampled and snapped to
///   the photo's own edges (`snap`), so the silhouette runs where the subject meets the
///   background, not where a 256-px mask's blur happened to cross half. The segmentation keeps
///   the two sides apart as if they were painted with two kits (`SegmentationParameters.sidePaints`),
///   so no region crosses the silhouette, and the smoothing never diffuses across it
///   (`barrier`).
/// - `importance`, what the rest of the pipeline reads in place of the app's importance map:
///   a low floor in the background rising with saliency, the subject above half, faces,
///   animals and the subjects' features (eyes, noses, mouths) toward 1. Paints, the smallest
///   area, band fusion and texture consolidation all follow it as they do the color method's.
/// - `stretch`, how much less than the background each pixel is smoothed: the background is
///   smoothed `SegmentationParameters.sceneBackgroundSmoothing` times as widely as the color
///   method smooths, the subject as the color method does, faces and features less.
/// - `areaFactor`, the background's extra multiple on the smallest area
///   (`sceneBackgroundArea`), on top of importance's.
///
/// Without a scene map (none found, or none given) the whole photo is the subject and the
/// importance is the color method's fallback: the scene method then differs from the color
/// method only by its knobs.
struct SceneLayers {
    let width: Int
    let height: Int
    /// Whether a scene with a subject was given: without one, the whole photo is the subject and
    /// the background treatments (its smoothing, area, fusion and calming) do not apply.
    var hasScene = false
    var isSubject: [Bool]
    var importance: [Float]
    var stretch: [Float]
    var areaFactor: [Float]
    /// Per pixel, how far the background treatments apply (0...1): fully on flat and blurred
    /// background, not at all on sharp structure there (`structure`).
    var treatment: [Float]
    /// Background pixels farther than the calming radius from the silhouette: the only ones the
    /// scene method's wider outline smoothing may change (`SegmentationParameters.sceneCalmRadius`).
    var calm: [Bool]
    var calmRadius: Int
    /// Per pixel, the term added to the smoothing's domain derivative across the step from the
    /// left / upper neighbour where the side changes: effectively infinite, so the diffusion
    /// stops at the silhouette.
    var barrier: (horizontal: [Float], vertical: [Float])

    /// A subject pixel is one whose mask value is at least half once snapped.
    static let half: Float = 0.5
    /// Mask values this far from half are sure; between, the photo's colours decide (`snap`).
    static let sureMargin: Float = 0.3
    /// Window radius of the colour vote, as a share of the canvas side.
    static let voteRadius: Float = 1 / 60
    /// An island of either side smaller than this many times the smallest area flips to the
    /// side around it: the mask's wobble, not a subject.
    static let islandAreas: Float = 16
    /// Importance of the background: the app's own map's levels (`SubjectImportance.analysis`:
    /// a floor of 0.25, and 0.2 + 0.4 × saliency where that is more), so the background keeps the
    /// paints the color method gives it (a red barn behind a small subject stays red) and its
    /// bands fuse as the color method's do; the background's simplification is `treatment`'s.
    static let backgroundFloor: Float = 0.25
    static let backgroundSaliency: Float = 0.4
    /// Sharpness (`sharpness`): the ratio of the gradient energy at one pixel to that at the
    /// coarse scale, less one, over this reads as fully sharp. A step edge's ratio is about 8, a
    /// bokeh edge's (blurred over six pixels or more) near 1.
    static let sharpnessRange: Float = 4
    static let coarseRadius = 4
    /// Importance of the subject at no saliency, and how far saliency raises it (the app's map
    /// gives the subject 0.75: the subject keeps the smallest area it had).
    static let subjectFloor: Float = 0.7
    static let subjectSaliency: Float = 0.2
    /// Importance inside a face's ellipse (the box grown as `SubjectImportance.emphasize` grows
    /// it) and an animal's; a feature's within its radius, falling to the face's at twice it.
    static let faceImportance: Float = 1
    static let animalImportance: Float = 0.85
    static let featureImportance: Float = 1

    static func make(
        scene: SceneMap?, lab: Grid<SIMD4<Float>>, structure: StructureMap, parameters p: SegmentationParameters,
        cancel: CancellationCheck
    ) throws -> SceneLayers {
        let w = lab.width, h = lab.height, n = w * h
        var layers = SceneLayers(
            width: w, height: h, isSubject: [Bool](repeating: true, count: n), importance: [], stretch: [], areaFactor: [],
            treatment: [Float](repeating: 0, count: n), calm: [], calmRadius: max(2, Int((Float(p.boundaryRadius) * p.sceneCalmRadius).rounded())),
            barrier: ([Float](repeating: 0, count: n), [Float](repeating: 0, count: n)))
        if let scene, scene.hasSubject {
            let snapped = try snap(scene.subjectResampled(width: w, height: h), lab: lab, parameters: p, cancel: cancel)
            try cancel.throwIfCancelled()
            // A subject that vanished in the snap (a mask of specks) is none.
            let covered = snapped.count { $0 }
            layers.hasScene = Float(covered) >= SceneMap.minimumSubjectShare * Float(n)
            if layers.hasScene { layers.isSubject = snapped }
        }
        if layers.hasScene, let scene {
            let saliency = scene.saliencyResampled(width: w, height: h)
            let busy = try ImportanceMap.busyness(structure: structure.coherentMagnitude(), width: w, height: h, cancel: cancel)
            let sharp = try sharpness(lab, cancel: cancel)
            // Sharp structure in the background (an in-focus flower behind the butterfly the mask
            // chose, a house, the trains) is drawn as the color method draws it: the treatments
            // fall off with it (half the busiest contours' density is already full structure).
            for i in 0..<n where !layers.isSubject[i] { layers.treatment[i] = 1 - min(1, 2 * busy[i]) * sharp[i] }
            layers.importance = importance(scene: scene, isSubject: layers.isSubject, saliency: saliency, width: w, height: h)
        } else if let scene {
            // No subject: the photo is all subject, and the importance is the app's own map of these
            // findings (`SubjectImportance.analysis`: a floor, raised by saliency), so the scene
            // method differs from the color method only where it knows the scene.
            let saliency = scene.saliencyResampled(width: w, height: h)
            layers.importance = saliency.map { max(0.25, 0.2 + 0.4 * $0) }
        } else {
            layers.importance = try ImportanceMap.fallback(structure: structure.coherentMagnitude(), width: w, height: h, cancel: cancel)
        }
        try cancel.throwIfCancelled()
        // The color method smooths a pixel of importance i with sigma / (1 + sharpening × i);
        // the subject keeps exactly that, the background gets up to `sceneBackgroundSmoothing`
        // times it (by `treatment`), a face `sceneFacePlanes` times (a few planes of skin, not
        // patches) and a feature `sceneFeatureSmoothing` of it. The filter runs at the
        // background's sigma; `stretch` is what divides it back down per pixel.
        let background = layers.hasScene ? p.sceneBackgroundSmoothing : 1
        let (faces, features) = scene.map { marks(scene: $0, width: w, height: h) } ?? ([], [])
        layers.stretch = layers.importance.indices.map { i in
            let imp = layers.importance[i]
            var multiplier = (layers.isSubject[i] ? 1 : lerp(1, background, layers.treatment[i])) / (1 + p.importanceSharpening * imp)
            if !faces.isEmpty {
                if features[i] > 0 {
                    multiplier *= p.sceneFeatureSmoothing
                } else if faces[i] > 0 {
                    multiplier *= p.sceneFacePlanes
                }
            }
            return background / multiplier - 1
        }
        layers.areaFactor = layers.isSubject.indices.map { i in
            layers.isSubject[i] || !layers.hasScene ? 1 : lerp(1, p.sceneBackgroundArea, layers.treatment[i])
        }
        let distance = try DistanceTransform.squaredDistances(
            layers.isSubject.map { $0 ? 1 : 0 }, width: w, height: h, cancel: cancel)
        let reach = Double((layers.calmRadius + 1) * (layers.calmRadius + 1))
        layers.calm = (0..<n).map { !layers.isSubject[$0] && distance[$0] > reach && layers.treatment[$0] > 0.5 }
        let wall = p.smoothSpatial * background / p.smoothRange
        layers.isSubject.withUnsafeBufferPointer { s in
            for y in 0..<h {
                let row = y * w
                for x in 1..<w where s[row + x] != s[row + x - 1] { layers.barrier.horizontal[row + x] = wall }
                if y > 0 { for x in 0..<w where s[row + x] != s[row + x - w] { layers.barrier.vertical[row + x] = wall } }
            }
        }
        return layers
    }

    /// The mask's side per pixel, snapped to the photo: pixels the mask is sure of keep its
    /// side; in the band between, a pixel joins the side whose nearby sure colours it is
    /// closer to, the mask's own leaning counting as much as the colours' verdict. Then islands
    /// smaller than `islandAreas` smallest areas flip, so the sides are a few clean shapes.
    static func snap(
        _ soft: [Float], lab: Grid<SIMD4<Float>>, parameters p: SegmentationParameters, cancel: CancellationCheck
    ) throws -> [Bool] {
        let w = lab.width, h = lab.height, n = w * h
        let side = Float(n).squareRoot()
        let radius = max(2, Int((side * voteRadius).rounded()))
        // Colour sums of the sure pixels of each side, box-blurred: w holds the count.
        var sureSubject = [SIMD4<Float>](repeating: .zero, count: n)
        var sureBackground = [SIMD4<Float>](repeating: .zero, count: n)
        for i in 0..<n {
            let c = lab.storage[i]
            if soft[i] >= half + sureMargin {
                sureSubject[i] = SIMD4(c.x, c.y, c.z, 1)
            } else if soft[i] <= half - sureMargin {
                sureBackground[i] = SIMD4(c.x, c.y, c.z, 1)
            }
        }
        let nearSubject = try BoxBlur.apply(sureSubject, width: w, height: h, radius: radius, passes: 2, cancel: cancel)
        let nearBackground = try BoxBlur.apply(sureBackground, width: w, height: h, radius: radius, passes: 2, cancel: cancel)
        var isSubject = [Bool](repeating: false, count: n)
        for i in 0..<n {
            let s = soft[i]
            if s >= half + sureMargin || s <= half - sureMargin {
                isSubject[i] = s >= half
                continue
            }
            let a = nearSubject[i], b = nearBackground[i]
            var score = (s - half) / sureMargin
            if a.w > 1e-3, b.w > 1e-3 {
                let c = lab.storage[i]
                let ma = SIMD3(a.x, a.y, a.z) / a.w, mb = SIMD3(b.x, b.y, b.z) / b.w
                let da = ColorScience.distance(SIMD3(c.x, c.y, c.z), ma), db = ColorScience.distance(SIMD3(c.x, c.y, c.z), mb)
                score += (db - da) / (da + db + 1e-4)
            }
            isSubject[i] = score >= 0
        }
        // Islands: components of either side under the limit take the other side.
        let limit = Int(islandAreas * p.minArea)
        var changed = true
        var passes = 0
        while changed && passes < 3 {
            changed = false
            passes += 1
            let components = ConnectedComponents.label(Grid(width: w, height: h, storage: isSubject.map { $0 ? 1 : 0 }))
            var flip = [Bool](repeating: false, count: components.count)
            for c in 0..<components.count where components.area[c] < limit { flip[c] = true; changed = true }
            if changed {
                for i in 0..<n where flip[Int(components.labels.storage[i])] { isSubject[i].toggle() }
            }
        }
        return isSubject
    }

    /// How sharp each pixel's surroundings are, 0...1: the energy of the lightness gradient at
    /// one pixel against the energy of the gradient of the image box-blurred by `coarseRadius`,
    /// both averaged over a window of a few percent of the frame. A focused edge carries its
    /// contrast in a pixel or two, so its fine energy is many times the coarse; a blurred edge
    /// spreads it, and the two are alike.
    static func sharpness(_ lab: Grid<SIMD4<Float>>, cancel: CancellationCheck) throws -> [Float] {
        let w = lab.width, h = lab.height, n = w * h
        guard w > 2, h > 2 else { return [Float](repeating: 1, count: n) }
        let lightness = lab.storage.map(\.x)
        let coarse = try BoxBlur.apply(lightness, width: w, height: h, radius: coarseRadius, passes: 1, cancel: cancel)
        func energy(_ v: [Float]) -> [Float] {
            var out = [Float](repeating: 0, count: n)
            for y in 1..<(h - 1) {
                let row = y * w
                for x in 1..<(w - 1) {
                    let gx = (v[row + x + 1] - v[row + x - 1]) * 0.5
                    let gy = (v[row + w + x] - v[row - w + x]) * 0.5
                    out[row + x] = gx * gx + gy * gy
                }
            }
            return out
        }
        let side = Float(n).squareRoot()
        let window = max(2, Int(side / 40))
        let fine = try BoxBlur.apply(energy(lightness), width: w, height: h, radius: window, passes: 2, cancel: cancel)
        let low = try BoxBlur.apply(energy(coarse), width: w, height: h, radius: window, passes: 2, cancel: cancel)
        return (0..<n).map { i in
            let ratio = fine[i] / (low[i] + 1e-7)
            return min(max((ratio - 1) / sharpnessRange, 0), 1)
        }
    }

    /// The importance map of a scene at working size (see the type's doc comment).
    static func importance(
        scene: SceneMap, isSubject: [Bool], saliency: [Float], width w: Int, height h: Int
    ) -> [Float] {
        var out = [Float](repeating: 0, count: w * h)
        for i in out.indices {
            let s = saliency[i]
            out[i] = isSubject[i] ? subjectFloor + subjectSaliency * s : max(backgroundFloor, 0.2 + backgroundSaliency * s)
        }
        let fw = Float(w), fh = Float(h)
        func lift(ellipseAt cx: Float, _ cy: Float, rx: Float, ry: Float, to value: Float) {
            raise(&out, ellipseAt: cx, cy, rx: rx, ry: ry, to: value, width: w, height: h)
        }
        for (rects, value) in [(scene.faces, faceImportance), (scene.animals, animalImportance)] {
            for r in rects {
                let grown = (x: r.x - r.width * 0.25, y: r.y - r.height * 0.3, w: r.width * 1.5, h: r.height * 1.6)
                lift(ellipseAt: (grown.x + grown.w / 2) * fw, (grown.y + grown.h / 2) * fh,
                     rx: max(1, grown.w * fw / 2), ry: max(1, grown.h * fh / 2), to: value)
            }
        }
        let long = max(fw, fh)
        for f in scene.features {
            let r = max(2, f.radius * long)
            lift(ellipseAt: f.x * fw, f.y * fh, rx: 2 * r, ry: 2 * r, to: faceImportance)
            lift(ellipseAt: f.x * fw, f.y * fh, rx: r, ry: r, to: featureImportance)
        }
        return out
    }

    /// Per pixel, 1 inside a face's or an animal's ellipse (`faces`) and inside a feature's
    /// radius (`features`), else 0: the face is smoothed into planes, the features kept.
    static func marks(scene: SceneMap, width w: Int, height h: Int) -> (faces: [Float], features: [Float]) {
        var faces = [Float](repeating: 0, count: w * h), features = [Float](repeating: 0, count: w * h)
        let fw = Float(w), fh = Float(h)
        for r in scene.faces + scene.animals {
            let grown = (x: r.x - r.width * 0.25, y: r.y - r.height * 0.3, w: r.width * 1.5, h: r.height * 1.6)
            raise(&faces, ellipseAt: (grown.x + grown.w / 2) * fw, (grown.y + grown.h / 2) * fh,
                  rx: max(1, grown.w * fw / 2), ry: max(1, grown.h * fh / 2), to: 1, flat: true, width: w, height: h)
        }
        let long = max(fw, fh)
        for f in scene.features {
            let r = max(2, f.radius * long)
            raise(&features, ellipseAt: f.x * fw, f.y * fh, rx: r, ry: r, to: 1, flat: true, width: w, height: h)
        }
        return (faces, features)
    }

    /// Raises `out` inside an ellipse toward `value`, falling off past it as
    /// `SubjectImportance.emphasize` falls (`flat`: `value` throughout the ellipse, nothing past it).
    static func raise(
        _ out: inout [Float], ellipseAt cx: Float, _ cy: Float, rx: Float, ry: Float, to value: Float, flat: Bool = false,
        width w: Int, height h: Int
    ) {
        let limit: Float = flat ? 1 : 1.6
        let x0 = max(0, Int(cx - rx * 1.3)), x1 = min(w - 1, Int(cx + rx * 1.3))
        let y0 = max(0, Int(cy - ry * 1.3)), y1 = min(h - 1, Int(cy + ry * 1.3))
        guard x0 <= x1, y0 <= y1 else { return }
        for y in y0...y1 {
            let dy = (Float(y) + 0.5 - cy) / ry
            for x in x0...x1 {
                let dx = (Float(x) + 0.5 - cx) / rx
                let d = dx * dx + dy * dy
                if d < limit {
                    let v = flat ? value : min(value, value * (1.25 - 0.5 * d))
                    out[y * w + x] = max(out[y * w + x], v)
                }
            }
        }
    }
}
