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

/// Figure engine v1. Version changes accompany any output change. All sampling is pure:
/// SVG serialization, motion and checks are independent of invocation order and core count.
public struct FigureEngine: Sendable {
    public static let version = "1.0.0"
    public let spec: FigureSpec, scene: FigureScene, card: CardLayout
    let rigs: [Rig], inks: [InkRenderer], magics: [MagicRenderer]
    let ground: InkDrawing
    var rig: Rig { rigs[0] }
    var ink: InkRenderer { inks[0] }
    var magic: MagicRenderer { magics[0] }
    public var duration: Double { rigs.map(\.duration).max()! }
    public var frameCount: Int { max(1, Int(ceil(duration * Double(spec.motion.fps)))) }
    public var actions: [ActionTiming] { rigs.flatMap { $0.actions.map(\.timing) } }
    public init(spec: FigureSpec, scene: FigureScene) throws {
        self.spec = spec; self.scene = scene
        rigs = try scene.actors.indices.map { try Rig(spec: spec, scene: scene, actorIndex: $0) }
        inks = rigs.map { InkRenderer(spec: spec, unit: $0.unit, seed: actorSeed(scene.seed, $0.actor.id)) }
        magics = rigs.map { MagicRenderer(spec: spec, scene: scene, rig: $0) }
        var ground = InkDrawing()
        let groundInk = InkRenderer(spec: spec, unit: rigs[0].unit, seed: streamSeed(scene.seed, 500))
        for (i, prop) in scene.props.enumerated() {
            guard let data = scene.paths[prop.at.path] else { throw FigureInputError("props[\(i)].at.path: unknown path \(prop.at.path)") }
            let point = try ArcPath(data).sample(prop.at.t).point
            let elevation = prop.kind == .mortar ? 0.13 : prop.kind.length
            let base = point - Point(0, elevation * scene.figureHeight * spec.view.heightScale)
            let drawing = groundInk.prop(prop.kind, base: base, axis: Point(0, spec.view.heightScale), at: 0, stream: 600 + UInt64(i) * 20)
            ground.shapes += drawing.shapes; ground.minimumWidth = min(ground.minimumWidth, drawing.minimumWidth)
        }
        self.ground = ground
        card = CardLayout(spec: spec, scene: scene)
    }
    public func pose(at time: Double) -> ActorPose { rig.pose(at: time) }
    public func frame(_ index: Int) -> FigureFrame {
        let time = Double(index) / Double(spec.motion.fps)
        let poses = rigs.map { $0.pose(at: time) }
        var shapes = ground.shapes, minimumWidth = ground.minimumWidth
        for i in rigs.indices {
            let drawing = inks[i].laidInk(rigs[i], at: time)
            shapes += drawing.shapes; minimumWidth = min(minimumWidth, drawing.minimumWidth)
        }
        let order = poses.indices.sorted {
            func depth(_ index: Int) -> Double {
                (poses[index].joints["leftAnkle"]!.y + poses[index].joints["rightAnkle"]!.y) / 2
            }
            let a = depth($0), b = depth($1)
            return a == b ? $0 < $1 : a < b
        }
        for i in order {
            let drawing = inks[i].draw(poses[i], at: time)
            shapes += drawing.shapes; minimumWidth = min(minimumWidth, drawing.minimumWidth)
            if let prop = poses[i].prop {
                let held = inks[i].heldProp(prop, at: time)
                shapes += held.shapes; minimumWidth = min(minimumWidth, held.minimumWidth)
            }
        }
        var alive = 0
        for magic in magics {
            let particles = magic.draw(at: time)
            shapes += particles.shapes; alive += particles.alive
        }
        let opacity = card.opacity(at: time)
        let cardShapes: [FilledShape] = opacity > 0 ? card.shapes.map { s in var s = s; s.opacity *= opacity; return s } : []
        return FigureFrame(time: time, actors: poses, shapes: shapes + cardShapes,
                           particles: alive, minimumInkWidth: minimumWidth)
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
        var previous: [String: ActorPose] = [:]
        var brushError = 0.0, gripError = 0.0
        var separation = hypot(scene.canvas.width, scene.canvas.height)
        for frame in frames {
            for pose in frame.actors {
                if let last = previous[pose.id] {
                    for side in ["left", "right"] where pose.planted[side] == true && last.planted[side] == true && pose.contacts[side] == last.contacts[side] {
                        slide = max(slide, (pose.joints[side + "Ankle"]! - last.joints[side + "Ankle"]!).length * pts)
                    }
                }
                previous[pose.id] = pose
                knees += hasReversedKnee(pose) ? 1 : 0; elbows += hasReversedElbow(pose) ? 1 : 0; clamps += pose.ikClamps > 0 ? 1 : 0
                if pose.action == "ink" {
                    if let prop = pose.prop, prop.kind == .brush, let target = pose.inkPathPoint {
                        brushError = max(brushError, (prop.tip - target).length)
                    } else { brushError = max(brushError, 1) }
                }
                if let prop = pose.prop {
                    for (side, grip) in prop.grips {
                        gripError = max(gripError, (grip - pose.joints[side + "Hand"]!).length)
                    }
                }
            }
            for i in frame.actors.indices {
                for j in frame.actors.indices where j > i {
                    separation = min(separation, (frame.actors[i].joints["pelvis"]! - frame.actors[j].joints["pelvis"]!).length)
                }
            }
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
        var checks = [upper("footSlide", slide, 0.5), upper("kneeReverse", Double(knees), 0), upper("elbowReverse", Double(elbows), 0),
                upper("ikClamps", Double(clamps), 0), lower("inkWidth", minimumInk, 1),
                FigureCheck(name: "figureHeight", value: .number(height), limit: .text("\(heightRange.lowerBound)...\(heightRange.upperBound)"), pass: heightRange.contains(height)),
                FigureCheck(name: "inBounds", value: .flag(inBounds), limit: .flag(true), pass: inBounds), upper("particles", Double(alive), 200),
                lower("cardHold", visibleHold, requiredHold), lower("cardSize", spec.card.size, 11),
                FigureCheck(name: "cardOnScreen", value: .flag(onScreen), limit: .flag(true), pass: onScreen)]
        if scene.version == 2 {
            checks += [upper("brushTip", brushError, 0.5), upper("propGrip", gripError, 0.5),
                       lower("actorSeparation", separation, spec.figure.hipWidth * rig.unit)]
        }
        return checks
    }
}
