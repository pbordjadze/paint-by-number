import Foundation
import PaintCore

struct Particle: Sendable {
    var birth: Double, start: Point, velocity: Point, life: Double, color: String, phase: Double, size: Double, rotation: Double
}

struct MagicRenderer: Sendable {
    let spec: FigureSpec, scene: FigureScene, particles: [Particle]
    init(spec: FigureSpec, scene: FigureScene, rig: Rig) {
        self.spec = spec; self.scene = scene
        let seed = actorSeed(scene.seed, scene.actors[0].id)
        var result: [Particle] = []
        func emit(_ time: Double, _ start: Point, _ burst: Bool) {
            var rng = SplitMix64(seed: streamSeed(seed, 100, UInt64(result.count)))
            let angle = Double(rng.nextFloat()) * 2 * .pi
            let speed = scene.figureHeight * spec.magic.spread * (burst ? 1 : 0.15) * (0.25 + Double(rng.nextFloat()) * 0.75)
            let life = spec.magic.life * (0.85 + Double(rng.nextFloat()) * 0.3)
            let phase = Double(rng.nextFloat()) * 2 * .pi, size = spec.magic.size * rig.unit * (0.8 + Double(rng.nextFloat()) * 0.4)
            let jitter = Point(Double(rng.nextFloat()) - 0.5, Double(rng.nextFloat()) - 0.5) * (size * 0.1)
            result.append(Particle(birth: time, start: start + jitter, velocity: Point(cos(angle), sin(angle)) * speed,
                                   life: life, color: spec.magic.colors[result.count % spec.magic.colors.count], phase: phase,
                                   size: size, rotation: angle))
        }
        for action in rig.actions {
            if action.timing.kind == "walk", spec.magic.trail > 0 {
                var tick = 1
                while true {
                    let time = action.timing.start + Double(tick) / spec.magic.trail
                    if time >= action.timing.end { break }
                    let pose = rig.pose(at: time, quantized: false)
                    emit(time, pose.joints[pose.swingFoot + "Ankle"]!, false)
                    tick += 1
                }
            } else if let release = action.timing.release {
                let pose = rig.pose(at: release, quantized: false)
                for i in 0..<spec.magic.burst { emit(release, pose.joints[(i % 2 == 0 ? "left" : "right") + "Hand"]!, true) }
            }
        }
        particles = result.sorted { $0.birth < $1.birth }
    }
    func draw(at time: Double) -> (shapes: [FilledShape], alive: Int) {
        var shapes: [FilledShape] = [], alive = 0
        for p in particles {
            let age = time - p.birth
            guard age >= 0, age < p.life else { continue }
            alive += 1
            let progress = age / p.life, fade = cubic(age / 0.08) * (1 - cubic((progress - 0.6) / 0.4))
            let alpha = fade * (0.75 + 0.25 * cos(age * spec.magic.twinkle * 2 * .pi + p.phase))
            let size = p.size * (1 - 0.85 * cubic((progress - 0.6) / 0.4))
            let center = p.start + p.velocity * age + Point(0, -spec.magic.drift * scene.figureHeight * age)
            let contour: [Point]
            switch spec.magic.shape {
            case "dot": contour = ellipse(center, size / 2, size / 2, 16)
            case "leaf":
                contour = (0..<24).map { i in let a = Double(i) * 2 * .pi / 24; let point = Point(cos(a) * size * 0.65, sin(a) * size * 0.25); return center + Point(point.x * cos(p.rotation) - point.y * sin(p.rotation), point.x * sin(p.rotation) + point.y * cos(p.rotation)) }
            default:
                let tips = spec.magic.shape == "star" ? 5 : 4
                contour = (0..<(tips * 2)).map { i in let a = Double(i) * .pi / Double(tips) - .pi / 2 + (tips == 5 ? p.rotation : 0); return center + Point(cos(a), sin(a)) * (size * (i % 2 == 0 ? 0.65 : 0.16)) }
            }
            if spec.magic.glow > 0 { shapes.append(FilledShape(subpaths: [contour], color: p.color, opacity: alpha * spec.magic.glow * 0.5, blur: size * 0.6, layer: "particles")) }
            shapes.append(FilledShape(subpaths: [contour], color: p.color, opacity: alpha, layer: "particles"))
        }
        return (shapes, alive)
    }
}
