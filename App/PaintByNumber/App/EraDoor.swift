#if UNRELEASED
import Foundation
import Observation
import SwiftUI

/// The secret door (painting-company row 234): the app's clock, set back to 547 in Settings ›
/// About (hold the Version row, roll the year), opens Ravenna, the mosaic era (the `Ravenna`
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

    /// One tile: where it sits, when it is set (0 to 1 through the cover), its color.
    struct Tile {
        let rect: CGRect
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
        for tile in Self.tiles(in: size) {
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
            let rect = tile.rect
            let scaled = CGRect(
                x: rect.midX - rect.width * scale / 2, y: rect.midY - rect.height * scale / 2,
                width: rect.width * scale, height: rect.height * scale)
            graphics.fill(Path(roundedRect: scaled, cornerRadius: 1.5), with: .color(tile.color.opacity(opacity)))
        }
        // The joints: the apse's dark between the tiles, laid with the first of them.
        let bed = min(1, max(0, t / (Self.cover * 0.3)))
        let lifted = max(0, (t - Self.cover - Self.hold) / Self.lift)
        let ground = t < Self.cover + Self.hold ? bed : max(0, 1 - lifted * 1.4)
        graphics.blendMode = .destinationOver
        graphics.fill(Path(CGRect(origin: .zero, size: size)), with: .color(apse.opacity(ground)))
    }

    /// The courses: rings round the bottom's middle, every fourth in gold, the rest in lapis, the
    /// apse's dark and lime, a little uneven as smalti are.
    static func tiles(in size: CGSize) -> [Tile] {
        // About 36 across the short side: a phone's tiles are 22 points, an iPad's larger.
        let side = max(22, (min(size.width, size.height) / 36).rounded())
        let gap: CGFloat = 2
        let columns = Int((size.width / side).rounded(.up)) + 1
        let rows = Int((size.height / side).rounded(.up)) + 1
        let centre = CGPoint(x: size.width / 2, y: size.height + side)
        let farthest = hypot(max(centre.x, size.width - centre.x), centre.y) + side
        let gold = Color(red: 0.788, green: 0.635, blue: 0.290)
        let lapis = Color(red: 0.122, green: 0.165, blue: 0.322)
        let deep = Color(red: 0.165, green: 0.153, blue: 0.125)
        let lime = Color(red: 0.914, green: 0.886, blue: 0.827)
        var random = PassageRandom(seed: 547)
        var tiles: [Tile] = []
        tiles.reserveCapacity(columns * rows)
        for row in 0..<rows {
            for column in 0..<columns {
                let rect = CGRect(x: CGFloat(column) * side, y: CGFloat(row) * side, width: side - gap, height: side - gap)
                let distance = hypot(rect.midX - centre.x, rect.midY - centre.y)
                let course = Int(distance / side)
                let jitter = random.next() * 0.06
                let delay = min(1, distance / farthest + jitter)
                let color: Color
                switch course % 8 {
                case 0, 1: color = gold.opacity(0.88 + random.next() * 0.12)
                case 2: color = lime.opacity(0.8 + random.next() * 0.2)
                case 3, 4, 5: color = lapis.opacity(0.8 + random.next() * 0.2)
                default: color = deep
                }
                tiles.append(Tile(rect: rect, delay: delay, color: color))
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
#endif
