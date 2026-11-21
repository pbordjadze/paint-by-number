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
/// 1. **Graphite** (the wait): from the moment the photo shows, its color drains as a graphite
///    drawing of it spreads out from the middle (`GraphiteSketch`, revealed by `Front`), and holds
///    there for as long as the template is still being made: a faster device sees less of it.
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
/// Each frame only moves what was made once: the front is an image (`FrontMasks`) scaled about
/// its centre, the gold lines an image with their glow in it (`FormingShow.glow`), the ink lines
/// the forming's own, stroked once.
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

    /// How far the graphite has spread, `elapsed` seconds after it began: racing out, easing in.
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

    /// Where every beat arrives: a soft-edged blot growing from a little above the picture's
    /// middle, its outline wavering (`shape`), so it spreads rather than wipes. The same front
    /// in every beat, so the ink follows where the graphite went and the numbers where the ink
    /// did. It only grows (its shape is the same at every size), so one image of it, scaled
    /// about its centre, draws it at any progress (`FrontMasks`); at progress 1 even its soft
    /// edge has passed every corner.
    nonisolated enum Front {
        static let centre = CGPoint(x: 0.5, y: 0.45)
        /// How far the outline wavers, as a share of its reach.
        static let wobble = 0.22

        /// How wide the front's soft edge is, as a share of its reach: the graphite's soft, the
        /// ink's and the numbers' nearly sharp.
        nonisolated enum Edge: Sendable {
            case soft, sharp

            var share: Double {
                switch self {
                case .soft: 0.3
                case .sharp: 0.05
                }
            }
        }

        /// The outline's reach at `angle` (radians, y down), relative to its mean.
        static func shape(at angle: Double) -> Double {
            1 + wobble * (0.5 * sin(3 * angle + 0.7) + 0.3 * sin(5 * angle + 2.1) + 0.2 * sin(8 * angle + 4.4))
        }

        static func origin(in rect: CGRect) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * centre.x, y: rect.minY + rect.height * centre.y)
        }

        /// The mean reach at progress 1 (points): the inner end of its soft edge past the
        /// farthest corner wherever the outline wavers in.
        static func reach(in rect: CGRect, edge: Edge) -> Double {
            let o = origin(in: rect)
            let dx = Double(max(o.x - rect.minX, rect.maxX - o.x)), dy = Double(max(o.y - rect.minY, rect.maxY - o.y))
            return (dx * dx + dy * dy).squareRoot() / ((1 - wobble) * (1 - edge.share))
        }

        /// The side of the square the front's image fills at progress 1 (points).
        static func side(in rect: CGRect, edge: Edge) -> Double {
            2 * (1 + wobble) * reach(in: rect, edge: edge)
        }

        /// The progress (0…1) at which the middle of the front's soft edge reaches `point`.
        static func arrival(of point: CGPoint, in rect: CGRect, edge: Edge) -> Double {
            let o = origin(in: rect)
            let dx = Double(point.x - o.x), dy = Double(point.y - o.y)
            let full = reach(in: rect, edge: edge)
            guard full > 0 else { return 0 }
            let ratio = (dx * dx + dy * dy).squareRoot() / (full * shape(at: atan2(dy, dx)))
            return min(1, ratio / (1 - edge.share / 2))
        }

        /// How opaque the front is at a point `ratio` of the way to its outline: whole inside its
        /// soft edge, nothing past the outline.
        static func alpha(ratio: Double, edge: Edge) -> Double {
            let t = min(max((1 - ratio) / edge.share, 0), 1)
            return t * t * (3 - 2 * t)
        }

        /// The front at progress 1 as a square image `pixels` across, white with the front's
        /// opacity, its centre the front's origin. Made once, off the main actor.
        @concurrent
        static func image(edge: Edge, pixels: Int) async -> CGImage? {
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
                    let a = UInt8((alpha(ratio: (u * u + v * v).squareRoot() / table[k], edge: edge) * 255).rounded())
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
                return (point, min(max(CGFloat(label.z) * w * 1.4, 4), 14), Front.arrival(of: point, in: rect, edge: .sharp))
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

/// The front's images (`FormingShow.Front.image`), made once for the app's life, off the main
/// actor, as the first show begins; until then a front fades instead of spreading.
enum FrontMasks {
    private static var soft: CGImage?
    private static var sharp: CGImage?
    private static var preparing = false

    static func image(_ edge: FormingShow.Front.Edge) -> CGImage? {
        switch edge {
        case .soft: soft
        case .sharp: sharp
        }
    }

    static func prepare() async {
        guard !preparing, soft == nil || sharp == nil else { return }
        preparing = true
        async let soft = FormingShow.Front.image(edge: .soft, pixels: 256)
        async let sharp = FormingShow.Front.image(edge: .sharp, pixels: 768)
        let made = await (soft, sharp)
        Self.soft = made.0
        Self.sharp = made.1
        preparing = false
    }
}

/// The graphite drawing of a photo, the show's wait (`FormingShow`): the photo without its
/// color, mostly gone to the paper, with its edges drawn over it in the page's ink, like pencil.
/// One Core Image pass on a copy at most `longSide` across, off the main actor, once per photo:
/// on the GPU, beside the template's making rather than in its way.
nonisolated enum GraphiteSketch {
    static let longSide: CGFloat = 900
    /// How far the photo goes toward the paper under the pencil.
    static let paperShare = 0.72
    /// How much of the ink's strength the pencil has.
    static let pencil: Float = 0.8
    /// One context for every drawing (Core Image's contexts are thread-safe and costly to make).
    private static let context = CIContext(options: [.cacheIntermediates: false])

    @concurrent
    static func draw(_ photo: CGImage, sheet: FormingPlan.Sheet) async -> CGImage? {
        let source = CIImage(cgImage: photo)
        let extent = source.extent
        guard extent.width >= 16, extent.height >= 16 else { return nil }
        let s = min(1, longSide / max(extent.width, extent.height))
        let bounds = CGRect(x: 0, y: 0, width: (extent.width * s).rounded(.down), height: (extent.height * s).rounded(.down))
        let scaled = source.transformed(by: CGAffineTransform(scaleX: s, y: s))
        let mono = scaled.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.0, kCIInputContrastKey: 1.1])
        let edges = mono.clampedToExtent()
            .applyingGaussianBlur(sigma: 1.2)
            .applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 3.0])
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.0])
            .applyingFilter("CIColorClamp")
            .cropped(to: bounds)
        let paper = CIImage(color: color(sheet.paper)).cropped(to: bounds)
        let lead = sheet.ink * pencil + sheet.paper * (1 - pencil)
        let ink = CIImage(color: color(lead)).cropped(to: bounds)
        let washed = mono.cropped(to: bounds).applyingFilter(
            "CIDissolveTransition", parameters: [kCIInputTargetImageKey: paper, kCIInputTimeKey: paperShare])
        let drawing = ink.applyingFilter(
            "CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: washed, kCIInputMaskImageKey: edges])
        return context.createCGImage(drawing.cropped(to: bounds), from: bounds)
    }

    private static func color(_ rgb: SIMD3<Float>) -> CIColor {
        CIColor(red: CGFloat(rgb.x), green: CGFloat(rgb.y), blue: CGFloat(rgb.z))
    }
}

/// The show's moments on the preview, as `TemplatePreviewView` keeps them.
struct FormingMoments {
    /// The photo's graphite drawing, and when it began to spread over the photo.
    var graphite: CGImage?
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
    let edge: FormingShow.Front.Edge

    var body: some View {
        if progress >= 1 {
            Rectangle()
        } else if progress <= 0 {
            Color.clear
        } else if let image = FrontMasks.image(edge) {
            let o = FormingShow.Front.origin(in: picture)
            let side = CGFloat(FormingShow.Front.side(in: picture, edge: edge))
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
/// far as it has spread, then the page's paper and its lines as far as they have burned, with the
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
            if let image = moments.graphite, graphite > 0, fuse < 1 {
                placed(image)
                    .mask(alignment: .topLeading) { FormingFrontMask(picture: picture, progress: graphite, edge: .soft) }
                    .transition(.opacity)
            }
            if let lines {
                // In from the moment the template is made, behind a front not yet lit: the lines
                // are stroked once, before they burn.
                FormingPaper()
                    .mask(alignment: .topLeading) { FormingFrontMask(picture: picture, progress: fuse, edge: .sharp) }
                FormingLines(drawing: lines, picture: picture, scale: scale)
                    .equatable()
                    .frame(width: size.width, height: size.height)
                    .mask(alignment: .topLeading) { FormingFrontMask(picture: picture, progress: fuse, edge: .sharp) }
                if let gold, gold.id == lines.id, fuse > 0, fuse < 1 {
                    // The burning front: the lines in gold along a narrow band behind it.
                    placed(gold.image)
                        .mask(alignment: .topLeading) {
                            ZStack {
                                FormingFrontMask(picture: picture, progress: fuse, edge: .sharp)
                                FormingFrontMask(picture: picture, progress: fuse - 0.07, edge: .sharp)
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
                        FormingFrontMask(picture: CGRect(origin: .zero, size: size), progress: progress, edge: .sharp)
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
