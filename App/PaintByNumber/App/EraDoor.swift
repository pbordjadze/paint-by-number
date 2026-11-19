import Foundation
import Observation
import SwiftUI

/// The secret door (painting-company row 234): the app's year, set back to 0547 in Settings ›
/// About (tap the Year row, roll its wheel), opens Ravenna, the mosaic era (the `Ravenna`
/// module); rolled forward again in Ravenna's own Settings, it brings Paint by Moonlight back.
/// From 1.1 in every build (painting-company row 236). With the door closed nothing is stored and
/// nothing changes.
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

    #if DEBUG
    /// The `era-passage-back` and `era-passage-night` demos: the way back played over the gallery,
    /// with no Paint by Mosaic loaded to leave (their stills hold it where the night hides both).
    func playDemoWayBack() {
        passage = .moonlight
    }
    #endif
}

/// The passage between eras: tiles are set over the whole screen, row on row out from the bottom's
/// middle like the courses of an apse, the new era goes in beneath them, and they lift away. Under
/// Reduce Motion the screen dims to the apse's dark and back. In SideStore and Debug builds the
/// way back to Paint by Moonlight is its own (`EraWayBack`, painting-company row 281): the tiles
/// come down from the top courses, on a night with the crescent and a few stars, which clears
/// over the gallery.
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

    /// Whether the passage to `destination` is the way back's own: to Paint by Moonlight, with
    /// motion, in SideStore and Debug builds. Every other passage is the tiles set and lifted.
    static func isWayBack(to destination: Era, reduceMotion: Bool) -> Bool {
        return destination == .moonlight && !reduceMotion
    }

    /// When the screen is wholly covered, so the era can go in beneath, and when the passage is
    /// over (seconds from its start).
    static func moments(to destination: Era, reduceMotion: Bool) -> (covered: TimeInterval, done: TimeInterval) {
        if isWayBack(to: destination, reduceMotion: reduceMotion) { return (EraWayBack.swap, EraWayBack.total) }
        return (wait + cover, total)
    }

    var body: some View {
        if let destination = door.passage {
            TimelineView(.animation) { context in
                let elapsed = Self.held(start.map { context.date.timeIntervalSince($0) } ?? 0)
                let timing = Self.moments(to: destination, reduceMotion: reduceMotion)
                Canvas { graphics, size in
                    draw(in: &graphics, size: size, elapsed: elapsed, destination: destination)
                }
                .onChange(of: elapsed >= timing.covered) { _, covered in
                    if covered && !settledCover {
                        settledCover = true
                        door.covered()
                    }
                }
                .onChange(of: elapsed >= timing.done) { _, done in
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
                if let hold = Self.demoHold {
                    Task {
                        try? await Task.sleep(for: .seconds(hold + 0.5))
                        DemoMode.markReady()
                    }
                }
                #endif
            }
            .id(destination)
        }
    }

    #if DEBUG
    /// Where a demo holds the passage for a screenshot: `era-passage` two thirds of the way
    /// through its cover, the gallery half laid over; `era-passage-back` the way back with its
    /// tiles half fallen, and `era-passage-night` its still night, just before it clears.
    private static var demoHold: TimeInterval? {
        switch DemoMode.scenario {
        case "era-passage": return wait + cover * 0.67
        case "era-passage-back": return EraWayBack.halfFallen
        case "era-passage-night": return EraWayBack.clears
        default: return nil
        }
    }
    #endif

    /// The passage's time, stopped where a demo holds it (Debug builds).
    private static func held(_ elapsed: TimeInterval) -> TimeInterval {
        #if DEBUG
        if let hold = demoHold { return min(elapsed, hold) }
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

    private func draw(in graphics: inout GraphicsContext, size: CGSize, elapsed: TimeInterval, destination: Era) {
        if Self.isWayBack(to: destination, reduceMotion: reduceMotion) {
            drawWayBack(in: &graphics, size: size, elapsed: elapsed)
            return
        }
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
            Self.set(tile, side: side, turn: turn, opacity: opacity, in: &graphics)
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

    /// Draws one tessera, `side` across, placed and turned by `turn`.
    private static func set(_ tile: Tile, side: CGFloat, turn: CGAffineTransform, opacity: Double,
                            in graphics: inout GraphicsContext) {
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

    /// The night behind the wall: deepest overhead, a little of the dusk toward the horizon.
    private static let zenith = Color(red: 0.047, green: 0.043, blue: 0.098)
    private static let horizon = Color(red: 0.118, green: 0.086, blue: 0.243)

    /// The way back (`EraWayBack` says when): the night, its crescent and stars, and over them
    /// the tiles, set quickly and then let go.
    private func drawWayBack(in graphics: inout GraphicsContext, size: CGSize, elapsed: TimeInterval) {
        guard elapsed > EraWayBack.wait else { return }
        let layout = Self.layout(in: size)
        // The night is the tiles' setting bed too, spread only as far as the courses are laid, so
        // Paint by Mosaic shows beyond them until the cover is whole.
        let night = EraWayBack.night(at: elapsed)
        if night > 0 {
            var sky = graphics
            sky.opacity = night
            let spread = EraWayBack.bed(at: elapsed)
            if spread < 1 {
                let front = layout.farthest * CGFloat(spread)
                let centre = layout.centre
                sky.clip(to: Path(ellipseIn: CGRect(x: centre.x - front, y: centre.y - front, width: 2 * front, height: 2 * front)))
            }
            sky.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(Gradient(colors: [Self.zenith, Self.horizon]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        }
        let gold = EraWayBack.gold(at: elapsed)
        let moon = EraWayBack.moon(at: elapsed) * gold
        if moon > 0 {
            let sky = EraWayBack.sky(in: size)
            // The crescent is the night's light: lit gold, a glow around it, its ink's outline on
            // top, at least as bright as the stars it brings out.
            let crescent = Path(Crescent.cgPath(in: sky.moon))
            var glow = graphics
            glow.addFilter(.shadow(color: Theme.gold.opacity(0.7 * moon), radius: sky.moon.width * 0.24))
            glow.fill(crescent, with: .color(Theme.gold.opacity(0.92 * moon)))
            graphics.stroke(crescent, with: .color(Theme.gold.opacity(moon)),
                            style: StrokeStyle(lineWidth: min(4, max(2, sky.moon.width * 0.04)), lineCap: .round, lineJoin: .round))
            for star in sky.stars {
                let state = EraWayBack.star(appearing: star.appears, at: elapsed)
                guard state.opacity > 0 else { continue }
                let side = star.side * CGFloat(state.scale)
                let place = CGRect(x: star.centre.x - side / 2, y: star.centre.y - side / 2, width: side, height: side)
                graphics.fill(Path(Sparkle.starPath(in: place)), with: .color(Theme.gold.opacity(state.opacity * gold)))
            }
        }
        guard elapsed < EraWayBack.fallen else { return }
        for (index, tile) in layout.tiles.enumerated() {
            guard let state = EraWayBack.tile(delay: tile.delay, index: index, at: elapsed) else { continue }
            let centre = CGPoint(x: tile.centre.x, y: tile.centre.y + layout.pitch * CGFloat(state.drop))
            let turn = CGAffineTransform(translationX: centre.x, y: centre.y).rotated(by: CGFloat(tile.angle + state.turn))
            Self.set(tile, side: tile.side * CGFloat(state.scale), turn: turn, opacity: state.opacity, in: &graphics)
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

/// The way back from Paint by Mosaic to Paint by Moonlight (painting-company row 281), the way
/// in's counterpart: when each thing happens and how far along it is, the drawing left to
/// `EraPassage`. After the same wait, the wall's tiles come over the screen quickly (`cover`), in
/// the way in's order, on a bed of night; the era is swapped at `swap`, once that bed is whole and
/// the last courses are still being set, so the work of the swap is over before anything falls;
/// from `laid` they let go from the top courses down, each loosening, dropping and fading (`fall`), so the wall comes
/// down on the night with its crescent; a few stars come out and the night stands a moment
/// (`still`); then it clears over the gallery, the crescent and stars last (`clear`). As long as
/// the way in, and nothing in it is drawn at random: a size and a time give one frame.
enum EraWayBack {
    static let wait = EraPassage.wait
    static let cover: TimeInterval = 0.55
    static let fall: TimeInterval = 0.9
    static let still: TimeInterval = 0.45
    /// How far through the cover the bed of night is whole, the last courses still to set.
    private static let bedded = 0.75
    /// The screen is wholly night and tiles: the era goes in beneath, a moment before the wall
    /// is whole, so a main thread kept busy by the swap costs the fall none of its opening.
    static var swap: TimeInterval { wait + cover * bedded }
    /// The wall is whole, and its top courses begin to let go.
    static var laid: TimeInterval { wait + cover }
    /// The last tile is gone.
    static var fallen: TimeInterval { laid + fall }
    /// The night begins to clear.
    static var clears: TimeInterval { fallen + still }
    /// The way in's length exactly; the clearing takes what the rest leaves (0.6 s).
    static var total: TimeInterval { EraPassage.total }
    static var clear: TimeInterval { total - clears }
    /// Where the `era-passage-back` demo holds it: the upper courses gone, the crescent showing.
    static var halfFallen: TimeInterval { laid + fall * 0.55 }

    /// A tile's course sets how late it is laid (`delay`, 0 at the bottom's middle to 1 at the
    /// farthest corner) and, turned round, how early it falls: the last three tenths of the fall
    /// are the lowest course's own.
    private static let stagger = 0.7

    struct TileState: Equatable {
        var opacity: Double
        var scale: Double
        /// How far it has dropped, in tile pitches.
        var drop: Double
        /// How far it has turned from its course, in radians.
        var turn: Double
    }

    /// The tile `index` of the layout, laid at `delay`, at a time; nil while it isn't there.
    static func tile(delay: Double, index: Int, at elapsed: TimeInterval) -> TileState? {
        guard elapsed > wait, elapsed < fallen else { return nil }
        if elapsed < laid {
            let local = ((elapsed - wait) / cover - delay * 0.75) / 0.25
            guard local > 0 else { return nil }
            let eased = min(1, local)
            return TileState(opacity: eased, scale: 1.35 - 0.35 * (1 - pow(1 - eased, 3)), drop: 0, turn: 0)
        }
        let local = ((elapsed - laid) / fall - (1 - delay) * stagger) / (1 - stagger)
        guard local < 1 else { return nil }
        let loose = max(0, local)
        let lean = sway(index)
        return TileState(opacity: 1 - loose * loose, scale: 1 - 0.12 * loose,
                         drop: 5 * loose * loose * (1 + lean), turn: 2.4 * lean * loose)
    }

    /// Each tile's own lean as it falls, -0.5 to 0.5, from its place in the layout alone.
    static func sway(_ index: Int) -> Double {
        var random = PassageRandom(seed: UInt64(truncatingIfNeeded: index))
        return random.next() - 0.5
    }

    /// How far the bed of night has spread under the courses being laid, 0 to 1 of the way to the
    /// farthest corner; whole from `swap`, a quarter of the cover before the last tile is.
    static func bed(at elapsed: TimeInterval) -> Double {
        elapsed >= swap ? 1 : min(1, max(0, (elapsed - wait) / cover / bedded))
    }

    /// The night's opacity: whole until it clears, gone a little before the end.
    static func night(at elapsed: TimeInterval) -> Double {
        1 - ease((elapsed - clears) / clear / 0.8)
    }

    /// The crescent's and the stars' opacity: they outlast the night a moment, over the gallery.
    static func gold(at elapsed: TimeInterval) -> Double {
        1 - ease(((elapsed - clears) / clear - 0.3) / 0.7)
    }

    /// The crescent's own coming: it rises as the courses over it let go (it stands a little
    /// above the middle of every screen), whole before `halfFallen`, so no gold glints in the
    /// joints of a wall still standing.
    static func moon(at elapsed: TimeInterval) -> Double {
        ease(((elapsed - laid) / fall - 0.3) / 0.2)
    }

    struct Star: Equatable {
        let centre: CGPoint
        let side: CGFloat
        /// When it comes out (seconds from the passage's start).
        let appears: TimeInterval
    }

    struct NightSky: Equatable {
        /// The crescent's square.
        let moon: CGRect
        let stars: [Star]
    }

    /// How long a star takes to come out.
    static let starPop: TimeInterval = 0.24

    /// The night's sky for a screen: the crescent above the middle, and five stars placed by
    /// hand round it, coming out from the top down as the last tiles fall, all out before the
    /// night clears.
    static func sky(in size: CGSize) -> NightSky {
        let side = min(160, max(64, min(size.width, size.height) * 0.2))
        let moon = CGRect(x: size.width / 2 - side / 2, y: size.height * 0.36 - side / 2, width: side, height: side)
        // Across, down, and the star's size beside the crescent's.
        let places: [(x: CGFloat, y: CGFloat, side: CGFloat)] =
            [(0.77, 0.13, 0.22), (0.24, 0.17, 0.30), (0.85, 0.40, 0.26), (0.15, 0.47, 0.20), (0.68, 0.60, 0.24)]
        var stars: [Star] = []
        for (index, place) in places.enumerated() {
            stars.append(Star(centre: CGPoint(x: size.width * place.x, y: size.height * place.y),
                              side: side * place.side, appears: fallen - 0.25 + 0.11 * Double(index)))
        }
        return NightSky(moon: moon, stars: stars)
    }

    /// A star that comes out at `appearing`: it fades in and pops a little past its size.
    static func star(appearing: TimeInterval, at elapsed: TimeInterval) -> (opacity: Double, scale: Double) {
        let s = elapsed - appearing
        guard s > 0 else { return (0, 0.3) }
        let opacity = min(1, s / 0.12)
        if s < 0.14 { return (opacity, 0.3 + 0.82 * ease(s / 0.14)) }
        return (opacity, 1.12 - 0.12 * ease((s - 0.14) / (starPop - 0.14)))
    }

    /// Smoothstep, held at its ends.
    private static func ease(_ x: Double) -> Double {
        let t = min(1, max(0, x))
        return t * t * (3 - 2 * t)
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
