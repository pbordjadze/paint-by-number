import CoreGraphics
import Foundation
import os
import PaintCore
import SwiftUI

/// The short Making-of as everyone's wait, "graphite and fuse" (painting-company row 361; every
/// build from 1.5). It grows out of
/// the picture forming (`FormingPlan`) and keeps its rule: it adds nothing to the making, and it
/// ends on exactly the page the painting will show.
///
/// 1. **Graphite** (the wait): once the making has the painting's line drawing (`LineArtInput`,
///    long before the template: `CreateModel.linesFound`), thin pencil strokes travel along it from
///    the middle (`GraphiteSketch`), a warm point at each stroke's tip, the photo's color draining
///    only close around the strokes drawn; until then (the models running, before Vision's
///    finds) the photo stands as it is. Once begun, the race nears its end without reaching it
///    for as long as the template is still being made (`graphiteProgress`), so it never stands
///    still, and finishes under the fuse: a faster device
///    sees less of it. No status shows over it until the making has taken `patience`.
/// 2. **Fuse**: once the template is made, its own lines burn in over the same drawing like a fuse,
///    a soft band of gold at the burning front, the paper drying to the page's behind it. It is
///    done `fuse` after the template is made, and the drawing rests `rest` before it lifts: a
///    template made almost at once lets the graphite show `graphiteAtLeast` first, and its fuse
///    burns that much faster.
/// 3. **Stars**: as the picture glides to the painting's place (the hand-off's own `settle`, no
///    time of its own), the page's numbers come out behind the same front, a few of them with a
///    soft twinkle (`Stars`), and the picture is the page the canvas draws.
///
/// A tap skips at any moment (`skip`): once the template is made, to the painting; before, to the
/// plain picture forming, its lines drawn in as ever once made. Reduce Motion and The Making-of
/// switched on bring none of it, as they bring no lines (`FormingPlan.hasLines`). VoiceOver hears
/// the forming's one status, as before.
///
/// Each frame only moves what was made once: the graphite is one image a shader reads at the
/// progress (`GraphiteSketch.Drawing`), the front an image (`FrontMasks`) scaled about its centre, the gold
/// lines an image with their glow in it (`FormingShow.glow`), the ink lines the forming's own,
/// stroked once.
nonisolated enum FormingShow {
    static let isOn = true

    /// Whether the picture forming plays the show: it forms with lines, and no tap has sent it to
    /// the plain forming.
    static func plays(forms: Bool, reduceMotion: Bool, playsMakingOf: Bool, skipped: Skip?) -> Bool {
        isOn && forms && FormingPlan.hasLines(reduceMotion: reduceMotion, playsShow: playsMakingOf) && skipped != .toPlainLines
    }

    // MARK: Timing

    /// How soon the graphite's race is half run (`graphiteProgress`): half by the making of a
    /// template on an iPad Air (1.1 s), slowed with the hand-off (`-handoffSlowdown`). A pencil
    /// drawing, not a race: twice 1.5's pace darted across the photo (Paul, November 24: "a
    /// little abrasive").
    static var graphitePace: Double { 2.2 * StartHandoffPlan.glide }
    /// How near its end the race comes while the template is still being made.
    static let graphiteNears = 0.97
    /// The least the graphite shows before the fuse is lit: a template made at once would show
    /// it for a flicker, which reads as a glitch rather than a drawing. Taken from the fuse,
    /// never added to the wait.
    static var graphiteAtLeast: Double { 0.3 * StartHandoffPlan.glide }
    /// How long the lines take to burn in once the template is made: half as long again as the
    /// plain forming's drawing in, so the gold travels rather than flashes.
    static var fuse: Double { 2.2 * StartHandoffPlan.glide }
    /// The finished drawing held still a moment before it lifts away: one move, then still,
    /// then the next, rather than one move running into the next.
    static var rest: Double { 0.6 * StartHandoffPlan.glide }
    /// The most the show keeps the hand-off waiting once the template is made: the fuse and the
    /// rest after it (0.7 s more than 1.5's show, which ended the moment the lines were in).
    static var longestTail: Double { fuse + rest }
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

    /// When the lines have burned in: `fuse` after the making, whenever the fuse was lit. The
    /// hand-off lifts `rest` later.
    static func done(madeAt made: Double) -> Double {
        made + fuse
    }

    /// How far the graphite has raced, `elapsed` seconds after it began, while the template is
    /// being made: racing out, then ever slower toward `graphiteNears`, never still and never
    /// done (a making of 4 s leaves it at 0.76, of 10 s at 0.87).
    static func graphiteProgress(since elapsed: Double) -> Double {
        let t = max(elapsed, 0)
        return graphiteNears * t / (t + graphitePace)
    }

    /// How far a fuse burning for `length` seconds has burned `elapsed` seconds after it was
    /// lit: catching softly, steady, and settling softly (smootherstep: no jolt at either end).
    static func fuseProgress(since elapsed: Double, length: Double) -> Double {
        guard length > 0 else { return elapsed >= 0 ? 1 : 0 }
        let x = min(max(elapsed / length, 0), 1)
        return x * x * x * (x * (6 * x - 15) + 10)
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
    /// middle, near where the graphite began (`GraphiteSketch.seed`), its outline wavering (`shape`),
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
    static func glow(_ drawing: LineArtDrawing, size: CGSize, lineWidth: CGFloat, weight: CGFloat = 1.3) async -> CGImage? {
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
        context.setShadow(offset: .zero, blur: 10 * scale, color: gold)
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

        /// Few enough to read as stars coming out, not a burst of glitter.
        static let limit = 60
        /// How long each twinkles, as a share of the beat.
        static let life = 0.45
        /// A twinkle's brightest: a glint, never a flash.
        static let brightest = 0.75

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
                context.opacity = glow * brightest
                context.fill(sparkle(at: star.point, radius: star.radius * CGFloat(0.5 + 0.3 * glow)), with: .color(color))
            }
            context.opacity = 1
        }
    }
}

/// The graphite's shader (`FormingGraphite.metal`, `GraphiteSketch.shade`), compiled once for the
/// app's life as the first show begins (`prepare`), so its first frame doesn't wait for it.
enum GraphiteShader {
    private static var compiled = false

    static func shader(_ sheet: FormingPlan.Sheet, progress: Double) -> Shader {
        let graphite = sheet.paper + (sheet.ink - sheet.paper) * GraphiteSketch.lead
        let point = sheet.ink * (1 - GraphiteSketch.pointWarmth) + GraphiteSketch.warm * GraphiteSketch.pointWarmth
        return ShaderLibrary.formingGraphite(
            .float(progress), .color(color(graphite)), .color(color(point)), .color(color(sheet.paper)),
            .float(GraphiteSketch.pencil), .float(GraphiteSketch.edge), .float(GraphiteSketch.fresh), .float(GraphiteSketch.wash),
            .float(GraphiteSketch.inkFrom), .float(GraphiteSketch.inkTo), .float(GraphiteSketch.pointFrom), .float(GraphiteSketch.pointTo),
            .float(GraphiteSketch.grain))
    }

    static func prepare() async {
        guard !compiled else { return }
        compiled = true
        let sheet = FormingPlan.Sheet(paper: SIMD3(1, 1, 1), ink: SIMD3(0, 0, 0))
        do {
            try await shader(sheet, progress: 0).compile(as: .colorEffect)
        } catch {
            Log.create.error("Graphite shader didn't compile: \(String(describing: error), privacy: .public)")
        }
    }

    private static func color(_ rgb: SIMD3<Float>) -> Color {
        Color(.sRGB, red: Double(rgb.x), green: Double(rgb.y), blue: Double(rgb.z))
    }
}

/// The front's image (`FormingShow.Front.image`), made once for the app's life, off the main
/// actor, as the first show begins; until then a front fades instead of spreading.
enum FrontMasks {
    private(set) static var image: CGImage?
    /// The making under way, which a second caller waits for too.
    private static var preparing: Task<Void, Never>?

    static func prepare() async {
        guard image == nil else { return }
        if let preparing { return await preparing.value }
        let making = Task { image = await FormingShow.Front.image(pixels: 768) }
        preparing = making
        await making.value
        preparing = nil
    }
}

/// The graphite drawing, the show's wait (`FormingShow`): the painting's own line drawing, the
/// one its lines are traced from (`LineArtInput`, which the making has long before the template),
/// laid down in thin pencil strokes travelling along it from a seed near the middle, the freshest
/// stretch of each stroke darker and warmer (the pencil's point), and the photo's color draining
/// only close around the strokes drawn. No filter of the photo: the fuse then burns the
/// template's lines over the same drawing.
///
/// Made once per photo, off the main actor, as one image at the map's size (`Drawing.map`): its
/// red is when each pixel is reached (0…1), its green the stroke there, its blue how close a
/// stroke is. A frame passes the progress to a shader (`FormingGraphite.metal`'s
/// `formingGraphite`), which draws the pixel as `shade` says, so nothing is made per frame.
/// `tools/graphite_sim.py` makes and lays out the same off the device from the maps in
/// `tools/baseline/lines/`.
nonisolated enum GraphiteSketch {
    /// The drawing's strokes: the drawing map (where it wins over the contours in `edges`)
    /// between `drawingFrom` and `drawingTo`, and the contours' cores between `contourFrom` and
    /// `contourTo` at `contourShare`, so the outlines the drawing misses are drawn thin.
    static let drawingFrom: Float = 0.3
    static let drawingTo: Float = 0.7
    static let contourFrom: Float = 0.62
    static let contourTo: Float = 0.92
    static let contourShare: Float = 0.8
    /// The pencil's pressure wavers by this much along a stroke.
    static let pressure: Float = 0.2
    /// The race is worked out on a grid this many times coarser than the map.
    static let coarse = 3
    /// How far around a stroke the color drains (map pixels), and how strongly.
    static let haloRadius = 2
    static let haloGain: Float = 2
    /// A piece of stroke (above `strokeFloor`, its pixels touching) smaller than this many map
    /// pixels is the photo's texture rather than its drawing, and is left out (`withoutSpecks`):
    /// drawn, it read as a filter over a busy area.
    static let shortest = 24
    static let strokeFloor: Float = 0.1

    /// The shading's constants, the shader's too: the strokes' strongest, how sharply a stroke
    /// comes in, how long a stretch behind the point is fresh, and how much of the photo's color
    /// goes near a stroke.
    static let pencil = 0.8
    /// Graphite, not ink: the line is the sheet's ink `lead` of the way from its paper (a mid
    /// grey on light paper), and the paper's grain takes up to `grain` of it, pixel by pixel
    /// (the shader alone: `shade` is the line before the grain).
    static let lead: Float = 0.85
    static let grain = 0.3
    static let edge = 0.012
    static let fresh = 0.06
    static let wash = 0.25
    /// The ink takes a stroke's crisp ridge (the map's stroke between `inkFrom` and `inkTo`, the
    /// map being smaller than the screen and its strokes soft there), the point a little more
    /// (`pointFrom` to `pointTo`), so it shows as a warm dot at the front.
    static let inkFrom = 0.35
    static let inkTo = 0.6
    static let pointFrom = 0.12
    static let pointTo = 0.4
    /// The point's warmth, `pointWarmth` of it over the ink, so the moving point shows.
    static let warm = SIMD3<Float>(0.95, 0.60, 0.25)
    static let pointWarmth: Float = 0.8

    nonisolated struct Drawing: Sendable {
        /// Red: arrival; green: stroke; blue: halo (sRGB-tagged, read as values).
        let map: CGImage
        /// The paper it is drawn on.
        let sheet: FormingPlan.Sheet
    }

    @concurrent
    static func draw(_ lines: LineArtInput, sheet: FormingPlan.Sheet) async -> Drawing? {
        let w = lines.edges.width, h = lines.edges.height
        guard w >= 2 * coarse, h >= 2 * coarse, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let stroke = strokes(lines)
        guard !Task.isCancelled else { return nil }
        let near = halo(stroke, width: w, height: h)
        guard !Task.isCancelled else { return nil }
        let arrival = arrivals(of: stroke, width: w, height: h)
        guard arrival.count == w * h, !Task.isCancelled else { return nil }
        var bytes = [UInt8](repeating: 255, count: w * h * 4)
        for i in 0..<(w * h) {
            bytes[4 * i] = byte(arrival[i])
            bytes[4 * i + 1] = byte(stroke[i])
            bytes[4 * i + 2] = byte(near[i])
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let map = CGImage(
                width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: space,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider,
                decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        return Drawing(map: map, sheet: sheet)
    }

    private static func byte(_ value: Float) -> UInt8 {
        UInt8((min(max(value, 0), 1) * 255).rounded())
    }

    /// The strokes (0…1) at the map's size, rows first.
    static func strokes(_ lines: LineArtInput) -> [Float] {
        let edges = lines.edges, w = edges.width, h = edges.height
        let contours = lines.contours.map { $0.resampled(width: w, height: h) }
        var out = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                let e = edges.values[i]
                var drawn = Float(e) / 255, outline: Float = 0
                if let contours {
                    let c = contours.values[i]
                    let scaled = UInt8(min(max((Float(c) * EdgeMap.contourWeight + 0.5).rounded(.down), 0), 255))
                    // Where the contours won, `edges` is theirs: the drawing had less there.
                    if e <= scaled { drawn = 0 }
                    outline = ramp(Float(c) / 255, contourFrom, contourTo) * contourShare
                }
                let s = max(ramp(drawn, drawingFrom, drawingTo), outline)
                out[i] = s * (1 - pressure + pressure * wavering(x, y))
            }
        }
        return withoutSpecks(out, width: w, height: h)
    }

    /// The strokes with every piece smaller than `shortest` pixels taken out (8-connected, above
    /// `strokeFloor`).
    static func withoutSpecks(_ stroke: [Float], width w: Int, height h: Int) -> [Float] {
        var out = stroke
        var seen = [Bool](repeating: false, count: w * h)
        var stack: [Int] = [], piece: [Int] = []
        for start in 0..<(w * h) where !seen[start] && stroke[start] > strokeFloor {
            seen[start] = true
            stack = [start]
            piece.removeAll(keepingCapacity: true)
            while let i = stack.popLast() {
                piece.append(i)
                let x = i % w, y = i / w
                for ny in max(y - 1, 0)...min(y + 1, h - 1) {
                    for nx in max(x - 1, 0)...min(x + 1, w - 1) {
                        let n = ny * w + nx
                        if !seen[n] && stroke[n] > strokeFloor {
                            seen[n] = true
                            stack.append(n)
                        }
                    }
                }
            }
            if piece.count < shortest {
                for i in piece { out[i] = 0 }
            }
        }
        return out
    }

    private static func ramp(_ v: Float, _ from: Float, _ to: Float) -> Float {
        let t = min(max((v - from) / (to - from), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// A slow, smooth wavering in 0…1 (the pencil's pressure), the same for the same pixel.
    static func wavering(_ x: Int, _ y: Int) -> Float {
        let u = Float(x) * 0.043, v = Float(y) * 0.037
        return 0.5 + 0.25 * sin(u + 1.7 * sin(v * 0.8)) + 0.25 * sin(v * 1.3 - 0.9 * sin(u * 0.7))
    }

    /// How close a stroke is (0…1): the strokes box-blurred twice over `haloRadius`, raised.
    static func halo(_ stroke: [Float], width w: Int, height h: Int) -> [Float] {
        var a = stroke
        for _ in 0..<2 {
            a = boxBlur(a, width: w, height: h, radius: haloRadius)
        }
        return a.map { min($0 * haloGain, 1) }
    }

    private static func boxBlur(_ values: [Float], width w: Int, height h: Int, radius r: Int) -> [Float] {
        var horizontal = [Float](repeating: 0, count: w * h)
        let span = Float(2 * r + 1)
        for y in 0..<h {
            var sum: Float = 0
            let row = y * w
            for k in -r...r { sum += values[row + min(max(k, 0), w - 1)] }
            for x in 0..<w {
                horizontal[row + x] = sum / span
                sum += values[row + min(x + r + 1, w - 1)] - values[row + max(x - r, 0)]
            }
        }
        var out = [Float](repeating: 0, count: w * h)
        for x in 0..<w {
            var sum: Float = 0
            for k in -r...r { sum += horizontal[min(max(k, 0), h - 1) * w + x] }
            for y in 0..<h {
                out[y * w + x] = sum / span
                sum += horizontal[min(y + r + 1, h - 1) * w + x] - horizontal[max(y - r, 0) * w + x]
            }
        }
        return out
    }

    /// When the race reaches each pixel of strokes `width` × `height` (rows first): its coarse
    /// cell's arrival (`arrivals`, on each cell's strongest stroke), bilinear between cells.
    static func arrivals(of stroke: [Float], width w: Int, height h: Int) -> [Float] {
        let cw = w / coarse, ch = h / coarse
        guard cw >= 2, ch >= 2 else { return [] }
        var cells = [Float](repeating: 0, count: cw * ch)
        for y in 0..<(ch * coarse) {
            for x in 0..<(cw * coarse) {
                let c = (y / coarse) * cw + x / coarse
                cells[c] = max(cells[c], stroke[y * w + x])
            }
        }
        let coarseArrival = arrivals(cells, width: cw, height: ch)
        var out = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            let fy = min(max((Float(y) + 0.5) / Float(coarse) - 0.5, 0), Float(ch - 1))
            let y0 = min(Int(fy), ch - 2), ty = fy - Float(y0)
            for x in 0..<w {
                let fx = min(max((Float(x) + 0.5) / Float(coarse) - 0.5, 0), Float(cw - 1))
                let x0 = min(Int(fx), cw - 2), tx = fx - Float(x0)
                let a = coarseArrival[y0 * cw + x0], b = coarseArrival[y0 * cw + x0 + 1]
                let c = coarseArrival[(y0 + 1) * cw + x0], d = coarseArrival[(y0 + 1) * cw + x0 + 1]
                out[y * w + x] = (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty
            }
        }
        return out
    }

    /// Where the race begins on a grid `width` × `height` of strokes (0…1, rows first): the
    /// strongest stroke near the front's centre (`FormingShow.Front.centre`).
    static func seed(_ lines: [Float], width w: Int, height h: Int) -> Int {
        let cx = Double(w) * Double(FormingShow.Front.centre.x), cy = Double(h) * Double(FormingShow.Front.centre.y)
        let far = Double(max(w, h))
        var best = 0, bestScore = -Double.infinity
        for y in 0..<h {
            for x in 0..<w {
                let dx = Double(x) - cx, dy = Double(y) - cy
                let score = Double(lines[y * w + x]) - 0.6 * (dx * dx + dy * dy).squareRoot() / far
                if score > bestScore { best = y * w + x; bestScore = score }
            }
        }
        return best
    }

    /// When the race reaches each cell of a grid `width` × `height` of strokes (0…1, rows
    /// first), from 0 at `seed` to 1 at the last: the cells in order of their shortest way there
    /// over the grid's eight neighbours (a step along a stroke cheap, across bare paper dear), each
    /// arriving at the share of the ink, and of a little of the paper, reached by then, so the
    /// pencil draws at an even pace.
    static func arrivals(_ lines: [Float], width w: Int, height h: Int) -> [Float] {
        let n = w * h
        guard n > 0, lines.count == n else { return [] }
        let cost = lines.map { 1 / (0.08 + $0) }
        var distance = [Float](repeating: .infinity, count: n)
        var heap = CellHeap()
        let start = seed(lines, width: w, height: h)
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
        let order = distance.indices.sorted { (distance[$0], $0) < (distance[$1], $1) }
        let total = lines.reduce(Float(0)) { $0 + $1 + 0.02 }
        var arrival = [Float](repeating: 0, count: n)
        var reached: Float = 0
        for cell in order {
            reached += lines[cell] + 0.02
            arrival[cell] = min(reached / total, 1)
        }
        arrival[start] = 0
        return arrival
    }

    /// What a pixel shows at `progress` (the shader's arithmetic, kept here for the tests and
    /// the simulation): how much of the ink its stroke has, how much of it is the warm point,
    /// and how much of the photo's color has drained to the paper.
    nonisolated struct Shade: Equatable {
        var ink: Double
        var point: Double
        var wash: Double
    }

    static func shade(arrival: Double, stroke: Double, halo: Double, progress: Double) -> Shade {
        let reached = min(max((progress - arrival) / edge, 0), 1)
        let behind = progress - arrival
        let point = behind >= 0 && behind < fresh ? 1 - behind / fresh : 0
        let pointShare = smooth(stroke, pointFrom, pointTo) * reached * point
        return Shade(
            ink: max(smooth(stroke, inkFrom, inkTo) * reached * (pencil + (1 - pencil) * point), pointShare),
            point: pointShare, wash: wash * halo * reached)
    }

    private static func smooth(_ v: Double, _ from: Double, _ to: Double) -> Double {
        let t = min(max((v - from) / (to - from), 0), 1)
        return t * t * (3 - 2 * t)
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

    /// How far the graphite has raced: by the clock until the fuse is lit, then the rest of the
    /// way as the fuse burns.
    func graphiteProgress(at now: Date) -> Double {
        if let heldGraphite { return heldGraphite }
        guard graphite != nil, let graphiteBegan else { return 0 }
        guard let fuseLit, now >= fuseLit else {
            return FormingShow.graphiteProgress(since: now.timeIntervalSince(graphiteBegan))
        }
        let raced = FormingShow.graphiteProgress(since: fuseLit.timeIntervalSince(graphiteBegan))
        return raced + (1 - raced) * fuseProgress(at: now)
    }

    func fuseProgress(at now: Date) -> Double {
        if let heldFuse { return heldFuse }
        guard let fuseLit, let fuseDone else { return 0 }
        return FormingShow.fuseProgress(since: now.timeIntervalSince(fuseLit), length: fuseDone.timeIntervalSince(fuseLit))
    }

    /// Until when anything moves: nil once nothing will, `distantFuture` while the graphite races
    /// on a template still being made.
    var movesUntil: Date? {
        var until: Date?
        if heldGraphite == nil, graphite != nil, graphiteBegan != nil {
            until = fuseDone ?? .distantFuture
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
    /// The burning front's gold lines (`FormingShow.glow`), for these lines at this size.
    @State private var gold: (key: GoldKey, image: CGImage)?

    private struct GoldKey: Equatable {
        var lines: UUID
        var size: CGSize
    }
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
            guard let until = moments.movesUntil, until < .distantFuture else { return }
            let wait = until.timeIntervalSinceNow
            if wait > 0 {
                guard (try? await Task.sleep(for: .seconds(wait))) != nil else { return }
            }
            stillAt = until
        }
        // Keyed on the size too: a first layout at no size makes nothing, and the next retries.
        .task(id: lines.map { GoldKey(lines: $0.id, size: picture.size) }) {
            guard let lines, gold?.key != GoldKey(lines: lines.id, size: picture.size) else { return }
            let key = GoldKey(lines: lines.id, size: picture.size)
            let width = lines.lineWidth(scale: scale, weight: lineWeight)
            guard let image = await FormingShow.glow(lines, size: key.size, lineWidth: width) else { return }
            gold = (key, image)
        }
    }

    @ViewBuilder
    private func layers(graphite: Double, fuse: Double) -> some View {
        ZStack(alignment: .topLeading) {
            // Under paper wherever the fuse has burned: drawn only while some of it shows.
            if let drawing = moments.graphite, graphite > 0, fuse < 1 {
                // A map of values, not a picture: no sharpening filter between its pixels.
                placed(drawing.map, interpolation: .medium)
                    .colorEffect(GraphiteShader.shader(drawing.sheet, progress: graphite))
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
                if let gold, gold.key.lines == lines.id, fuse > 0, fuse < 1 {
                    // The burning front: the lines in gold along a narrow band behind it.
                    placed(gold.image)
                        .opacity(0.8)
                        .mask(alignment: .topLeading) {
                            ZStack {
                                FormingFrontMask(picture: picture, progress: fuse)
                                FormingFrontMask(picture: picture, progress: fuse - 0.1)
                                    .blendMode(.destinationOut)
                            }
                            .compositingGroup()
                        }
                }
            }
        }
    }

    /// An image filling the picture, in the frame.
    private func placed(_ image: CGImage, interpolation: Image.Interpolation = .high) -> some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(interpolation)
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
