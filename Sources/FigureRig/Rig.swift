import Foundation

public struct ActionTiming: Codable, Sendable {
    public var actor: String, kind: String, start: Double, end: Double
    public var windUp: Double?, release: Double?, settled: Double?
}

struct Foot: Sendable {
    var ground: Point, up: Double = 0, heading: Double, planted = true
    var contact = 0
}
struct PlannedAction: Sendable {
    var timing: ActionTiming, path: ArcPath?, from: Double, to: Double, origin: Point
    var headingFrom: Double, headingTo: Double, feet: [Foot], endFeet: [Foot]
    var distance: Double = 0, ramp: Double = 0, headings: [Double] = []
    var contactBase = 0
    var duration: Double { timing.end - timing.start }
    func travelled(_ t: Double) -> Double {
        let elapsed = clamp(t, 0, duration)
        guard distance > 0 else { return 0 }
        let speed = distance / max(duration - ramp, 1e-12)
        guard ramp > 0 else { return min(distance, elapsed * speed) }
        func integral(_ u: Double) -> Double { u * u * u - 0.5 * u * u * u * u }
        if elapsed < ramp { return speed * ramp * integral(elapsed / ramp) }
        if elapsed > duration - ramp { return distance - speed * ramp * integral((duration - elapsed) / ramp) }
        return speed * (elapsed - ramp * 0.5)
    }
    func walkSample(_ distance: Double) -> (point: Point, heading: Double) {
        let sample = path!.sample(mix(from, to, self.distance > 0 ? clamp(distance / self.distance) : 0))
        return (sample.point, wrapHeading(sample.heading + (to < from ? 180 : 0)))
    }
}

public struct ActorPose: Codable, Sendable {
    public var id: String, action: String, heading: Double, drawnHeading: Double
    public var joints: [String: Point], planted: [String: Bool]
    public var contacts: [String: Int]
    public var poseTime: Double
    var world: [String: Vector3] = [:]
    var origin = Point.zero
    var ikClamps = 0, kneeReverse = false, elbowReverse = false
    var swingFoot = "left"
    var handsOpen = false
    enum CodingKeys: CodingKey { case id, action, heading, drawnHeading, joints, planted, contacts, poseTime }
}

/// A stateless sampler: footfalls are absolute path samples, so a planted foot is identical
/// even when frames are requested backwards. IK is solved in 3D before projection.
struct Rig: Sendable {
    let spec: FigureSpec, scene: FigureScene
    let unit: Double, actions: [PlannedAction]
    let initialOrigin: Point, initialHeading: Double, initialFeet: [Foot]
    var duration: Double { (actions.last?.timing.end ?? 0) + scene.tail }

    init(spec: FigureSpec, scene: FigureScene) throws {
        self.spec = spec; self.scene = scene; unit = spec.normalizationScale * scene.figureHeight
        var paths: [String: ArcPath] = [:]
        for name in scene.paths.keys.sorted() {
            do { paths[name] = try ArcPath(scene.paths[name]!) }
            catch { throw FigureInputError("paths.\(name): \(error)") }
        }
        let actor = scene.actors[0]
        guard let firstPath = paths[actor.at.path] else { throw FigureInputError("actors[0].at.path: unknown path \(actor.at.path)") }
        let first = firstPath.sample(actor.at.t)
        initialOrigin = first.point; initialHeading = first.heading
        let k = unit, halfHip = spec.figure.hipWidth * k / 2, depth = spec.view.depth
        func foot(_ p: Point, _ heading: Double, _ side: Int) -> Foot {
            let lateral = headingVector(heading).normal * (side == 0 ? -halfHip : halfHip)
            return Foot(ground: p + Point(lateral.x, lateral.y * depth), heading: heading)
        }
        var feet = [foot(first.point, first.heading, 0), foot(first.point, first.heading, 1)]
        initialFeet = feet
        var origin = first.point, heading = first.heading, time = 0.0, fraction = actor.at.t, pathName = actor.at.path
        var result: [PlannedAction] = []
        for (i, input) in actor.timeline.enumerated() {
            var action = PlannedAction(timing: ActionTiming(actor: actor.id, kind: input.kind, start: time, end: time), path: nil,
                                       from: fraction, to: fraction, origin: origin,
                                       headingFrom: heading, headingTo: heading, feet: feet, endFeet: feet)
            action.contactBase = (i + 1) * 1_000_000
            switch input.kind {
            case "walk":
                guard let path = paths[input.path!] else { throw FigureInputError("actors[0].timeline[\(i)].path: unknown path \(input.path!)") }
                if pathName != input.path! {
                    guard (path.sample(0).point - origin).length < 1e-6 else {
                        throw FigureInputError("actors[0].timeline[\(i)].path: new path must start at the actor's current position")
                    }
                    fraction = 0
                }
                action.path = path; action.from = fraction; action.to = input.to!
                action.distance = abs(action.to - fraction) * path.length
                let speed = spec.motion.step * k * spec.motion.cadence
                let base = action.distance / speed
                action.ramp = min(spec.motion.ease, base)
                action.timing.end += base + action.ramp
                let count = Int(ceil(action.distance / (spec.motion.step * k)))
                if count > 0 {
                    for step in 0..<count {
                        let sample = action.walkSample(min(action.distance, Double(step + 1) * spec.motion.step * k))
                        action.endFeet[step % 2] = foot(sample.point, sample.heading, step % 2)
                        action.endFeet[step % 2].contact = action.contactBase + step + 1
                    }
                }
                // Fixed 240 Hz heading integration limits turns independently of output FPS.
                var h = heading
                let samples = max(1, Int(ceil(action.duration * 240)))
                action.headings = [h]
                for sample in 1...samples {
                    let target = action.walkSample(action.travelled(min(action.duration, Double(sample) / 240))).heading
                    h = wrapHeading(h + clamp(headingDelta(h, target), -spec.motion.turnRate / 240, spec.motion.turnRate / 240))
                    action.headings.append(h)
                }
                action.headingTo = h
                origin = path.sample(action.to).point; fraction = action.to; pathName = input.path!
            case "turn":
                action.headingTo = wrapHeading(input.heading!)
                let delta = headingDelta(heading, action.headingTo)
                action.timing.end += max(2 / Double(spec.motion.fps), abs(delta) * 1.5 / spec.motion.turnRate)
                let count = max(2, Int(ceil(abs(delta) / 45)))
                for step in 0..<count {
                    let h = wrapHeading(heading + delta * cubic(Double(step + 1) / Double(count)))
                    action.endFeet[step % 2] = foot(origin, h, step % 2)
                    action.endFeet[step % 2].contact = action.contactBase + step + 1
                }
            case "cast":
                action.timing.end += input.duration!
                let duration = input.duration!, settle = min(spec.motion.settle, duration * 0.4)
                let wind = duration * spec.motion.anticipation
                let release = wind + max(0, duration - settle - wind) * 0.6
                action.timing.windUp = time + wind; action.timing.release = time + release
                action.timing.settled = action.timing.end
            default: action.timing.end += input.duration!
            }
            result.append(action); time = action.timing.end; feet = action.endFeet; heading = action.headingTo
        }
        actions = result
    }

    func pose(at time: Double, quantized: Bool = true) -> ActorPose {
        let quantum = (spec.motion.onTwos ? 2.0 : 1.0) / Double(spec.motion.fps)
        let t = quantized ? floor(max(0, time) / quantum + 1e-9) * quantum : max(0, time)
        var origin = initialOrigin, heading = initialHeading, feet = initialFeet
        var phase = 0.0, armAngle = 0.0, crouch = 0.0, lean = 0.0, effort = 0.0, actionName = "idle", open = false
        var swing = 0
        let active = actions.first(where: { t >= $0.timing.start && t < $0.timing.end })
        if let action = active {
            actionName = action.timing.kind; origin = action.origin; heading = action.headingFrom; feet = action.feet
            let elapsed = t - action.timing.start
            if actionName == "walk", action.distance > 0 {
                let distance = action.travelled(elapsed), step = spec.motion.step * unit
                origin = action.walkSample(distance).point
                let sample = elapsed * 240, index = min(action.headings.count - 2, Int(sample))
                heading = wrapHeading(action.headings[index] + headingDelta(action.headings[index], action.headings[index + 1]) * (sample - Double(index)))
                let count = Int(ceil(action.distance / step)), segment = min(count - 1, Int(distance / step))
                for i in 0..<segment { feet[i % 2] = footfall(action, min(action.distance, Double(i + 1) * step), i % 2) }
                let span = min(step, action.distance - Double(segment) * step)
                phase = clamp((distance - Double(segment) * step) / max(span, 1e-12)); swing = segment % 2
                feet[swing] = swinging(feet[swing], footfall(action, min(action.distance, Double(segment + 1) * step), swing), phase, spec.motion.footLift * unit)
                effort = action.ramp > 0 ? min(cubic(elapsed / action.ramp), cubic((action.duration - elapsed) / action.ramp)) : 1
                armAngle = spec.motion.armSwing * sin(2 * .pi * (Double(segment) + phase) / 2) * effort
                lean = spec.motion.lean * effort
            } else if actionName == "turn" {
                let u = elapsed / max(action.duration, 1e-12), delta = headingDelta(action.headingFrom, action.headingTo)
                heading = wrapHeading(action.headingFrom + delta * cubic(u))
                let count = max(2, Int(ceil(abs(delta) / 45))), segment = min(count - 1, Int(u * Double(count)))
                func target(_ i: Int) -> Foot {
                    var foot = footAt(origin, wrapHeading(action.headingFrom + delta * cubic(Double(i + 1) / Double(count))), i % 2)
                    foot.contact = action.contactBase + i + 1
                    return foot
                }
                for i in 0..<segment { feet[i % 2] = target(i) }
                phase = u * Double(count) - Double(segment); swing = segment % 2
                feet[swing] = swinging(feet[swing], target(segment), phase, spec.motion.footLift * unit * 0.5)
            } else if actionName == "cast" {
                let wind = action.timing.windUp! - action.timing.start
                let release = action.timing.release! - action.timing.start
                let settleStart = action.duration - min(spec.motion.settle, action.duration * 0.4)
                let follow = mix(release, settleStart, 0.5)
                if elapsed < wind {
                    let u = cubic(elapsed / max(wind, 1e-12)); armAngle = -35 * u; crouch = 0.035 * u
                } else if elapsed < release {
                    let u = cubic((elapsed - wind) / max(release - wind, 1e-12))
                    armAngle = mix(-35, 135, u); crouch = 0.035 * (1 - u); lean = 6 * u
                } else if elapsed < follow {
                    let u = cubic((elapsed - release) / max(follow - release, 1e-12))
                    armAngle = 135 + 60 * spec.motion.followThrough * u; lean = 6
                } else if elapsed < settleStart {
                    let u = cubic((elapsed - follow) / max(settleStart - follow, 1e-12))
                    armAngle = 135 + 60 * spec.motion.followThrough * (1 - u); lean = 6
                } else {
                    let u = cubic((elapsed - settleStart) / max(action.duration - settleStart, 1e-12))
                    armAngle = 135 * (1 - u); lean = 6 * (1 - u)
                }
                open = elapsed >= wind && elapsed < settleStart
            }
        } else if let last = actions.last(where: { $0.timing.end <= t }) {
            origin = last.path.map { $0.sample(last.to).point } ?? last.origin
            heading = last.headingTo; feet = last.endFeet
        }
        return body(origin: origin, heading: heading, feet: feet, time: t, action: actionName,
                    phase: phase, swing: swing, armAngle: armAngle, crouch: crouch, lean: lean, effort: effort, open: open)
    }

    private func footAt(_ p: Point, _ h: Double, _ side: Int) -> Foot {
        let offset = headingVector(h).normal * (spec.figure.hipWidth * unit / 2 * (side == 0 ? -1 : 1))
        return Foot(ground: p + Point(offset.x, offset.y * spec.view.depth), heading: h)
    }
    private func footfall(_ action: PlannedAction, _ distance: Double, _ side: Int) -> Foot {
        let s = action.walkSample(distance)
        var foot = footAt(s.point, s.heading, side)
        foot.contact = action.contactBase + Int(ceil(distance / (spec.motion.step * unit) - 1e-9))
        return foot
    }
    private func swinging(_ from: Foot, _ to: Foot, _ phase: Double, _ lift: Double) -> Foot {
        // A brief double support leaves enough time for the rear foot to lift before
        // an eased swing would stretch the leg beyond its two-bone reach.
        if phase <= 0.04 { return from }
        if phase >= 0.96 { return to }
        let u = (phase - 0.04) / 0.92
        return Foot(ground: mix(from.ground, to.ground, cubic(u)), up: lift * sin(.pi * u),
                    heading: wrapHeading(from.heading + headingDelta(from.heading, to.heading) * cubic(u)), planted: false)
    }

    private func body(origin: Point, heading: Double, feet: [Foot], time: Double, action: String,
                      phase: Double, swing: Int, armAngle: Double, crouch: Double, lean: Double, effort: Double, open: Bool) -> ActorPose {
        let f = spec.figure, m = spec.motion, k = unit
        let drawn = m.headingSteps == 0 ? heading : wrapHeading((heading / (360 / Double(m.headingSteps))).rounded() * (360 / Double(m.headingSteps)))
        let forward = headingVector(drawn), lateral = forward.normal
        let gaitForward = Vector3(headingVector(heading), 0)
        var pose = ActorPose(id: scene.actors[0].id, action: action, heading: heading, drawnHeading: drawn,
                             joints: [:], planted: ["left": feet[0].planted, "right": feet[1].planted],
                             contacts: ["left": feet[0].contact, "right": feet[1].contact], poseTime: time)
        pose.origin = origin; pose.swingFoot = swing == 0 ? "left" : "right"; pose.handsOpen = open
        func local(_ a: Double, _ b: Double, _ c: Double) -> Vector3 { Vector3(origin + (forward * a + lateral * b) * k, c * k) }
        func project(_ p: Vector3) -> Point {
            Point(p.x, origin.y + (p.y - origin.y) * spec.view.depth - p.z * spec.view.heightScale)
        }
        let walking = action == "walk", idle = action == "idle"
        let sway = m.sway * (idle ? sin(time * 2 * .pi * 0.18) : (walking ? sin(phase * .pi) * (swing == 0 ? 1 : -1) * effort : 0))
        let pelvisHeight = 0.97 * (f.thigh + f.shin) - m.bounce + (walking ? m.bounce * pow(sin(.pi * phase), 2) * effort : 0) - crouch
        let pelvis = local(0, sway, pelvisHeight)
        let breathing = idle ? 0.003 * sin(time * 2 * .pi * 0.3) : 0
        let chest = pelvis + Vector3(forward * ((tan(radians(lean)) * f.torso + f.hunch * f.torso * 0.5) * k), (f.torso + breathing) * k)
        let neck = chest + Vector3(forward * (f.hunch * f.neck * k), f.neck * k)
        let head = neck + Vector3(0, 0, f.headSize * k / 2)
        pose.world = ["pelvis": pelvis, "chest": chest, "neck": neck, "head": head]
        for side in 0..<2 {
            let prefix = side == 0 ? "left" : "right", sign = side == 0 ? -1.0 : 1.0
            let hip = pelvis + Vector3(lateral * (sign * f.hipWidth * k / 2), 0)
            // Ground contacts live on the painting. Unproject around the current root so the
            // screen point stays fixed while the paper doll moves above it.
            let foot = feet[side]
            let depth = spec.view.depth
            let ankle = Vector3(foot.ground.x, depth > 1e-9 ? origin.y + (foot.ground.y - origin.y) / depth : origin.y, foot.up)
            let leg = twoBone(hip, ankle, f.thigh * k, f.shin * k, gaitForward)
            pose.ikClamps += leg.clamped ? 1 : 0; pose.kneeReverse = pose.kneeReverse || leg.reverse
            let shoulder = chest + Vector3(lateral * (sign * f.shoulderWidth * k / 2), 0)
            let angle = radians(walking ? armAngle * (side == 0 ? -1 : 1) : armAngle)
            let hand = shoulder + Vector3(forward * (sin(angle) * (f.upperArm + f.forearm) * k * 0.94),
                                          -cos(angle) * (f.upperArm + f.forearm) * k * 0.94)
            let arm = twoBone(shoulder, hand, f.upperArm * k, f.forearm * k, Vector3(forward, 0))
            pose.elbowReverse = pose.elbowReverse || arm.reverse
            let toeDirection = headingVector(foot.heading)
            let toeLength = f.foot * k
            let toeOffset = Point(toeDirection.x * toeLength, toeDirection.y * toeLength)
            let toe = ankle + Vector3(toeOffset, 0)
            for (joint, point) in [("Hip", hip), ("Knee", leg.joint), ("Ankle", ankle), ("Toe", toe),
                                   ("Shoulder", shoulder), ("Elbow", arm.joint), ("Hand", hand)] { pose.world[prefix + joint] = point }
            pose.joints[prefix + "Ankle"] = Point(foot.ground.x, foot.ground.y - foot.up * spec.view.heightScale)
            pose.joints[prefix + "Toe"] = pose.joints[prefix + "Ankle"]! + Point(toeOffset.x, toeOffset.y * depth)
        }
        for (name, point) in pose.world where pose.joints[name] == nil { pose.joints[name] = project(point) }
        return pose
    }
}

func twoBone(_ root: Vector3, _ end: Vector3, _ first: Double, _ second: Double, _ preferred: Vector3)
    -> (joint: Vector3, clamped: Bool, reverse: Bool) {
    let vector = end - root, actual = vector.length
    let lower = abs(first - second) + 1e-10, upper = first + second - 1e-10
    let distance = clamp(actual, lower, upper), axis = vector.unit
    var bend = preferred - axis * preferred.dot(axis)
    if bend.length < 1e-9 { let fallback = Vector3(0, 0, 1); bend = fallback - axis * fallback.dot(axis) }
    let along = (first * first - second * second + distance * distance) / (2 * distance)
    let height = sqrt(max(0, first * first - along * along))
    let offset = bend.unit * height
    return (root + axis * along + offset, actual < lower - 1e-8 || actual > upper + 1e-8, offset.dot(preferred) < -1e-8)
}
