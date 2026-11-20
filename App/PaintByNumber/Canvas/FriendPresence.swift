#if UNRELEASED
import PaintCore
import QuartzCore
import simd
import UIKit

/// What the canvas shows of a friend painting with you (Paint Together; painting-company row
/// 350, its design and the critic's rounds in `factory/pieces/shareplay/` there): the friend as
/// a soft light in the color of the paint they hold, never a badge or a cursor; a glow on the
/// edge of the screen toward them when they paint out of view; the hand's ripples and stars; and
/// the finale's two lights.
///
/// Everything moves on Core Animation's own clock, so nothing here costs the main thread a frame:
/// the light, ripples and stars lie in the canvas's units on a layer inside the scroll view's
/// zooming view (`world`), which pans and zooms with the painting for free, each drawn at a size
/// of its own on screen by an inverse scale (`zoomed(to:)`); a presence message only retargets an
/// animation. Reduce Motion: the light jumps, ripples and the finale's lights fade in place, a
/// star appears in the sky.
@MainActor
final class FriendPresence {
    /// In canvas units, inside the zooming view.
    private let world = CALayer()
    /// The canvas view's own layer, for the edge glow.
    private weak var screen: CALayer?
    private let light = CAGradientLayer()
    private let edge = CAGradientLayer()
    private var lightPoint: SIMD2<Float>?
    private var lightColor = UIColor.white
    private var isHere = false
    private var lightIsDown = false
    private var zoom: CGFloat = 1
    private var stars: [CAShapeLayer] = []
    /// Ripples and the finale's lights, each with the time it has played out by, removed by the
    /// next that comes (`sweep`).
    private var passing: [(layer: CALayer, until: CFTimeInterval)] = []
    private let canvasSize: CGSize
    var reduceMotion = false

    /// Across the light on screen, in points.
    static let lightSide: CGFloat = 220
    /// Across the edge glow.
    static let edgeSide: CGFloat = 240
    /// A star at rest in the sky.
    static let starSide: CGFloat = 26
    /// Stars kept in the sky at once.
    static let mostStars = 30
    /// Light retargets take this long: a presence message comes every 50 ms, and a little more
    /// rides over the network's unevenness.
    static let follow: CFTimeInterval = 0.11

    init(zoomingLayer: CALayer, screen: CALayer, canvasSize: CGSize) {
        self.screen = screen
        self.canvasSize = canvasSize
        world.frame = CGRect(origin: .zero, size: canvasSize)
        world.zPosition = 20
        zoomingLayer.addSublayer(world)
        for layer in [light, edge] {
            layer.type = .radial
            layer.startPoint = CGPoint(x: 0.5, y: 0.5)
            layer.endPoint = CGPoint(x: 1, y: 1)
            layer.opacity = 0
        }
        light.bounds = CGRect(x: 0, y: 0, width: Self.lightSide, height: Self.lightSide)
        world.addSublayer(light)
        edge.bounds = CGRect(x: 0, y: 0, width: Self.edgeSide, height: Self.edgeSide)
        edge.zPosition = 20
        screen.addSublayer(edge)
    }

    func remove() {
        world.removeFromSuperlayer()
        edge.removeFromSuperlayer()
    }

    // MARK: The light

    /// The colors of a light in `color`: a small bright core of the paint itself, a little
    /// lifted, inside a wide bloom of it falling off to nothing. A core lifted far toward white
    /// read as grey haze on light paper (the build's first critic round): the paint has to show.
    static func glow(_ color: UIColor, strength: CGFloat = 1) -> [CGColor] {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let spark = UIColor(red: r + (1 - r) * 0.55, green: g + (1 - g) * 0.55, blue: b + (1 - b) * 0.55, alpha: strength)
        let core = UIColor(red: r + (1 - r) * 0.18, green: g + (1 - g) * 0.18, blue: b + (1 - b) * 0.18, alpha: strength)
        return [spark.cgColor, core.cgColor, color.withAlphaComponent(0.55 * strength).cgColor,
                color.withAlphaComponent(0.3 * strength).cgColor, color.withAlphaComponent(0.1 * strength).cgColor,
                color.withAlphaComponent(0).cgColor]
    }

    /// The core is about an eighth of the light across; the bloom takes the rest.
    static let glowLocations: [NSNumber] = [0, 0.05, 0.11, 0.24, 0.55, 1]

    func arrived() {
        isHere = true
    }

    func left() {
        isHere = false
        lightPoint = nil
        fade(light, to: 0, duration: 0.8)
        fade(edge, to: 0, duration: 0.4)
    }

    /// The friend's finger is at `point` (nil: lifted: the light rests where it was, dimmer and
    /// smaller), holding a paint of `color`.
    func move(to point: SIMD2<Float>?, color: UIColor) {
        isHere = true
        if color != lightColor {
            lightColor = color
            CATransaction.begin()
            CATransaction.setAnimationDuration(reduceMotion ? 0 : 0.3)
            light.colors = Self.glow(color)
            light.locations = Self.glowLocations
            edge.colors = Self.glow(color, strength: 0.8)
            edge.locations = Self.glowLocations
            CATransaction.commit()
        }
        guard let point else {
            guard lightPoint != nil, lightIsDown else { return }
            lightIsDown = false
            settle(down: false)
            return
        }
        let p = CGPoint(x: CGFloat(min(max(point.x, 0), Float(canvasSize.width))),
                        y: CGFloat(min(max(point.y, 0), Float(canvasSize.height))))
        let appearing = lightPoint == nil || light.opacity < 0.05
        lightPoint = SIMD2(Float(p.x), Float(p.y))
        if appearing || reduceMotion {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            light.removeAnimation(forKey: "follow")
            light.position = p
            CATransaction.commit()
        } else {
            let from = light.presentation()?.position ?? light.position
            let follow = CABasicAnimation(keyPath: "position")
            follow.fromValue = NSValue(cgPoint: from)
            follow.toValue = NSValue(cgPoint: p)
            follow.duration = Self.follow
            follow.timingFunction = CAMediaTimingFunction(name: .linear)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            light.position = p
            light.add(follow, forKey: "follow")
            CATransaction.commit()
        }
        if !lightIsDown || appearing {
            lightIsDown = true
            settle(down: true)
        }
    }

    /// Down, the light is whole; lifted, it rests where it was, dimmer and smaller.
    private func settle(down: Bool) {
        fade(light, to: down ? 1 : 0.5, duration: down ? 0.2 : 0.6)
        let scale = (down ? 1 : 0.72) / zoom
        CATransaction.begin()
        CATransaction.setAnimationDuration(reduceMotion ? 0 : (down ? 0.2 : 0.6))
        light.transform = CATransform3DMakeScale(scale, scale, 1)
        CATransaction.commit()
    }

    private func fade(_ layer: CALayer, to opacity: Float, duration: CFTimeInterval) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        layer.opacity = opacity
        CATransaction.commit()
    }

    /// The painting was zoomed: everything in the world keeps its size on screen.
    func zoomed(to zoom: CGFloat) {
        guard zoom > 0, zoom != self.zoom else { return }
        self.zoom = zoom
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let lightScale = (lightIsDown || lightPoint == nil ? 1 : 0.72) / zoom
        light.transform = CATransform3DMakeScale(lightScale, lightScale, 1)
        for layer in world.sublayers ?? [] where layer !== light {
            layer.transform = CATransform3DMakeScale(1 / zoom, 1 / zoom, 1)
        }
        CATransaction.commit()
    }

    // MARK: The edge

    /// Where on screen the edge glow stands for a friend out of view, or nil when they are in
    /// view or away. `toView` maps canvas units to the canvas view's points; `visible` is the
    /// part of it the bars leave.
    func edgePoint(toView: (SIMD2<Float>) -> CGPoint, visible: CGRect) -> CGPoint? {
        guard isHere, let lightPoint, visible.width > 0, visible.height > 0 else { return nil }
        let p = toView(lightPoint)
        guard !visible.insetBy(dx: 8, dy: 8).contains(p) else { return nil }
        // Along the line from the middle of the view toward the friend, where it leaves the view.
        let c = CGPoint(x: visible.midX, y: visible.midY)
        let dx = p.x - c.x, dy = p.y - c.y
        let sx = dx == 0 ? .infinity : (visible.width / 2) / abs(dx)
        let sy = dy == 0 ? .infinity : (visible.height / 2) / abs(dy)
        let s = min(sx, sy)
        return CGPoint(x: c.x + dx * s, y: c.y + dy * s)
    }

    /// Shows the edge glow at `point` (nil hides it). `gliding`: the friend moved, so the glow
    /// follows over the same time the light does; a scroll moves it with the finger, at once.
    func showEdge(at point: CGPoint?, gliding: Bool = false) {
        guard let point else {
            if edge.opacity > 0 { fade(edge, to: 0, duration: 0.3) }
            return
        }
        let shown = edge.opacity > 0.05
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if gliding, shown, !reduceMotion {
            let follow = CABasicAnimation(keyPath: "position")
            follow.fromValue = NSValue(cgPoint: edge.presentation()?.position ?? edge.position)
            follow.toValue = NSValue(cgPoint: point)
            follow.duration = Self.follow
            follow.timingFunction = CAMediaTimingFunction(name: .linear)
            edge.add(follow, forKey: "follow")
        } else {
            edge.removeAnimation(forKey: "follow")
        }
        edge.position = point
        if edge.colors == nil {
            edge.colors = Self.glow(lightColor, strength: 0.8)
            edge.locations = Self.glowLocations
        }
        CATransaction.commit()
        let target: Float = lightIsDown ? 1 : 0.6
        if edge.opacity != target { fade(edge, to: target, duration: 0.3) }
    }

    /// Where the friend's light is, in canvas units.
    var friendPoint: SIMD2<Float>? { isHere ? lightPoint : nil }

    // MARK: The hand

    /// Two rings widen from `point` and fade: "there's one here".
    func ripple(at point: SIMD2<Float>, color: UIColor) {
        sweep()
        let p = CGPoint(x: CGFloat(point.x), y: CGFloat(point.y))
        for k in 0..<2 {
            let ring = CAShapeLayer()
            let side: CGFloat = 64
            ring.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            ring.path = CGPath(ellipseIn: ring.bounds.insetBy(dx: 2, dy: 2), transform: nil)
            ring.fillColor = nil
            ring.strokeColor = color.cgColor
            ring.lineWidth = 2
            ring.opacity = 0
            ring.transform = CATransform3DMakeScale(1 / zoom, 1 / zoom, 1)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            ring.position = p
            world.addSublayer(ring)
            CATransaction.commit()
            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = (reduceMotion ? 1 : 0.25) / zoom
            grow.toValue = (reduceMotion ? 1 : 1.5) / zoom
            grow.timingFunction = CAMediaTimingFunction(name: .easeOut)
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 0.85, 0]
            fade.keyTimes = [0, 0.18, 1]
            let group = CAAnimationGroup()
            group.animations = [grow, fade]
            group.duration = reduceMotion ? 1.2 : 1.3
            group.beginTime = CACurrentMediaTime() + Double(k) * (reduceMotion ? 0 : 0.28)
            group.fillMode = .backwards
            group.isRemovedOnCompletion = true
            ring.add(group, forKey: "ripple")
            // Gone once played; a ripple is a moment, not a mark.
            passing.append((ring, group.beginTime + group.duration))
            if reduceMotion { break }
        }
    }

    /// Where a star sent from `point` comes to rest: high in the sky above it, a little to one
    /// side, the same on both screens for the same point.
    func skyPoint(above point: SIMD2<Float>) -> CGPoint {
        let w = canvasSize.width, h = canvasSize.height
        // A hash of the point, so two stars sent from one place don't sit on each other exactly.
        let mix = (Int(point.x * 7.3) &* 31 &+ Int(point.y * 3.1)) & 0xff
        let side = (CGFloat(mix) / 255 - 0.5) * 0.16 * w
        let x = min(max(CGFloat(point.x) + side, w * 0.06), w * 0.94)
        let y = h * (0.05 + 0.08 * CGFloat((mix * 37) & 0xff) / 255)
        return CGPoint(x: x, y: y)
    }

    /// A star leaves `point`, drifts up over the painting and settles in its sky, where it stays,
    /// twinkling, while the painting is open.
    func star(from point: SIMD2<Float>) {
        let star = CAShapeLayer()
        let side = Self.starSide
        star.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        star.path = Sparkle.starPath(in: star.bounds)
        // A star of light: a pale gold, glowing in `Theme.gold` (spelled out as the fill's
        // sparkles do: the theme is SwiftUI).
        star.fillColor = UIColor(red: 1, green: 0.93, blue: 0.74, alpha: 1).cgColor
        star.shadowColor = UIColor(red: 0.95, green: 0.76, blue: 0.33, alpha: 1).cgColor
        star.shadowOpacity = 1
        star.shadowRadius = 7
        star.shadowOffset = .zero
        star.shadowPath = star.path
        star.transform = CATransform3DMakeScale(1 / zoom, 1 / zoom, 1)
        let from = CGPoint(x: CGFloat(point.x), y: CGFloat(point.y))
        let rest = skyPoint(above: point)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        star.position = rest
        world.addSublayer(star)
        CATransaction.commit()
        stars.append(star)
        // A sky keeps its newest stars; the oldest fade out so it never fills.
        if stars.count > Self.mostStars {
            let oldest = stars.removeFirst()
            oldest.removeAllAnimations()
            CATransaction.begin()
            CATransaction.setAnimationDuration(1)
            CATransaction.setCompletionBlock { oldest.removeFromSuperlayer() }
            oldest.opacity = 0
            CATransaction.commit()
        }
        let now = CACurrentMediaTime()
        if reduceMotion {
            let appear = CABasicAnimation(keyPath: "opacity")
            appear.fromValue = 0
            appear.toValue = 1
            appear.duration = 0.6
            star.add(appear, forKey: "appear")
        } else {
            // Up in a gentle arc, slowing as it settles.
            let path = CGMutablePath()
            path.move(to: from)
            let bend = CGPoint(x: from.x + (rest.x - from.x) * 0.15 + (from.x < rest.x ? -1 : 1) * canvasSize.width * 0.06,
                               y: from.y + (rest.y - from.y) * 0.55)
            path.addQuadCurve(to: rest, control: bend)
            let drift = CAKeyframeAnimation(keyPath: "position")
            drift.path = path
            drift.duration = 3.2
            drift.timingFunction = CAMediaTimingFunction(controlPoints: 0.3, 0, 0.2, 1)
            let pop = CAKeyframeAnimation(keyPath: "opacity")
            pop.values = [0, 1, 1]
            pop.keyTimes = [0, 0.08, 1]
            pop.duration = 3.2
            let group = CAAnimationGroup()
            group.animations = [drift, pop]
            group.duration = 3.2
            star.add(group, forKey: "drift")
        }
        let twinkle = CABasicAnimation(keyPath: "opacity")
        twinkle.fromValue = 1
        twinkle.toValue = 0.65
        twinkle.duration = 1.6
        twinkle.autoreverses = true
        twinkle.repeatCount = .infinity
        twinkle.beginTime = now + (reduceMotion ? 0.6 : 3.2)
        twinkle.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        if !reduceMotion { star.add(twinkle, forKey: "twinkle") }
    }

    // MARK: The finale

    /// The finale's two lights, one for each painter: each passes over the areas its painter
    /// painted at the times the replay paints them again. `steps` are the areas' places (canvas
    /// units), their start times (`CACurrentMediaTime`'s clock) and paints.
    func playLights(mine: [Step], friend: [Step], until end: CFTimeInterval) {
        sweep()
        for (steps, layer) in [(mine, makeFinaleLight()), (friend, makeFinaleLight())] {
            guard let first = steps.first else { layer.removeFromSuperlayer(); continue }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.position = first.point
            layer.colors = Self.glow(first.color)
            CATransaction.commit()
            let begin = first.time - 0.3
            let span = max(0.1, end - begin)
            // Core Animation spaces the keyframes evenly unless the times run from 0 to 1, so
            // the first and last places are held at both ends.
            let last = steps[steps.count - 1]
            let held = [first] + steps + [last]
            let times = [NSNumber(value: 0)]
                + steps.map { NSNumber(value: min(1, max(0, ($0.time - begin) / span))) }
                + [NSNumber(value: 1)]
            let move = CAKeyframeAnimation(keyPath: "position")
            move.values = held.map { NSValue(cgPoint: $0.point) }
            move.keyTimes = times
            move.calculationMode = .cubic
            let tint = CAKeyframeAnimation(keyPath: "colors")
            tint.values = held.map { Self.glow($0.color) }
            tint.keyTimes = times
            let shine = CAKeyframeAnimation(keyPath: "opacity")
            shine.values = [0, 1, 1, 0]
            shine.keyTimes = [0, NSNumber(value: min(0.3 / span, 0.2)), 0.85, 1]
            let group = CAAnimationGroup()
            group.animations = reduceMotion ? [shine] : [move, tint, shine]
            group.duration = span
            group.beginTime = begin
            group.fillMode = .both
            group.isRemovedOnCompletion = false
            layer.add(group, forKey: "finale")
            passing.append((layer, end))
        }
    }

    /// The replay stopped: its lights go with it.
    func stopLights() {
        for item in passing where item.layer.animation(forKey: "finale") != nil {
            item.layer.removeFromSuperlayer()
        }
        passing.removeAll { $0.layer.superlayer == nil }
    }

    /// Takes away the ripples and finale lights that have played out.
    private func sweep() {
        let now = CACurrentMediaTime()
        passing.removeAll { item in
            guard item.until < now else { return false }
            item.layer.removeFromSuperlayer()
            return true
        }
    }

    struct Step {
        var point: CGPoint
        var time: CFTimeInterval
        var color: UIColor
    }

    private func makeFinaleLight() -> CAGradientLayer {
        let layer = CAGradientLayer()
        layer.type = .radial
        layer.startPoint = CGPoint(x: 0.5, y: 0.5)
        layer.endPoint = CGPoint(x: 1, y: 1)
        layer.locations = Self.glowLocations
        layer.bounds = CGRect(x: 0, y: 0, width: Self.lightSide, height: Self.lightSide)
        layer.transform = CATransform3DMakeScale(1 / zoom, 1 / zoom, 1)
        layer.opacity = 0
        world.addSublayer(layer)
        return layer
    }

    /// The friend's light hides while the finale's own lights play.
    func hideLight() {
        fade(light, to: 0, duration: 0.3)
        lightPoint = nil
        showEdge(at: nil)
    }
}
#endif
