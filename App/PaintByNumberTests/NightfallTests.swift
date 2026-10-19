import CoreGraphics
import QuartzCore
import Testing
@testable import PaintByNumber

/// Night falling over a finished painting (`Nightfall`, SideStore and Debug builds): about three
/// seconds by Moon with a crescent and two stars, a warm evening light alone by Sun, no motion
/// under Reduce Motion, and it stays on the painting as the camera moves.
@MainActor
struct NightfallTests {
    private let painting = CGRect(x: 20, y: 80, width: 400, height: 300)

    private func fall(_ sky: Sky, reduceMotion: Bool = false, pace: Double = 1) -> (Nightfall, CALayer, CFTimeInterval) {
        let host = CALayer()
        let before = CACurrentMediaTime()
        return (Nightfall(over: painting, in: host, sky: sky, reduceMotion: reduceMotion, pace: pace), host, before)
    }

    @Test func byMoonACrescentAndTwoStarsComeOutOverTheDusk() throws {
        let (night, host, before) = fall(.moon)
        let container = try #require(host.sublayers?.first)
        #expect(host.sublayers?.count == 1)
        #expect(container.frame == painting)
        // The dusk, the crescent and two stars: few enough that the crescent stays the one thing.
        let parts = container.sublayers ?? []
        #expect(parts.count == 4)
        let shapes = parts.compactMap { $0 as? CAShapeLayer }
        #expect(shapes.count == 3)
        // The crescent is inked (a stroke, no fill) inside the painting's top right.
        let moon = try #require(shapes.first { $0.fillColor == nil })
        #expect(moon.frame.maxX <= painting.width && moon.frame.minY >= 0)
        #expect(moon.frame.midX > painting.width / 2 && moon.frame.midY < painting.height / 2)
        #expect(abs(night.duration - 3.2) < 0.001)
        #expect(night.peak - before > 1.9 && night.peak - before < 2.2)
        #expect(night.announcement == "The moon rises over your painting.")
    }

    @Test func bySunOnlyAnEveningLightNoMoonNoStars() throws {
        let (night, host, _) = fall(.sun)
        let container = try #require(host.sublayers?.first)
        #expect(container.sublayers?.count == 1)
        #expect(container.sublayers?.contains { $0 is CAShapeLayer } == false)
        #expect(night.duration < 3)
        #expect(night.announcement == "Evening light falls over your painting.")
    }

    /// Under Reduce Motion nothing moves: the crescent is whole from the start (no inking) and the
    /// stars don't pop; the night only fades in and out.
    @Test func reduceMotionFadesOneStill() throws {
        let (night, host, before) = fall(.moon, reduceMotion: true)
        let container = try #require(host.sublayers?.first)
        for part in container.sublayers ?? [] {
            #expect(part.animation(forKey: "strokeEnd") == nil)
            #expect(part.animation(forKey: "transform.scale") == nil)
            #expect(part.animation(forKey: "opacity") != nil)
        }
        #expect(night.peak - before < 0.7)
    }

    @Test func paceStretchesEveryTime() {
        let (night, _, before) = fall(.moon, pace: 3)
        #expect(abs(night.duration - 9.6) < 0.001)
        #expect(night.peak - before > 5.9)
    }

    /// The camera moved (a pan, a zoom, the completion bar changing the layout): the night moves
    /// and scales with the painting.
    @Test func followsThePainting() throws {
        let (night, host, _) = fall(.moon)
        let container = try #require(host.sublayers?.first)
        let moved = CGRect(x: 100, y: 40, width: 200, height: 150)
        night.follow(moved)
        #expect(abs(container.frame.minX - moved.minX) < 0.001 && abs(container.frame.minY - moved.minY) < 0.001)
        #expect(abs(container.frame.width - moved.width) < 0.001 && abs(container.frame.height - moved.height) < 0.001)
        night.remove()
        #expect(host.sublayers?.isEmpty ?? true)
    }

    /// The crescent is the empty gallery's: its outline fills the square it is drawn in.
    @Test func theCrescentFillsItsSquare() {
        let square = CGRect(x: 10, y: 20, width: 52, height: 52)
        let bounds = Crescent.cgPath(in: square).boundingBoxOfPath
        #expect(bounds.minX >= square.minX - 0.5 && bounds.maxX <= square.maxX + 0.5)
        #expect(bounds.minY >= square.minY - 0.5 && bounds.maxY <= square.maxY + 0.5)
        #expect(bounds.width > square.width * 0.8 && bounds.height > square.height * 0.9)
    }
}
