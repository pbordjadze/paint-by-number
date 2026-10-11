import Foundation

public struct FigureFrame: Sendable {
    public let time: Double, actors: [ActorPose], shapes: [FilledShape]
    public let particles: Int, minimumInkWidth: Double
}
public struct MotionFrame: Codable, Sendable {
    public let frame: Int, time: Double, actors: [ActorPose]
    public init(frame: Int, time: Double, actors: [ActorPose]) { self.frame = frame; self.time = time; self.actors = actors }
}

public struct FigureManifest: Codable, Sendable {
    public var engineVersion: String, specSHA256: String, sceneSHA256: String
    public var normalizationScale: Double, fps: Int, frameCount: Int, duration: Double, display: String
    public var pixelWidth: Int, pixelHeight: Int, actions: [ActionTiming]
    public var cardStart: Double, cardHoldStart: Double, cardHoldEnd: Double, cardEnd: Double
}

public enum CheckValue: Codable, Sendable {
    case number(Double), flag(Bool), text(String)
    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) { self = .flag(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else { self = .text(try c.decode(String.self)) }
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self { case .number(let n): try c.encode(n); case .flag(let b): try c.encode(b); case .text(let s): try c.encode(s) }
    }
}
public struct FigureCheck: Codable, Sendable {
    public let name: String, value: CheckValue, limit: CheckValue, pass: Bool
}

/// Figure engine v0. Version changes accompany any output change. All sampling is pure:
/// SVG serialization, motion and checks are independent of invocation order and core count.
public struct FigureEngine: Sendable {
    public static let version = "0.1.1"
    public let spec: FigureSpec, scene: FigureScene, card: CardLayout
    let rig: Rig, ink: InkRenderer, magic: MagicRenderer
    public var duration: Double { rig.duration }
    public var frameCount: Int { max(1, Int(ceil(duration * Double(spec.motion.fps)))) }
    public var actions: [ActionTiming] { rig.actions.map(\.timing) }
    public init(spec: FigureSpec, scene: FigureScene) throws {
        self.spec = spec; self.scene = scene
        rig = try Rig(spec: spec, scene: scene)
        ink = InkRenderer(spec: spec, unit: rig.unit, seed: actorSeed(scene.seed, scene.actors[0].id))
        magic = MagicRenderer(spec: spec, scene: scene, rig: rig)
        card = CardLayout(spec: spec, scene: scene)
    }
    public func pose(at time: Double) -> ActorPose { rig.pose(at: time) }
    public func frame(_ index: Int) -> FigureFrame {
        let time = Double(index) / Double(spec.motion.fps), pose = rig.pose(at: time)
        let drawing = ink.draw(pose, at: time), particles = magic.draw(at: time)
        let opacity = card.opacity(at: time)
        let cardShapes: [FilledShape] = opacity > 0 ? card.shapes.map { s in var s = s; s.opacity *= opacity; return s } : []
        return FigureFrame(time: time, actors: [pose], shapes: drawing.shapes + particles.shapes + cardShapes,
                           particles: particles.alive, minimumInkWidth: drawing.minimumWidth)
    }
    public func manifest(specSHA256: String, sceneSHA256: String) -> FigureManifest {
        FigureManifest(engineVersion: Self.version, specSHA256: specSHA256, sceneSHA256: sceneSHA256,
                       normalizationScale: spec.normalizationScale, fps: spec.motion.fps, frameCount: frameCount,
                       duration: duration, display: scene.display, pixelWidth: scene.pixelWidth, pixelHeight: scene.pixelHeight,
                       actions: actions, cardStart: card.start, cardHoldStart: card.holdStart,
                       cardHoldEnd: card.holdStart + card.hold, cardEnd: card.end)
    }
    public func checks(_ frames: [FigureFrame]) -> [FigureCheck] {
        let pts = scene.pointsPerUnit
        var slide = 0.0, knees = 0, elbows = 0, clamps = 0, minimumInk = Double.infinity, alive = 0, inBounds = true
        var previous: ActorPose?
        for frame in frames {
            let pose = frame.actors[0]
            if let previous {
                for side in ["left", "right"] where pose.planted[side] == true && previous.planted[side] == true && pose.contacts[side] == previous.contacts[side] {
                    slide = max(slide, (pose.joints[side + "Ankle"]! - previous.joints[side + "Ankle"]!).length * pts)
                }
            }
            previous = pose
            knees += hasReversedKnee(pose) ? 1 : 0; elbows += hasReversedElbow(pose) ? 1 : 0; clamps += pose.ikClamps > 0 ? 1 : 0
            minimumInk = min(minimumInk, frame.minimumInkWidth * pts); alive = max(alive, frame.particles)
            for shape in frame.shapes where shape.layer == "figure" {
                for point in shape.subpaths.joined() {
                    if point.x < 0 || point.y < 0 || point.x > scene.canvas.width || point.y > scene.canvas.height { inBounds = false }
                }
            }
        }
        let height = scene.figureHeight * spec.view.heightScale * pts
        let heightRange = scene.display == "ipad13" ? 24.0...56.0 : 18.0...40.0
        let requiredHold = max(2, spec.card.holdBase + spec.card.perWord * Double(scene.card.words))
        let visibleHold = min(card.hold, max(0, duration - card.holdStart))
        let onScreen = card.minimum.x >= 0 && card.minimum.y >= 0 && card.maximum.x <= scene.canvas.width && card.maximum.y <= scene.canvas.height
        func upper(_ name: String, _ value: Double, _ limit: Double) -> FigureCheck { FigureCheck(name: name, value: .number(value), limit: .number(limit), pass: value <= limit) }
        func lower(_ name: String, _ value: Double, _ limit: Double) -> FigureCheck { FigureCheck(name: name, value: .number(value), limit: .number(limit), pass: value >= limit) }
        return [upper("footSlide", slide, 0.5), upper("kneeReverse", Double(knees), 0), upper("elbowReverse", Double(elbows), 0),
                upper("ikClamps", Double(clamps), 0), lower("inkWidth", minimumInk, 1),
                FigureCheck(name: "figureHeight", value: .number(height), limit: .text("\(heightRange.lowerBound)...\(heightRange.upperBound)"), pass: heightRange.contains(height)),
                FigureCheck(name: "inBounds", value: .flag(inBounds), limit: .flag(true), pass: inBounds), upper("particles", Double(alive), 200),
                lower("cardHold", visibleHold, requiredHold), lower("cardSize", spec.card.size, 11),
                FigureCheck(name: "cardOnScreen", value: .flag(onScreen), limit: .flag(true), pass: onScreen)]
    }
}
