import PaintCore
import Testing
import UIKit
@testable import PaintByNumber

/// The Apple Pencil on the painting screen: it paints while fingers move the page, its hover lights
/// the area under its tip, "Only Draw with Apple Pencil" keeps fingers from painting, and its
/// double tap and squeeze take the next color and show a hint. No simulator has a Pencil, so the
/// canvas's own handlers are handed recognizers that say where it is.
@MainActor
struct PencilTests {
    private let template = Fixtures.mosaic

    /// A recognizer in the state and at the place a test says, wherever it is asked from: `place`
    /// on the canvas (canvas units, the zoomed view's own) and where that is in the canvas view.
    private final class Touch: UILongPressGestureRecognizer {
        var phase = UIGestureRecognizer.State.began
        var place = SIMD2<Float>.zero
        weak var canvas: CanvasView?

        override var state: UIGestureRecognizer.State {
            get { phase }
            set { phase = newValue }
        }

        override func location(in view: UIView?) -> CGPoint {
            if let canvas, view === canvas { return canvas.viewPoint(forCanvas: place) }
            return CGPoint(x: CGFloat(place.x), y: CGFloat(place.y))
        }
    }

    private final class Hover: UIHoverGestureRecognizer {
        var phase = UIGestureRecognizer.State.changed
        var place = SIMD2<Float>.zero

        override var state: UIGestureRecognizer.State {
            get { phase }
            set { phase = newValue }
        }

        override func location(in view: UIView?) -> CGPoint { CGPoint(x: CGFloat(place.x), y: CGFloat(place.y)) }
    }

    private final class Tap: UITapGestureRecognizer {
        var place = SIMD2<Float>.zero
        weak var canvas: CanvasView?

        override var state: UIGestureRecognizer.State {
            get { .ended }
            set {}
        }

        override func location(in view: UIView?) -> CGPoint {
            if let canvas, view === canvas { return canvas.viewPoint(forCanvas: place) }
            return CGPoint(x: CGFloat(place.x), y: CGFloat(place.y))
        }
    }

    private func makeCanvas(_ session: PaintingSession) -> CanvasView {
        let canvas = CanvasView(session: session)
        canvas.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        canvas.layoutIfNeeded()
        return canvas
    }

    private func scrollView(of canvas: CanvasView) throws -> UIScrollView {
        try #require(canvas.subviews.compactMap { $0 as? UIScrollView }.first, "the canvas has no scroll view")
    }

    private func touchTypes(_ recognizer: UIGestureRecognizer) -> Set<Int> {
        Set(recognizer.allowedTouchTypes.map(\.intValue))
    }

    private let finger = UITouch.TouchType.direct.rawValue
    private let pointer = UITouch.TouchType.indirectPointer.rawValue
    private let trackpad = UITouch.TouchType.indirect.rawValue
    private let pencil = UITouch.TouchType.pencil.rawValue

    private func center(_ region: Int) -> SIMD2<Float> {
        template.labels(ofRegion: region).first?.position ?? template.anchor(ofRegion: region)
    }

    /// Unpainted areas of the selected color, and one of another color.
    private func areas(of session: PaintingSession) throws -> (own: [Int], other: Int) {
        let color = try #require(session.selectedColor)
        let own = template.regions.indices.filter { session.colorOf($0) == color && !session.isPainted($0) }
        let other = try #require(template.regions.indices.first { session.colorOf($0) != color })
        try #require(own.count >= 2)
        return (own, other)
    }

    private func send(_ selector: String, _ recognizer: UIGestureRecognizer, to canvas: CanvasView) {
        let selector = Selector((selector))
        precondition(canvas.responds(to: selector), "CanvasView has no \(selector)")
        canvas.perform(selector, with: recognizer)
    }

    private func pencilStroke(_ points: [SIMD2<Float>], on canvas: CanvasView) {
        let touch = Touch(target: nil, action: nil)
        touch.canvas = canvas
        for (i, point) in points.enumerated() {
            touch.place = point
            touch.phase = i == 0 ? .began : .changed
            send("handlePencil:", touch, to: canvas)
        }
        touch.phase = .ended
        send("handlePencil:", touch, to: canvas)
    }

    /// A finger's tap at `point`, as the tap recognizer delivers it.
    private func fingerTap(at point: SIMD2<Float>, on canvas: CanvasView) throws {
        let real = try #require(try scrollView(of: canvas).gestureRecognizers?.compactMap { $0 as? UITapGestureRecognizer }
            .first { $0.delegate === canvas }, "the canvas has no tap recognizer of its own")
        // The touch's kind is read as it comes down: a `UITouch` made here is a finger's.
        let touch = UITouch()
        #expect(touch.type == .direct)
        #expect(canvas.gestureRecognizer(real, shouldReceive: touch))
        let tap = Tap(target: nil, action: nil)
        tap.canvas = canvas
        tap.place = point
        send("handleTap:", tap, to: canvas)
    }

    private func fingerDrag(_ points: [SIMD2<Float>], on canvas: CanvasView) {
        let touch = Touch(target: nil, action: nil)
        touch.canvas = canvas
        for (i, point) in points.enumerated() {
            touch.place = point
            touch.phase = i == 0 ? .began : .changed
            send("handleDragPaint:", touch, to: canvas)
        }
        touch.phase = .ended
        send("handleDragPaint:", touch, to: canvas)
    }

    // MARK: Who may touch what

    /// Fingers (and a pointer) tap, only fingers drag-paint after a hold, the Pencil paints at
    /// once with a recognizer of its own, hover is watched and the Pencil's double tap and squeeze
    /// come to the canvas; panning and pinching are fingers', never the Pencil's.
    @Test func thePencilPaintsWhileFingersNavigate() throws {
        let canvas = makeCanvas(PaintingSession(template: template))
        let scroll = try scrollView(of: canvas)
        // The canvas's own: UIKit's classes themselves, not the scroll view's private kinds.
        let own = (scroll.gestureRecognizers ?? []).filter { $0 !== scroll.panGestureRecognizer && $0 !== scroll.pinchGestureRecognizer }

        let taps = own.filter { type(of: $0) == UITapGestureRecognizer.self }
        #expect(taps.count == 1)
        #expect(taps.first.map(touchTypes) == [finger, pointer])
        #expect(taps.first?.delegate === canvas)

        let presses = own.filter { type(of: $0) == UILongPressGestureRecognizer.self }.compactMap { $0 as? UILongPressGestureRecognizer }
        let drag = try #require(presses.first { $0.minimumPressDuration > 0 }, "no hold-and-drag recognizer")
        #expect(abs(drag.minimumPressDuration - 0.28) < 1e-9)
        #expect(drag.allowableMovement == 12)
        #expect(touchTypes(drag) == [finger])
        let pencilPress = try #require(presses.first { $0.minimumPressDuration == 0 }, "no Pencil recognizer")
        #expect(touchTypes(pencilPress) == [pencil])
        #expect(presses.count == 2)

        #expect(own.contains { type(of: $0) == UIHoverGestureRecognizer.self })
        let interaction = try #require(canvas.interactions.compactMap { $0 as? UIPencilInteraction }.first, "no Pencil interaction")
        #expect(interaction.delegate === canvas)

        #expect(touchTypes(scroll.panGestureRecognizer) == [finger, pointer, trackpad])
        #expect(scroll.pinchGestureRecognizer.map(touchTypes) == [finger, pointer])
    }

    // MARK: The Pencil's stroke

    /// The Pencil paints the area it touches down on and every area of the color it began with
    /// that it then crosses, as one stroke (one undo step), and says when it lifts.
    @Test func aPencilStrokePaintsWhatItCrosses() throws {
        let session = PaintingSession(template: template)
        let canvas = makeCanvas(session)
        let (own, _) = try areas(of: session)
        var actions: [PencilAction] = []
        canvas.onPencilAction = { actions.append($0) }
        var events: [PaintEvent] = []
        session.onEvent { events.append($0) }

        pencilStroke([center(own[0]), center(own[1])], on: canvas)

        #expect(session.isPainted(own[0]) && session.isPainted(own[1]))
        #expect(actions == [.lifted])
        #expect(!session.isStroking)
        let ended = events.compactMap { event -> [Int]? in
            if case let .strokeEnded(regions) = event { return regions }
            return nil
        }
        #expect(ended.count == 1)
        #expect(Set(try #require(ended.first)).isSuperset(of: [own[0], own[1]]))
    }

    /// On another color's area the Pencil paints nothing: the area is refused, as under a finger.
    @Test func aPencilOnAnotherColorIsRefused() throws {
        let session = PaintingSession(template: template)
        let canvas = makeCanvas(session)
        let (_, other) = try areas(of: session)
        var events: [PaintEvent] = []
        session.onEvent { events.append($0) }

        pencilStroke([center(other)], on: canvas)

        #expect(!session.isPainted(other))
        #expect(events.contains(.rejected(region: other, expectedColor: session.colorOf(other))))
    }

    /// While the photo shows, the Pencil's touch hides it and paints nothing.
    @Test func aPencilTouchHidesThePhotoInsteadOfPainting() throws {
        let session = PaintingSession(template: template)
        let canvas = makeCanvas(session)
        let (own, _) = try areas(of: session)
        var dismissed = 0
        canvas.onDismissPhoto = { dismissed += 1 }
        canvas.showsPhoto = true

        pencilStroke([center(own[0])], on: canvas)

        #expect(dismissed == 1)
        #expect(!session.isPainted(own[0]))
    }

    // MARK: Hover

    /// The Pencil's tip (or a pointer) over an unpainted area of the selected color lights it;
    /// over anything else, and once it leaves, nothing is lit.
    @Test func hoverLightsTheAreaUnderTheTip() throws {
        let session = PaintingSession(template: template)
        let canvas = makeCanvas(session)
        let (own, other) = try areas(of: session)
        let hover = Hover(target: nil, action: nil)
        func hovered() -> Int { Int(canvas.frameUniforms().ids.y) }
        #expect(hovered() == -1)

        hover.place = center(own[0])
        send("handleHover:", hover, to: canvas)
        #expect(hovered() == own[0])

        hover.place = center(other)
        send("handleHover:", hover, to: canvas)
        #expect(hovered() == -1)

        hover.place = center(own[1])
        send("handleHover:", hover, to: canvas)
        #expect(hovered() == own[1])
        hover.phase = .ended
        send("handleHover:", hover, to: canvas)
        #expect(hovered() == -1)

        // An area painted while hovered is no longer lit.
        hover.phase = .changed
        hover.place = center(own[0])
        send("handleHover:", hover, to: canvas)
        session.paint([own[0]], from: center(own[0]), animated: false)
        #expect(hovered() == -1)
    }

    // MARK: Only Draw with Apple Pencil

    /// With the system setting on, a finger's tap and a finger's drag paint nothing (they move the
    /// page), and the Pencil still paints.
    @Test func onlyThePencilDrawsWhenTheSettingSaysSo() throws {
        let session = PaintingSession(template: template)
        let canvas = makeCanvas(session)
        canvas.prefersPencilOnlyDrawing = { true }
        let (own, _) = try areas(of: session)

        try fingerTap(at: center(own[0]), on: canvas)
        #expect(!session.isPainted(own[0]))
        fingerDrag([center(own[0]), center(own[1])], on: canvas)
        #expect(!session.isPainted(own[0]) && !session.isPainted(own[1]))
        #expect(!session.isStroking)

        pencilStroke([center(own[0])], on: canvas)
        #expect(session.isPainted(own[0]))
    }

    /// With it off (the default), a finger's tap paints, and so does a finger's drag.
    @Test func fingersPaintWhenTheSettingIsOff() throws {
        let session = PaintingSession(template: template)
        let canvas = makeCanvas(session)
        canvas.prefersPencilOnlyDrawing = { false }
        let (own, _) = try areas(of: session)

        try fingerTap(at: center(own[0]), on: canvas)
        #expect(session.isPainted(own[0]))
        fingerDrag([center(own[1])], on: canvas)
        #expect(session.isPainted(own[1]))
    }

    // MARK: Double tap and squeeze

    /// The Pencil's double tap takes the next color that has areas left, with a detent; its squeeze
    /// shows a hint; the end of a stroke tells whoever listens that a Pencil paints here.
    @Test func doubleTapTakesTheNextColorAndSqueezeShowsAHint() throws {
        let session = PaintingSession(template: template)
        let haptics = HapticsPlayer(isSupported: true)
        let feedback = FeedbackEngine(haptics: haptics, sounds: SoundPlayer(playsAloud: false))
        let first = try #require(session.selectedColor)
        let next = try #require(session.nextIncompleteColor(after: first))
        try #require(next != first)
        var hints = 0, lifts = 0

        PencilAction.tap.perform(on: session, feedback: feedback, showHint: { hints += 1 }, pencilUsed: { lifts += 1 })
        #expect(session.selectedColor == next)
        #expect(haptics.played() == ["tick"])
        #expect(hints == 0 && lifts == 0)

        PencilAction.squeeze.perform(on: session, feedback: feedback, showHint: { hints += 1 }, pencilUsed: { lifts += 1 })
        #expect(hints == 1 && lifts == 0)
        #expect(session.selectedColor == next)

        PencilAction.lifted.perform(on: session, feedback: feedback, showHint: { hints += 1 }, pencilUsed: { lifts += 1 })
        #expect(hints == 1 && lifts == 1)
        #expect(haptics.played() == ["tick"])
    }

    /// With one color left the double tap has nowhere to go and the color stays (its detent still
    /// plays, as it always has; the keyboard's `]` plays none there).
    @Test func doubleTapStaysOnTheLastColorLeft() throws {
        let stripes = Fixtures.stripes(count: 2)
        let session = PaintingSession(template: stripes)
        session.autoAdvance = false
        session.select(color: 0)
        session.paint([0], from: .zero, animated: false)
        session.select(color: 1)
        let haptics = HapticsPlayer(isSupported: true)
        let feedback = FeedbackEngine(haptics: haptics, sounds: SoundPlayer(playsAloud: false))

        PencilAction.tap.perform(on: session, feedback: feedback, showHint: {}, pencilUsed: {})

        #expect(session.selectedColor == 1)
        #expect(haptics.played() == ["tick"])
    }
}
