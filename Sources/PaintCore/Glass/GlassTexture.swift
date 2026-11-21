/// How the glass of a Stained Glass window looks, pixel by pixel (painting-company row 366): lit
/// glass brightest deep inside a piece and dimmer against its lead, streaked and seeded like
/// cathedral glass, light through it even where the glass is dark; unlit glass flat, dark and
/// matte, with only a hint of its color, so a piece
/// lights up when it is glazed and what is left to glaze is plain to see. Built once a window
/// (the depth of every pixel from its lead, the streaks), then any piece is painted into an RGBA
/// buffer in its own time.
///
/// Colors are the template's encoded RGB, 0 to 1; the buffer is 8-bit RGBA at the template's size.
public struct GlassTexture: Sendable {
    public let width: Int
    public let height: Int
    /// Per pixel, how much of its glass's color the light lets through (lit glass).
    private let shade: [Float]
    /// Per pixel, the warm light deep in its piece, 0 at the lead to 1 at the piece's deepest.
    private let depth: [Float]
    /// Per pixel, the grain of unlit glass.
    private let grain: [Float]
    /// Per pixel, how far it lies from its piece's lead, in pixels (1 on the piece's edge).
    private let lead: [Float]
    /// The pixels of each piece, piece by piece (`order[start[r]..<start[r + 1]]`).
    private let order: [Int32]
    private let start: [Int]

    /// The dark of unlit glass, and how much of its own color shows through it.
    public static let unlitBase = SIMD3<Float>(30, 31, 40) / 255
    public static let unlitTint: Float = 0.1
    /// Light through lit glass deep in its piece, so even a dark glass glows in its middle.
    public static let warm = SIMD3<Float>(30, 26, 18) / 255

    public init(template t: Template) {
        let w = t.width, h = t.height, n = w * h
        let pieces = t.regions.count
        width = w
        height = h
        var label = [Int](repeating: 0, count: n)
        for y in 0..<h {
            for x in 0..<w { label[y * w + x] = min(max(0, pieces - 1), Int(t.regionMap[x, y])) }
        }
        // Distance from the lead: a chamfer transform from each piece's edge pixels.
        let far: Float = 1e9
        var d = [Float](repeating: far, count: n)
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x, k = label[i]
                if x == 0 || y == 0 || x == w - 1 || y == h - 1
                    || label[i - 1] != k || label[i + 1] != k || label[i - w] != k || label[i + w] != k {
                    d[i] = 1
                }
            }
        }
        let a: Float = 1, b: Float = 1.4142
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                guard d[i] > 1 else { continue }
                var v = d[i]
                if x > 0 { v = min(v, d[i - 1] + a) }
                if y > 0 {
                    v = min(v, d[i - w] + a)
                    if x > 0 { v = min(v, d[i - w - 1] + b) }
                    if x < w - 1 { v = min(v, d[i - w + 1] + b) }
                }
                d[i] = v
            }
        }
        for y in stride(from: h - 1, through: 0, by: -1) {
            for x in stride(from: w - 1, through: 0, by: -1) {
                let i = y * w + x
                guard d[i] > 1 else { continue }
                var v = d[i]
                if x < w - 1 { v = min(v, d[i + 1] + a) }
                if y < h - 1 {
                    v = min(v, d[i + w] + a)
                    if x < w - 1 { v = min(v, d[i + w + 1] + b) }
                    if x > 0 { v = min(v, d[i + w - 1] + b) }
                }
                d[i] = v
            }
        }
        var deepest = [Float](repeating: 0, count: max(1, pieces))
        for i in 0..<n where pieces > 0 { deepest[label[i]] = max(deepest[label[i]], d[i]) }

        // The streaks and seeds, sized to the window as the mockup sized them on its 270 grid.
        let s = Float(max(1, min(w, h))) / 270
        var shade = [Float](repeating: 1, count: n), depth = [Float](repeating: 0, count: n)
        var grain = [Float](repeating: 1, count: n)
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x, k = label[i]
                let fx = Float(x) / s, fy = Float(y) / s
                let t = min(1, d[i] / max(2.5 * s, deepest[k]))
                let ripple = Self.noise(fx / 9 + Float(k) * 3.1, fy / 23, seed: k) * 0.6
                    + Self.noise(fx / 3.5, fy / 3.5, seed: 7 + k) * 0.4
                shade[i] = 0.72 + 0.36 * t.squareRoot() + (ripple - 0.5) * 0.22
                depth[i] = t
                grain[i] = Self.noise(fx / 9 + Float(k), fy / 23, seed: k) * 0.12 + 0.94
            }
        }
        self.shade = shade
        self.depth = depth
        self.grain = grain
        lead = d

        var count = [Int](repeating: 0, count: pieces + 1)
        for k in label where pieces > 0 { count[k + 1] += 1 }
        for r in 0..<pieces { count[r + 1] += count[r] }
        start = count
        var next = count
        var order = [Int32](repeating: 0, count: pieces > 0 ? n : 0)
        for i in 0..<n where pieces > 0 {
            order[next[label[i]]] = Int32(i)
            next[label[i]] += 1
        }
        self.order = order
    }

    /// Paints piece `r` in `rgb`, lit (glazed) or not, into `pixels` (RGBA, `width` × `height`).
    public func paint(_ r: Int, rgb: SIMD3<Float>, lit: Bool, into pixels: inout [UInt8]) {
        guard r >= 0, r + 1 < start.count, pixels.count >= width * height * 4 else { return }
        let warm = Self.warm
        let tinted = rgb * Self.unlitTint + Self.unlitBase * (1 - Self.unlitTint)
        pixels.withUnsafeMutableBufferPointer { out in
            for j in start[r]..<start[r + 1] {
                let i = Int(order[j])
                let c = lit ? rgb * shade[i] + warm * depth[i] : tinted * grain[i]
                let o = i * 4
                out[o] = Self.byte(c.x)
                out[o + 1] = Self.byte(c.y)
                out[o + 2] = Self.byte(c.z)
                out[o + 3] = 255
            }
        }
    }

    /// The whole window: each piece in its color, lit where `lit` says.
    public func pixels(colors: [SIMD3<Float>], lit: [Bool]) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for r in 0..<min(colors.count, lit.count, start.count - 1) {
            paint(r, rgb: colors[r], lit: lit[r], into: &pixels)
        }
        return pixels
    }

    /// The window's fields for a renderer that paints the glass itself (the canvas's Stained Glass
    /// look): four floats a pixel, row by row from the top: the distance from the lead in pixels,
    /// then `shade`, `depth` and `grain` as `paint` uses them.
    public func fields() -> [Float] {
        var out = [Float](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            out[i * 4] = lead[i]
            out[i * 4 + 1] = shade[i]
            out[i * 4 + 2] = depth[i]
            out[i * 4 + 3] = grain[i]
        }
        return out
    }

    private static func byte(_ v: Float) -> UInt8 { UInt8(min(255, max(0, (v * 255).rounded()))) }

    /// Value noise, smooth between the integer lattice's hashed corners (0 to 1).
    static func noise(_ x: Float, _ y: Float, seed: Int) -> Float {
        func hash(_ i: Int, _ j: Int) -> Float {
            var n = UInt32(truncatingIfNeeded: i &* 374_761_393 &+ j &* 668_265_263 &+ seed &* 2_147_483)
            n = (n ^ (n >> 13)) &* 1_274_126_177
            return Float((n ^ (n >> 16)) & 1023) / 1023
        }
        let xi = Int(x.rounded(.down)), yi = Int(y.rounded(.down))
        let xf = x - Float(xi), yf = y - Float(yi)
        let u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf)
        return hash(xi, yi) * (1 - u) * (1 - v) + hash(xi + 1, yi) * u * (1 - v)
            + hash(xi, yi + 1) * (1 - u) * v + hash(xi + 1, yi + 1) * u * v
    }
}
