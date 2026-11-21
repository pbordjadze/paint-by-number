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
///    a band of gold at the burning front (`fuse`), the paper drying to the page's behind it. A
///    template made almost at once still lets the graphite show for `graphiteAtLeast` first.
/// 3. **Stars**: as the picture glides to the painting's place (the hand-off's own `settle`, no
///    time of its own), the page's numbers come out behind the same front, each with a twinkle
///    (`Stars`), and the picture is the page the canvas draws.
///
/// A tap skips at any moment (`skip`): once the template is made, to the painting; before, to the
/// plain picture forming, its lines drawn in as ever once made. Reduce Motion and The Making-of
/// switched on bring none of it, as they bring no lines (`FormingPlan.hasLines`). VoiceOver hears
/// the forming's one status, as before.
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
    /// it for a flicker, which reads as a glitch rather than a drawing.
    static var graphiteAtLeast: Double { 0.9 * StartHandoffPlan.glide }
    /// The lines burn in: as long as the plain forming's drawing in, so the show takes the
    /// hand-off no longer than the forming did.
    static var fuse: Double { FormingPlan.drawIn }
    /// The numbers come out during the glide: the hand-off's own settling into the page.
    static var stars: Double { StartHandoffPlan.settle }
    /// The most the show keeps the hand-off waiting once the template is made.
    static var longestTail: Double { graphiteAtLeast + fuse }

    /// When the fuse is lit (seconds, any clock), the template made at `made` and the graphite
    /// begun at `graphiteBegan` (nil: it never began): at once, unless the graphite has shown
    /// for less than `graphiteAtLeast`.
    static func fuseLit(madeAt made: Double, graphiteBegan: Double?) -> Double {
        guard let began = graphiteBegan else { return made }
        return max(made, min(began + graphiteAtLeast, made + graphiteAtLeast))
    }

    /// When the lines have burned in and the hand-off may lift.
    static func done(madeAt made: Double, graphiteBegan: Double?) -> Double {
        fuseLit(madeAt: made, graphiteBegan: graphiteBegan) + fuse
    }

    /// How far the graphite has spread, `elapsed` seconds after it began: racing out, easing in.
    static func graphiteProgress(since elapsed: Double) -> Double {
        let x = min(max(elapsed / graphiteSweep, 0), 1)
        return 1 - (1 - x) * (1 - x) * (1 - x)
    }

    /// How far the fuse has burned, `elapsed` seconds after it was lit: catching, then steady.
    static func fuseProgress(since elapsed: Double) -> Double {
        let x = min(max(elapsed / fuse, 0), 1)
        return x * x * (3 - 2 * x)
    }

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
    /// did. `margin` is how far its soft edge reaches: at 1 it has passed every corner by that.
    nonisolated enum Front {
        static let centre = CGPoint(x: 0.5, y: 0.45)
        /// How far the outline wavers, as a share of its reach.
        static let wobble = 0.22
        static let segments = 96

        /// The outline's reach at `angle` (radians, y down), relative to its mean.
        static func shape(at angle: Double) -> Double {
            1 + wobble * (0.5 * sin(3 * angle + 0.7) + 0.3 * sin(5 * angle + 2.1) + 0.2 * sin(8 * angle + 4.4))
        }

        static func origin(in rect: CGRect) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * centre.x, y: rect.minY + rect.height * centre.y)
        }

        /// The mean reach at progress 1: past the farthest corner by `margin` wherever the
        /// outline wavers in.
        static func reach(in rect: CGRect, margin: CGFloat) -> Double {
            let o = origin(in: rect)
            let dx = Double(max(o.x - rect.minX, rect.maxX - o.x)), dy = Double(max(o.y - rect.minY, rect.maxY - o.y))
            return ((dx * dx + dy * dy).squareRoot() + Double(margin)) / (1 - wobble)
        }

        /// The progress (0…1) at which the front reaches `point`.
        static func arrival(of point: CGPoint, in rect: CGRect, margin: CGFloat) -> Double {
            let o = origin(in: rect)
            let dx = Double(point.x - o.x), dy = Double(point.y - o.y)
            let full = reach(in: rect, margin: margin)
            guard full > 0 else { return 0 }
            return min(1, (dx * dx + dy * dy).squareRoot() / (full * shape(at: atan2(dy, dx))))
        }

        /// Everything the front has reached at `progress`.
        static func path(in rect: CGRect, progress: Double, margin: CGFloat) -> Path {
            var path = Path()
            add(to: &path, in: rect, progress: progress, margin: margin)
            return path
        }

        /// The band between the front at `inner` and at `outer`, to be filled even-odd.
        static func band(in rect: CGRect, from inner: Double, to outer: Double, margin: CGFloat) -> Path {
            var path = Path()
            add(to: &path, in: rect, progress: outer, margin: margin)
            add(to: &path, in: rect, progress: inner, margin: margin)
            return path
        }

        private static func add(to path: inout Path, in rect: CGRect, progress: Double, margin: CGFloat) {
            guard progress > 0, rect.width > 0, rect.height > 0 else { return }
            let o = origin(in: rect)
            let r = progress * reach(in: rect, margin: margin)
            for k in 0..<segments {
                let angle = 2 * Double.pi * Double(k) / Double(segments)
                let extent = r * shape(at: angle)
                let point = CGPoint(x: o.x + CGFloat(extent * cos(angle)), y: o.y + CGFloat(extent * sin(angle)))
                if k == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
        }
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

        /// Draws the twinkles at `progress` on a page `size` points (its width the template's).
        func draw(in context: inout GraphicsContext, size: CGSize, progress: Double, margin: CGFloat, color: Color) {
            guard progress > 0, progress < 1 + Self.life, size.width > 0 else { return }
            let rect = CGRect(origin: .zero, size: size)
            let w = size.width
            for label in labels {
                let point = CGPoint(x: CGFloat(label.x) * w, y: CGFloat(label.y) * w)
                let glow = Self.twinkle(arrival: Front.arrival(of: point, in: rect, margin: margin), progress: progress)
                guard glow > 0 else { continue }
                let radius = min(max(CGFloat(label.z) * w * 1.4, 4), 14) * CGFloat(0.6 + 0.4 * glow)
                context.opacity = glow
                context.fill(Self.sparkle(at: point, radius: radius), with: .color(color))
            }
            context.opacity = 1
        }
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
        let context = CIContext(options: [.cacheIntermediates: false])
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
    /// When the template's lines began to burn in (it can be a moment ahead: `graphiteAtLeast`).
    var fuseLit: Date?
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
        guard let fuseLit else { return 0 }
        return FormingShow.fuseProgress(since: now.timeIntervalSince(fuseLit))
    }

    /// Until when anything moves: nil once nothing will.
    var movesUntil: Date? {
        var until: Date?
        if heldGraphite == nil, graphite != nil, let graphiteBegan {
            until = graphiteBegan.addingTimeInterval(FormingShow.graphiteSweep)
        }
        if heldFuse == nil, let fuseLit {
            let end = fuseLit.addingTimeInterval(FormingShow.fuse)
            until = until.map { max($0, end) } ?? end
        }
        return until
    }
}

/// What the front has reached at `progress`, soft over `feather` points: a mask over a frame
/// in which the picture is at `picture`.
struct FormingFrontMask: View {
    let picture: CGRect
    let progress: Double
    let feather: CGFloat

    var body: some View {
        if progress >= 1 {
            Rectangle()
        } else if progress > 0 {
            FormingShow.Front.path(in: picture, progress: progress, margin: feather)
                .fill(.black)
                .blur(radius: feather / 2)
        } else {
            Color.clear
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
    }

    private var diagonal: CGFloat { (picture.width * picture.width + picture.height * picture.height).squareRoot() }

    @ViewBuilder
    private func layers(graphite: Double, fuse: Double) -> some View {
        let soft = diagonal * 0.08, sharp = diagonal * 0.02
        ZStack(alignment: .topLeading) {
            // Under paper wherever the fuse has burned: drawn only while some of it shows.
            if let image = moments.graphite, graphite > 0, fuse < 1 {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: picture.width, height: picture.height)
                    .clipped()
                    .offset(x: picture.minX, y: picture.minY)
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                    .mask(alignment: .topLeading) { FormingFrontMask(picture: picture, progress: graphite, feather: soft) }
                    .transition(.opacity)
            }
            if let lines, fuse > 0 {
                FormingPaper()
                    .mask(alignment: .topLeading) { FormingFrontMask(picture: picture, progress: fuse, feather: sharp) }
                FormingLines(drawing: lines, picture: picture, scale: scale)
                    .equatable()
                    .frame(width: size.width, height: size.height)
                    .mask(alignment: .topLeading) { FormingFrontMask(picture: picture, progress: fuse, feather: sharp) }
                if fuse < 1 {
                    // The burning front: the lines in gold along a narrow band behind it.
                    FormingLines(drawing: lines, picture: picture, scale: scale, ink: Theme.gold, weight: 1.8)
                        .equatable()
                        .frame(width: size.width, height: size.height)
                        .mask(alignment: .topLeading) {
                            FormingShow.Front.band(in: picture, from: max(fuse - 0.06, 0), to: fuse, margin: sharp)
                                .fill(.black, style: FillStyle(eoFill: true))
                                .blur(radius: 1.5)
                        }
                        .shadow(color: Theme.gold.opacity(0.9), radius: 4)
                }
            }
        }
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

    var body: some View {
        let stars = stars, size = size, gold = Theme.gold
        let margin = (size.width * size.width + size.height * size.height).squareRoot() * 0.03
        TimelineView(.animation(paused: isOver || held != nil)) { context in
            let progress = held ?? frontProgress(at: isOver ? .distantFuture : context.date)
            ZStack(alignment: .topLeading) {
                Image(decorative: page, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size.width, height: size.height)
                    .mask(alignment: .topLeading) {
                        FormingFrontMask(picture: CGRect(origin: .zero, size: size), progress: progress, feather: margin)
                    }
                if progress < 1 + FormingShow.Stars.life {
                    Canvas { context, _ in
                        stars.draw(in: &context, size: size, progress: progress, margin: margin, color: gold)
                    }
                    .frame(width: size.width, height: size.height)
                }
            }
        }
        .allowsHitTesting(false)
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
