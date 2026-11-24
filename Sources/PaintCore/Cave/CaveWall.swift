#if canImport(FoundationEssentials) && !canImport(Darwin)
import FoundationEssentials
#else
import Foundation
#endif

/// The Cave (painting-company row 371): a hidden mode at 15,000 BC on the year wheel, where the
/// whole screen is a torch-lit rock wall and a painting is blown onto it in four earth pigments.
/// This is the wall's geometry, shared by the maps (`CaveBay`), the pigment (`CavePigmentLayer`)
/// and the app's renderer: one long wall, `height` points tall, made of bays `bayWidth` points
/// wide. Bay 0 is the cave mouth, open to the daylight; each painting after it has a bay of its
/// own, oldest nearest the mouth; past the newest is bare rock for the next. Everything is in
/// wall points, origin top-left, +y down; maps are `scale` pixels a point, the pigment one.
public enum CaveWall {
    public static let height = 852
    public static let bayWidth = 400
    /// Map pixels (relief, rock, drawing) per wall point.
    public static let scale = 2

    /// The ledge's edge runs along the wall at about this height.
    public static let ledge: Float = 724
    /// The middle of the cave mouth's opening, in bay 0.
    public static let mouth = SIMD2<Float>(200, 330)
    /// The mouth's opening: half its width and height.
    public static let mouthRadii = SIMD2<Float>(150, 230)

    /// Where a painting is drawn in its bay: centred in this box, as large as fits.
    public static let paintingBox = (minX: Float(26), maxX: Float(374), minY: Float(250), maxY: Float(600))

    /// The four hollows in the ledge that hold the pigments, in the bay being painted: each
    /// centre and half width and height, by pigment.
    public static let cups: [(centre: SIMD2<Float>, radii: SIMD2<Float>)] = [
        (SIMD2(54, 792), SIMD2(30, 21)),
        (SIMD2(130, 826), SIMD2(22, 15)),
        (SIMD2(218, 786), SIMD2(33, 22)),
        (SIMD2(281, 830), SIMD2(24, 17)),
    ]
    /// The stone fat-lamp on the ledge, and where its flame burns, by the bay's tools.
    public static let lamp = SIMD2<Float>(350, 800)
    public static let lampFlame = SIMD2<Float>(364, 790)
    /// The lump of charcoal on bare rock's ledge: what a new painting is drawn with.
    public static let charcoal = SIMD2<Float>(196, 796)
    /// Where a hand is waited for once a painting is finished: bare rock above it.
    public static let handSpot = SIMD2<Float>(292, 172)

    /// Map size of one bay.
    public static var mapWidth: Int { bayWidth * scale }
    public static var mapHeight: Int { height * scale }

    /// Is a point inside one of the hollows, with a fingertip's slack? Returns its pigment.
    public static func cup(at p: SIMD2<Float>) -> CavePigment? {
        for (k, cup) in cups.enumerated() {
            let d = (p - cup.centre) / (cup.radii + SIMD2(8, 12))
            if d.x * d.x + d.y * d.y < 1 { return CavePigment(rawValue: UInt8(k)) }
        }
        return nil
    }
}

/// The four earth pigments of the Lascaux painters, which replace numbers and the palette: each
/// area of a painting is one, marked by as many dots as its number (one to four).
public enum CavePigment: UInt8, CaseIterable, Sendable {
    case charcoal, manganese, redOchre, yellowOchre

    /// Its color on the rock, display-encoded sRGB.
    public var rgb: SIMD3<Float> {
        switch self {
        case .charcoal: return SIMD3(0.10, 0.085, 0.075)
        case .manganese: return SIMD3(0.40, 0.21, 0.12)
        case .redOchre: return SIMD3(0.74, 0.25, 0.11)
        case .yellowOchre: return SIMD3(0.90, 0.60, 0.22)
        }
    }

    /// The dots that mark it: one to four.
    public var dots: Int { Int(rawValue) + 1 }
}

/// Smooth noise for the rock: gradient noise on a hashed lattice, a pure function of a point and
/// a seed, so the wall is the same at every visit and continuous across bays (each bay's maps are
/// made from wall coordinates).
enum CaveNoise {
    @inline(__always)
    static func hash(_ x: Int32, _ y: Int32, _ seed: UInt32) -> UInt32 {
        var h = UInt32(bitPattern: x) &* 0x8DA6_B343 ^ UInt32(bitPattern: y) &* 0xD816_3841 ^ seed &* 0xCB1A_B31F
        h ^= h >> 16
        h &*= 0x7FEB_352D
        h ^= h >> 15
        h &*= 0x846C_A68B
        h ^= h >> 16
        return h
    }

    /// Uniform in [0, 1) at a lattice point.
    @inline(__always)
    static func unit(_ x: Int32, _ y: Int32, _ seed: UInt32) -> Float {
        Float(hash(x, y, seed) >> 8) * (1 / Float(1 << 24))
    }

    private static let gradients: [SIMD2<Float>] = (0..<16).map { k in
        let a = Float(k) / 16 * 2 * .pi + 0.2
        return SIMD2(cos(a), sin(a))
    }

    /// Gradient noise, about -1…1 with a standard deviation near 0.3.
    @inline(__always)
    static func gradient(_ x: Float, _ y: Float, seed: UInt32) -> Float {
        let fx = x.rounded(.down), fy = y.rounded(.down)
        let ix = Int32(clamping: Int(fx)), iy = Int32(clamping: Int(fy))
        let tx = x - fx, ty = y - fy
        @inline(__always) func corner(_ dx: Int32, _ dy: Int32) -> Float {
            let g = gradients[Int(hash(ix &+ dx, iy &+ dy, seed) & 15)]
            return g.x * (tx - Float(dx)) + g.y * (ty - Float(dy))
        }
        let u = tx * tx * tx * (tx * (tx * 6 - 15) + 10)
        let v = ty * ty * ty * (ty * (ty * 6 - 15) + 10)
        let a = corner(0, 0) + (corner(1, 0) - corner(0, 0)) * u
        let b = corner(0, 1) + (corner(1, 1) - corner(0, 1)) * u
        return (a + (b - a) * v) * 1.4
    }

    /// Fractal noise of `octaves` layers from features `size` points across, each layer half the
    /// last's size and 0.55 of its weight, turned a little so no lattice lines up; normalized to a
    /// standard deviation near 1.
    static func fbm(_ x: Float, _ y: Float, size: Float, octaves: Int, seed: UInt32) -> Float {
        var sum: Float = 0, amp: Float = 1, total: Float = 0
        var px = x / size, py = y / size
        for o in 0..<octaves {
            sum += amp * gradient(px, py, seed: seed &+ UInt32(o) &* 101)
            total += amp
            amp *= 0.55
            // Twice the frequency, turned by about 37°.
            let nx = 1.6 * px - 1.2 * py, ny = 1.2 * px + 1.6 * py
            px = nx + 17.3
            py = ny - 9.1
        }
        return sum / total * 2.6
    }
}
