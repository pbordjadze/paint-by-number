import CoreGraphics
import MakingOf
import PaintCore
import SwiftUI

/// The making-of show, full screen over the create flow after Start Painting when Settings › The
/// Making-of is on (`SettingsKey.playsMakingOf`, off by default): the painter's photo becoming its
/// painting in six steps (`Sources/MakingOf`, `FieldShow`: each step grows from seeds over the
/// picture itself), and beside the picture a faint card for each step. Skip, a tap anywhere or the
/// show's end calls `onFinish`, after which the painting Start has saved takes over; so does a show
/// that can't be made.
///
/// `MakingOfPlayer` makes and times the show; this draws it (`MakingOfCanvas`) on the screen's
/// paper in either appearance (the picture is a sheet of its own paper, like the canvas's). Reduce
/// Motion plays the cards over still pictures, cross-faded. The photo shows while the show is being
/// made, which is how it begins.
///
/// The show plays where the painting's page will be (`place`, `PaintingLayout.page`), so
/// the journey from the preview to the canvas is one move (`StartHandoff`): the picture fades in
/// where the preview's was (`entry`, window coordinates) while the paper fades in behind it, moves
/// to its place when the create flow says (`arrived`), and the card and Skip come in after it.
/// Without an `entry` (Reduce Motion) it fades in at its place. When the show is over, its last
/// picture settles into `page`, the page as the canvas draws it, and the card and Skip go; then,
/// once the painting beneath has drawn, the paper fades away around the picture (`leaving`), and
/// the canvas shows the same page.
struct MakingOfView: View {
    /// How the show goes, once the painting beneath the cover has drawn its first frame.
    enum Leaving: Equatable {
        /// The show plays, or holds its last picture while the painting opens.
        case staying
        /// The picture moves to the page where the canvas put it (window coordinates), should that
        /// be elsewhere than expected (`StartHandoffPlan.correction`).
        case moving(CGRect)
        /// The paper fades to the painting; the picture, the page now, stays over the canvas's, where
        /// it moved to (nil: its place).
        case revealing(CGRect?)
        /// Everything fades, the picture too, where it is: there is no page to become, or no
        /// painting drew.
        case fading(CGRect?)
    }

    private let source: MakingOfSource
    private let entry: CGRect?
    private let place: CGRect?
    private let arrived: Bool
    private let page: CGImage?
    private let leaving: Leaving
    private let onFinish: () -> Void
    #if DEBUG
    /// Demo scenarios: the time the show is held at (Reduce Motion: the still), and what to call
    /// once it shows.
    private var heldAt: Double?
    private var forcesReduceMotion = false
    private var onReady: () -> Void = {}
    #endif
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.layoutDirection) private var layoutDirection
    @AppStorage(SettingsKey.paletteRows) private var paletteRows = PaletteRows.default
    @ScaledMetric(relativeTo: .title3) private var band: CGFloat = 150
    @State private var player = MakingOfPlayer()
    /// The show has come in: its picture and its paper have faded in.
    @State private var shown = false

    /// Room at the top for Skip.
    private static let top: CGFloat = 64

    init(
        source: MakingOfSource, entry: CGRect? = nil, place: CGRect? = nil, arrived: Bool = true,
        page: CGImage? = nil, leaving: Leaving = .staying, onFinish: @escaping () -> Void
    ) {
        self.source = source
        self.entry = entry
        self.place = place
        self.arrived = arrived
        self.page = page
        self.leaving = leaving
        self.onFinish = onFinish
    }

    #if DEBUG
    init(demo source: MakingOfSource, heldAt: Double, reduceMotion: Bool, onReady: @escaping () -> Void) {
        self.init(source: source, onFinish: {})
        self.heldAt = heldAt
        forcesReduceMotion = reduceMotion
        self.onReady = onReady
        // The scenarios hold the show for a screenshot: it is simply there.
        _shown = State(initialValue: true)
    }
    #endif

    var body: some View {
        GeometryReader { geometry in
            let layout = layout(in: geometry)
            let move = travel(of: layout, from: geometry.frame(in: .global).origin)
            stage(layout)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .opacity(showsPicture ? 1 : 0)
                .animation(pictureAnimation, value: showsPicture)
                .scaleEffect(move.scale, anchor: .topLeading)
                .offset(x: move.dx, y: move.dy)
        }
        .background {
            Theme.paper.ignoresSafeArea()
                .opacity(showsPaper ? 1 : 0)
                .animation(paperAnimation, value: showsPaper)
        }
        .contentShape(.rect)
        .onTapGesture { player.skip() }
        .overlay(alignment: .topTrailing) {
            Button("Skip") { player.skip() }
                .buttonStyle(.glass)
                .controlSize(.large)
                .padding(16)
                .opacity(chromeOpacity)
                .animation(chromeAnimation, value: chromeOpacity)
                .accessibilityIdentifier("making-of-skip")
        }
        // Nothing to skip, or to touch beneath, once the show is over or on its way.
        .allowsHitTesting(arrived && leaving == .staying && player.phase != .finished)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("making-of")
        .task { await start() }
        // How it comes in is the picture's and the paper's own animations.
        .onAppear { shown = true }
        .onDisappear { player.release() }
    }

    // MARK: Coming and going

    /// The picture is seen: it has come in, and is not fading out.
    private var showsPicture: Bool {
        if case .fading = leaving { return false }
        return shown
    }

    /// The paper behind the show, which fades in with the picture and out to the painting.
    private var showsPaper: Bool {
        guard shown else { return false }
        if case .moving = leaving { return true }
        return leaving == .staying
    }

    /// The card and Skip: in once the picture has moved, out once the show is over.
    private var chromeOpacity: Double {
        shown && arrived && leaving == .staying && player.phase != .finished ? 1 : 0
    }

    /// The page as the canvas draws it shows over the show's last picture once the show is over.
    private var showsPage: Bool { page != nil && player.phase == .finished }

    /// The picture comes in over the preview's (`lift`), or at its place as long as it would
    /// have taken to get there.
    private var pictureAnimation: Animation {
        guard showsPicture else { return .easeInOut(duration: StartHandoffPlan.reveal) }
        return .easeOut(duration: entry == nil ? StartHandoffPlan.glide : StartHandoffPlan.lift)
    }

    /// The paper comes in once the picture has, with the flow's controls going: under a picture
    /// still coming in it would show through it.
    private var paperAnimation: Animation {
        guard showsPaper else { return .easeInOut(duration: StartHandoffPlan.reveal) }
        return entry == nil
            ? .easeOut(duration: StartHandoffPlan.glide)
            : .easeOut(duration: StartHandoffPlan.clear).delay(StartHandoffPlan.lift)
    }

    private var chromeAnimation: Animation {
        chromeOpacity > 0
            ? .easeOut(duration: 0.25).delay(StartHandoffPlan.glide)
            : .easeOut(duration: 0.2)
    }

    /// The template the painting will show: what places the picture and what it ends on.
    private var template: Template? { source.template ?? player.built?.template }

    /// The show where the painting's page will be, in this view's coordinates (inside the safe
    /// area), with the card in the roomiest band beside it: at `place`, where the create flow
    /// expects the page, or, before it knows (and in demos), where this screen's layout puts it.
    private func layout(in geometry: GeometryProxy) -> MakingOfLayout {
        let page: CGRect
        if let place {
            let origin = geometry.frame(in: .global).origin
            page = place.offsetBy(dx: -origin.x, dy: -origin.y)
        } else {
            let safe = geometry.safeAreaInsets
            let inputs = PaintingLayout.Inputs(
                size: geometry.size, safe: safe, regularWidth: sizeClass == .regular, dynamicTypeSize: dynamicTypeSize,
                rows: paletteRows, colors: template.map(PaletteBar.visibleColorCount) ?? 1, isComplete: false)
            page = PaintingLayout(inputs)
                .page(of: pictureSize, inputs: inputs, rightToLeft: layoutDirection == .rightToLeft)
                .offsetBy(dx: -safe.leading, dy: -safe.top)
        }
        return MakingOfLayout(
            size: geometry.size, picture: page, band: min(band, geometry.size.height * 0.4), top: Self.top)
    }

    /// Where the picture is carried to: the preview's picture until it has arrived, the page where
    /// the canvas put it should that be elsewhere, otherwise nowhere (`layout` is its place).
    /// `origin` is where this view starts, in global coordinates (the window's).
    private func travel(of layout: MakingOfLayout, from origin: CGPoint) -> PictureTravel {
        let destination: CGRect? = switch leaving {
        case .moving(let target): target
        case .revealing(let target), .fading(let target): target
        case .staying: arrived ? nil : entry
        }
        return PictureTravel(home: layout.picture, destination: destination?.offsetBy(dx: -origin.x, dy: -origin.y))
    }

    private func start() async {
        #if DEBUG
        if let heldAt {
            await player.hold(source, at: heldAt, reduceMotion: forcesReduceMotion, onReady: onReady)
            return
        }
        #endif
        await player.run(source, reduceMotion: reduceMotion, onFinish: onFinish)
    }

    /// The page's size in canvas units, or the photo's before there is a template (demos).
    private var pictureSize: CGSize {
        if let template { return CGSize(width: template.width, height: template.height) }
        return CGSize(width: source.photo.width, height: source.photo.height)
    }

    /// The show, and over it, once it is over, the page as the canvas draws it.
    private func stage(_ layout: MakingOfLayout) -> some View {
        ZStack(alignment: .topLeading) {
            show(layout)
            if let page, showsPage {
                Image(decorative: page, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: layout.picture.width, height: layout.picture.height)
                    .offset(x: layout.picture.minX, y: layout.picture.minY)
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }
        }
        .animation(.easeInOut(duration: StartHandoffPlan.settle), value: showsPage)
    }

    @ViewBuilder
    private func show(_ layout: MakingOfLayout) -> some View {
        if let built = player.built, player.phase == .playing || (player.phase == .finished && player.stills.isEmpty) {
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: player.phase != .playing)) { timeline in
                inTime(built, at: player.time(at: timeline.date), in: layout)
            }
        } else if let built = player.built, player.stills.indices.contains(player.still) {
            ZStack {
                still(built, player.stills[player.still], in: layout)
                    .id(player.still)
                    .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.6), value: player.still)
        } else {
            ZStack(alignment: .topLeading) {
                Image(decorative: source.photo, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: layout.picture.width, height: layout.picture.height)
                    .clipShape(.rect(cornerRadius: MakingOfCanvas.cornerRadius))
                    .offset(x: layout.picture.minX, y: layout.picture.minY)
                    .accessibilityHidden(true)
                if player.phase == .preparing {
                    ProgressView()
                        .padding(layout.side.cardEdge, 24)
                        .frame(width: layout.band.width, height: layout.band.height, alignment: layout.side.cardAlignment)
                        .offset(x: layout.band.minX, y: layout.band.minY)
                        .accessibilityLabel(Text("Preparing the Making-of"))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// The show at time `t`, with its card.
    private func inTime(_ built: MakingOfShow, at t: Double, in layout: MakingOfLayout) -> some View {
        let frame = built.show.frame(at: t)
        return ZStack(alignment: .topLeading) {
            MakingOfCanvas(built: built, frame: frame, picture: player.picture ?? source.photo, layout: layout, marks: true)
            if let card = frame.card {
                cardView(built.cards[card.step], opacity: card.opacity, footnote: card.footnoteOpacity, in: layout)
            }
        }
    }

    /// A still of Reduce Motion, with its step's card at full strength.
    private func still(_ built: MakingOfShow, _ still: MakingOfPlayer.Still, in layout: MakingOfLayout) -> some View {
        let cards = built.spec.cards
        return ZStack(alignment: .topLeading) {
            MakingOfCanvas(built: built, frame: still.frame, picture: still.picture ?? source.photo, layout: layout, marks: false)
            if let k = still.step {
                cardView(built.cards[k], opacity: cards.opacity, footnote: cards.opacity * cards.footnote, in: layout)
            }
        }
    }

    private func cardView(_ card: MakingOfCard, opacity: Double, footnote: Double, in layout: MakingOfLayout) -> some View {
        MakingOfCardView(card: card, opacity: opacity, footnoteOpacity: footnote)
            .padding(layout.side.cardEdge, 16)
            .frame(width: layout.band.width, height: layout.band.height, alignment: layout.side.cardAlignment)
            .offset(x: layout.band.minX, y: layout.band.minY)
            .opacity(chromeOpacity)
            .animation(chromeAnimation, value: chromeOpacity)
    }
}

/// Where the show goes on a screen of `size` (inside the safe area): the picture at `picture`, the
/// painting's page (`PaintingLayout.page`), and the card in the band of the screen beside it that
/// suits it best: under the picture where `band` points are free there, as on most screens, else
/// whichever of under, above (below `top`, Skip's room) and beside it (where a side palette will be)
/// is largest, of those the card fits in at all.
nonisolated struct MakingOfLayout: Equatable, Sendable {
    /// Which band the card is in.
    nonisolated enum Side: Equatable, Sendable {
        case under, above, beside

        /// The card hugs the picture: the top of a band under it, the bottom of one above.
        var cardAlignment: Alignment {
            switch self {
            case .under: .top
            case .above: .bottom
            case .beside: .center
            }
        }

        var cardEdge: Edge.Set {
            switch self {
            case .under: .top
            case .above: .bottom
            case .beside: .horizontal
            }
        }
    }

    let picture: CGRect
    let band: CGRect
    let side: Side

    static let margin: CGFloat = 16
    /// The least a band takes the card in.
    static let least = CGSize(width: 120, height: 72)

    init(size: CGSize, picture: CGRect, band: CGFloat, top: CGFloat) {
        let margin = Self.margin
        let width = max(size.width - 2 * margin, 0)
        let bands: [(CGRect, Side)] = [
            (CGRect(x: margin, y: picture.maxY, width: width, height: max(size.height - margin - picture.maxY, 0)), .under),
            (CGRect(x: margin, y: top, width: width, height: max(picture.minY - top, 0)), .above),
            (CGRect(
                x: picture.maxX + margin, y: top, width: max(size.width - 2 * margin - picture.maxX, 0),
                height: max(size.height - margin - top, 0)), .beside),
        ]
        self.picture = picture
        let under = bands[0]
        let chosen = under.0.height >= band ? under : bands
            .filter { $0.0.width >= Self.least.width && $0.0.height >= Self.least.height }
            .max { $0.0.width * $0.0.height < $1.0.width * $1.0.height } ?? under
        self.band = chosen.0
        side = chosen.1
    }
}

/// One frame of the show, as `ShowFrame`'s doc comment says: the picture (layers and ink,
/// composited by `MakingOfPlayer`), the real template at its hand-off, the numbers, the seed rings,
/// and the sparks and stars of the field show, in ink over the rest. The real template comes in
/// under the numbers rather than over them: it is drawn without its numbers
/// (`MakingOfShow.handoff`), and the show's are the template's own, in place.
struct MakingOfCanvas: View {
    let built: MakingOfShow
    let frame: ShowFrame
    let picture: CGImage
    let layout: MakingOfLayout
    /// The seed rings, sparks and stars; Reduce Motion's stills have none of them.
    let marks: Bool

    nonisolated static let cornerRadius: CGFloat = 6
    /// The size digits are set at, then scaled to each number's.
    nonisolated private static let digitSize: CGFloat = 64
    /// A spark is a filled circle of `sparkRadius + sparkGrowth * heat` picture pixels at
    /// `sparkOpacity * heat` (`Spark`'s doc comment: `230 * heat / 255`), a star an outline
    /// `starWidth` pixel wide; all in `RevealStyle.ink`, scaled to the view like the rings.
    nonisolated private static let sparkRadius = 1.6
    nonisolated private static let sparkGrowth = 1.6
    nonisolated private static let sparkOpacity = 230.0 / 255
    nonisolated private static let starWidth: CGFloat = 1
    nonisolated private static let paper = color(RevealStyle.standard.paper)
    nonisolated private static let ink = color(RevealStyle.standard.ink)

    nonisolated private static func color(_ rgb: SIMD3<Double>) -> Color {
        Color(.sRGB, red: rgb.x / 255, green: rgb.y / 255, blue: rgb.z / 255)
    }

    var body: some View {
        let built = built, frame = frame, picture = picture, rect = layout.picture, marks = marks
        Canvas { context, _ in
            Self.draw(built, frame, picture: picture, in: rect, marks: marks, context: &context)
        }
        .accessibilityHidden(true)
    }

    /// Places of the pictures' pixels on screen.
    nonisolated private struct Placement {
        let rect: CGRect
        /// Points per pixel of the pictures.
        let scale: CGFloat

        func callAsFunction(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: rect.minX + CGFloat(x) * scale, y: rect.minY + CGFloat(y) * scale)
        }
    }

    nonisolated private static func draw(
        _ built: MakingOfShow, _ frame: ShowFrame, picture: CGImage, in rect: CGRect, marks: Bool,
        context: inout GraphicsContext
    ) {
        guard rect.width > 0, rect.height > 0 else { return }
        let place = Placement(rect: rect, scale: rect.width / CGFloat(max(built.show.size.width, 1)))
        var sheet = context
        sheet.clip(to: Path(roundedRect: rect, cornerRadius: cornerRadius))
        sheet.draw(Image(decorative: picture, scale: 1).interpolation(.high), in: rect)
        let handoff = frame.picture.handoff
        if handoff > 0, let template = built.handoff {
            sheet.opacity = handoff
            sheet.draw(Image(decorative: template, scale: 1).interpolation(.high), in: rect)
        }
        drawNumbers(built, frame, place: place, context: context)
        if marks {
            drawRings(frame, place: place, context: context)
            drawSparks(frame, place: place, context: context)
            drawStars(frame, place: place, context: context)
        }
    }

    nonisolated private static func drawNumbers(
        _ built: MakingOfShow, _ frame: ShowFrame, place: Placement, context: GraphicsContext
    ) {
        guard !frame.numbers.isEmpty else { return }
        var digits: [Int: GraphicsContext.ResolvedText] = [:]
        for (i, alpha) in frame.numbers.enumerated() where alpha > 0.01 && i < built.numbers.count && i < built.digits.count {
            let value = built.digits[i]
            let text: GraphicsContext.ResolvedText
            if let resolved = digits[value] {
                text = resolved
            } else {
                text = context.resolve(
                    Text(verbatim: String(value)).font(.system(size: digitSize, design: .serif)).foregroundStyle(ink))
                digits[value] = text
            }
            let number = built.numbers[i]
            var c = context
            c.opacity = alpha
            let at = place(number.x, number.y)
            c.translateBy(x: at.x, y: at.y)
            let s = CGFloat(number.size) * place.scale / digitSize
            c.scaleBy(x: s, y: s)
            c.draw(text, at: .zero, anchor: .center)
        }
    }

    /// Each k-means++ seed's ring, as `SeedRing` says: an ink circle over a paper halo, a dot in
    /// its middle.
    nonisolated private static func drawRings(_ frame: ShowFrame, place: Placement, context: GraphicsContext) {
        let k = place.scale
        for ring in frame.seedRings where ring.alpha > 0 {
            let center = place(ring.x, ring.y)
            let r = CGFloat(ring.radius) * k
            let width = CGFloat(SeedRing.lineWidth) * k
            var c = context
            c.opacity = ring.alpha
            c.fill(disc(center, r + CGFloat(SeedRing.halo) * k), with: .color(paper))
            c.stroke(disc(center, r - width / 2), with: .color(ink), lineWidth: width)
            c.fill(disc(center, CGFloat(SeedRing.dotRadius) * k), with: .color(ink))
        }
    }

    /// The hot tips of the lines burning in the ink step (`Spark`): a filled ink circle at each,
    /// bigger and stronger while hot, normally blended over the picture and the rings.
    nonisolated private static func drawSparks(_ frame: ShowFrame, place: Placement, context: GraphicsContext) {
        let k = place.scale
        for spark in frame.sparks where spark.heat > 0 {
            let heat = min(spark.heat, 1)
            var c = context
            c.opacity = sparkOpacity * heat
            c.fill(disc(place(spark.x, spark.y), CGFloat(sparkRadius + sparkGrowth * heat) * k), with: .color(ink))
        }
    }

    /// The faint rings that open round the numbers as they come out in the last step (`Star`): a
    /// circle outline one picture pixel wide in ink, its outer edge at the star's radius.
    nonisolated private static func drawStars(_ frame: ShowFrame, place: Placement, context: GraphicsContext) {
        let k = place.scale
        let width = starWidth * k
        for star in frame.stars where star.alpha > 0 {
            var c = context
            c.opacity = min(star.alpha, 1)
            let radius = max(CGFloat(star.radius) * k - width / 2, 0)
            c.stroke(disc(place(star.x, star.y), radius), with: .color(ink), lineWidth: width)
        }
    }

    nonisolated private static func disc(_ center: CGPoint, _ radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
    }
}
