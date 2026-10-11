import Foundation
import PaintCore

/// The app can draw these same filled contours; font outlines are shapes too. Layer labels
/// let the factory isolate the figure without changing the rendering contract.
public struct FilledShape: Codable, Sendable {
    public var subpaths: [[Point]], color: String, opacity: Double = 1, blur: Double? = nil
    public var layer: String = "figure"
    public init(subpaths: [[Point]], color: String, opacity: Double = 1, blur: Double? = nil, layer: String = "figure") {
        self.subpaths = subpaths; self.color = color; self.opacity = opacity; self.blur = blur; self.layer = layer
    }
}

func actorSeed(_ seed: UInt64, _ id: String) -> UInt64 {
    var hash: UInt64 = 0xcbf29ce484222325
    for byte in id.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
    return seed ^ hash
}
func streamSeed(_ seed: UInt64, _ stream: UInt64, _ index: UInt64 = 0) -> UInt64 {
    var rng = SplitMix64(seed: seed ^ (stream &* 0x9e3779b97f4a7c15) ^ (index &* 0xd1b54a32d192ed03))
    return rng.next()
}
private func noise(_ distance: Double, _ seed: UInt64) -> Double {
    let cell = Int64(floor(distance)), fraction = distance - floor(distance)
    func value(_ index: Int64) -> Double {
        var rng = SplitMix64(seed: streamSeed(seed, 7, UInt64(bitPattern: index)))
        return Double(rng.nextFloat()) * 2 - 1
    }
    return mix(value(cell), value(cell + 1), cubic(fraction))
}
func ellipse(_ center: Point, _ rx: Double, _ ry: Double, _ count: Int = 32) -> [Point] {
    (0..<count).map { let a = Double($0) * 2 * .pi / Double(count); return center + Point(cos(a) * rx, sin(a) * ry) }
}

struct InkDrawing {
    var shapes: [FilledShape] = []
    var minimumWidth = Double.infinity
}

struct InkRenderer: Sendable {
    let spec: FigureSpec, unit: Double, seed: UInt64

    func draw(_ pose: ActorPose, at time: Double) -> InkDrawing {
        var drawing = InkDrawing()
        let f = spec.figure, k = unit, ink = spec.ink
        let boil = UInt64(max(0, floor(time * ink.boilFps)))
        var groups: [(depth: Double, index: Int, shapes: [FilledShape])] = []
        var serial = 0
        func group(_ names: [String], _ contours: [FilledShape]) {
            let depth = names.reduce(0.0) { $0 + pose.world[$1]!.y } / Double(names.count)
            groups.append((depth, serial, contours)); serial += 1
        }
        func stroke(_ points: [Point], _ index: UInt64, closed: Bool = false) -> FilledShape {
            let result = outline(points, seed: streamSeed(seed, 1 + index, boil), closed: closed)
            drawing.minimumWidth = min(drawing.minimumWidth, result.minimumWidth)
            return result.shape
        }
        for (i, prefix) in ["left", "right"].enumerated() {
            let leg = [prefix + "Hip", prefix + "Knee", prefix + "Ankle"] + (f.foot > 0 ? [prefix + "Toe"] : [])
            var shapes = [stroke(leg.map { pose.joints[$0]! }, UInt64(i))]
            if f.knobs > 0 { shapes.append(FilledShape(subpaths: [ellipse(pose.joints[prefix + "Knee"]!, f.knobs * ink.width * k, f.knobs * ink.width * k)], color: ink.color)) }
            group(leg, shapes)
            let arm = [prefix + "Shoulder", prefix + "Elbow", prefix + "Hand"]
            shapes = [stroke(arm.map { pose.joints[$0]! }, UInt64(i + 2))]
            if f.knobs > 0 { shapes.append(FilledShape(subpaths: [ellipse(pose.joints[prefix + "Elbow"]!, f.knobs * ink.width * k, f.knobs * ink.width * k)], color: ink.color)) }
            if f.hands != "none" {
                let r = ink.width * k * (f.hands == "mitten" || pose.handsOpen ? 0.95 : 0.65)
                var hand = ellipse(pose.joints[prefix + "Hand"]!, r, r * (f.hands == "mitten" ? 1.4 : 1))
                if pose.handsOpen {
                    let center = pose.joints[prefix + "Hand"]!
                    hand = (0..<10).map { j in let a = Double(j) * 2 * .pi / 10; let radius = r * (j % 2 == 0 ? 1.4 : 0.65); return center + Point(cos(a), sin(a)) * radius }
                }
                shapes.append(FilledShape(subpaths: [hand], color: ink.color))
            }
            group(arm, shapes)
        }
        let pelvis = pose.joints["pelvis"]!, chest = pose.joints["chest"]!, neck = pose.joints["neck"]!
        var spine: [Point] = []
        let forward = headingVector(pose.drawnHeading)
        let control = mix(pelvis, chest, 0.5) - Point(forward.x, forward.y * spec.view.depth) * (f.hunch * f.torso * k * 0.25)
        for i in 0...24 { let u = Double(i) / 24; spine.append(pelvis * ((1 - u) * (1 - u)) + control * (2 * (1 - u) * u) + chest * (u * u)) }
        spine.append(neck)
        var torso = [stroke(spine, 4)]
        if f.shoulderWidth > 0 { torso.append(stroke([pose.joints["leftShoulder"]!, pose.joints["rightShoulder"]!], 5)) }
        if f.skirt > 0 {
            let r = f.skirt * k
            let hem = pelvis + Point(0, r * 0.75 * spec.view.heightScale)
            let skirt = [pelvis, hem + Point(-r * 0.5, 0), hem + Point(r * 0.5, 0)]
            if let accent = f.accent { torso.append(FilledShape(subpaths: [skirt], color: accent)) }
            torso.append(stroke(skirt, 9, closed: true))
        }
        group(["pelvis", "chest", "neck"], torso)
        let head = pose.joints["head"]!, ry = f.headSize * k / 2 * spec.view.heightScale, rx = f.headSize * f.headAspect * k / 2
        var headShapes = [stroke(ellipse(head, rx, ry), 6, closed: true)]
        if f.headwear != "none" {
            let size = f.headwearSize
            var contour: [Point] = []
            for i in 0...24 {
                let a = .pi + Double(i) * .pi / 24
                let y = f.headwear == "kerchief" ? -ry * 0.65 + sin(a) * ry * 0.55 * size : sin(a) * ry * size
                contour.append(head + Point(cos(a) * rx * size, y))
            }
            if f.headwear == "hood" {
                contour += [head + Point(rx * size, ry * 0.8), head + Point(-rx * size, ry * 0.8)]
            }
            if let accent = f.accent { headShapes.append(FilledShape(subpaths: [contour], color: accent)) }
            headShapes.append(stroke(contour, 7, closed: true))
            if f.headwear == "kerchief", sin(radians(pose.drawnHeading)) <= 0, f.knot > 0 {
                let knot = head + Point(0, ry * 0.7), r = ry * f.knot * 0.3
                headShapes.append(FilledShape(subpaths: [ellipse(knot, r, r)], color: f.accent ?? ink.color))
                let tails = [knot, knot + Point(-r * 1.5, r * 2.8), knot + Point(0, r * 1.2), knot + Point(r * 1.5, r * 2.8)]
                headShapes.append(stroke(tails, 8))
            }
        }
        group(["head"], headShapes)
        drawing.shapes = groups.sorted { $0.depth == $1.depth ? $0.index < $1.index : $0.depth < $1.depth }.flatMap(\.shapes)
        return drawing
    }

    private func outline(_ input: [Point], seed: UInt64, closed: Bool) -> (shape: FilledShape, minimumWidth: Double) {
        var chain = input
        if closed { chain.append(input[0]) }
        else if spec.ink.overshoot > 0 {
            chain[0] = chain[0] - (chain[1] - chain[0]).unit * (spec.ink.overshoot * unit)
            chain[chain.count - 1] = chain.last! + (chain.last! - chain[chain.count - 2]).unit * (spec.ink.overshoot * unit)
        }
        var lengths = [0.0]
        for i in 1..<chain.count { lengths.append(lengths.last! + (chain[i] - chain[i - 1]).length) }
        let total = lengths.last!, count = max(closed ? 12 : 2, Int(ceil(total / (0.01 * unit))))
        var centers: [Point] = [], widths: [Double] = [], normals: [Point] = []
        var segment = 1, minWidth = Double.infinity
        for i in 0...(closed ? count - 1 : count) {
            let distance = total * Double(i) / Double(count)
            while segment < chain.count - 1 && lengths[segment] < distance { segment += 1 }
            let span = lengths[segment] - lengths[segment - 1]
            let point = mix(chain[segment - 1], chain[segment], span > 1e-12 ? (distance - lengths[segment - 1]) / span : 0)
            let u = Double(i) / Double(count)
            let taper = closed ? 1 : 1 - spec.ink.taper * (1 - cubic(min(u, 1 - u) / 0.12))
            let width = spec.ink.width * unit * taper * (1 + spec.ink.pressure * 0.35 * noise(distance / (spec.ink.wobbleLength * unit), seed ^ 0x5052455353555245))
            if closed || (u >= 0.15 && u <= 0.85) { minWidth = min(minWidth, width) }
            centers.append(point); widths.append(width)
        }
        for i in centers.indices {
            let prev = centers[closed ? (i + centers.count - 1) % centers.count : max(0, i - 1)]
            let next = centers[closed ? (i + 1) % centers.count : min(centers.count - 1, i + 1)]
            normals.append((next - prev).unit.normal)
        }
        for i in centers.indices {
            let distance = total * Double(i) / Double(count)
            // The ring's seam shares its periodic displacement.
            let n = closed ? mix(noise(distance / (spec.ink.wobbleLength * unit), seed), noise((distance - total) / (spec.ink.wobbleLength * unit), seed), Double(i) / Double(count))
                : noise(distance / (spec.ink.wobbleLength * unit), seed)
            centers[i] = centers[i] + normals[i] * (n * spec.ink.wobble * unit)
        }
        let left = centers.indices.map { centers[$0] + normals[$0] * (widths[$0] / 2) }
        let right = centers.indices.map { centers[$0] - normals[$0] * (widths[$0] / 2) }
        let paths: [[Point]]
        if closed { paths = [left, Array(right.reversed())] }
        else {
            func cap(_ index: Int, _ end: Bool) -> [Point] {
                let angle = atan2(normals[index].y, normals[index].x) + (end ? 0 : .pi)
                return (1..<8).map { let a = angle - Double($0) * .pi / 8; return centers[index] + Point(cos(a), sin(a)) * (widths[index] / 2) }
            }
            paths = [left + cap(centers.count - 1, true) + Array(right.reversed()) + cap(0, false)]
        }
        return (FilledShape(subpaths: paths, color: spec.ink.color), minWidth)
    }
}
