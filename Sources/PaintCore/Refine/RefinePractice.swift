import Foundation

/// The practice picture of Refine's Tool Guide: a moonlit evening (a sky deepening upward, a moon,
/// far hills, a near hill with a tree on it and a cottage with a lit window), drawn here as a photo
/// and made a template by the editor's own edits, so each tool's page has something to work on
/// at once, with no generation, no models and no photo of the painter's.
///
/// The template is `TemplateEditor.blank` of the photo with the picture's outlines drawn on it in
/// order (`lines`), each a draw the editor lays as the Pen's: an end on a line joins it, every
/// crossing is a junction. Its scenes:
/// - `painted`: every piece a line closes takes the photo's color there (`TemplateEditor.painted`),
///   the picture as the generator might have made it;
/// - `inked`: the hills' lines give their pieces the photo's colors, the rest is ink alone (a draw
///   with no paints), each shape keeping the paint around it: the sky one paint with the moon's
///   outline in it, the cottage the hill's green. What Make Cell and the Bucket are for, whose
///   pages say to tap inside the moon and pour into the roof; every other page shows `painted`.
///
/// Same inputs, same bytes: the photo is a function of nothing (each pixel its own, whatever the
/// bands), the edits are exact.
public enum RefinePractice {
    public enum Scene: String, CaseIterable, Sendable {
        case painted, inked
    }

    /// The photo's size, and the template's canvas: 4 × 3.
    public static let width = 1200
    public static let height = 900

    /// The practice photo (sRGB), each pixel the average of 2 × 2 samples of the picture in linear
    /// light.
    public static func photo() -> RGBAImage {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        let scale = Float(height)
        let offsets: [Float] = [0.25, 0.75]
        // The hills' heights at each sample's column, once.
        let columns: [Float] = (0..<(width * 2)).map { k in
            let x = Float(k / 2) + offsets[k % 2]
            return x / scale
        }
        let far = columns.map(farHill), near = columns.map(nearHill)
        pixels.withUnsafeMutableBufferPointer { buffer in
            let out = UncheckedSendable(buffer.baseAddress!)
            Parallel.forEachBand(height, minimumBandSize: 16) { rows in
                for y in rows {
                    for x in 0..<width {
                        var sum = SIMD3<Float>()
                        for sy in offsets {
                            for k in 2 * x..<2 * x + 2 {
                                let column = Hills(far: far[k], near: near[k])
                                sum += color(at: SIMD2(columns[k], (Float(y) + sy) / scale), hills: column)
                            }
                        }
                        let c = sum / 4
                        let i = (y * width + x) * 4
                        out.value[i] = encode(c.x)
                        out.value[i + 1] = encode(c.y)
                        out.value[i + 2] = encode(c.z)
                    }
                }
            }
        }
        return RGBAImage(width: width, height: height, pixels: pixels)
    }

    /// The template of `scene` over `photo` (`photo()`, or any image: its colors are read where the
    /// pieces lie).
    public static func template(_ scene: Scene, photo: RGBAImage) throws -> Template {
        var template = try TemplateEditor.blank(width: width, height: height, photo: photo, colorSpace: photo.colorSpace)
        let scale = Float(height)
        for line in lines {
            let points = line.points.map { $0 * scale }
            let bare = TemplateEditor.Edit.draw(points: points, closed: line.closed, paints: [])
            let edit = scene == .painted || line.paintsInk ? TemplateEditor.painted(
                .draw(points: points, closed: line.closed), on: template, photo: photo) : bare
            let (next, outcome) = try TemplateEditor.apply(edit, to: template)
            if let declined = outcome.declined { throw TemplateEditor.Failure.unsupported("practice line: \(declined)") }
            template = next
        }
        return template
    }

    // MARK: The picture

    // Units of the picture's height, origin top-left, +y down: the canvas is 4/3 wide.

    struct Line {
        var points: [SIMD2<Float>]
        var closed = false
        /// Gives its pieces the photo's colors in the inked scene too.
        var paintsInk = false
    }

    static let aspect: Float = 4 / 3

    static let moon = (center: SIMD2<Float>(1.04, 0.2), radius: Float(0.075))
    static let crown = (center: SIMD2<Float>(0.3, 0.71), radius: Float(0.085))
    static let trunkBottom: Float = 0.9
    static let roof = (left: SIMD2<Float>(0.76, 0.8), apex: SIMD2<Float>(0.88, 0.7), right: SIMD2<Float>(1.0, 0.8))
    static let walls = (minX: Float(0.79), maxX: Float(0.97), bottom: Float(0.95))
    static let window = (minX: Float(0.82), minY: Float(0.83), maxX: Float(0.88), maxY: Float(0.89))
    static let door = (minX: Float(0.91), top: Float(0.85), maxX: Float(0.95))
    /// The crown's outline: 48 vertices, the first at the bottom, so the trunk's sides start on
    /// two of them.
    static let crownVertices = 48

    static func farHill(_ x: Float) -> Float {
        0.47 + 0.03 * sin(2 * .pi * x / 1.1 + 0.6) + 0.012 * sin(2 * .pi * x / 0.37)
    }

    static func nearHill(_ x: Float) -> Float {
        let bump = (x - 0.3) / 0.28
        return 0.63 - 0.075 * exp(-bump * bump) + 0.03 * x
    }

    static func circle(_ center: SIMD2<Float>, _ radius: Float, count: Int) -> [SIMD2<Float>] {
        (0..<count).map { k in
            let angle = Float.pi / 2 + 2 * .pi * Float(k) / Float(count)
            return center + radius * SIMD2(cos(angle), sin(angle))
        }
    }

    /// The outlines, in the order they are drawn.
    static var lines: [Line] {
        func hill(_ y: (Float) -> Float) -> [SIMD2<Float>] {
            let steps = 64
            return (0...steps).map { k in
                let x = aspect * Float(k) / Float(steps)
                return SIMD2(x, y(x))
            }
        }
        let crownOutline = circle(crown.center, crown.radius, count: crownVertices)
        let trunkLeft = crownOutline[1], trunkRight = crownOutline[crownVertices - 1]
        let wallsTop = roof.left.y
        return [
            Line(points: hill(farHill), paintsInk: true),
            Line(points: hill(nearHill), paintsInk: true),
            Line(points: circle(moon.center, moon.radius, count: 40), closed: true),
            Line(points: crownOutline, closed: true),
            Line(points: [
                trunkLeft, SIMD2(trunkLeft.x, trunkBottom), SIMD2(trunkRight.x, trunkBottom), trunkRight,
            ]),
            Line(points: [roof.left, roof.apex, roof.right], closed: true),
            Line(points: [
                SIMD2(walls.minX, wallsTop), SIMD2(walls.minX, walls.bottom), SIMD2(walls.maxX, walls.bottom),
                SIMD2(walls.maxX, wallsTop),
            ]),
            Line(points: [
                SIMD2(window.minX, window.minY), SIMD2(window.maxX, window.minY), SIMD2(window.maxX, window.maxY),
                SIMD2(window.minX, window.maxY),
            ], closed: true),
            Line(points: [
                SIMD2((window.minX + window.maxX) / 2, window.minY), SIMD2((window.minX + window.maxX) / 2, window.maxY),
            ]),
            Line(points: [
                SIMD2(window.minX, (window.minY + window.maxY) / 2), SIMD2(window.maxX, (window.minY + window.maxY) / 2),
            ]),
            Line(points: [
                SIMD2(door.minX, walls.bottom), SIMD2(door.minX, door.top), SIMD2(door.maxX, door.top),
                SIMD2(door.maxX, walls.bottom),
            ]),
        ]
    }

    /// The hills' heights at a column.
    struct Hills {
        var far: Float
        var near: Float
    }

    /// The picture's colors, linear sRGB.
    enum Ink {
        static let roof = srgb(0.66, 0.25, 0.21), walls = srgb(0.93, 0.85, 0.68), window = srgb(1, 0.82, 0.38)
        static let frame = srgb(0.42, 0.27, 0.18), door = srgb(0.43, 0.27, 0.18), trunk = srgb(0.38, 0.25, 0.17)
        static let crownTop = srgb(0.2, 0.4, 0.26), crownBottom = srgb(0.13, 0.29, 0.19)
        static let nearTop = srgb(0.38, 0.56, 0.33), nearBottom = srgb(0.24, 0.42, 0.25)
        static let farTop = srgb(0.45, 0.5, 0.66), farBottom = srgb(0.36, 0.42, 0.58)
        static let moon = srgb(0.98, 0.94, 0.78), star = srgb(1, 0.97, 0.88)
        static let night = srgb(0.11, 0.14, 0.34), dusk = srgb(0.4, 0.34, 0.56), glow = srgb(0.96, 0.7, 0.54)
    }

    /// The trunk's sides: the crown's outline's vertices beside its bottom one.
    static let trunkSides: (left: Float, right: Float) = {
        let offset = crown.radius * sin(2 * .pi / Float(crownVertices))
        return (crown.center.x - offset, crown.center.x + offset)
    }()

    /// The picture's linear-light sRGB color at `p`, over the hills of its column.
    static func color(at p: SIMD2<Float>, hills: Hills) -> SIMD3<Float> {
        let x = p.x, y = p.y
        if inside(p, ofTriangle: roof.left, roof.apex, roof.right) { return Ink.roof }
        if x >= walls.minX, x <= walls.maxX, y >= roof.left.y, y <= walls.bottom {
            if x >= window.minX, x <= window.maxX, y >= window.minY, y <= window.maxY {
                let midX = (window.minX + window.maxX) / 2, midY = (window.minY + window.maxY) / 2
                return abs(x - midX) < 0.003 || abs(y - midY) < 0.003 ? Ink.frame : Ink.window
            }
            if x >= door.minX, x <= door.maxX, y >= door.top { return Ink.door }
            return Ink.walls
        }
        if distance(p, crown.center) <= crown.radius {
            return mix(Ink.crownTop, Ink.crownBottom, (y - crown.center.y + crown.radius) / (2 * crown.radius))
        }
        if x >= trunkSides.left, x <= trunkSides.right, y >= crown.center.y, y <= trunkBottom { return Ink.trunk }
        if y >= hills.near { return mix(Ink.nearTop, Ink.nearBottom, (y - 0.55) / 0.45) }
        if y >= hills.far { return mix(Ink.farTop, Ink.farBottom, (y - 0.44) / 0.15) }
        if distance(p, moon.center) <= moon.radius { return Ink.moon }
        // The sky: deep indigo overhead to a peach glow at the hills, with a few stars.
        for star in stars where distance(p, star) < 0.0045 { return Ink.star }
        let t = min(max(y / 0.52, 0), 1)
        return t < 0.55 ? mix(Ink.night, Ink.dusk, t / 0.55) : mix(Ink.dusk, Ink.glow, (t - 0.55) / 0.45)
    }

    static let stars: [SIMD2<Float>] = [
        SIMD2(0.12, 0.08), SIMD2(0.3, 0.16), SIMD2(0.52, 0.06), SIMD2(0.68, 0.19), SIMD2(0.86, 0.09), SIMD2(1.25, 0.13),
        SIMD2(0.42, 0.27), SIMD2(1.2, 0.3),
    ]

    static func inside(_ p: SIMD2<Float>, ofTriangle a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>) -> Bool {
        func side(_ u: SIMD2<Float>, _ v: SIMD2<Float>) -> Float { (v.x - u.x) * (p.y - u.y) - (v.y - u.y) * (p.x - u.x) }
        let d1 = side(a, b), d2 = side(b, c), d3 = side(c, a)
        return !((d1 < 0 || d2 < 0 || d3 < 0) && (d1 > 0 || d2 > 0 || d3 > 0))
    }

    static func distance(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        let d = a - b
        return (d * d).sum().squareRoot()
    }

    static func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
        let t = min(max(t, 0), 1)
        return a + (b - a) * t
    }

    /// An sRGB-encoded color, linearized (the samples are averaged in linear light).
    static func srgb(_ r: Float, _ g: Float, _ b: Float) -> SIMD3<Float> {
        func linear(_ c: Float) -> Float { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return SIMD3(linear(r), linear(g), linear(b))
    }

    static func encode(_ c: Float) -> UInt8 {
        let c = min(max(c, 0), 1)
        let e = c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
        return UInt8((e * 255).rounded())
    }
}
