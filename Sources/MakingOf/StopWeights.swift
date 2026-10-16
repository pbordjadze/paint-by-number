/// The pixels a line runs through, by the distance from each pixel's centre to the line, with
/// nothing from a rasterizer: `line_mask` in `making_of_exact.py`, the same pixels. It stands in for
/// the rasterized drawing where the show must decide something from where lines run, since
/// anti-aliasing differs between rasterizers.
struct LineMask: Sendable, Equatable {
    /// 1 where a line runs, else 0.
    var plane: Plane<UInt8>

    /// How far past a line's half width a pixel's centre may be and still count as inked: it makes
    /// the mask as big as resvg's (`lines < 0.85`, a pixel at least a sixth covered), the parrots'
    /// 18814 pixels against its 18844.
    static let reach = 0.33

    /// The mask of `strokes` drawn `lineWidth` wide in a plane `width` x `height`.
    init(width: Int, height: Int, strokes: [Polyline], lineWidth: Double) {
        self.init(width: width, height: height, strokes: strokes, halfWidth: lineWidth / 2 + Self.reach)
    }

    /// The pixels whose centre is within `halfWidth` of a stroke (`line_mask(..., half_width)`).
    init(width: Int, height: Int, strokes: [Polyline], halfWidth half: Double) {
        var plane = Plane<UInt8>(width: width, height: height, repeating: 0)
        let near = half * half
        for stroke in strokes {
            for (a, b) in zip(stroke.points, stroke.points.dropFirst()) {
                let x0 = max(truncated((min(a.x, b.x) - half).rounded(.down)) - 1, 0)
                let x1 = min(truncated((max(a.x, b.x) + half).rounded(.down)) + 2, width)
                let y0 = max(truncated((min(a.y, b.y) - half).rounded(.down)) - 1, 0)
                let y1 = min(truncated((max(a.y, b.y) + half).rounded(.down)) + 2, height)
                guard x0 < x1, y0 < y1 else { continue }
                let vx = b.x - a.x, vy = b.y - a.y
                let length2 = vx * vx + vy * vy
                for y in y0..<y1 {
                    let py = Double(y) + 0.5
                    for x in x0..<x1 {
                        let px = Double(x) + 0.5
                        var t = 0.0
                        if length2 > 0 { t = min(max(((px - a.x) * vx + (py - a.y) * vy) / length2, 0), 1) }
                        let dx = px - (a.x + t * vx), dy = py - (a.y + t * vy)
                        if dx * dx + dy * dy <= near { plane.data[y * width + x] = 1 }
                    }
                }
            }
        }
        self.plane = plane
    }
}

/// How likely each pixel is to be picked as a place to work, per step: the planes
/// `tools/factory/making_of_inputs.py` weighs spots by, which are integers or doubles made of
/// `+ - * /` and `squareRoot()` only, so Swift and Python draw the same spots. Every plane is zero
/// outside `room`, the picture without a margin where a guardian would stand in a corner.
struct StopWeights {
    let pictures: ShowPictures
    let template: ShowTemplate
    let petHeight: Double
    /// The rows and columns a guardian may work in: below the top margin and the guardian's own height (so
    /// all of it stays in the picture), above the bottom 8 px, off the sides' margins.
    let rows: Range<Int>
    let columns: Range<Int>

    init(pictures: ShowPictures, template: ShowTemplate, petHeight: Double, margin: Double) {
        self.pictures = pictures
        self.template = template
        self.petHeight = petHeight
        let w = pictures.width, h = pictures.height
        let top = min(truncated(margin * Double(h) + petHeight), h)
        let side = truncated(margin * Double(w))
        rows = top..<min(max(h - 8, top), h)
        columns = min(side, w)..<min(max(w - side, side), w)
    }

    /// The weights of step `step`, which must be one that draws spots from a plane: the first, second,
    /// fourth and sixth.
    func plane(forStep step: Int) -> [Double] {
        switch step {
        case 0: structure()
        case 1: uniform()
        case 3: shrinking()
        case 5: numbers()
        default: preconditionFailure("step \(step) has no weights")
        }
    }

    /// The structure plus 0.35, in units of 1/1020 (`structure / 255 + 0.35` as integers): edges
    /// first, but the whole picture is visited.
    func structure() -> [Double] {
        filled { Double(pictures.structure.data[$0]) * 4 + 357 }
    }

    func uniform() -> [Double] {
        filled { _ in 1 }
    }

    /// 1 over the square root of the area of the merged region a pixel is in, so small regions are
    /// visited as much as large ones.
    func shrinking() -> [Double] {
        let regions = Labeling.regions(of: pictures.simplified)
        var area = [Int](repeating: 0, count: regions.count)
        for label in regions.labels.data { area[Int(label)] += 1 }
        return filled {
            let a = Double(area[Int(regions.labels.data[$0])])
            return a.squareRoot() / a
        }
    }

    /// Where the numbers are, in the open: a number counts one (and a floor of 1e-6, so every pixel
    /// stays possible), times `0.05 + open^2`, where `open` is 1 less how thick lines run within a
    /// guardian's reach (a box of 0.35 of its height, against the thickest 5% of the picture), so a guardian
    /// doesn't stand tangled in the finished drawing's ink.
    func numbers() -> [Double] {
        let w = pictures.width, h = pictures.height
        var count = [Double](repeating: 0, count: w * h)
        for number in template.numbers {
            let x = truncated(min(max(number.x, 0), Double(w - 1)))
            let y = truncated(min(max(number.y, 0), Double(h - 1)))
            count[y * w + x] += 1
        }
        let ink = LineMask(width: w, height: h, strokes: template.strokes, lineWidth: template.lineWidth)
        let density = ExactMath.boxSums(ink.plane, radius: max(1, truncated(0.35 * petHeight)))
        let p95 = ExactMath.percentile(density.data, percent: 95)
        return filled {
            let open = 1 - min(Double(density.data[$0]) / (p95 + 1e-6), 1)
            return (count[$0] + 1e-6) * (0.05 + open * open)
        }
    }

    /// A plane of `weight(index)` inside the room, zero outside.
    private func filled(_ weight: (Int) -> Double) -> [Double] {
        let w = pictures.width
        var plane = [Double](repeating: 0, count: w * pictures.height)
        for y in rows {
            for x in columns { plane[y * w + x] = weight(y * w + x) }
        }
        return plane
    }
}
