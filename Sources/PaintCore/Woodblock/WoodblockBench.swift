import Foundation

/// A print in progress on the bench (painting-company row 375): which block is being worked,
/// how far, and the sheet as printed so far. Every array is on the plan's grid, in the block's
/// (mirrored) space, laid out as the canvas's textures are, so the app uploads them as they are.
///
/// Each block goes **carve** (the finger clears the wood around what stays: the tool sizes
/// itself to the room it has, from the knife beside a line to the wide gouge in the open, and
/// never cuts what stays; once most of the wood is gone the rest is tidied, so no stray wood
/// prints), **ink** (the brush lays the colour on what stands), **sheet** (damp paper drops into
/// the kentō), **rub** (the baren presses it: the more passes, the fuller the colour; a light
/// rub leaves gomazuri's speckle) and **peeled** (the sheet lifted, this block's colour laid over
/// the sheet's). The bokashi block is the colour block of its ground again, so it starts inked:
/// its ink is wiped to nothing down the sky.
public struct WoodblockBench: Sendable, Equatable {
    public enum Step: UInt8, Sendable { case carve = 0, ink, sheet, rub, peeled }

    public let width: Int
    public let height: Int
    /// The block being worked (`WoodblockPlan.blocks`); `blocks.count` once the print is done.
    public internal(set) var block: Int
    public internal(set) var step: Step
    /// Two bytes a cell: 0 for wood still standing, else the direction the gouge ran (1…255 over
    /// a half turn); then the tool's radius in cells (its kind: the knife, the round gouge, the
    /// wide one), which sets the grooves it leaves.
    public internal(set) var carved: [UInt8]
    /// Two bytes a cell: the ink on the block (0…255), then how much of it the baren has pressed
    /// into the sheet (0…255).
    public internal(set) var inked: [UInt8]
    /// Four bytes a cell: the sheet's face (RGBA, gamma-encoded in the template's space), in the
    /// block's space: the print is its mirror.
    public internal(set) var sheet: [UInt8]

    /// The share of the carveable wood cut before the rest is tidied.
    public static let tidyAt: Float = 0.72
    /// The share of what stands inked before the brush's work is done.
    public static let inkedAt: Float = 0.9
    /// How full the sheet's colour must be on average before it can be lifted.
    public static let rubbedAt: Float = 0.3
    /// Wood within this many cells of what stays is the shoulder the knife leaves.
    public static let shoulder: Float = 1.5
    /// How much one pass of the baren presses (of 255).
    static let pass = 70

    public init(plan: WoodblockPlan) {
        width = plan.grid.width
        height = plan.grid.height
        block = 0
        step = .carve
        let n = width * height
        carved = [UInt8](repeating: 0, count: 2 * n)
        inked = [UInt8](repeating: 0, count: 2 * n)
        let paper = SIMD4(Self.byte(WoodblockPlan.paper.x), Self.byte(WoodblockPlan.paper.y), Self.byte(WoodblockPlan.paper.z), 255)
        sheet = [UInt8](repeating: 0, count: 4 * n)
        for i in 0..<n {
            sheet[4 * i] = paper.x; sheet[4 * i + 1] = paper.y; sheet[4 * i + 2] = paper.z; sheet[4 * i + 3] = paper.w
        }
        // Washi's fibres: a faint cloud of kozo, and the odd long fibre lying along the sheet.
        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                let cloud = Self.noise(Float(x) / 9, Float(y) / 9, 91)
                let fibre = max(0, Self.noise(Float(x) / 22, Float(y) / 1.4, 92) - 0.72) * 3.2
                let shade = 1 - 0.035 * cloud - 0.05 * fibre - 0.012 * Self.hash(x, y, 93)
                for c in 0..<3 { sheet[4 * i + c] = Self.byte(Float(sheet[4 * i + c]) / 255 * shade) }
            }
        }
    }

    public func isDone(in plan: WoodblockPlan) -> Bool { block >= plan.blocks.count }

    /// The biggest tool, in cells: the wide gouge.
    public var widest: Float { Float(max(width, height)) * 0.04 }

    /// A cell's rectangle of cells changed by an action (half-open), for uploading only those.
    public struct Dirty: Sendable, Equatable {
        public var x0, y0, x1, y1: Int
        public init(x0: Int, y0: Int, x1: Int, y1: Int) {
            self.x0 = x0; self.y0 = y0; self.x1 = x1; self.y1 = y1
        }
        static let none = Dirty(x0: .max, y0: .max, x1: .min, y1: .min)
        public var isEmpty: Bool { x0 >= x1 || y0 >= y1 }
        mutating func add(x: Int, y: Int) { x0 = min(x0, x); y0 = min(y0, y); x1 = max(x1, x + 1); y1 = max(y1, y + 1) }
    }

    // MARK: Carve

    /// The tool's radius at `p` (cells): as much as the room it has, never into the shoulder.
    public func tool(at p: SIMD2<Float>, field: WoodblockField) -> Float {
        let x = Int(p.x), y = Int(p.y)
        guard x >= 0, y >= 0, x < width, y < height else { return 0 }
        return min(field.clearance[y * width + x] - Self.shoulder, widest)
    }

    /// Carves along a stroke from `a` to `b` (cells), stamping the tool every half its width.
    /// Returns the cells it cut.
    @discardableResult
    public mutating func carve(from a: SIMD2<Float>, to b: SIMD2<Float>, field: WoodblockField) -> Dirty {
        guard step == .carve else { return .none }
        var dirty = Dirty.none
        let d = b - a
        let len = (d.x * d.x + d.y * d.y).squareRoot()
        let angle = len > 0.01 ? atan2(d.y, d.x) : 0
        var turn = angle < 0 ? angle + .pi : angle
        if turn >= .pi { turn -= .pi }
        let code = UInt8(1 + min(253, Int(turn / .pi * 254)))
        var s: Float = 0
        repeat {
            let p = len > 0 ? a + d * (s / len) : a
            let r = tool(at: p, field: field)
            if r >= 0.5 { cut(at: p, radius: r, code: code, field: field, dirty: &dirty) }
            s += max(0.75, r * 0.5)
        } while s < len
        if len > 0 {
            let r = tool(at: b, field: field)
            if r >= 0.5 { cut(at: b, radius: r, code: code, field: field, dirty: &dirty) }
        }
        return dirty
    }

    private mutating func cut(at p: SIMD2<Float>, radius r: Float, code: UInt8, field: WoodblockField, dirty: inout Dirty) {
        let x0 = max(0, Int(p.x - r)), x1 = min(width - 1, Int(p.x + r))
        let y0 = max(0, Int(p.y - r)), y1 = min(height - 1, Int(p.y + r))
        guard x0 <= x1, y0 <= y1 else { return }
        let tool = UInt8(min(255, Int(r.rounded())))
        for y in y0...y1 {
            for x in x0...x1 {
                let dx = Float(x) + 0.5 - p.x, dy = Float(y) + 0.5 - p.y
                guard dx * dx + dy * dy <= r * r else { continue }
                let i = y * width + x
                guard carved[2 * i] == 0, field.clearance[i] > Self.shoulder else { continue }
                carved[2 * i] = code
                carved[2 * i + 1] = tool
                dirty.add(x: x, y: y)
            }
        }
    }

    /// The share of the carveable wood cut so far.
    public func carvedFraction(field: WoodblockField) -> Float {
        var cut = 0, all = 0
        for i in 0..<(width * height) where field.clearance[i] > Self.shoulder {
            all += 1
            if carved[2 * i] != 0 { cut += 1 }
        }
        return all == 0 ? 1 : Float(cut) / Float(all)
    }

    /// Clears what is left of the carveable wood, swept along the grain with the wide gouge.
    @discardableResult
    public mutating func tidy(field: WoodblockField) -> Dirty {
        var dirty = Dirty.none
        let tool = UInt8(min(255, Int(widest.rounded())))
        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                guard carved[2 * i] == 0, field.clearance[i] > Self.shoulder else { continue }
                carved[2 * i] = 1
                carved[2 * i + 1] = tool
                dirty.add(x: x, y: y)
            }
        }
        return dirty
    }

    // MARK: Ink and rub

    /// Brushes ink over a stroke (cells) with a brush of `radius` cells: only what stands takes it.
    @discardableResult
    public mutating func ink(from a: SIMD2<Float>, to b: SIMD2<Float>, radius: Float, field: WoodblockField) -> Dirty {
        guard step == .ink else { return .none }
        var dirty = Dirty.none
        for i in cells(from: a, to: b, radius: radius) where field.stays(i) && inked[2 * i] < 255 {
            inked[2 * i] = UInt8(min(255, Int(inked[2 * i]) + 150))
            dirty.add(x: i % width, y: i / width)
        }
        return dirty
    }

    /// The share of what stands that is inked fully.
    public func inkedFraction(field: WoodblockField) -> Float {
        guard field.standing > 0 else { return 1 }
        var n = 0
        for i in 0..<(width * height) where field.stays(i) && inked[2 * i] == 255 { n += 1 }
        return Float(n) / Float(field.standing)
    }

    /// Inks every cell that stands (the brush's work finished, or a block that starts inked).
    @discardableResult
    public mutating func inkAll(field: WoodblockField) -> Dirty {
        var dirty = Dirty.none
        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                guard field.stays(i), inked[2 * i] != 255 else { continue }
                inked[2 * i] = 255
                dirty.add(x: x, y: y)
            }
        }
        return dirty
    }

    /// One pass of the baren over a stroke (cells): each cell it passes presses more of the ink
    /// into the sheet, once a stroke.
    @discardableResult
    public mutating func rub(from a: SIMD2<Float>, to b: SIMD2<Float>, radius: Float) -> Dirty {
        guard step == .rub else { return .none }
        var dirty = Dirty.none
        for i in cells(from: a, to: b, radius: radius) where inked[2 * i + 1] < 255 {
            inked[2 * i + 1] = UInt8(min(255, Int(inked[2 * i + 1]) + Self.pass))
            dirty.add(x: i % width, y: i / width)
        }
        return dirty
    }

    /// How full the sheet's colour is, on average over what this block prints (0…1).
    public func rubbedFraction(field: WoodblockField) -> Float {
        guard field.standing > 0 else { return 1 }
        var sum = 0
        for i in 0..<(width * height) where field.stays(i) { sum += Int(inked[2 * i + 1]) }
        return Float(sum) / Float(255 * field.standing)
    }

    /// Rubs the whole sheet fully (VoiceOver's Rub, and demos).
    @discardableResult
    public mutating func rubAll() -> Dirty {
        guard step == .rub else { return .none }
        for i in 0..<(width * height) { inked[2 * i + 1] = 255 }
        return Dirty(x0: 0, y0: 0, x1: width, y1: height)
    }

    /// The cells within `r` of the segment from `a` to `b` (cells), each once.
    private func cells(from a: SIMD2<Float>, to b: SIMD2<Float>, radius r: Float) -> [Int] {
        var out: [Int] = []
        let d = b - a
        let len = (d.x * d.x + d.y * d.y).squareRoot()
        let x0 = max(0, Int(min(a.x, b.x) - r)), x1 = min(width - 1, Int(max(a.x, b.x) + r))
        let y0 = max(0, Int(min(a.y, b.y) - r)), y1 = min(height - 1, Int(max(a.y, b.y) + r))
        guard x0 <= x1, y0 <= y1 else { return out }
        let len2 = max(len * len, 1e-9)
        for y in y0...y1 {
            for x in x0...x1 {
                let c = SIMD2(Float(x) + 0.5, Float(y) + 0.5)
                let t = min(max(((c - a) * d).sum() / len2, 0), 1)
                let q = c - (a + d * t)
                guard (q * q).sum() <= r * r else { continue }
                out.append(y * width + x)
            }
        }
        return out
    }

    // MARK: Steps

    /// Moves on when the step's work is done: the wood carved far enough is tidied, the block
    /// inked far enough is inked whole. Returns the cells that changed, or nil if the step stays.
    public mutating func advanceIfReady(field: WoodblockField) -> Dirty? {
        switch step {
        case .carve:
            guard carvedFraction(field: field) >= Self.tidyAt else { return nil }
            let dirty = tidy(field: field)
            step = .ink
            return dirty
        case .ink:
            guard inkedFraction(field: field) >= Self.inkedAt else { return nil }
            let dirty = inkAll(field: field)
            step = .sheet
            return dirty
        default:
            return nil
        }
    }

    /// Finishes the step at once (VoiceOver's action for it, and demos): carving tidies, inking
    /// inks the rest, the sheet is laid, the baren rubs it all.
    public mutating func finishStep(plan: WoodblockPlan, field: WoodblockField) {
        switch step {
        case .carve: tidy(field: field); step = .ink
        case .ink: inkAll(field: field); step = .sheet
        case .sheet: step = .rub
        case .rub: rubAll(); peel(plan: plan, field: field)
        case .peeled: next(plan: plan, field: nil)
        }
    }

    /// Lays the sheet in the kentō.
    public mutating func laySheet() {
        if step == .sheet { step = .rub }
    }

    /// Lifts the sheet: this block's ink, as far as the baren pressed it, is laid over the
    /// sheet's colour (multiplied in linear light, a little short of hiding it: washi takes
    /// pigment transparently). A light rub prints a speckle (gomazuri); the bokashi block's
    /// colour fades down from the top of the picture.
    public mutating func peel(plan: WoodblockPlan, field: WoodblockField) {
        guard step == .rub, plan.blocks.indices.contains(block) else { return }
        let b = plan.blocks[block]
        let inkLinear = SIMD3(ColorScience.decodeSRGB(b.ink.x), ColorScience.decodeSRGB(b.ink.y), ColorScience.decodeSRGB(b.ink.z))
        let decode = (0..<256).map { ColorScience.decodeSRGB(Float($0) / 255) }
        let fade = Float(height) * 0.42
        for y in 0..<height {
            let bokashi: Float = b.kind == .bokashi ? max(0, 1 - Float(y) / fade) : 1
            let wipe = bokashi * bokashi * (3 - 2 * bokashi)
            for x in 0..<width {
                let i = y * width + x
                guard field.stays(i), inked[2 * i] > 0 else { continue }
                let t = Float(inked[2 * i + 1]) / 255
                guard t > 0 else { continue }
                let speck = Self.hash(x, y, block)
                var cover = min(max((t * 1.25 - speck * (1 - t) * 0.9), 0), 1) * Float(inked[2 * i]) / 255
                // What the baren leaves: the block's grain drawn along the sheet, its mottle,
                // the fibres taking more or less; a little more ink along an edge, where it gathers.
                let grain = Self.noise(Float(x) / 60, Float(y) / 3.5, block)
                let mottle = Self.noise(Float(x) / 13, Float(y) / 13, block + 40)
                let take = b.kind == .key
                    ? 0.9 + 0.07 * grain + 0.03 * speck
                    : 0.8 + 0.1 * grain + 0.07 * mottle + 0.03 * speck
                cover *= take * (field.shape[i] > -1.2 ? 1.1 : 1)
                let a = min(cover, 1) * b.opacity * wipe
                guard a > 0 else { continue }
                for c in 0..<3 {
                    let lin = decode[Int(sheet[4 * i + c])]
                    let out = lin * (1 - a + a * inkLinear[c])
                    sheet[4 * i + c] = Self.byte(ColorScience.encodeSRGB(out))
                }
            }
        }
        step = .peeled
    }

    /// Takes the next block to the bench: carved from fresh wood, or inked at once for the
    /// bokashi block, whose shape is its ground's colour block again (`field`, nil: the caller
    /// inks it when the field is made, `startInked`).
    public mutating func next(plan: WoodblockPlan, field: WoodblockField?) {
        guard step == .peeled, block < plan.blocks.count else { return }
        block += 1
        for i in carved.indices { carved[i] = 0 }
        for i in inked.indices { inked[i] = 0 }
        step = block < plan.blocks.count ? .carve : .peeled
        if block < plan.blocks.count, plan.blocks[block].kind == .bokashi {
            if let field { startInked(field: field) } else { step = .ink }
        }
    }

    /// A block that needs no carving (bokashi): every carveable cell cleared, all of it inked.
    public mutating func startInked(field: WoodblockField) {
        tidy(field: field)
        inkAll(field: field)
        step = .sheet
    }

    static func byte(_ v: Float) -> UInt8 { UInt8(min(max(v, 0), 1) * 255 + 0.5) }

    /// A cell's fixed speckle, 0…1.
    static func hash(_ x: Int, _ y: Int, _ b: Int) -> Float {
        var h = UInt64(truncatingIfNeeded: x) &* 0x9E37_79B9_7F4A_7C15 ^ UInt64(truncatingIfNeeded: y) &* 0xC2B2_AE3D_27D4_EB4F
            ^ UInt64(truncatingIfNeeded: b) &* 0x1656_67B1_9E37_79F9
        h ^= h >> 29; h &*= 0xBF58_476D_1CE4_E5B9; h ^= h >> 32
        return Float(h >> 40) / Float(1 << 24)
    }

    /// Smooth value noise, 0…1, at `(x, y)` in cells over a lattice of unit steps.
    static func noise(_ x: Float, _ y: Float, _ seed: Int) -> Float {
        let x0 = x.rounded(.down), y0 = y.rounded(.down)
        let fx = x - x0, fy = y - y0
        let ix = Int(x0), iy = Int(y0)
        let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
        let a = hash(ix, iy, seed), b = hash(ix + 1, iy, seed)
        let c = hash(ix, iy + 1, seed), d = hash(ix + 1, iy + 1, seed)
        return (a + (b - a) * sx) * (1 - sy) + (c + (d - c) * sx) * sy
    }

    // MARK: The print

    /// The print the right way round (the sheet's face, its mirror), RGBA rows.
    public func print() -> RGBAImage {
        var pixels = [UInt8](repeating: 0, count: 4 * width * height)
        for y in 0..<height {
            for x in 0..<width {
                let from = 4 * (y * width + width - 1 - x), to = 4 * (y * width + x)
                for c in 0..<4 { pixels[to + c] = sheet[from + c] }
            }
        }
        return RGBAImage(width: width, height: height, pixels: pixels)
    }

    // MARK: Coding

    public enum CodingError: Error, Equatable {
        case notABench
        case newerVersion
        case corrupt
    }

    static let magic: [UInt8] = Array("WDBK".utf8)
    public static let version: UInt8 = 1

    /// The bench as bytes: magic, version, size, block, step, then the arrays as they are.
    public func encoded() -> [UInt8] {
        var out = Self.magic
        out.append(Self.version)
        for v in [UInt32(width), UInt32(height), UInt32(block)] {
            withUnsafeBytes(of: v.littleEndian) { out.append(contentsOf: $0) }
        }
        out.append(step.rawValue)
        out += carved
        out += inked
        out += sheet
        return out
    }

    /// Reads a bench saved for `plan` (hostile bytes: every size is checked against the plan's
    /// grid and the bytes there are before anything is read).
    public init(decoding bytes: [UInt8], plan: WoodblockPlan) throws {
        guard bytes.count >= 18, Array(bytes[0..<4]) == Self.magic else { throw CodingError.notABench }
        guard bytes[4] <= Self.version else { throw CodingError.newerVersion }
        func u32(_ at: Int) -> Int {
            Int(UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24)
        }
        let w = u32(5), h = u32(9), b = u32(13)
        guard w == plan.grid.width, h == plan.grid.height, b <= plan.blocks.count,
              let step = Step(rawValue: bytes[17]) else { throw CodingError.corrupt }
        let n = w * h
        guard bytes.count == 18 + 8 * n else { throw CodingError.corrupt }
        width = w
        height = h
        block = b
        self.step = b == plan.blocks.count ? .peeled : step
        carved = Array(bytes[18..<(18 + 2 * n)])
        inked = Array(bytes[(18 + 2 * n)..<(18 + 4 * n)])
        sheet = Array(bytes[(18 + 4 * n)..<(18 + 8 * n)])
    }
}
