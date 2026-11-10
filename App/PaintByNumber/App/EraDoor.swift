import Foundation
import Observation
import SwiftUI

/// The secret door (painting-company row 234): the app's year, set back to 0547 in Settings ›
/// About (tap the Year row, roll its wheel), opens Ravenna, the mosaic era (the `Ravenna`
/// module); rolled forward again in Ravenna's own Settings, it brings Paint by Moonlight back.
/// SideStore and Debug builds only. With the door closed nothing is stored and nothing changes.
enum Era: String {
    case moonlight
    case byzantium
}

/// Which era is on screen, kept across launches (UserDefaults `era`, absent for Paint by
/// Moonlight's own), and the passage between two while it plays.
@Observable
final class EraDoor {
    static let shared: EraDoor = {
        #if DEBUG
        // Demo and test launches start with the door shut, whatever a run before left.
        if DemoMode.isActive || DemoMode.isTestHost { UserDefaults.standard.removeObject(forKey: key) }
        #endif
        return EraDoor()
    }()
    static let key = "era"

    /// The era the root shows.
    private(set) var shown: Era
    /// The era the passage is on its way to, while it plays (`EraPassage`).
    private(set) var passage: Era?
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        shown = defaults.string(forKey: Self.key).flatMap(Era.init(rawValue:)) ?? .moonlight
    }

    /// Sets the clock: the passage starts, and the era is the new one from now on, this launch's
    /// and the next's.
    func go(to era: Era) {
        guard era != (passage ?? shown) else { return }
        if era == .moonlight {
            defaults.removeObject(forKey: Self.key)
        } else {
            defaults.set(era.rawValue, forKey: Self.key)
        }
        passage = era
    }

    /// The passage has covered the screen: the new era goes under it.
    func covered() {
        if let passage { shown = passage }
    }

    /// The passage has lifted. The new era is in even if the cover went unseen (the app was away
    /// while it played, and both moments came at once).
    func passed() {
        if let passage { shown = passage }
        passage = nil
    }
}

/// The passage between eras: tiles are set over the whole screen, row on row out from the bottom's
/// middle like the courses of an apse, the new era goes in beneath them, and they lift away. Under
/// Reduce Motion the screen dims to the apse's dark and back.
struct EraPassage: View {
    let door: EraDoor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start: Date?
    @State private var settledCover = false

    /// The presenting sheet goes first: nothing can cover a sheet from the root.
    static let wait: TimeInterval = 0.45
    static let cover: TimeInterval = 1.25
    static let hold: TimeInterval = 0.25
    static let lift: TimeInterval = 1.0
    static var total: TimeInterval { wait + cover + hold + lift }

    var body: some View {
        if let destination = door.passage {
            TimelineView(.animation) { context in
                let elapsed = Self.held(start.map { context.date.timeIntervalSince($0) } ?? 0)
                Canvas { graphics, size in
                    draw(in: &graphics, size: size, elapsed: elapsed)
                }
                .onChange(of: elapsed >= Self.wait + Self.cover) { _, covered in
                    if covered && !settledCover {
                        settledCover = true
                        door.covered()
                    }
                }
                .onChange(of: elapsed >= Self.total) { _, done in
                    if done { door.passed() }
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(true)
            .accessibilityHidden(true)
            .sensoryFeedback(.impact(weight: .heavy), trigger: settledCover) { _, covered in covered }
            .onAppear {
                start = .now
                settledCover = false
                #if DEBUG
                if DemoMode.scenario == "era-passage" {
                    Task {
                        try? await Task.sleep(for: .seconds(Self.wait + Self.cover * 0.67 + 0.5))
                        DemoMode.markReady()
                    }
                }
                #endif
            }
            .id(destination)
        }
    }

    /// The `era-passage` demo holds the passage two thirds of the way through its cover, the
    /// gallery half laid over, for a screenshot (Debug builds).
    private static func held(_ elapsed: TimeInterval) -> TimeInterval {
        #if DEBUG
        if DemoMode.scenario == "era-passage" { return min(elapsed, wait + cover * 0.67) }
        #endif
        return elapsed
    }

    /// One tessera: its centre, side and turn, when it is set (0 to 1 through the cover), its color.
    struct Tile {
        let centre: CGPoint
        let side: CGFloat
        let angle: Double
        let delay: Double
        let color: Color
    }

    private func draw(in graphics: inout GraphicsContext, size: CGSize, elapsed: TimeInterval) {
        let apse = Color(red: 0.082, green: 0.075, blue: 0.059)
        if reduceMotion {
            let fade = 0.35
            let t = elapsed - Self.wait
            let opacity = t < 0 ? 0 : t < Self.cover ? min(1, t / fade)
                : max(0, 1 - (t - Self.cover - Self.hold) / fade)
            graphics.fill(Path(CGRect(origin: .zero, size: size)), with: .color(apse.opacity(opacity)))
            return
        }
        let t = elapsed - Self.wait
        guard t > 0 else { return }
        let layout = Self.layout(in: size)
        for tile in layout.tiles {
            let opacity: Double
            let scale: Double
            if t < Self.cover {
                let local = (t / Self.cover - tile.delay * 0.75) / 0.25
                guard local > 0 else { continue }
                let eased = min(1, local)
                opacity = eased
                scale = 1.35 - 0.35 * (1 - pow(1 - eased, 3))
            } else if t < Self.cover + Self.hold {
                opacity = 1
                scale = 1
            } else {
                let local = ((t - Self.cover - Self.hold) / Self.lift - tile.delay * 0.7) / 0.3
                guard local < 1 else { continue }
                let eased = max(0, local)
                opacity = 1 - eased
                scale = 1 - 0.25 * eased
            }
            let side = tile.side * scale
            let turn = CGAffineTransform(translationX: tile.centre.x, y: tile.centre.y).rotated(by: tile.angle)
            let face = CGRect(x: -side / 2, y: -side / 2, width: side, height: side)
            graphics.fill(Path(roundedRect: face, cornerRadius: side * 0.12).applying(turn),
                          with: .color(tile.color.opacity(opacity)))
            // The light on the glass: a bright edge along the course, a shade along the other.
            let lit = CGRect(x: face.minX + side * 0.12, y: face.minY + side * 0.08, width: side * 0.76, height: side * 0.14)
            graphics.fill(Path(roundedRect: lit, cornerRadius: side * 0.07).applying(turn),
                          with: .color(.white.opacity(0.22 * opacity)))
            let shade = CGRect(x: face.minX + side * 0.1, y: face.maxY - side * 0.16, width: side * 0.8, height: side * 0.1)
            graphics.fill(Path(roundedRect: shade, cornerRadius: side * 0.05).applying(turn),
                          with: .color(.black.opacity(0.18 * opacity)))
        }
        // The setting bed: the apse's dark in the joints, spread only as far as the courses are laid,
        // so the old era shows beyond them until the cover is whole.
        graphics.blendMode = .destinationOver
        let whole = Path(CGRect(origin: .zero, size: size))
        if t < Self.cover {
            let front = min(layout.farthest, CGFloat(t / Self.cover / 0.75) * layout.farthest)
            let centre = layout.centre
            let bed = Path(ellipseIn: CGRect(x: centre.x - front, y: centre.y - front, width: 2 * front, height: 2 * front))
            graphics.fill(bed, with: .color(apse))
        } else {
            let lifted = max(0, (t - Self.cover - Self.hold) / Self.lift)
            graphics.fill(whole, with: .color(apse.opacity(max(0, 1 - lifted * 1.4))))
        }
    }

    struct Layout {
        let size: CGSize
        let pitch: CGFloat
        let centre: CGPoint
        let farthest: CGFloat
        let tiles: [Tile]
    }

    /// The last layout laid, kept for the passage's frames: tiles are laid once per screen size.
    private static var laid: Layout?

    static func layout(in size: CGSize) -> Layout {
        if let laid, laid.size == size { return laid }
        // About 36 across the short side: a phone's tiles are 22 points, an iPad's larger.
        let pitch = max(22, (min(size.width, size.height) / 36).rounded())
        let centre = CGPoint(x: size.width / 2, y: size.height + pitch)
        let farthest = hypot(max(centre.x, size.width - centre.x), centre.y) + pitch
        let layout = Layout(size: size, pitch: pitch, centre: centre, farthest: farthest,
                            tiles: tiles(pitch: pitch, centre: centre, farthest: farthest, size: size))
        laid = layout
        return layout
    }

    /// The courses: tesserae laid along true arcs round the bottom's middle, each turned to its
    /// course as an apse's are, mostly gold smalti with bands of lime and lapis, every one a little
    /// uneven in size, turn, place and tone. The same seed lays the same tiles every time.
    private static func tiles(pitch: CGFloat, centre: CGPoint, farthest: CGFloat, size: CGSize) -> [Tile] {
        let gold: (Double, Double, Double) = (0.788, 0.635, 0.290)
        let lime: (Double, Double, Double) = (0.914, 0.886, 0.827)
        let lapis: (Double, Double, Double) = (0.122, 0.165, 0.322)
        var random = PassageRandom(seed: 547)
        var tiles: [Tile] = []
        let courses = Int((farthest / pitch).rounded(.up))
        for course in 0..<courses {
            let radius = (CGFloat(course) + 0.6) * pitch
            let count = max(3, Int((CGFloat.pi * radius / pitch).rounded()))
            let step = Double.pi / Double(count)
            let shift = random.next() * step
            let tone: (Double, Double, Double)
            switch course % 7 {
            case 4: tone = lime
            case 5, 6: tone = lapis
            default: tone = gold
            }
            for index in 0..<count {
                let theta = shift + Double(index) * step
                let r = radius + CGFloat(random.next() - 0.5) * pitch * 0.12
                let point = CGPoint(x: centre.x + r * CGFloat(cos(theta)), y: centre.y - r * CGFloat(sin(theta)))
                let side = pitch * CGFloat(0.8 + random.next() * 0.1)
                guard point.x > -side, point.x < size.width + side, point.y > -side, point.y < size.height + side else { continue }
                let angle = -theta + (random.next() - 0.5) * 0.14
                let light = 0.86 + random.next() * 0.24
                let color = Color(red: min(1, tone.0 * light), green: min(1, tone.1 * light), blue: min(1, tone.2 * light))
                let delay = min(1, Double(radius / farthest) + random.next() * 0.06)
                tiles.append(Tile(centre: point, side: side, angle: angle, delay: delay, color: color))
            }
        }
        return tiles
    }
}

/// The passage's own little generator (SplitMix64), so it lays the same tiles every time.
private struct PassageRandom {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}
