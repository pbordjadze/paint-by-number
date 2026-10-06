/// Writing in the photo (a note, a card, a sign) drawn legibly: the pen strokes around the
/// lines of text the app's text recognition found (`LineArtInput.writing`), traced from the
/// working image at canvas resolution and drawn in ink inside their cells, over paper painted as
/// if the ink weren't there. Templates draw it only from an edge map (`LayeredLines`), while
/// `LineArtSettings.keepWriting` is on.
///
/// The detectors can't keep writing: the line drawing runs at a long side of 768 px, where a
/// pen stroke is about a pixel and letters smear; the contour map draws no letters; and tracing
/// drops lines shorter than `minimumStrokeLength`, which most pieces of a letter are. (A note
/// photographed among stuffed animals: the drawing held its letters at 0.4–0.8, the coloring
/// book draws from 0.6, and nothing survived tracing.)
///
/// Per area (a line of text as the recognizer boxed it, a quadrilateral normalized to the photo;
/// `h` its height in pixels, from `minimumHeight` to `maximumHeight` of the canvas's short side),
/// in the input's order, every area reading the photo as it is:
/// 1. Polarity and pen: the core (the box grown by `margin` × h) split plainly into dark and light
///    (Otsu's, on OKLab lightness); the paper is the side most of the margin around the box lies
///    on, so the writing is dark ink on paper or light (chalk on a board) however much of the box
///    bold letters fill. That split's pen sizes the closing's square: `strokeWindow` × h either
///    side, or past the pen (3 to `maximumWindow` px), since a stroke wider than the square
///    survives the closing and shows no contrast.
/// 2. Ink: contrast (grey closing minus lightness for dark ink, lightness minus the opening for
///    light) above Otsu's threshold of the core (at least `minimumContrast`), grown by up to
///    `growth` pixels into contrast above half of it, so a faint rule a letter touches stays
///    behind. Not ink: strokes too wide for the square and the band along their edges, all the
///    square sees of them (`Patch.wideStrokes`: bold letters, a dark shape beside the writing);
///    ink an earlier area drew (`Ink.claim`); ink on other paper than the writing's (`writingPaper`:
///    a speckled door, tape, the ground beyond the paper's edge); and connected ink lying more in
///    another line's box than in this one's. A core that comes out mostly ink
///    (`maximumCoverage`) is a picture, and one whose paper is grainy (`maximumGrain`) texture:
///    both are left to the detectors.
/// 3. What is writing, by connected ink in the zone around the box (`reach` heights along and
///    across the line): ink at least `coreShare` in the core is taken whole (a recognizer's box
///    often cuts a letter); ink apart from it is a mark (a heart, a letter the box missed) where
///    it lies wholly in the zone, on the writing's paper (`paperTolerance`), measures at least
///    `markSize` × h and is no wider than `markPen` of the writing's pens. Ink mostly beyond the
///    core (a drawing or a frame the writing touches) is neither.
/// 4. Lines: the ink thinned and traced (`StrokeGraph`), knots popped and spurs pruned, then
///    joined into strokes. Straight structures go: a straight run of `ruleLength` × h that reaches
///    the zone's edge (a ruled line, a margin, the paper's edge), a straight stroke longer than a
///    letter's (`longestStraight`), and one of at least `straightLength` × h whose line the photo
///    carries on beyond it (`continuation`: a rule between letters, a seam), as do specks and
///    lines wider than `blobWidth` pens (a hole, a shadow). Dots (an i's, a full stop) come as
///    short strokes. An area left with less line than `minimumInk` of its length holds no
///    writing; one with more than `maximumInk`, or broken into more than `maximumPieces` pieces
///    per height of line, holds texture.
///
/// Only thin writing is taken: an area whose pen (by that plain split, or as traced) reaches
/// `boldPens` of the smallest region's radius (`SegmentationParameters.minRadius`) is bold enough
/// to be painted, and the detectors already draw its letters as shapes to paint in their own
/// color (a sign's white capitals on blue), which a pen line over the ground would lose.
///
/// Once every area is read, the ink the lines draw is painted over with the paper around it
/// before the photo is segmented, so the paint ignores the letters; the writing's bounds keep
/// numbers out (`keepOut`, `LabelKeepOut`) and the detectors' lines on the ink, its smudged copy,
/// go (`nearInk`). The constants were measured on 53 photos (`docs/writing.md`). Deterministic:
/// areas, pixels and strokes are visited in a fixed order and every threshold comes from the
/// area's own pixels.
struct Writing {
    /// The writing's centerlines in canvas pixel coordinates, outlines at full strength.
    var lines: [DrawnLine] = []
    /// Per canvas pixel, whether it lies within `nearReach` pens of the ink. Empty when no
    /// writing was kept.
    var nearInk: [Bool] = []
    /// Rectangles (min x, min y, max x, max y; canvas units) numbers keep out of: the writing's
    /// strokes in clusters (`keepOutJoin`), grown by half the pen and `keepOutGap`.
    var keepOut: [SIMD4<Float>] = []
    /// Areas whose writing was kept, and marks kept beside them.
    var areas = 0
    var marks = 0
    /// What each area measured, in the input's order (`LineArtStats.writing`).
    var report: [WritingAreaStats] = []

    /// Text lower than this (pixels) is too small to draw legibly and is left to the paint.
    static let minimumHeight: Float = 10
    /// Text higher than this share of the canvas's short side is big enough for the detectors.
    static let maximumHeight: Float = 0.25
    /// The core: the box grown by this many heights, whose ink is writing, and the least share
    /// of a piece of ink in it for the piece to be.
    static let margin: Float = 0.3
    static let coreShare: Float = 0.4
    /// The zone: how far around the box (heights along and across the line, at most
    /// `maximumReach` pixels) writing reaches.
    static let reach = SIMD2<Float>(1, 1.5)
    static let maximumReach: Float = 120
    /// The closing's reach per height (pixels either side; at most `maximumWindow`): a stroke
    /// wider than the square survives the closing and shows no contrast, so it is generous,
    /// wide enough for a marker. Broader dark features it takes in (a hole, the gap between the
    /// paper and what lies behind it) are blobs or structures and go.
    static let strokeWindow: Float = 0.08
    static let maximumWindow = 20
    /// Least contrast (OKLab lightness) that counts as ink: notebook rules are about 0.07 on
    /// white paper, a ballpoint's ink 0.3.
    static let minimumContrast: Float = 0.12
    /// Pixels the ink may grow into contrast above half its threshold.
    static let growth = 3
    /// Share of the core's pixels above which it is a picture, not writing.
    static let maximumCoverage: Float = 0.3
    /// Lines wider than this many pens are not pen strokes.
    static let blobWidth: Float = 2.2
    /// How many times the closing's square a stroke is looked for in that is too wide for it
    /// (`Patch.wideStrokes`).
    static let wideWindow = 3
    /// A straight run at least this long (per height) that reaches the zone's edge is a rule.
    static let ruleLength: Float = 0.3
    /// Straight strokes at least this long (per height) are checked for a continuation; from
    /// `longestStraight` they are longer than a letter's stroke (an edge, a frame, an underline).
    static let straightLength: Float = 0.2
    static let longestStraight: Float = 1.2
    /// A straight stroke is part of a longer structure when its line runs on past one of its ends
    /// in faint ink (contrast above `supportLevel` of the threshold, along `supportShare` of the
    /// way, with paper either side) for as long as the stroke, and at least `continuation`
    /// heights: a ruled line between letters does, an i's stem doesn't, its dot set apart by
    /// paper, nor a letter's stem on a smudged chalkboard.
    static let continuation: Float = 0.5
    static let supportLevel: Float = 0.3
    static let supportShare: Float = 0.8
    /// Least and most line per length of an area for it to hold writing (the corpus's writing ran
    /// at 0.5 to 9.5, most of it under 4.5: a short box holds little of the line its letters
    /// reach into).
    static let minimumInk: Float = 0.5
    static let maximumInk: Float = 10
    /// Most the paper behind writing may differ from the core's (OKLab lightness).
    static let writingPaper: Float = 0.15
    /// Writing whose pen reaches this many times the smallest region's radius is bold: left to
    /// the detectors.
    static let boldPens: Float = 3
    /// Texture, not writing: a ground whose grain comes through as ink (granite, a halftone print,
    /// a smudged board), the median contrast of the core's paper away from the ink above this
    /// share of the ink's threshold (paper, lined or not, measured at most 0.1, those grounds 0.14
    /// to 0.6); or a trace broken into more than `maximumPieces` strokes and dots per height of
    /// line (a letter's strokes run a height or so between their ends and junctions; crumbs and a
    /// mesh don't).
    static let maximumGrain: Float = 0.15
    static let maximumPieces: Float = 3
    /// Least extent of a mark, per height.
    static let markSize: Float = 0.25
    /// Widest a mark's line may be, in the writing's pens.
    static let markPen: Float = 2
    /// Most the paper around a mark may differ from the writing's (OKLab lightness).
    static let paperTolerance: Float = 0.08
    /// Smoothing along the traced lines (Gaussian σ, points): takes the pixel steps out and
    /// keeps the letters' shapes.
    static let smoothing: Float = 1
    /// Room kept between the writing and a number (canvas units).
    static let keepOutGap: Float = 2
    /// Strokes closer than this many heights share a keep-out rectangle.
    static let keepOutJoin: Float = 0.5
    /// Keep-out rectangles of one line this far apart (per height) join (`joinLines`).
    static let lineGap: Float = 1.5
    /// Detector lines within this many pens of the ink are its smudged copy.
    static let nearReach: Float = 2

    /// The writing in `areas`, painted out of `image` (the working image); `minRadius` is the
    /// smallest region's radius there (`SegmentationParameters.minRadius`).
    static func find(
        in image: inout RGBAImage, areas: [[SIMD2<Float>]], minRadius: Float, cancel: CancellationCheck,
        clock: StageClock = StageClock()
    ) throws -> Writing {
        let w = image.width, h = image.height
        var out = Writing()
        let tallest = maximumHeight * Float(min(w, h))
        let all = areas.compactMap { Frame($0, width: w, height: h) }
        let frames = all.filter { $0.height >= minimumHeight && $0.height <= tallest }
        for f in all where !frames.contains(where: { $0.origin == f.origin && $0.u == f.u && $0.length == f.length }) {
            var skipped = f.stats
            skipped.verdict = "size"
            out.report.append(skipped)
        }
        guard !frames.isEmpty else { return out }
        // Lightness once for every zone: the zones of one line's words overlap.
        var union = (x0: w, y0: h, x1: 0, y1: 0)
        for f in frames {
            let b = f.bounds(grow: zone(of: f), pad: maximumWindow, width: w, height: h)
            union = (min(union.x0, b.x0), min(union.y0, b.y0), max(union.x1, b.x1), max(union.y1, b.y1))
        }
        let lightness = clock.measure("writing.lightness") { Lightness(image: image, bounds: union) }
        // Every area reads the photo as it is; ink an earlier area kept is claimed, so an area
        // overlapping it doesn't trace it again (painting it out first left fringes that traced as
        // crumbs).
        var claimed = [Bool](repeating: false, count: w * h)
        var kept: [Ink] = []
        for (k, frame) in frames.enumerated() {
            try cancel.throwIfCancelled()
            var others = frames
            others.remove(at: k)
            let (found, stats) = ink(
                of: frame, others: others, image: image, lightness: lightness, claimed: claimed, boldPen: boldPens * minRadius,
                clock: clock)
            out.report.append(stats)
            guard let ink = found else { continue }
            ink.claim(&claimed, canvasWidth: w)
            kept.append(ink)
            out.lines += ink.lines
            out.keepOut += ink.keepOut
            out.areas += 1
            out.marks += ink.marks
        }
        guard !kept.isEmpty else { return out }
        clock.measure("writing.paint") {
            Ink.paint(kept, over: &image)
            var near = [Bool](repeating: false, count: w * h)
            for ink in kept { ink.markNear(&near, canvasWidth: w) }
            out.nearInk = near
        }
        out.keepOut = joinLines(out.keepOut)
        return out
    }

    /// Keep-out rectangles along one line of text as one, so no number sits between its words
    /// (a recognizer may box each word): rectangles overlapping across by half the lower one's
    /// height and apart along by at most `lineGap` of the taller one's.
    static func joinLines(_ rects: [SIMD4<Float>]) -> [SIMD4<Float>] {
        var boxes = rects
        var merged = true
        while merged {
            merged = false
            search: for i in boxes.indices {
                for j in boxes.indices where j > i {
                    let a = boxes[i], b = boxes[j]
                    let ha = a.w - a.y, hb = b.w - b.y
                    let across = min(a.w, b.w) - max(a.y, b.y), along = max(a.x, b.x) - min(a.z, b.z)
                    guard across >= 0.5 * min(ha, hb), along <= lineGap * max(ha, hb) else { continue }
                    boxes[i] = SIMD4(min(a.x, b.x), min(a.y, b.y), max(a.z, b.z), max(a.w, b.w))
                    boxes.remove(at: j)
                    merged = true
                    break search
                }
            }
        }
        return boxes
    }

    /// How far around `frame` its zone reaches.
    static func zone(of frame: Frame) -> SIMD2<Float> { pointwiseMin(reach * frame.height, SIMD2(repeating: maximumReach)) }

    /// The closing's radius for `frame`'s writing, before its pen is known.
    static func radius(of frame: Frame) -> Int { min(maximumWindow, max(3, Int((strokeWindow * frame.height).rounded()))) }

    /// The writing of one area, or nil when it holds none, or bold writing (a pen of `boldPen`),
    /// and what was measured.
    static func ink(
        of frame: Frame, others: [Frame], image: RGBAImage, lightness: Lightness, claimed: [Bool], boldPen: Float,
        clock: StageClock
    ) -> (Ink?, WritingAreaStats) {
        var stats = frame.stats
        let h = frame.height
        let patch = clock.measure("writing.patch") {
            Patch(
                image: image, lightness: lightness, frame: frame, zone: zone(of: frame), core: SIMD2(repeating: margin * h),
                radius: radius(of: frame), boldPen: boldPen)
        }
        guard !patch.bold else {
            stats.pen = patch.plainPen
            stats.verdict = "bold"
            return (nil, stats)
        }
        let high = max(Patch.otsu(patch.contrast, patch.core), minimumContrast)
        stats.contrast = high
        var all = patch.mask(threshold: high)
        let wide = patch.wideStrokes(threshold: high)
        for i in all.indices where all[i] && (wide[i] || claimed[patch.canvasIndex(i, canvasWidth: image.width)]) {
            all[i] = false
        }
        let paper = patch.paperLightness(ink: all)
        for i in all.indices where all[i] && abs(patch.paper[i] - paper) > writingPaper { all[i] = false }
        // Ink lying more in another line's box than in this one's is that line's (a letter of the
        // line above reaching into this one's core).
        let neighbours = others.filter { patch.overlaps($0) }
        let components = Patch.components(all, width: patch.w, height: patch.h).filter { c in
            guard !neighbours.isEmpty else { return true }
            let points = c.map { patch.canvasPoint(SIMD2(Float($0 % patch.w), Float($0 / patch.w))) }
            let ours = points.count(where: { frame.inset($0, grow: .zero) >= 0 })
            let theirs = neighbours.map { other in points.count(where: { other.inset($0, grow: .zero) >= 0 }) }.max() ?? 0
            if theirs > ours {
                for i in c { all[i] = false }
                return false
            }
            return true
        }
        var coreCount = 0, coreInk = 0
        for i in all.indices where patch.core[i] {
            coreCount += 1
            if all[i] { coreInk += 1 }
        }
        stats.coverage = Float(coreInk) / Float(max(coreCount, 1))
        guard coreInk > 0 else { stats.verdict = "noInk"; return (nil, stats) }
        guard stats.coverage <= maximumCoverage else { stats.verdict = "picture"; return (nil, stats) }
        let fromInk = DistanceTransform.squaredEDT(width: patch.w, height: patch.h) { all[$0] }.storage
        let away = Float((growth + 1) * (growth + 1))
        var ground: [Float] = []
        for i in all.indices where patch.core[i] && fromInk[i] > away { ground.append(patch.contrast[i]) }
        ground.sort()
        stats.grain = ground.isEmpty ? 0 : ground[ground.count / 2] / high
        guard stats.grain <= maximumGrain else { stats.verdict = "texture"; return (nil, stats) }

        // Ink in the core is writing, whole where the box cuts a letter, unless most of it lies
        // beyond (a drawing or a frame the writing touches).
        var writing = [Bool](repeating: false, count: patch.w * patch.h)
        var apart: [[Int]] = []
        for c in components {
            if Float(c.count(where: { patch.core[$0] })) >= coreShare * Float(c.count) {
                for i in c { writing[i] = true }
            } else {
                apart.append(c)
            }
        }
        let halfWidth = Patch.halfWidths(all, width: patch.w, height: patch.h)
        let pen = Patch.lineWidth(writing, halfWidth: halfWidth, width: patch.w, height: patch.h)
        stats.pen = pen
        guard pen < boldPen else { stats.verdict = "bold"; return (nil, stats) }
        var mask = writing
        var marks = 0
        for c in apart where patch.isMark(c, height: h, pen: pen, paper: paper, halfWidth: halfWidth) {
            for i in c { mask[i] = true }
            marks += 1
        }
        var ink = clock.measure("writing.trace") { Ink(mask: mask, patch: patch, threshold: high) }
        ink.marks = marks
        stats.marks = marks
        clock.measure("writing.clean") {
            ink.removeStructures(height: h, patch: patch, support: supportLevel * high)
            ink.dropSpecksAndBlobs(height: h)
        }
        let length = ink.length
        stats.inkPerLength = length / frame.length
        stats.piecesPerHeight = Float(ink.strokes.count + ink.dots.count) / max(length / h, 1e-3)
        if length < minimumInk * frame.length { stats.verdict = "sparse"; return (nil, stats) }
        if length > maximumInk * frame.length { stats.verdict = "dense"; return (nil, stats) }
        if stats.piecesPerHeight > maximumPieces { stats.verdict = "texture"; return (nil, stats) }
        ink.finish(height: h)
        stats.verdict = "kept"
        return (ink, stats)
    }

    // MARK: - Ink

    /// Ink found in a patch: its pixels, pen, and the strokes traced from it (patch pixel
    /// coordinates until `finish` moves them onto the canvas).
    struct Ink {
        let x0: Int, y0: Int, w: Int, h: Int
        let mask: [Bool]
        let halfWidth: [Float]
        var strokes: [StrokeGraph.Stroke]
        /// Dots, by their centres.
        var dots: [SIMD2<Float>]
        /// Line width, the median across the ink's centerlines of twice a centre pixel's
        /// distance to the paper (a stroke 3 px wide measures 4; whole pixels can't tell
        /// finer).
        let pen: Float
        /// Pixels with ink, faint ink included: the paper's color is taken around them.
        let exclude: [Bool]
        /// How far around a pixel the paper's color is taken (the closing's radius).
        let radius: Int
        var marks = 0
        /// Canvas lines and the rectangles numbers keep out of, made by `finish`.
        var lines: [DrawnLine] = []
        var keepOut: [SIMD4<Float>] = []

        init(mask: [Bool], patch: Patch, threshold: Float) {
            x0 = patch.x0; y0 = patch.y0; w = patch.w; h = patch.h
            self.mask = mask
            radius = patch.radius
            exclude = (0..<(patch.w * patch.h)).map { mask[$0] || patch.contrast[$0] >= 0.5 * threshold }
            halfWidth = Patch.halfWidths(mask, width: w, height: h)
            let thin = Patch.centerlines(mask, width: w, height: h)
            pen = Patch.lineWidth(thin: thin, halfWidth: halfWidth)
            var g = StrokeGraph.trace(thin, strength: [Float](repeating: 1, count: w * h), width: w, height: h)
            g.mergeDegree2()
            g.popBubbles(perimeter: 2 * pen + 6)
            g.pruneSpurs(max(2, pen), rounds: 2)
            strokes = g.strokes(sigma: Writing.smoothing)
            // Dots thin to a pixel or two, which tracing drops: each pen-sized speck of ink
            // stands for itself.
            dots = []
            let largest = 2.5 * pen + 1, least = max(4, 0.5 * pen * pen)
            for pixels in Patch.components(mask, width: w, height: h) where Float(pixels.count) >= least {
                var lo = SIMD2<Int>(w, h), hi = SIMD2<Int>(-1, -1), sum = SIMD2<Float>(0, 0)
                for i in pixels {
                    let p = SIMD2(i % w, i / w)
                    lo = pointwiseMin(lo, p); hi = pointwiseMax(hi, p)
                    sum += SIMD2(Float(p.x), Float(p.y))
                }
                guard Float(hi.x - lo.x + 1) <= largest && Float(hi.y - lo.y + 1) <= largest else { continue }
                dots.append(sum / Float(pixels.count))
                // Whatever tracing made of the dot goes, so it isn't drawn twice.
                let inDot = Set(pixels)
                strokes.removeAll { s in s.points.allSatisfy { inDot.contains(Self.index(of: $0, width: w, height: h)) } }
            }
        }

        static func index(of p: SIMD2<Float>, width w: Int, height h: Int) -> Int {
            min(max(Int(p.y.rounded()), 0), h - 1) * w + min(max(Int(p.x.rounded()), 0), w - 1)
        }

        /// Line traced, dots aside (pixels).
        var length: Float {
            strokes.reduce(0) { $0 + StrokeGraph.length($1.points, closed: $1.closed) } + Float(dots.count) * 2
        }

        /// Drops what is a straight structure rather than writing: straight runs of a stroke that
        /// reach the zone's edge are cut off, and straight strokes whose line carries on past
        /// them in the photo (contrast above `support`) go.
        mutating func removeStructures(height: Float, patch: Patch, support level: Float) {
            let tolerance = max(1.5, 0.5 * pen)
            let edge = 2 + pen / 2
            func reachesEdge(_ p: SIMD2<Float>) -> Bool { patch.zoneInset(p) <= edge }
            /// Points of the straight run from `points[0]`.
            func straightRun(_ points: [SIMD2<Float>]) -> Int {
                var k = 1
                while k < points.count {
                    let a = points[0], ab = points[k] - a
                    let l = simdLength(ab)
                    var straight = true
                    if l > 0 {
                        for j in 1..<k where abs((points[j] - a).x * ab.y - (points[j] - a).y * ab.x) / l > tolerance {
                            straight = false
                            break
                        }
                    }
                    if !straight { break }
                    k += 1
                }
                return k
            }
            var kept: [StrokeGraph.Stroke] = []
            for var s in strokes {
                guard !s.closed, s.points.count >= 2 else { kept.append(s); continue }
                for _ in 0..<2 {
                    if s.points.count >= 2, reachesEdge(s.points[0]) {
                        let k = straightRun(s.points)
                        if StrokeGraph.length(Array(s.points[0..<k]), closed: false) >= Writing.ruleLength * height {
                            s.points.removeFirst(k - 1)
                            s.strength.removeFirst(k - 1)
                            s.free.0 = true
                        }
                    }
                    s.points.reverse(); s.strength.reverse(); s.free = (s.free.1, s.free.0)
                }
                if s.points.count >= 2 { kept.append(s) }
            }
            let faint = patch.contrast.map { $0 >= level }
            let w = w, h = h, offset = pen / 2 + 2.5
            func isFaint(_ p: SIMD2<Float>) -> Bool {
                let x = Int(p.x.rounded()), y = Int(p.y.rounded())
                return x >= 0 && y >= 0 && x < w && y < h && faint[y * w + x]
            }
            /// Whether a faint line carries on for `length` pixels past `end` along `direction`:
            /// faint ink along most of it (`supportShare`) and at most half as much either side
            /// (on a smudged or grainy ground faint ink lies everywhere, which is no line).
            func carriesOn(from end: SIMD2<Float>, _ direction: SIMD2<Float>, for length: Float) -> Bool {
                let side = SIMD2(-direction.y, direction.x) * offset
                let steps = max(Int(length.rounded(.up)), 1)
                var along = 0, beside = 0
                var p = end
                for _ in 0..<steps {
                    p += direction
                    guard patch.zoneInset(p) >= 0 else { break }
                    if (-1...1).contains(where: { dy in (-1...1).contains { dx in isFaint(p + SIMD2(Float(dx), Float(dy))) } }) {
                        along += 1
                    }
                    if isFaint(p + side) { beside += 1 }
                    if isFaint(p - side) { beside += 1 }
                }
                let share = Float(along) / Float(steps)
                return share >= Writing.supportShare && Float(beside) / Float(2 * steps) <= share / 2
            }
            strokes = kept.filter { s in
                guard !s.closed, let a = s.points.first, let b = s.points.last else { return true }
                let length = StrokeGraph.length(s.points, closed: false)
                guard length >= Writing.straightLength * height, straightRun(s.points) == s.points.count else { return true }
                if length >= Writing.longestStraight * height { return false }
                let d = (b - a) / max(simdLength(b - a), 1e-6)
                let needed = max(length, Writing.continuation * height)
                return !carriesOn(from: b, d, for: needed) && !carriesOn(from: a, -d, for: needed)
            }
        }

        /// Drops specks and lines wider than `blobWidth` pens all along: the width a quarter of the
        /// way up its points, since where strokes meet the ink is wider (a short stroke meeting
        /// another is wide for half its length).
        mutating func dropSpecksAndBlobs(height: Float) {
            let speck = max(2, 0.05 * height), widest = Writing.blobWidth * pen
            let halfWidth = halfWidth, w = w, h = h
            strokes.removeAll { s in
                if s.points.isEmpty || StrokeGraph.length(s.points, closed: s.closed) < speck { return true }
                let widths = s.points.map { 2 * halfWidth[Self.index(of: $0, width: w, height: h)] }.sorted()
                return widths[widths.count / 4] > widest
            }
        }

        /// Moves the strokes and dots onto the canvas as lines, and the rectangles numbers keep
        /// out of: strokes within `keepOutJoin` heights of each other share one.
        mutating func finish(height: Float) {
            let offset = SIMD2(Float(x0), Float(y0))
            var out: [DrawnLine] = []
            func line(_ points: [SIMD2<Float>], closed: Bool) -> DrawnLine {
                DrawnLine(
                    points: points.map { $0 + offset }, strength: [Float](repeating: 1, count: points.count),
                    layer: [UInt8](repeating: LineLayer.outline.rawValue, count: points.count), closed: closed,
                    free: (false, false), links: [], eye: false)
            }
            for s in strokes { out.append(line(s.points, closed: s.closed)) }
            // A dot as a stroke two units long: the shortest a template keeps.
            for d in dots { out.append(line([d - SIMD2(1, 0), d + SIMD2(1, 0)], closed: false)) }
            lines = out
            var boxes = out.map { l -> SIMD4<Float> in
                var lo = SIMD2<Float>(repeating: .infinity), hi = SIMD2<Float>(repeating: -.infinity)
                for p in l.points { lo = pointwiseMin(lo, p); hi = pointwiseMax(hi, p) }
                return SIMD4(lo.x, lo.y, hi.x, hi.y)
            }
            let join = Writing.keepOutJoin * height
            func near(_ a: SIMD4<Float>, _ b: SIMD4<Float>) -> Bool {
                a.x - join <= b.z && b.x - join <= a.z && a.y - join <= b.w && b.y - join <= a.w
            }
            var merged = true
            while merged {
                merged = false
                var i = 0
                while i < boxes.count {
                    var j = i + 1
                    while j < boxes.count {
                        if near(boxes[i], boxes[j]) {
                            let a = boxes[i], b = boxes.remove(at: j)
                            boxes[i] = SIMD4(min(a.x, b.x), min(a.y, b.y), max(a.z, b.z), max(a.w, b.w))
                            merged = true
                        } else {
                            j += 1
                        }
                    }
                    i += 1
                }
            }
            let grow = pen / 2 + Writing.keepOutGap
            keepOut = boxes.map { SIMD4($0.x - grow, $0.y - grow, $0.z + grow, $0.w + grow) }
        }

        /// Squared distance (patch pixels) from each patch pixel to the traced lines.
        private func distanceToLines() -> [Float] {
            var on = [Bool](repeating: false, count: w * h)
            let offset = SIMD2(Float(x0), Float(y0))
            for l in lines {
                let pts = l.points.map { $0 - offset }
                for k in pts.indices {
                    let next = k + 1 < pts.count ? pts[k + 1] : (l.closed ? pts[0] : pts[k])
                    LineLayering.segment(pts[k], next) { x, y in
                        if x >= 0 && y >= 0 && x < w && y < h { on[y * w + x] = true }
                    }
                }
            }
            return DistanceTransform.squaredEDT(width: w, height: h) { on[$0] }.storage
        }

        /// Claims the ink the lines draw, and `growth` pixels around it: the fringe an overlapping
        /// area with a lower threshold would grow into. Ink left undrawn (a rule, a stroke cut at the
        /// zone's edge) stays for another area.
        func claim(_ claimed: inout [Bool], canvasWidth: Int) {
            let drawn = cover()
            let grown = DistanceTransform.squaredEDT(width: w, height: h) { drawn[$0] }.storage
            let reach = Float(Writing.growth * Writing.growth)
            for y in 0..<h {
                for x in 0..<w where grown[y * w + x] <= reach { claimed[(y0 + y) * canvasWidth + x0 + x] = true }
            }
        }

        /// The ink the lines draw (and a pixel around it): what is painted over.
        private func cover() -> [Bool] {
            let d = distanceToLines()
            let reach = pen / 2 + 1.5
            var drawn = [Bool](repeating: false, count: w * h)
            for i in 0..<(w * h) where mask[i] && d[i] <= reach * reach { drawn[i] = true }
            return Morphology.square(drawn, width: w, height: h, any: true)
        }

        /// Paints the ink the areas' lines draw with the paper around it: the mean color of the
        /// pixels within an area's `radius` (twice, four times that where there are none) that no
        /// area has ink on, from integral images. Pixels read are never painted, so the order of
        /// the areas doesn't matter.
        static func paint(_ inks: [Ink], over image: inout RGBAImage) {
            let canvasWidth = image.width
            var blocked = [Bool](repeating: false, count: canvasWidth * image.height)
            let covers = inks.map { $0.cover() }
            for (ink, cover) in zip(inks, covers) {
                for y in 0..<ink.h {
                    for x in 0..<ink.w where cover[y * ink.w + x] || ink.exclude[y * ink.w + x] {
                        blocked[(ink.y0 + y) * canvasWidth + ink.x0 + x] = true
                    }
                }
            }
            for (ink, cover) in zip(inks, covers) { ink.paint(cover, blocked: blocked, over: &image) }
        }

        private func paint(_ cover: [Bool], blocked: [Bool], over image: inout RGBAImage) {
            let stride = w + 1
            var sum = [SIMD4<Int32>](repeating: .zero, count: stride * (h + 1))
            for y in 0..<h {
                var row = SIMD4<Int32>.zero
                for x in 0..<w {
                    let c = (y0 + y) * image.width + x0 + x
                    if !blocked[c] {
                        let j = c * 4
                        row &+= SIMD4(Int32(image.pixels[j]), Int32(image.pixels[j + 1]), Int32(image.pixels[j + 2]), 1)
                    }
                    sum[(y + 1) * stride + x + 1] = sum[y * stride + x + 1] &+ row
                }
            }
            for y in 0..<h {
                for x in 0..<w where cover[y * w + x] {
                    for scale in [1, 2, 4] {
                        let r = radius * scale
                        let ax = max(0, x - r), bx = min(w, x + r + 1), ay = max(0, y - r), by = min(h, y + r + 1)
                        let s = sum[by * stride + bx] &- sum[ay * stride + bx] &- sum[by * stride + ax] &+ sum[ay * stride + ax]
                        guard s.w > 0 else { continue }
                        let j = ((y0 + y) * image.width + x0 + x) * 4
                        image.pixels[j] = UInt8(clamping: (s.x + s.w / 2) / s.w)
                        image.pixels[j + 1] = UInt8(clamping: (s.y + s.w / 2) / s.w)
                        image.pixels[j + 2] = UInt8(clamping: (s.z + s.w / 2) / s.w)
                        break
                    }
                }
            }
        }

        /// Sets the canvas pixels within `nearReach` pens of the lines.
        func markNear(_ near: inout [Bool], canvasWidth: Int) {
            let d = distanceToLines()
            let reach = Writing.nearReach * pen + 1
            for y in 0..<h {
                for x in 0..<w where d[y * w + x] <= reach * reach { near[(y0 + y) * canvasWidth + x0 + x] = true }
            }
        }
    }

    // MARK: - Geometry

    /// A line of text: its box in pixel coordinates, `u` along the line, `v` across it.
    struct Frame {
        var origin: SIMD2<Float>
        var u: SIMD2<Float>
        var v: SIMD2<Float>
        var length: Float
        var height: Float

        /// The box around `polygon` (normalized to the photo) along its longest side.
        init?(_ polygon: [SIMD2<Float>], width w: Int, height h: Int) {
            let pts = polygon.filter { $0.x.isFinite && $0.y.isFinite }.map {
                SIMD2(min(max($0.x, 0), 1) * Float(w) - 0.5, min(max($0.y, 0), 1) * Float(h) - 0.5)
            }
            guard pts.count >= 3 else { return nil }
            var along = SIMD2<Float>(1, 0), longest: Float = 0
            for i in pts.indices {
                let d = pts[(i + 1) % pts.count] - pts[i]
                let l = simdLength(d)
                if l > longest { longest = l; along = d / l }
            }
            guard longest > 0 else { return nil }
            if abs(along.x) >= abs(along.y) ? along.x < 0 : along.y < 0 { along = -along }
            u = along
            v = SIMD2(-along.y, along.x)
            var lo = SIMD2<Float>(repeating: .infinity), hi = SIMD2<Float>(repeating: -.infinity)
            for p in pts {
                let q = SIMD2(simdDot(p, u), simdDot(p, v))
                lo = pointwiseMin(lo, q); hi = pointwiseMax(hi, q)
            }
            origin = u * lo.x + v * lo.y
            length = hi.x - lo.x
            height = hi.y - lo.y
            guard length >= 1, height >= 1 else { return nil }
        }

        /// The box's centre and height, for the report.
        var stats: WritingAreaStats {
            var s = WritingAreaStats()
            let centre = origin + u * (length / 2) + v * (height / 2)
            s.x = centre.x; s.y = centre.y; s.height = height
            return s
        }

        /// How far `p` lies inside the box grown by `grow` (along, across); negative outside.
        func inset(_ p: SIMD2<Float>, grow: SIMD2<Float>) -> Float {
            let d = p - origin
            let s = simdDot(d, u), t = simdDot(d, v)
            return min(min(s + grow.x, length + grow.x - s), min(t + grow.y, height + grow.y - t))
        }

        /// The canvas pixels (min inclusive, max exclusive) of the box grown by `grow`, `pad`
        /// pixels more on every side.
        func bounds(grow: SIMD2<Float>, pad: Int, width w: Int, height h: Int) -> (x0: Int, y0: Int, x1: Int, y1: Int) {
            var lo = SIMD2<Float>(repeating: .infinity), hi = SIMD2<Float>(repeating: -.infinity)
            for c in [SIMD2(-grow.x, -grow.y), SIMD2(length + grow.x, -grow.y), SIMD2(-grow.x, height + grow.y),
                      SIMD2(length + grow.x, height + grow.y)] {
                let p = origin + u * c.x + v * c.y
                lo = pointwiseMin(lo, p); hi = pointwiseMax(hi, p)
            }
            return (max(0, Int(lo.x.rounded(.down)) - pad), max(0, Int(lo.y.rounded(.down)) - pad),
                    min(w, Int(hi.x.rounded(.up)) + 1 + pad), min(h, Int(hi.y.rounded(.up)) + 1 + pad))
        }
    }

    // MARK: - Lightness

    /// OKLab lightness of the canvas pixels the zones cover, computed once.
    struct Lightness {
        let x0: Int, y0: Int, w: Int, h: Int
        let values: [Float]

        init(image: RGBAImage, bounds b: (x0: Int, y0: Int, x1: Int, y1: Int)) {
            x0 = b.x0; y0 = b.y0; w = max(b.x1 - b.x0, 0); h = max(b.y1 - b.y0, 0)
            var values = [Float](repeating: 0, count: w * h)
            for y in 0..<h {
                for x in 0..<w { values[y * w + x] = Self.lightness(image, x: x0 + x, y: y0 + y) }
            }
            self.values = values
        }

        static func lightness(_ image: RGBAImage, x: Int, y: Int) -> Float {
            let lut = ColorScience.decodeLUT
            let j = (y * image.width + x) * 4
            let rgb = SIMD3(lut[Int(image.pixels[j])], lut[Int(image.pixels[j + 1])], lut[Int(image.pixels[j + 2])])
            return ColorScience.linearToOKLab(rgb, space: image.colorSpace).x
        }

        /// The lightness at a canvas pixel inside the bounds.
        func at(_ x: Int, _ y: Int) -> Float { values[(y - y0) * w + x - x0] }
    }

    // MARK: - Patch

    /// A window of the canvas around an area: the ink's contrast, the paper behind it, and which
    /// pixels belong to the zone and to the core.
    struct Patch {
        let x0: Int, y0: Int, w: Int, h: Int
        let frame: Frame
        let zone: SIMD2<Float>
        let radius: Int
        let contrast: [Float]
        /// The paper's lightness (the closing for dark ink, the opening for light).
        let paper: [Float]
        let inside: [Bool]
        let core: [Bool]
        let lightness: [Float]
        /// Whether the ink is darker than the paper.
        let dark: Bool
        /// The pen of the core's plain split into ink and paper, and whether that is bold (when
        /// the rest goes uncomputed).
        let plainPen: Float
        let bold: Bool

        init(
            image: RGBAImage, lightness canvas: Lightness, frame: Frame, zone: SIMD2<Float>, core coreGrow: SIMD2<Float>,
            radius least: Int, boldPen: Float
        ) {
            let b = frame.bounds(grow: zone, pad: Writing.maximumWindow, width: image.width, height: image.height)
            x0 = b.x0; y0 = b.y0; w = max(b.x1 - b.x0, 1); h = max(b.y1 - b.y0, 1)
            self.frame = frame
            self.zone = zone
            let n = w * h
            var lightness = [Float](repeating: 0, count: n)
            var inside = [Bool](repeating: false, count: n), core = [Bool](repeating: false, count: n)
            for y in 0..<h {
                for x in 0..<w {
                    let cx = min(x0 + x, image.width - 1), cy = min(y0 + y, image.height - 1)
                    lightness[y * w + x] = canvas.at(cx, cy)
                    let p = SIMD2(Float(cx), Float(cy))
                    inside[y * w + x] = frame.inset(p, grow: zone) >= 0
                    core[y * w + x] = frame.inset(p, grow: coreGrow) >= 0
                }
            }
            self.inside = inside
            self.core = core
            self.lightness = lightness
            // The paper is what surrounds the writing: of a plain split of the core into dark and
            // light, the side most of the margin around the box lies on, whether the writing is dark
            // ink on paper or light (chalk on a board), and however much of the box bold letters
            // fill. (The zone's extremes can't tell: a chalkboard's dark frame lies as far below
            // the board as the chalk lies above it; nor can the hats: the paper between close
            // strokes is a light feature narrower than the square.)
            let cut = Self.otsu(lightness, core)
            var below = 0, total = 0
            for y in 0..<h {
                for x in 0..<w where core[y * w + x] {
                    let p = SIMD2(Float(min(x0 + x, image.width - 1)), Float(min(y0 + y, image.height - 1)))
                    guard frame.inset(p, grow: .zero) < 0 else { continue }
                    total += 1
                    if lightness[y * w + x] < cut { below += 1 }
                }
            }
            let dark = 2 * below <= total
            self.dark = dark
            let plain = (0..<n).map { core[$0] && (dark ? lightness[$0] < cut : lightness[$0] >= cut) }
            plainPen = Self.lineWidth(plain, halfWidth: Self.halfWidths(plain, width: w, height: h), width: w, height: h)
            bold = plainPen >= boldPen
            let r = min(Writing.maximumWindow, max(least, Int((plainPen / 2).rounded(.up)) + 2))
            radius = r
            guard !bold else {
                contrast = []
                paper = []
                return
            }
            let paper = Self.extreme(Self.extreme(lightness, w, h, r, maximum: dark), w, h, r, maximum: !dark)
            self.paper = paper
            contrast = (0..<n).map { dark ? paper[$0] - lightness[$0] : lightness[$0] - paper[$0] }
        }

        /// The canvas position of a patch point.
        func canvasPoint(_ p: SIMD2<Float>) -> SIMD2<Float> { p + SIMD2(Float(x0), Float(y0)) }

        /// Whether `other`'s box reaches into the patch.
        func overlaps(_ other: Frame) -> Bool {
            let b = other.bounds(grow: .zero, pad: 0, width: Int.max, height: Int.max)
            return b.x0 < x0 + w && b.x1 > x0 && b.y0 < y0 + h && b.y1 > y0
        }

        /// The canvas index of patch pixel `i`.
        func canvasIndex(_ i: Int, canvasWidth: Int) -> Int { (y0 + i / w) * canvasWidth + x0 + i % w }

        /// Strokes too wide for the square, and the band along their edges, all the square sees of
        /// them (bold letters, a dark shape beside the writing): within the square's reach of ink,
        /// found by a square `wideWindow` times as wide, that holds the closing's whole square
        /// (which is what lets a stroke survive the closing).
        func wideStrokes(threshold high: Float) -> [Bool] {
            let n = w * h
            let big = Writing.wideWindow * radius
            let paper = Self.extreme(Self.extreme(lightness, w, h, big, maximum: dark), w, h, big, maximum: !dark)
            let ink = (0..<n).map { (dark ? paper[$0] - lightness[$0] : lightness[$0] - paper[$0]) >= high ? Float(1) : 0 }
            let inside = Self.extreme(ink, w, h, radius, maximum: false)
            guard inside.contains(1) else { return [Bool](repeating: false, count: n) }
            return Self.extreme(inside, w, h, radius + 2, maximum: true).map { $0 > 0 }
        }

        /// How far a patch point lies inside the zone (negative outside).
        func zoneInset(_ p: SIMD2<Float>) -> Float { frame.inset(canvasPoint(p), grow: zone) }

        /// The zone's pixels above `threshold`, grown by `growth` pixels into contrast above half of it.
        func mask(threshold high: Float) -> [Bool] {
            let n = w * h
            var ink = (0..<n).map { inside[$0] && contrast[$0] >= high }
            let weak = (0..<n).map { inside[$0] && contrast[$0] >= 0.5 * high }
            for _ in 0..<Writing.growth {
                var next = ink
                for y in 0..<h {
                    for x in 0..<w where weak[y * w + x] && !ink[y * w + x] {
                        search: for dy in -1...1 where y + dy >= 0 && y + dy < h {
                            for dx in -1...1 where x + dx >= 0 && x + dx < w && ink[(y + dy) * w + x + dx] {
                                next[y * w + x] = true
                                break search
                            }
                        }
                    }
                }
                ink = next
            }
            return ink
        }

        /// The median lightness of the core's paper (its pixels off the ink).
        func paperLightness(ink: [Bool]) -> Float {
            var values: [Float] = []
            for i in 0..<(w * h) where core[i] && !ink[i] { values.append(paper[i]) }
            values.sort()
            return values.isEmpty ? 1 : values[values.count / 2]
        }

        /// Whether ink apart from the writing is a mark: wholly in the zone, at least
        /// `markSize` heights across, drawn with the writing's pen on its paper.
        func isMark(_ pixels: [Int], height: Float, pen: Float, paper lightness: Float, halfWidth: [Float]) -> Bool {
            var lo = SIMD2<Int>(w, h), hi = SIMD2<Int>(-1, -1)
            for i in pixels {
                let p = SIMD2(i % w, i / w)
                lo = pointwiseMin(lo, p); hi = pointwiseMax(hi, p)
                if zoneInset(SIMD2(Float(p.x), Float(p.y))) < 1.5 { return false }
            }
            guard Float(max(hi.x - lo.x, hi.y - lo.y) + 1) >= Writing.markSize * height else { return false }
            // Its broadest part (the 90th percentile, against stray thick pixels) is pen-like.
            let widths = pixels.map { 2 * halfWidth[$0] }.sorted()
            guard widths[widths.count * 9 / 10] <= Writing.markPen * pen else { return false }
            // The ring three pixels around it is the writing's paper.
            let bx0 = max(lo.x - 3, 0), by0 = max(lo.y - 3, 0), bx1 = min(hi.x + 3, w - 1), by1 = min(hi.y + 3, h - 1)
            let bw = bx1 - bx0 + 1, bh = by1 - by0 + 1
            var mark = [Bool](repeating: false, count: bw * bh)
            for i in pixels { mark[(i / w - by0) * bw + i % w - bx0] = true }
            var ring = mark
            for _ in 0..<3 { ring = Morphology.square(ring, width: bw, height: bh, any: true) }
            var total = 0, alike = 0
            for k in 0..<(bw * bh) where ring[k] && !mark[k] {
                total += 1
                if abs(paper[(k / bw + by0) * w + k % bw + bx0] - lightness) <= Writing.paperTolerance { alike += 1 }
            }
            return total > 0 && Float(alike) >= 0.9 * Float(total)
        }

        // MARK: Helpers

        /// Square max (or min) filter of radius `r`, separable, the window clipped at the edges:
        /// van Herk and Gil-Werman's blocks, a few comparisons a pixel whatever the radius.
        static func extreme(_ v: [Float], _ w: Int, _ h: Int, _ r: Int, maximum: Bool) -> [Float] {
            guard r > 0, w > 0, h > 0 else { return v }
            let k = 2 * r + 1, none: Float = maximum ? -.infinity : .infinity
            var line = [Float](repeating: none, count: max(w, h) + 2 * r), prefix = line, suffix = line
            @inline(__always) func pick(_ a: Float, _ b: Float) -> Float { maximum ? max(a, b) : min(a, b) }
            /// `line[0..<n + 2r]` (a line padded by `r` either side): running extremes from each
            /// block's start (`prefix`) and to each block's end (`suffix`), so the window at `i`
            /// is `pick(suffix[i], prefix[i + 2r])`.
            func blocks(_ n: Int) {
                let m = n + 2 * r
                for i in 0..<m { prefix[i] = i % k == 0 ? line[i] : pick(prefix[i - 1], line[i]) }
                var i = m - 1
                while i >= 0 {
                    suffix[i] = (i % k == k - 1 || i == m - 1) ? line[i] : pick(suffix[i + 1], line[i])
                    i -= 1
                }
            }
            var mid = v, out = v
            for y in 0..<h {
                for i in 0..<r { line[i] = none; line[r + w + i] = none }
                for x in 0..<w { line[r + x] = v[y * w + x] }
                blocks(w)
                for x in 0..<w { mid[y * w + x] = pick(suffix[x], prefix[x + 2 * r]) }
            }
            for x in 0..<w {
                for i in 0..<r { line[i] = none; line[r + h + i] = none }
                for y in 0..<h { line[r + y] = mid[y * w + x] }
                blocks(h)
                for y in 0..<h { out[y * w + x] = pick(suffix[y], prefix[y + 2 * r]) }
            }
            return out
        }

        /// 256-bin histogram of `values` in 0...1 over the `inside` pixels.
        static func histogram(_ values: [Float], _ inside: [Bool]) -> (bins: [Int], count: Int) {
            var bins = [Int](repeating: 0, count: 256), count = 0
            for i in values.indices where inside[i] {
                bins[min(max(Int(values[i] * 255), 0), 255)] += 1
                count += 1
            }
            return (bins, count)
        }

        /// Otsu's threshold of `values` over the `inside` pixels: the cut between the two
        /// classes that differ most.
        static func otsu(_ values: [Float], _ inside: [Bool]) -> Float {
            let (bins, count) = histogram(values, inside)
            guard count > 0 else { return 1 }
            var total = 0.0
            for b in 0..<256 { total += Double(b * bins[b]) }
            var below = 0, belowSum = 0.0, best = -1.0, cut = 255
            for b in 0..<255 {
                below += bins[b]
                belowSum += Double(b * bins[b])
                let above = count - below
                guard below > 0, above > 0 else { continue }
                let m0 = belowSum / Double(below), m1 = (total - belowSum) / Double(above)
                let between = Double(below) * Double(above) * (m0 - m1) * (m0 - m1)
                if between > best { best = between; cut = b + 1 }
            }
            return Float(cut) / 255
        }

        /// 8-connected components of `mask`, each its pixels in raster order, in raster order of
        /// their first pixel.
        static func components(_ mask: [Bool], width w: Int, height h: Int) -> [[Int]] {
            var seen = [Bool](repeating: false, count: w * h)
            var out: [[Int]] = []
            var stack: [Int] = []
            for start in 0..<(w * h) where mask[start] && !seen[start] {
                var pixels: [Int] = []
                seen[start] = true
                stack.append(start)
                while let i = stack.popLast() {
                    pixels.append(i)
                    let x = i % w, y = i / w
                    for dy in -1...1 where y + dy >= 0 && y + dy < h {
                        for dx in -1...1 where x + dx >= 0 && x + dx < w {
                            let j = (y + dy) * w + x + dx
                            if mask[j] && !seen[j] { seen[j] = true; stack.append(j) }
                        }
                    }
                }
                pixels.sort()
                out.append(pixels)
            }
            return out
        }

        /// Distance from each pixel of `mask` to the nearest pixel outside it (pixel centres).
        static func halfWidths(_ mask: [Bool], width w: Int, height h: Int) -> [Float] {
            DistanceTransform.squaredEDT(width: w, height: h) { !mask[$0] }.storage.map { $0.squareRoot() }
        }

        /// `mask` thinned to one-pixel centerlines (its frame cleared, as tracing needs).
        static func centerlines(_ mask: [Bool], width w: Int, height h: Int) -> [Bool] {
            var thin = mask
            for x in 0..<w { thin[x] = false; thin[(h - 1) * w + x] = false }
            for y in 0..<h { thin[y * w] = false; thin[y * w + w - 1] = false }
            Thinning.thin(&thin, width: w, height: h)
            dropRedundant(&thin, width: w, height: h)
            return thin
        }

        /// Takes out the pixels Zhang–Suen leaves that aren't junctions: one with three or more
        /// neighbours that stay connected without it (a staircase corner on a diagonal stroke a
        /// few pixels wide, a 2×2 block), which tracing would take for a junction, losing the
        /// stroke into it. In raster order, until none is left; the detectors' ridges, a pixel or
        /// two wide, rarely leave one.
        static func dropRedundant(_ mask: inout [Bool], width w: Int, height h: Int) {
            guard w > 2, h > 2 else { return }
            // Clockwise from north: N NE E SE S SW W NW.
            let offsets = [-w, -w + 1, 1, w + 1, w, w - 1, -1, -w - 1]
            var changed = true
            while changed {
                changed = false
                for y in 1..<(h - 1) {
                    for x in 1..<(w - 1) where mask[y * w + x] {
                        let i = y * w + x
                        var b: UInt8 = 0
                        for k in 0..<8 where mask[i + offsets[k]] { b |= 1 << k }
                        guard b.nonzeroBitCount >= 3, Self.simple[Int(b)] else { continue }
                        mask[i] = false
                        changed = true
                    }
                }
            }
        }

        /// By neighbourhood (bits as in `dropRedundant`): whether the set neighbours are one
        /// group, neighbours along the ring touching, and so the two 4-neighbours around a corner.
        static let simple: [Bool] = (0..<256).map { v in
            var parent = Array(0..<8)
            func find(_ k: Int) -> Int { var k = k; while parent[k] != k { k = parent[k] }; return k }
            func join(_ a: Int, _ b: Int) { parent[find(a)] = find(b) }
            for k in 0..<8 where v & (1 << k) != 0 {
                if v & (1 << ((k + 1) % 8)) != 0 { join(k, (k + 1) % 8) }
                if k % 2 == 0 && v & (1 << ((k + 2) % 8)) != 0 { join(k, (k + 2) % 8) }
            }
            return Set((0..<8).filter { v & (1 << $0) != 0 }.map(find)).count == 1
        }

        /// The width of the lines of `mask`, measured as `Ink.pen`.
        static func lineWidth(_ mask: [Bool], halfWidth: [Float], width w: Int, height h: Int) -> Float {
            lineWidth(thin: centerlines(mask, width: w, height: h), halfWidth: halfWidth)
        }

        /// Twice the median distance from the centerline pixels to the outside (`Ink.pen`).
        static func lineWidth(thin: [Bool], halfWidth: [Float]) -> Float {
            var widths: [Float] = []
            for i in thin.indices where thin[i] { widths.append(2 * halfWidth[i]) }
            guard !widths.isEmpty else { return 2 }
            widths.sort()
            return max(widths[widths.count / 2], 2)
        }
    }
}
