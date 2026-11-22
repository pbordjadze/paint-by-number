import CoreGraphics
import CoreImage
import Foundation
import PaintCore
import SwiftUI

/// The short Making-of as everyone's wait, "graphite and fuse" (painting-company row 361; SideStore
/// and Debug builds, `UNRELEASED`: the release keeps the picture forming as it is). It grows out of
/// the picture forming (`FormingPlan`) and keeps its rule: it adds nothing to the making, and it
/// ends on exactly the page the painting will show.
///
/// 1. **Graphite** (the wait): from the moment the photo shows, its color drains away as pencil
///    strokes race along its shapes from the middle (`GraphiteSketch`), and the drawing holds there
///    for as long as the template is still being made: a faster device sees less of it. No status
///    shows over it until the making has taken `patience`.
/// 2. **Fuse**: once the template is made, its own lines burn in across the graphite like a fuse,
///    a band of gold at the burning front, the paper drying to the page's behind it. It is done
///    `FormingPlan.drawIn` after the template is made, as the plain forming's drawing in is: a
///    template made almost at once lets the graphite show `graphiteAtLeast` first, and its fuse
///    burns that much faster.
/// 3. **Stars**: as the picture glides to the painting's place (the hand-off's own `settle`, no
///    time of its own), the page's numbers come out behind the same front, each with a twinkle
///    (`Stars`), and the picture is the page the canvas draws.
///
/// A tap skips at any moment (`skip`): once the template is made, to the painting; before, to the
/// plain picture forming, its lines drawn in as ever once made. Reduce Motion and The Making-of
/// switched on bring none of it, as they bring no lines (`FormingPlan.hasLines`). VoiceOver hears
/// the forming's one status, as before.
///
/// Each frame only moves what was made once: the graphite is a few images cross-faded
/// (`GraphiteSketch.Drawing`), the front an image (`FrontMasks`) scaled about its centre, the gold
/// lines an image with their glow in it (`FormingShow.glow`), the ink lines the forming's own,
/// stroked once.
nonisolated enum FormingShow {
    #if UNRELEASED
    static let isOn = true
    #else
    static let isOn = false
    #endif

    /// Whether the picture forming plays the show: it forms with lines, and no tap has sent it to
    /// the plain forming.
    static func plays(forms: Bool, reduceMotion: Bool, playsMakingOf: Bool, skipped: Skip?) -> Bool {
        isOn && forms && FormingPlan.hasLines(reduceMotion: reduceMotion, playsShow: playsMakingOf) && skipped != .toPlainLines
    }

    // MARK: Timing

    /// The graphite's front crosses the whole picture, racing out and slowing: about the making
    /// of a template on an iPad Air (1.1 s), slowed with the hand-off (`-handoffSlowdown`).
    static var graphiteSweep: Double { 2.4 * StartHandoffPlan.glide }
    /// The least the graphite shows before the fuse is lit: a template made at once would show
    /// it for a flicker, which reads as a glitch rather than a drawing. Taken from the fuse,
    /// never added to the wait.
    static var graphiteAtLeast: Double { 0.3 * StartHandoffPlan.glide }
    /// The most the show keeps the hand-off waiting once the template is made: the plain
    /// forming's drawing in, and no more.
    static var longestTail: Double { FormingPlan.drawIn }
    /// How long the graphite stands for the forming's status (seconds): a making slower than
    /// this (an older device, a large photo) brings the status back, so the wait has a sign.
    static let patience = 4.0

    /// When the fuse is lit (seconds, any clock), the template made at `made` and the graphite
    /// begun at `graphiteBegan` (nil: it never began): at once, unless the graphite has shown
    /// for less than `graphiteAtLeast`.
    static func fuseLit(madeAt made: Double, graphiteBegan: Double?) -> Double {
        guard let began = graphiteBegan else { return made }
        return max(made, min(began + graphiteAtLeast, made + graphiteAtLeast))
    }

    /// When the lines have burned in and the hand-off may lift: `longestTail` after the making,
    /// whenever the fuse was lit.
    static func done(madeAt made: Double) -> Double {
        made + longestTail
    }

    /// How far the graphite has raced, `elapsed` seconds after it began: racing out, easing in.
    static func graphiteProgress(since elapsed: Double) -> Double {
        let x = min(max(elapsed / graphiteSweep, 0), 1)
        return 1 - (1 - x) * (1 - x) * (1 - x)
    }

    /// How far a fuse burning for `length` seconds has burned `elapsed` seconds after it was
    /// lit: catching, then steady.
    static func fuseProgress(since elapsed: Double, length: Double) -> Double {
        guard length > 0 else { return elapsed >= 0 ? 1 : 0 }
        let x = min(max(elapsed / length, 0), 1)
        return x * x * (3 - 2 * x)
    }

    /// The numbers come out during the glide: the hand-off's own settling into the page.
    static var stars: Double { StartHandoffPlan.settle }

    /// How far the numbers have come out, `elapsed` seconds after the page came in.
    static func starsProgress(since elapsed: Double) -> Double {
        let x = min(max(elapsed / stars, 0), 1)
        return 1 - (1 - x) * (1 - x)
    }

    // MARK: Skipping

    /// Where a tap goes.
    nonisolated enum Skip: Equatable, Sendable {
        /// The template isn't made: the graphite goes, and the photo waits as the plain forming's
        /// does, its lines drawn in once made.
        case toPlainLines
        /// The template is made: the lines are all there at once, and the hand-off lifts now.
        case toPainting
    }

    static func skip(isMade: Bool) -> Skip {
        isMade ? .toPainting : .toPlainLines
    }

    // MARK: The front

    /// Where the fuse and the numbers arrive: a blot growing from a little above the picture's
    /// middle, where the graphite began (`GraphiteSketch.seed`), its outline wavering (`shape`),
    /// so it spreads rather than wipes. The same front in both, so the numbers come out where
    /// the ink went. It only grows (its shape is the same at every size), so one image of it,
    /// scaled about its centre, draws it at any progress (`FrontMasks`); at progress 1 even its
    /// soft edge has passed every corner.
    nonisolated enum Front {
        static let centre = CGPoint(x: 0.5, y: 0.45)
        /// How far the outline wavers, as a share of its reach.
        static let wobble = 0.22
        /// How wide the front's soft edge is, as a share of its reach: nearly sharp.
        static let edge = 0.05

        /// The outline's reach at `angle` (radians, y down), relative to its mean.
        static func shape(at angle: Double) -> Double {
            1 + wobble * (0.5 * sin(3 * angle + 0.7) + 0.3 * sin(5 * angle + 2.1) + 0.2 * sin(8 * angle + 4.4))
        }

        static func origin(in rect: CGRect) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * centre.x, y: rect.minY + rect.height * centre.y)
        }

        /// The mean reach at progress 1 (points): the inner end of its soft edge past the
        /// farthest corner wherever the outline wavers in.
        static func reach(in rect: CGRect) -> Double {
            let o = origin(in: rect)
            let dx = Double(max(o.x - rect.minX, rect.maxX - o.x)), dy = Double(max(o.y - rect.minY, rect.maxY - o.y))
            return (dx * dx + dy * dy).squareRoot() / ((1 - wobble) * (1 - edge))
        }

        /// The side of the square the front's image fills at progress 1 (points).
        static func side(in rect: CGRect) -> Double {
            2 * (1 + wobble) * reach(in: rect)
        }

        /// The progress (0…1) at which the middle of the front's soft edge reaches `point`.
        static func arrival(of point: CGPoint, in rect: CGRect) -> Double {
            let o = origin(in: rect)
            let dx = Double(point.x - o.x), dy = Double(point.y - o.y)
            let full = reach(in: rect)
            guard full > 0 else { return 0 }
            let ratio = (dx * dx + dy * dy).squareRoot() / (full * shape(at: atan2(dy, dx)))
            return min(1, ratio / (1 - edge / 2))
        }

        /// How opaque the front is at a point `ratio` of the way to its outline: whole inside its
        /// soft edge, nothing past the outline.
        static func alpha(ratio: Double) -> Double {
            let t = min(max((1 - ratio) / edge, 0), 1)
            return t * t * (3 - 2 * t)
        }

        /// The front at progress 1 as a square image `pixels` across, white with the front's
        /// opacity, its centre the front's origin. Made once, off the main actor.
        @concurrent
        static func image(pixels: Int) async -> CGImage? {
            guard pixels > 1 else { return nil }
            let angles = 2048
            let table = (0..<angles).map { shape(at: 2 * Double.pi * Double($0) / Double(angles)) }
            let half = Double(pixels) / 2, extent = 1 + wobble
            var bytes = [UInt8](repeating: 0, count: pixels * pixels * 4)
            for y in 0..<pixels {
                let v = (Double(y) + 0.5 - half) / half * extent
                for x in 0..<pixels {
                    let u = (Double(x) + 0.5 - half) / half * extent
                    var angle = atan2(v, u)
                    if angle < 0 { angle += 2 * Double.pi }
                    let k = min(Int(angle / (2 * Double.pi) * Double(angles)), angles - 1)
                    let a = UInt8((alpha(ratio: (u * u + v * v).squareRoot() / table[k]) * 255).rounded())
                    let i = (y * pixels + x) * 4
                    bytes[i] = a
                    bytes[i + 1] = a
                    bytes[i + 2] = a
                    bytes[i + 3] = a
                }
            }
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let provider = CGDataProvider(data: Data(bytes) as CFData)
            else { return nil }
            return CGImage(
                width: pixels, height: pixels, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: pixels * 4, space: space,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider,
                decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        }
    }

    // MARK: The burning front

    /// The gold of the burning front and of the twinkles: `Theme.gold`'s components.
    static let goldRGB = SIMD3<Double>(0.788, 0.635, 0.290)

    /// The template's lines in gold with their glow, filling a picture `size` points (as the
    /// forming photo is filled: centred, cropped), `lineWidth` points wide as the ink's are and
    /// heavier by `weight`: the burning front's layer, stroked once off the main actor at one
    /// pixel a point (a glow needs no more), so a frame only moves its mask.
    @concurrent
    static func glow(_ drawing: LineArtDrawing, size: CGSize, lineWidth: CGFloat, weight: CGFloat = 1.8) async -> CGImage? {
        let scale = min(1, 1600 / max(size.width, size.height, 1))
        let w = Int((size.width * scale).rounded()), h = Int((size.height * scale).rounded())
        let units = drawing.size
        guard w >= 1, h >= 1, units.width > 0, units.height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let s = max(size.width / units.width, size.height / units.height)
        let gold = CGColor(srgbRed: goldRGB.x, green: goldRGB.y, blue: goldRGB.z, alpha: 1)
        // Top-left origin, points, then canvas units filled into the picture.
        context.translateBy(x: 0, y: CGFloat(h))
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: (size.width - units.width * s) / 2, y: (size.height - units.height * s) / 2)
        context.scaleBy(x: s, y: s)
        context.setShadow(offset: .zero, blur: 6 * scale, color: gold)
        context.setStrokeColor(gold)
        context.setLineWidth(lineWidth * weight / s)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.addPath(drawing.path(within: CGRect(origin: .zero, size: units)).cgPath)
        context.strokePath()
        return context.makeImage()
    }

    // MARK: Stars

    /// The page's numbers, where each comes out: a label's place and size as shares of the page's
    /// width (the page is laid from its top at the picture's width, as the canvas lays it). At
    /// most `limit` of them twinkle, spread over the page; every number comes out with the page.
    nonisolated struct Stars: Sendable {
        /// x, y and radius, over the template's width.
        let labels: [SIMD3<Float>]

        static let limit = 240
        /// How long each twinkles, as a share of the beat.
        static let life = 0.3

        init(_ template: Template, limit: Int = Stars.limit) {
            let width = Float(max(template.width, 1))
            let all = template.labels
            let step = max(1, (all.count + max(limit, 1) - 1) / max(limit, 1))
            labels = Swift.stride(from: 0, to: all.count, by: step).map { i in
                let label = all[i]
                return SIMD3(label.position.x / width, label.position.y / width, label.radius / width)
            }
        }

        /// How bright the twinkle of a number the front reached at `arrival` is at `progress`:
        /// up and down again over `life`, nothing before or after.
        static func twinkle(arrival: Double, progress: Double) -> Double {
            let phase = (progress - arrival) / life
            guard phase > 0, phase < 1 else { return 0 }
            return sin(Double.pi * phase)
        }

        /// A four-pointed sparkle centred at `centre`.
        static func sparkle(at centre: CGPoint, radius r: CGFloat) -> Path {
            var path = Path()
            let k = r * 0.2
            path.move(to: CGPoint(x: centre.x, y: centre.y - r))
            path.addQuadCurve(to: CGPoint(x: centre.x + r, y: centre.y), control: CGPoint(x: centre.x + k, y: centre.y - k))
            path.addQuadCurve(to: CGPoint(x: centre.x, y: centre.y + r), control: CGPoint(x: centre.x + k, y: centre.y + k))
            path.addQuadCurve(to: CGPoint(x: centre.x - r, y: centre.y), control: CGPoint(x: centre.x - k, y: centre.y + k))
            path.addQuadCurve(to: CGPoint(x: centre.x, y: centre.y - r), control: CGPoint(x: centre.x - k, y: centre.y - k))
            path.closeSubpath()
            return path
        }

        /// The progress at which the front reaches each number on a page `size` points (its
        /// width the template's): worked out once per page, not per frame.
        func arrivals(on size: CGSize) -> [(point: CGPoint, radius: CGFloat, arrival: Double)] {
            let rect = CGRect(origin: .zero, size: size)
            let w = size.width
            return labels.map { label in
                let point = CGPoint(x: CGFloat(label.x) * w, y: CGFloat(label.y) * w)
                return (point, min(max(CGFloat(label.z) * w * 1.4, 4), 14), Front.arrival(of: point, in: rect))
            }
        }

        /// Draws the twinkles at `progress` of the numbers at `arrivals`.
        static func draw(
            _ arrivals: [(point: CGPoint, radius: CGFloat, arrival: Double)], in context: inout GraphicsContext,
            progress: Double, color: Color
        ) {
            guard progress > 0, progress < 1 + life else { return }
            for star in arrivals {
                let glow = twinkle(arrival: star.arrival, progress: progress)
                guard glow > 0 else { continue }
                context.opacity = glow
                context.fill(sparkle(at: star.point, radius: star.radius * CGFloat(0.6 + 0.4 * glow)), with: .color(color))
            }
            context.opacity = 1
        }
    }
}

/// The front's image (`FormingShow.Front.image`), made once for the app's life, off the main
/// actor, as the first show begins; until then a front fades instead of spreading.
enum FrontMasks {
    private(set) static var image: CGImage?
    private static var preparing = false

    static func prepare() async {
        guard !preparing, image == nil else { return }
        preparing = true
        image = await FormingShow.Front.image(pixels: 768)
        preparing = false
    }
}

/// The graphite drawing of a photo, the show's wait (`FormingShow`): pencil strokes in the page's
/// ink over the photo gone grey and mostly to the paper, the strokes racing along the photo's
/// shapes from the middle. Made once per photo and paper, off the main actor, at most `longSide`
/// across: the strokes and the images in Core Image (on the GPU, beside the template's making
/// rather than in its way), the race on the CPU at a quarter of the size. `tools/graphite_sim.py`
/// makes the same off the device.
///
/// The strokes are a color-dodge sketch: the grey photo over a blur of its negative is paper
/// wherever the photo is flat and darkens where it changes, along every edge and texture, as a
/// pencil would draw them (an edge filter alone gives faint hairlines that the paper swamps).
/// Each pixel's arrival is how far it lies from `seed` along the strokes, a stroke cheap to
/// travel and bare paper dear, so the drawing runs along a shape before it jumps to the next.
nonisolated enum GraphiteSketch {
    static let longSide: CGFloat = 900
    /// The blur of the negative (pixels): how far from an edge its stroke still darkens.
    static let reach = 4.0
    /// How dark the strokes are drawn, and how much the faint ones are held back.
    static let gain: CGFloat = 2.5
    static let gamma: CGFloat = 1.4
    /// How far the grey photo goes toward the paper under the pencil.
    static let paperShare = 0.88
    /// The pencil's strongest stroke, as a share of the ink.
    static let pencil: CGFloat = 0.9
    /// How many images the race is drawn in: each one the strokes arrived by its end.
    static let stages = 8
    /// The race is worked out on a grid this many times coarser than the drawing.
    static let coarse = 4
    /// How much of the race the photo takes to drain to the grey under the pencil.
    static let drains = 0.4

    nonisolated struct Drawing: Sendable {
        /// The grey photo on the paper, opaque.
        let base: CGImage
        /// The strokes arrived by the end of each of `stages` equal shares of the race (and the
        /// next share's coming in), in ink over nothing: each holds the one before it.
        let stages: [CGImage]
    }

    /// One context for every drawing (Core Image's contexts are thread-safe and costly to make),
    /// without color management: the sketch's arithmetic is on the photo's encoded values.
    private static let context = CIContext(options: [.workingColorSpace: NSNull(), .cacheIntermediates: false])

    @concurrent
    static func draw(_ photo: CGImage, sheet: FormingPlan.Sheet) async -> Drawing? {
        let source = CIImage(cgImage: photo)
        let extent = source.extent
        guard extent.width >= 16, extent.height >= 16, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let s = min(1, longSide / max(extent.width, extent.height))
        let bounds = CGRect(x: 0, y: 0, width: (extent.width * s).rounded(.down), height: (extent.height * s).rounded(.down))
        let grey = source.transformed(by: CGAffineTransform(scaleX: s, y: s))
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.0])
            .clampedToExtent()
        let soft = grey.applyingGaussianBlur(sigma: 0.8)
        let negative = soft.applyingFilter("CIColorInvert").applyingGaussianBlur(sigma: reach)
        let strokes = negative
            .applyingFilter("CIColorDodgeBlendMode", parameters: [kCIInputBackgroundImageKey: soft])
            .applyingFilter("CIColorMatrix", parameters: greyMatrix(times: -gain, plus: gain))
            .applyingFilter("CIColorClamp")
            .applyingFilter("CIGammaAdjust", parameters: ["inputPower": gamma])

        // The race, on the strokes' maximum over each coarse cell so that a thin line still counts.
        let w = Int(bounds.width) / coarse, h = Int(bounds.height) / coarse
        guard w >= 2, h >= 2 else { return nil }
        let pooled = strokes
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: Double(coarse) / 2])
            .transformed(by: CGAffineTransform(scaleX: CGFloat(w) / bounds.width, y: CGFloat(h) / bounds.height))
        var cells = [UInt8](repeating: 0, count: w * h)
        cells.withUnsafeMutableBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            context.render(pooled, toBitmap: base, rowBytes: w, bounds: CGRect(x: 0, y: 0, width: w, height: h), format: .L8, colorSpace: nil)
        }
        let arrived = arrivals(cells.map { Float($0) / 255 }, width: w, height: h)
        let arrival = CIImage(
            bitmapData: Data(arrived.map { UInt8((min(max($0, 0), 1) * 255).rounded()) }), bytesPerRow: w,
            size: CGSize(width: w, height: h), format: .L8, colorSpace: nil)
            .clampedToExtent()
            .transformed(by: CGAffineTransform(scaleX: bounds.width / CGFloat(w), y: bounds.height / CGFloat(h)))

        let paper = CIImage(color: color(sheet.paper))
        let base = grey.applyingFilter(
            "CIDissolveTransition", parameters: [kCIInputTargetImageKey: paper, kCIInputTimeKey: paperShare])
        guard let baseImage = context.createCGImage(base, from: bounds, format: .RGBA8, colorSpace: space) else { return nil }
        let ink = CIImage(color: color(sheet.ink))
        var images: [CGImage] = []
        for stage in 0..<stages {
            // Every stroke arrived by the stage's end, and those of the next share ramping in:
            // the pencil's strength times clamp(stage + 2 - stages × arrival).
            let n = CGFloat(stages)
            let ramp = arrival
                .applyingFilter("CIColorMatrix", parameters: greyMatrix(times: -n * pencil, plus: CGFloat(stage + 2) * pencil))
                .applyingFilter("CIColorClamp", parameters: [
                    "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
                    "inputMaxComponents": CIVector(x: pencil, y: pencil, z: pencil, w: 1),
                ])
            let mask = ramp.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: strokes])
            let drawn = ink.applyingFilter(
                "CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: mask])
            guard let image = context.createCGImage(drawn, from: bounds, format: .RGBA8, colorSpace: space) else { return nil }
            images.append(image)
        }
        return Drawing(base: baseImage, stages: images)
    }

    /// The color matrix that maps each of a grey's channels v to `times` × v + `plus`.
    private static func greyMatrix(times: CGFloat, plus: CGFloat) -> [String: Any] {
        [
            "inputRVector": CIVector(x: times, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: times, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: times, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: plus, y: plus, z: plus, w: 0),
        ]
    }

    private static func color(_ rgb: SIMD3<Float>) -> CIColor {
        CIColor(red: CGFloat(rgb.x), green: CGFloat(rgb.y), blue: CGFloat(rgb.z))
    }

    /// Where the race begins on a grid `width` × `height` of strokes (0…1, rows first): the
    /// strongest stroke near the front's centre (`FormingShow.Front.centre`).
    static func seed(_ strokes: [Float], width w: Int, height h: Int) -> Int {
        let cx = Double(w) * Double(FormingShow.Front.centre.x), cy = Double(h) * Double(FormingShow.Front.centre.y)
        let far = Double(max(w, h))
        var best = 0, bestScore = -Double.infinity
        for y in 0..<h {
            for x in 0..<w {
                let dx = Double(x) - cx, dy = Double(y) - cy
                let score = Double(strokes[y * w + x]) - 0.6 * (dx * dx + dy * dy).squareRoot() / far
                if score > bestScore { best = y * w + x; bestScore = score }
            }
        }
        return best
    }

    /// When the race reaches each cell of a grid `width` × `height` of strokes (0…1, rows
    /// first), from 0 at `seed` to 1 by all but the last hundredth: the shortest way there over
    /// the grid's eight neighbours, each step costing more the fainter the strokes it crosses.
    static func arrivals(_ strokes: [Float], width w: Int, height h: Int) -> [Float] {
        let n = w * h
        guard n > 0, strokes.count == n else { return [] }
        let cost = strokes.map { 1 / (0.06 + $0) }
        var distance = [Float](repeating: .infinity, count: n)
        var heap = CellHeap()
        let start = seed(strokes, width: w, height: h)
        distance[start] = 0
        heap.push(0, start)
        let steps: [(dx: Int, dy: Int, length: Float)] = [
            (-1, 0, 1), (1, 0, 1), (0, -1, 1), (0, 1, 1), (-1, -1, 1.414), (1, -1, 1.414), (-1, 1, 1.414), (1, 1, 1.414),
        ]
        while let item = heap.pop() {
            let d = item.key, cell = item.cell
            guard d <= distance[cell] else { continue }
            let x = cell % w, y = cell / w
            for step in steps {
                let nx = x + step.dx, ny = y + step.dy
                guard nx >= 0, nx < w, ny >= 0, ny < h else { continue }
                let next = ny * w + nx
                let reached = d + step.length * 0.5 * (cost[cell] + cost[next])
                if reached < distance[next] {
                    distance[next] = reached
                    heap.push(reached, next)
                }
            }
        }
        let sorted = distance.sorted()
        let far = max(sorted[Int(Double(n - 1) * 0.99)], 1e-6)
        return distance.map { min($0 / far, 1) }
    }

    /// The race's progress drawn at `progress` (0…1) of `stages` images: every stroke of stage
    /// `whole` (nil: none yet) and stage `fading` coming in at its opacity.
    static func shown(at progress: Double, stages: Int) -> (whole: Int?, fading: (stage: Int, opacity: Double)?) {
        guard stages > 0 else { return (nil, nil) }
        let k = min(max(progress, 0), 1) * Double(stages)
        let done = min(Int(k), stages)
        let fading: (stage: Int, opacity: Double)? = done < stages && k > Double(done) ? (done, k - Double(done)) : nil
        return (done >= 1 ? done - 1 : nil, fading)
    }

    /// How far the photo has drained to the grey under the pencil at `progress`.
    static func drained(at progress: Double) -> Double {
        min(max(progress / drains, 0), 1)
    }

    /// A binary min-heap of grid cells by distance.
    private nonisolated struct CellHeap {
        private var items: [(key: Float, cell: Int)] = []

        mutating func push(_ key: Float, _ cell: Int) {
            items.append((key, cell))
            var i = items.count - 1
            while i > 0 {
                let parent = (i - 1) / 2
                guard items[i].key < items[parent].key else { break }
                items.swapAt(i, parent)
                i = parent
            }
        }

        mutating func pop() -> (key: Float, cell: Int)? {
            guard let first = items.first else { return nil }
            let last = items.removeLast()
            if !items.isEmpty {
                items[0] = last
                var i = 0
                while true {
                    let l = 2 * i + 1, r = l + 1
                    var smallest = i
                    if l < items.count, items[l].key < items[smallest].key { smallest = l }
                    if r < items.count, items[r].key < items[smallest].key { smallest = r }
                    if smallest == i { break }
                    items.swapAt(i, smallest)
                    i = smallest
                }
            }
            return first
        }
    }
}

/// The show's moments on the preview, as `TemplatePreviewView` keeps them.
struct FormingMoments {
    /// The photo's graphite drawing, and when it began to race over the photo.
    var graphite: GraphiteSketch.Drawing?
    var graphiteBegan: Date?
    /// When the template's lines begin to burn in (it can be a moment ahead: `graphiteAtLeast`),
    /// and when they have.
    var fuseLit: Date?
    var fuseDone: Date?
    /// A demo's holds: how far the graphite and the fuse are (nil: as the clock says).
    var heldGraphite: Double?
    var heldFuse: Double?

    func graphiteProgress(at now: Date) -> Double {
        if let heldGraphite { return heldGraphite }
        guard graphite != nil, let graphiteBegan else { return 0 }
        return FormingShow.graphiteProgress(since: now.timeIntervalSince(graphiteBegan))
    }

    func fuseProgress(at now: Date) -> Double {
        if let heldFuse { return heldFuse }
        guard let fuseLit, let fuseDone else { return 0 }
        return FormingShow.fuseProgress(since: now.timeIntervalSince(fuseLit), length: fuseDone.timeIntervalSince(fuseLit))
    }

    /// Until when anything moves: nil once nothing will.
    var movesUntil: Date? {
        var until: Date?
        if heldGraphite == nil, graphite != nil, let graphiteBegan {
            until = graphiteBegan.addingTimeInterval(FormingShow.graphiteSweep)
        }
        if heldFuse == nil, let fuseDone {
            until = until.map { max($0, fuseDone) } ?? fuseDone
        }
        return until
    }
}

/// What the front has reached at `progress`: a mask over a frame in which the picture is at
/// `picture`, the front's image (`FrontMasks`) scaled about its origin.
struct FormingFrontMask: View {
    let picture: CGRect
    let progress: Double

    var body: some View {
        if progress >= 1 {
            Rectangle()
        } else if progress <= 0 {
            Color.clear
        } else if let image = FrontMasks.image {
            let o = FormingShow.Front.origin(in: picture)
            let side = CGFloat(FormingShow.Front.side(in: picture))
            Image(decorative: image, scale: 1)
                .resizable()
                .frame(width: side, height: side)
                .scaleEffect(progress)
                .position(x: o.x, y: o.y)
        } else {
            Rectangle().opacity(progress)
        }
    }
}

/// The show's graphite and fuse over the preview's photo (`FormingShow`): the graphite drawing as
/// far as its strokes have raced, then the page's paper and its lines as far as they have burned, with the
/// burning front in gold. `picture` is where the photo shows in a frame of `size`; `scale` is
/// the lines' size beside the canvas's (`CompareView.canvasScale`).
struct FormingShowLayers: View {
    let moments: FormingMoments
    let lines: LineArtDrawing?
    let picture: CGRect
    let size: CGSize
    let scale: CGFloat
    /// Nothing more will move: drawn as it ends, and the timeline paused.
    @State private var stillAt: Date?
    /// The burning front's gold lines (`FormingShow.glow`), for these lines.
    @State private var gold: (id: UUID, image: CGImage)?
    @AppStorage(SettingsKey.lineWeight) private var lineWeight = LineWeight.default

    private var isStill: Bool {
        guard let until = moments.movesUntil else { return true }
        return stillAt == until
    }

    var body: some View {
        TimelineView(.animation(paused: isStill)) { context in
            // Paused, every beat that began has ended, wherever the last frame left it.
            let now = isStill ? Date.distantFuture : context.date
            layers(graphite: moments.graphiteProgress(at: now), fuse: lines == nil ? 0 : moments.fuseProgress(at: now))
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .task(id: moments.movesUntil) {
            guard let until = moments.movesUntil else { return }
            let wait = until.timeIntervalSinceNow
            if wait > 0 {
                guard (try? await Task.sleep(for: .seconds(wait))) != nil else { return }
            }
            stillAt = until
        }
        .task(id: lines?.id) {
            guard let lines, gold?.id != lines.id else { return }
            let width = lines.lineWidth(scale: scale, weight: lineWeight)
            guard let image = await FormingShow.glow(lines, size: picture.size, lineWidth: width) else { return }
            gold = (lines.id, image)
        }
    }

    @ViewBuilder
    private func layers(graphite: Double, fuse: Double) -> some View {
        ZStack(alignment: .topLeading) {
            // Under paper wherever the fuse has burned: drawn only while some of it shows.
            if let drawing = moments.graphite, graphite > 0, fuse < 1 {
                let shown = GraphiteSketch.shown(at: graphite, stages: drawing.stages.count)
                ZStack(alignment: .topLeading) {
                    placed(drawing.base).opacity(GraphiteSketch.drained(at: graphite))
                    if let whole = shown.whole { placed(drawing.stages[whole]) }
                    if let fading = shown.fading { placed(drawing.stages[fading.stage]).opacity(fading.opacity) }
                }
                .transition(.opacity)
            }
            if let lines {
                // In from the moment the template is made, behind a front not yet lit: the lines
                // are stroked once, before they burn.
                FormingPaper()
                    .mask(alignment: .topLeading) { FormingFrontMask(picture: picture, progress: fuse) }
                FormingLines(drawing: lines, picture: picture, scale: scale)
                    .equatable()
                    .frame(width: size.width, height: size.height)
                    .mask(alignment: .topLeading) { FormingFrontMask(picture: picture, progress: fuse) }
                if let gold, gold.id == lines.id, fuse > 0, fuse < 1 {
                    // The burning front: the lines in gold along a narrow band behind it.
                    placed(gold.image)
                        .mask(alignment: .topLeading) {
                            ZStack {
                                FormingFrontMask(picture: picture, progress: fuse)
                                FormingFrontMask(picture: picture, progress: fuse - 0.07)
                                    .blendMode(.destinationOut)
                            }
                            .compositingGroup()
                        }
                }
            }
        }
    }

    /// An image filling the picture, in the frame.
    private func placed(_ image: CGImage) -> some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .frame(width: picture.width, height: picture.height)
            .clipped()
            .offset(x: picture.minX, y: picture.minY)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

/// The page coming into the departing picture as its numbers come out like stars
/// (`FormingShow`): the page as the canvas draws it, behind the show's front, `since` it came,
/// with a twinkle at each number as the front reaches it. The paper and lines under it are the
/// page's already, so only the numbers change. `size` is the page's, in points.
struct FormingPageStars: View {
    let page: CGImage
    let stars: FormingShow.Stars
    let since: Date
    let size: CGSize
    /// A demo's hold: how far the numbers have come out.
    var held: Double?
    @State private var isOver = false
    @State private var arrivals: [(point: CGPoint, radius: CGFloat, arrival: Double)] = []

    var body: some View {
        let shownArrivals = arrivals, gold = Color(.sRGB, red: FormingShow.goldRGB.x, green: FormingShow.goldRGB.y, blue: FormingShow.goldRGB.z)
        TimelineView(.animation(paused: isOver || held != nil)) { context in
            let progress = held ?? frontProgress(at: isOver ? .distantFuture : context.date)
            ZStack(alignment: .topLeading) {
                Image(decorative: page, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size.width, height: size.height)
                    .mask(alignment: .topLeading) {
                        FormingFrontMask(picture: CGRect(origin: .zero, size: size), progress: progress)
                    }
                if progress < 1 + FormingShow.Stars.life {
                    Canvas { context, _ in
                        FormingShow.Stars.draw(shownArrivals, in: &context, progress: progress, color: gold)
                    }
                    .frame(width: size.width, height: size.height)
                }
            }
        }
        .allowsHitTesting(false)
        .task(id: size) { arrivals = stars.arrivals(on: size) }
        .task {
            guard held == nil else { return }
            let wait = since.addingTimeInterval(FormingShow.stars).timeIntervalSinceNow
            if wait > 0 {
                guard (try? await Task.sleep(for: .seconds(wait))) != nil else { return }
            }
            isOver = true
        }
    }

    /// The front's progress over the page at `now`, past 1 by a twinkle's `life` so the last
    /// numbers reached twinkle out within the beat.
    private func frontProgress(at now: Date) -> Double {
        FormingShow.starsProgress(since: now.timeIntervalSince(since)) * (1 + FormingShow.Stars.life)
    }
}
